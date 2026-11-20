// ============================================================
// models/card_number.dart
// Parser único de números de carta Pokémon TCG.
//
// Sustituye las cuatro regex que hoy reparsean el número en sitios
// distintos (OCR, searchUniversal, searchByCollectionNumber y
// _parseManualQuery). El número se parsea UNA vez y se transporta
// como valor estructurado.
// ============================================================

enum CardNumberKind {
  fraction,
  prefixedFraction,
  setFraction,
  promo,
  setDash,
  prefixedNumber,
}

class CardNumber {
  final CardNumberKind kind;

  /// Código de set impreso junto al número (SV4a, s8a, sv-p...).
  final String? setCode;

  /// Prefijo del propio número (TG, GG, SWSH, SV...).
  final String? prefix;

  /// Número tal cual se imprime, conservando ceros a la izquierda.
  final String number;

  /// Total impreso en la fracción, conservando ceros.
  final String? total;

  const CardNumber({
    required this.kind,
    this.setCode,
    this.prefix,
    required this.number,
    this.total,
  });

  int? get numberInt => int.tryParse(number);
  int? get totalInt => total == null ? null : int.tryParse(total!);

  /// Identificador local tal como lo guarda el catálogo:
  /// TG14, GG05, SWSH001, SV001, 025...
  String get localId => prefix == null ? number : '$prefix$number';

  List<String> get localIdCandidates {
    final values = <String>{
      localId,
      number,
      if (number.isNotEmpty) number.padLeft(3, '0'),
    };
    return values.where((value) => value.isNotEmpty).toList(growable: false);
  }

  String get display {
    switch (kind) {
      case CardNumberKind.prefixedFraction:
        return '$prefix$number/$total';
      case CardNumberKind.fraction:
        return '$number/$total';
      case CardNumberKind.setFraction:
        return '$setCode $number/$total';
      case CardNumberKind.promo:
        return localId;
      case CardNumberKind.setDash:
        return '$setCode-$number';
      case CardNumberKind.prefixedNumber:
        return number;
    }
  }

  CardNumber withSetCode(String? code) {
    if (code == null || code.trim().isEmpty) return this;
    return CardNumber(
      kind: kind == CardNumberKind.fraction
          ? CardNumberKind.setFraction
          : kind,
      setCode: code.trim(),
      prefix: prefix,
      number: number,
      total: total,
    );
  }

  static const Set<String> _stopWords = {
    'NO', 'NUM', 'REF', 'CARD', 'PAGE', 'ITEM', 'BASIC', 'STAGE', 'POKEMON',
    'HP', 'PS', 'AR', 'SAR', 'SR', 'UR', 'RR', 'CHR', 'CSR', 'ACE', 'PROMO',
    'SET', 'TOTAL', 'ILLUS', 'ILLUST', 'ES', 'EN', 'FR', 'DE', 'IT', 'PT',
    // Nombres de ilustrador que el OCR puede pegar al número.
    'AKIRA', 'EGAWA', 'AKRA', 'ILLUSTRATOR',
  };

  static bool isStopWord(String value) =>
      _stopWords.contains(value.trim().toUpperCase());

  static const List<String> _prefixes = [
    'SWSH', 'SVP', 'SV', 'SM', 'XY', 'BW', 'DP', 'HGSS', 'TG', 'GG', 'RC',
  ];

  static String _normalize(String input) {
    final fullWidth = input.replaceAllMapped(
      RegExp(r'[０-９]'),
      (match) => String.fromCharCode(
        match.group(0)!.codeUnitAt(0) - 0xFEE0,
      ),
    );
    return fullWidth
        .replaceAll(RegExp(r'[|\\／]'), '/')
        .replaceAll(RegExp(r'\s*/\s*'), '/')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String _repairDigits(String value) => value
      .replaceAll(RegExp(r'[OoQqDd]'), '0')
      .replaceAll(RegExp(r'[Il|]'), '1')
      .replaceAll(RegExp(r'[Ss]'), '5')
      .replaceAll(RegExp(r'[Bb]'), '8')
      .replaceAll(RegExp(r'[Zz]'), '2')
      .replaceAll(RegExp(r'[Gg]'), '6')
      // En la tipografía diminuta del pie, el 4 se confunde con "a".
      .replaceAll(RegExp(r'[aA]'), '4');

  /// El OCR suele pegar la marca de regulación (G, H...) al código de set:
  /// "GSv2a" debe interpretarse como "Sv2a". No tocar "S8a" ni "DP01".
  static String _cleanSetCode(String value) {
    var set = value.trim();
    if (RegExp(r'^[D-Jd-j](?=[sS](?:[vVmM]\d|\d))').hasMatch(set)) {
      set = set.substring(1);
    }
    return set;
  }

  /// Devuelve null si el texto no contiene un número de carta.
  static CardNumber? parse(String input) {
    var raw = _normalize(input);
    if (raw.isEmpty) return null;

    // Reparar una barra extra introducida por el OCR: "0/12/028" -> "012/028".
    raw = raw.replaceAllMapped(
      RegExp(r'\b(\d)/(\d{2,3}/\d{2,4})\b'),
      (match) => '${match.group(1)}${match.group(2)}',
    );

    // Una línea de HP/PS no es un número de carta.
    if (RegExp(r'\b(?:HP|PS)\s*\d+\s*/\s*\d+\b', caseSensitive: false)
        .hasMatch(raw)) {
      return null;
    }

    // 1) TG14/TG30, GG05/GG70, SWSH025/SWSH100
    var match = RegExp(
      r'(?:^|[^A-Za-z0-9])([A-Za-z]{2,5})(\d{1,4})\s*/\s*(?:([A-Za-z]{2,5}))?(\d{1,4})(?![0-9A-Za-z])',
    ).firstMatch(raw);
    if (match != null && !isStopWord(match.group(1)!)) {
      final prefix = match.group(1)!.toUpperCase();
      return CardNumber(
        kind: CardNumberKind.prefixedFraction,
        prefix: prefix,
        number: match.group(2)!,
        total: match.group(4)!,
      );
    }

    // 2) s8a 001/028, [SV4a] 025/190, sv-p 001/288
    match = RegExp(
      r'(?:\[\s*([A-Za-z0-9.\-]{2,8})\s*\]|(?:^|[^A-Za-z0-9])([A-Za-z][A-Za-z0-9.\-]{1,7})\s+)(\d{1,4})\s*/\s*(\d{1,4})(?![0-9])',
    ).firstMatch(raw);
    if (match != null) {
      final bracketed = match.group(1) != null;
      final set = _cleanSetCode(match.group(1) ?? match.group(2)!);
      // Un código de set válido casi siempre lleva dígitos (sv11b, s8a,
      // base1...). Evita que "AKRA", "ILLUS" o el nombre del ilustrador se
      // cuelen como set cuando el OCR junta esa línea con el número.
      final looksLikeSetCode = bracketed ||
          RegExp(r'[0-9]').hasMatch(set) ||
          RegExp(r'^[a-z]{1,4}-[a-z]{1,4}$').hasMatch(set);
      if (!isStopWord(set) && looksLikeSetCode) {
        return CardNumber(
          kind: CardNumberKind.setFraction,
          setCode: set,
          number: match.group(3)!,
          total: match.group(4)!,
        );
      }
    }

    // 3) 140/195, 025/165, O25/165, 1O5/165, 025/16S
    match = RegExp(
      // El numerador admite "a" porque el 4 diminuto se confunde con esa
      // letra; el total no, para no capturar la "A" de la rareza ("086AR").
      r'(?:^|[^0-9A-Za-z])([0-9OIlSsBbZzGgQqDdaA]{1,4})\s*/\s*([0-9OIlSsBbZzGgQqDd]{1,4})(?![0-9])',
    ).firstMatch(raw);
    if (match != null) {
      final left = _repairDigits(match.group(1)!);
      final right = _repairDigits(match.group(2)!);
      if (RegExp(r'^\d+$').hasMatch(left) &&
          RegExp(r'^\d+$').hasMatch(right)) {
        return CardNumber(
          kind: CardNumberKind.fraction,
          number: left,
          total: right,
        );
      }
    }

    // 3b) SV2a025/165 (set y número pegados por el OCR)
    match = RegExp(
      r'(?:^|[^A-Za-z0-9])([A-Za-z]{1,3}\d{1,2}[a-z]?)(\d{3})\s*/\s*(\d{3})(?![0-9])',
    ).firstMatch(raw);
    if (match != null) {
      return CardNumber(
        kind: CardNumberKind.setFraction,
        setCode: _cleanSetCode(match.group(1)!),
        number: match.group(2)!,
        total: match.group(3)!,
      );
    }

    // 4) SWSH001, SV001, SVP001, GG05
    match = RegExp(
      '(?:^|[^A-Za-z0-9])(${_prefixes.join('|')})\\s*([0-9OIlSsBbZzGgQqDd]{2,4})(?![0-9A-Za-z])',
      caseSensitive: false,
    ).firstMatch(raw);
    if (match != null) {
      final prefix = match.group(1)!.toUpperCase();
      final number = _repairDigits(match.group(2)!);
      if (RegExp(r'^\d+$').hasMatch(number)) {
        return CardNumber(
          kind: CardNumberKind.promo,
          prefix: prefix,
          number: number,
        );
      }
    }

    // 5) SV-P 001
    match = RegExp(
      r'(?:^|[^A-Za-z0-9])([A-Za-z]{1,4})-([A-Za-z]{1,4})\s+(\d{1,4})(?![0-9])',
    ).firstMatch(raw);
    if (match != null) {
      final set = '${match.group(1)}-${match.group(2)}';
      if (!isStopWord(set)) {
        return CardNumber(
          kind: CardNumberKind.setDash,
          setCode: set,
          number: match.group(3)!,
        );
      }
    }

    // 6) s8a-012
    match = RegExp(
      r'(?:^|[^A-Za-z0-9])([A-Za-z][A-Za-z0-9.]{1,7})\s*[-–_]\s*(\d{1,4})(?![0-9])',
    ).firstMatch(raw);
    if (match != null && !isStopWord(match.group(1)!)) {
      return CardNumber(
        kind: CardNumberKind.setDash,
        setCode: match.group(1),
        number: match.group(2)!,
      );
    }

    // 7) No. 025, #025
    match = RegExp(
      r'(?:no\.?|#|ref:?)\s*(\d{2,4})(?![0-9])',
      caseSensitive: false,
    ).firstMatch(raw);
    if (match != null) {
      return CardNumber(
        kind: CardNumberKind.prefixedNumber,
        number: match.group(1)!,
      );
    }

    return null;
  }

  @override
  String toString() => display;
}
