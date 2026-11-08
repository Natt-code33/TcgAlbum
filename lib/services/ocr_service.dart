// ============================================================
// services/ocr_service.dart
// Servicio de reconocimiento óptico de caracteres (OCR) local
// usando Google ML Kit Text Recognition para cartas TCG:
// Pokémon, Magic (MTG), Yu-Gi-Oh!, Digimon, One Piece, Lorcana, etc.
// Incorpora ordenación espacial (zonas superior e inferior de la carta),
// normalización tolerante a fallos de OCR en números de colección y
// filtrado inteligente de encabezados de cartas.
// ============================================================

import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Idiomas soportados para el reconocimiento y búsqueda de cartas.
enum CardLanguage {
  auto('🌐 Auto', 'auto'),
  es('🇪🇸 Español', 'es'),
  en('🇬🇧 Inglés', 'en'),
  ja('🇯🇵 Japonés', 'ja'),
  ko('🇰🇷 Coreano', 'ko'),
  zh('🇨🇳 Chino', 'zh-tw');

  final String label;
  final String apiCode;
  const CardLanguage(this.label, this.apiCode);
}

/// Resultado del análisis OCR sobre una imagen de carta TCG.
class OcrResult {
  /// Número de colección o referencia detectado (ej. "140/195", "070/280", "LOB-005", "ST1-03", "OP01-025").
  final String? collectionNumber;

  /// Nombre del personaje/carta detectado en el texto.
  final String? pokemonName;

  /// Idioma detectado en la carta.
  final CardLanguage detectedLanguage;

  /// Todo el texto bruto extraído por ML Kit.
  final String rawText;

  const OcrResult({
    this.collectionNumber,
    this.pokemonName,
    this.detectedLanguage = CardLanguage.auto,
    required this.rawText,
  });

  /// Devuelve true si se encontró el número de colección o el nombre.
  bool get isSuccessful => collectionNumber != null || pokemonName != null;
}

/// Servicio que encapsula la lógica de OCR multi-juego y multiidioma con ordenación espacial.
class OcrService {
  // Palabras comunes a ignorar de todos los TCG para evitar falsos positivos
  static final Set<String> _ignoredWords = {
    // ── Pokémon ──
    'BASIC', 'BASICO', 'BÁSICO', 'GASICO', 'GÁSICO', 'CASICO', 'PASICO',
    'STAGE', 'STAGE 1', 'STAGE 2', 'FASE', 'FASE 1', 'FASE 2',
    'POKEMON', 'POKÉMON', 'POKEMON BASICO', 'POKÉMON BÁSICO',
    'TRAINER', 'ENTRENADOR', 'SUPPORTER', 'PARTIDARIO', 'ITEM', 'OBJETO',
    'ENERGY', 'ENERGIA', 'ENERGÍA', 'VSTAR', 'VMAX', 'ABILITY', 'HABILIDAD',
    'WEAKNESS', 'DEBILIDAD', 'RESISTANCE', 'RESISTENCIA', 'RETREAT', 'RETIRADA',
    'RULE', 'REGLA', 'HP', 'PS', 'ILUS', 'ILLUS', 'ILLUST',
    // Japonés Pokémon
    'たね', '1進化', '2進化', 'グッズ', 'サポート', 'スタジアム', 'トレーナーズ',
    'エネルギー', '特性', '弱点', '抵抗力', 'にげる', 'ルール',
    // Coreano Pokémon
    '기본', '1진화', '2진화', '아이템', '서포트', '스타디움', '트레이너스',
    '에너지', '특성', '약점', '저항力', '후퇴', '룰',
    // Chino Pokémon
    '基础', '1阶进化', '2阶进化', '物品', '支援者', '竞技场', '训练家',
    '能量', '撤退', '规则',

    // ── Magic: The Gathering (MTG) ──
    'CREATURE', 'CRIATURA', 'SORCERY', 'CONJURO', 'INSTANT', 'INSTANTANEO',
    'INSTANTÁNEO', 'ARTIFACT', 'ARTEFACTO', 'ENCHANTMENT', 'ENCANTAMIENTO',
    'PLANESWALKER', 'LAND', 'TIERRA', 'LEGENDARY', 'LEYENDA', 'TRAMPLE',
    'FLYING', 'VIGILANCE', 'DEATHTOUCH',

    // ── Yu-Gi-Oh! ──
    'MONSTER', 'MONSTRUO', 'SPELL', 'MAGIA', 'TRAP', 'TRAMPA', 'FUSION',
    'FUSIÓN', 'SYNCHRO', 'SINCRONÍA', 'XYZ', 'PENDULUM', 'PÉNDULO', 'LINK',
    'ENLACE', 'EFFECT', 'EFECTO', 'ATK', 'DEF', '1ST EDITION', 'EDICIÓN LIMITADA',

    // ── Digimon ──
    'DIGIMON', 'OPTION', 'OPCIÓN', 'TAMER', 'DOMADOR', 'DIGI-EGG', 'DIGIHUEVO',
    'ROOKIE', 'CHAMPION', 'ULTIMATE', 'MEGA', 'VACCINE', 'VIRUS', 'DATA',

    // ── One Piece ──
    'LEADER', 'LÍDER', 'CHARACTER', 'PERSONAJE', 'EVENT', 'EVENTO',
    'ESCENARIO', 'SLASH', 'STRIKE', 'DON!!', 'COUNTER', 'POWER', 'COST',
  };

  /// Reconoce texto de la imagen según el idioma seleccionado o auto-detección.
  Future<OcrResult> extractFromImage(
    File imageFile, {
    CardLanguage language = CardLanguage.auto,
  }) async {
    final inputImage = InputImage.fromFile(imageFile);

    // 1. Si el usuario seleccionó un idioma asiático específico, usar ese script
    if (language == CardLanguage.ja) {
      return _runRecognition(inputImage, TextRecognitionScript.japanese, CardLanguage.ja);
    } else if (language == CardLanguage.ko) {
      return _runRecognition(inputImage, TextRecognitionScript.korean, CardLanguage.ko);
    } else if (language == CardLanguage.zh) {
      return _runRecognition(inputImage, TextRecognitionScript.chinese, CardLanguage.zh);
    }

    // 2. Modo Auto o Latino: primero reconocer en Latin (lee números 140/195 y texto occidental)
    final latinResult = await _runRecognition(
      inputImage,
      TextRecognitionScript.latin,
      CardLanguage.en,
    );

    // Si encontró tanto el nombre como el número, es un resultado completo
    if (latinResult.pokemonName != null && latinResult.collectionNumber != null) {
      return latinResult;
    }

    // 3. Si en Auto falta el nombre o es carta asiática, probar scripts asiáticos
    final asianScripts = [
      (TextRecognitionScript.japanese, CardLanguage.ja),
      (TextRecognitionScript.korean, CardLanguage.ko),
      (TextRecognitionScript.chinese, CardLanguage.zh),
    ];

    for (final (script, lang) in asianScripts) {
      final asianResult = await _runRecognition(inputImage, script, lang);
      if (asianResult.pokemonName != null && asianResult.pokemonName!.isNotEmpty) {
        return OcrResult(
          collectionNumber: latinResult.collectionNumber ?? asianResult.collectionNumber,
          pokemonName: asianResult.pokemonName,
          detectedLanguage: lang,
          rawText: '${latinResult.rawText}\n${asianResult.rawText}',
        );
      }
    }

    return latinResult;
  }

  /// Ejecuta un reconocedor específico para un script dado aplicando lógica espacial.
  Future<OcrResult> _runRecognition(
    InputImage inputImage,
    TextRecognitionScript script,
    CardLanguage targetLanguage,
  ) async {
    final recognizer = TextRecognizer(script: script);
    try {
      final RecognizedText recognizedText =
          await recognizer.processImage(inputImage);

      final rawText = recognizedText.text;

      // ── 1. Recopilar todas las líneas con sus coordenadas espaciales ──
      final allLines = <TextLine>[];
      double minY = double.infinity;
      double maxY = 0;

      for (final block in recognizedText.blocks) {
        for (final line in block.lines) {
          allLines.add(line);
          final box = line.boundingBox;
          if (box.top < minY) minY = box.top;
          if (box.bottom > maxY) maxY = box.bottom;
        }
      }

      // Ordenar líneas verticalmente de arriba hacia abajo
      allLines.sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));

      final totalHeight = (maxY - minY).abs();
      final hasValidCoordinates = totalHeight > 80 && allLines.length >= 2;

      // ── 2. Extracción de Número de Colección / Código de Set ──────────
      // En cartas TCG, el número siempre está en el pie de carta (último 35% inferior)
      String? collectionNumber;

      if (hasValidCoordinates) {
        final bottomThreshold = minY + (totalHeight * 0.65);
        final bottomLines = allLines.where((l) => l.boundingBox.top >= bottomThreshold).toList();
        for (final line in bottomLines.reversed) {
          final found = _extractCollectionNumber(line.text);
          if (found != null) {
            collectionNumber = found;
            break;
          }
        }
      }

      // Si no se encontró en la zona inferior, buscar en todas las líneas individuales
      if (collectionNumber == null) {
        for (final line in allLines.reversed) {
          final found = _extractCollectionNumber(line.text);
          if (found != null) {
            collectionNumber = found;
            break;
          }
        }
      }

      // Si aún no se encontró, probar en todo el texto concatenado
      collectionNumber ??= _extractCollectionNumber(rawText);

      // ── 3. Extracción de Nombre de la Carta ────────────────────────────
      // En cartas TCG, el nombre SIEMPRE está en el encabezado (primer 30% superior)
      String? cardTitle;

      List<TextLine> topLines;
      if (hasValidCoordinates) {
        final topThreshold = minY + (totalHeight * 0.32);
        topLines = allLines.where((l) => l.boundingBox.top <= topThreshold).toList();
      } else {
        topLines = allLines.take(4).toList();
      }

      for (final line in topLines) {
        final candidate = _cleanAndValidateTitle(line.text, collectionNumber);
        if (candidate != null) {
          cardTitle = candidate;
          break;
        }
      }

      // Si no se encontró en el encabezado estricto, buscar en las líneas superiores
      if (cardTitle == null) {
        for (final line in allLines) {
          if (hasValidCoordinates && line.boundingBox.top > (minY + totalHeight * 0.70)) {
            continue; // Evitar el pie de carta (ilustradores, números, legal)
          }
          final candidate = _cleanAndValidateTitle(line.text, collectionNumber);
          if (candidate != null) {
            cardTitle = candidate;
            break;
          }
        }
      }

      // ── 4. Detección de idioma según caracteres del título o texto ────
      CardLanguage lang = targetLanguage;
      if (cardTitle != null) {
        if (RegExp(r'[\uAC00-\uD7AF]').hasMatch(cardTitle)) {
          lang = CardLanguage.ko;
        } else if (RegExp(r'[\u3040-\u30FF]').hasMatch(cardTitle)) {
          lang = CardLanguage.ja;
        } else if (RegExp(r'[\u4E00-\u9FFF]').hasMatch(cardTitle)) {
          lang = CardLanguage.zh;
        }
      }

      return OcrResult(
        collectionNumber: collectionNumber,
        pokemonName: cardTitle,
        detectedLanguage: lang,
        rawText: rawText,
      );
    } finally {
      await recognizer.close();
    }
  }

  /// Extractor resiliente de números de colección, códigos de set y passcodes.
  /// Tolera espacios accidentales ("140 / 195"), caracteres confundidos por OCR
  /// ("O25/165" -> "025/165", "025/l65" -> "025/165"), y separadores como pipes ("|").
  String? _extractCollectionNumber(String text) {
    if (text.trim().isEmpty) return null;

    // Normalizar separadores y barras
    var normalized = text.replaceAll(RegExp(r'[|\\／]'), '/');
    normalized = normalized.replaceAll(RegExp(r'\s*/\s*'), '/');

    // 1. Fracción estándar de colección (ej: "025/165", "140/195", "070/280")
    final matchStandard = RegExp(r'\b(\d{1,4}/\d{1,4})\b').firstMatch(normalized);
    if (matchStandard != null) {
      return matchStandard.group(1);
    }

    // 2. Fracción con caracteres alfanuméricos confundidos por OCR:
    // 'O'/'o' por 0, 'I'/'l' por 1, 'S'/'s' por 5 (ej: "O25/165", "025/l65", "140/19S")
    final matchConfused = RegExp(r'\b([0-9OIlS]{1,4}/[0-9OIlS]{1,4})\b').firstMatch(normalized);
    if (matchConfused != null) {
      final rawMatch = matchConfused.group(1)!;
      final repaired = rawMatch
          .replaceAll(RegExp(r'[Oo]'), '0')
          .replaceAll(RegExp(r'[Il]'), '1')
          .replaceAll(RegExp(r'[Ss]'), '5');
      if (RegExp(r'^\d{1,4}/\d{1,4}$').hasMatch(repaired)) {
        return repaired;
      }
    }

    // 3. Código de Set con prefijo y número (ej: "SV5K-005", "LOB-005", "ST1-03", "OP01-025", "BT1-025")
    final matchSetCode = RegExp(r'\b([A-Za-z0-9]{2,6}[A-Za-z0-9\.\-]*\s*[-–_]\s*\d{1,4})\b')
        .firstMatch(normalized);
    if (matchSetCode != null) {
      return matchSetCode.group(1)!.replaceAll(' ', '');
    }

    // 4. Formato Set + Número de expansión asiático (ej: "SV2a 025/165", "SV4K 051/066")
    final matchAsianSet = RegExp(r'\b([A-Za-z0-9]{2,6}\s+\d{1,4}/\d{1,4})\b').firstMatch(normalized);
    if (matchAsianSet != null) {
      final frac = RegExp(r'\b\d{1,4}/\d{1,4}\b').firstMatch(matchAsianSet.group(1)!);
      if (frac != null) return frac.group(0);
    }

    // 5. Código Passcode Yu-Gi-Oh! (8 dígitos exactos)
    final matchPasscode = RegExp(r'\b(\d{8})\b').firstMatch(normalized);
    if (matchPasscode != null) {
      return matchPasscode.group(1);
    }

    // 6. Número individual precedido de No. o # (ej: "No. 025", "#025", "Ref: 051")
    final matchPrefixedNumber = RegExp(r'(?:no\.?|#|ref:?)\s*(\d{2,4})\b', caseSensitive: false)
        .firstMatch(normalized);
    if (matchPrefixedNumber != null) {
      return matchPrefixedNumber.group(1);
    }

    return null;
  }

  /// Limpia y valida si una línea de texto corresponde al título de una carta.
  String? _cleanAndValidateTitle(String line, String? collectionNumber) {
    var trimmed = line.trim();
    if (trimmed.length < 2) return null;
    if (collectionNumber != null && trimmed.contains(collectionNumber)) return null;
    if (RegExp(r'^\d+$').hasMatch(trimmed)) return null;

    // Quitar indicadores de PS / HP / ATK / DEF / DP (ej: "HP 70", "70 HP", "PS 120", "ATK/2500")
    trimmed = trimmed
        .replaceAll(RegExp(r'\b(HP|PS|ATK|DEF|DP)\s*[:/]?\s*\d+\b', caseSensitive: false), '')
        .replaceAll(RegExp(r'\b\d+\s*(HP|PS|ATK|DEF|DP)\b', caseSensitive: false), '')
        .replaceAll(RegExp(r'\[(Monster|Spell|Trap|Creature|Monstruo|Magia|Trampa)\]', caseSensitive: false), '')
        .trim();

    // Quitar palabras de descriptor de fase y tipos
    trimmed = trimmed.replaceAll(
      RegExp(
        r'\b(pok[eé]mon\s+)?(b[aá]sico|g[aá]sico|c[aá]sico|p[aá]sico|fase\s*\d*|stage\s*\d*|basic|creature|instant|sorcery|trap|spell|monster|trainer|supporter|item)\b',
        caseSensitive: false,
      ),
      '',
    ).replaceAll(
      RegExp(r'(たね|1進化|2進化|기본|1진화|2진화|基础|1阶进化|2阶进化)'),
      '',
    ).trim();

    // Quitar caracteres no alfabéticos de los extremos
    trimmed = trimmed.replaceAll(
      RegExp(r'^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$', unicode: true),
      '',
    ).trim();

    // Separar sufijos pegados al nombre (ej: "Pikachuex" -> "Pikachu EX")
    trimmed = trimmed.replaceAllMapped(
      RegExp(r'([\p{L}\-]{2,})(vmax|vstar|ex|gx|break|v)$', caseSensitive: false, unicode: true),
      (m) => '${m.group(1)} ${m.group(2)!.toUpperCase()}',
    );

    if (trimmed.length < 2) return null;

    final upper = trimmed.toUpperCase();
    if (_ignoredWords.any((w) => upper == w || upper.startsWith('$w '))) {
      return null;
    }

    // Filtrar líneas largas de descripción o textos de ataques (> 4 palabras)
    if (trimmed.split(RegExp(r'\s+')).length > 4) {
      return null;
    }

    // Debe contener caracteres alfabéticos válidos
    if (RegExp(r'[\p{L}]', unicode: true).hasMatch(trimmed)) {
      return _cleanName(trimmed);
    }

    return null;
  }

  String _cleanName(String text) {
    var clean = text.trim();
    // Si es latino, capitalizar estilo título
    if (RegExp(r'^[A-Za-z\s\-\.]+$').hasMatch(clean)) {
      clean = clean.split(' ').map((word) {
        if (word.isEmpty) return word;
        if (['V', 'EX', 'GX', 'VSTAR', 'VMAX', 'SP', 'SR', 'SEC'].contains(word.toUpperCase())) {
          return word.toUpperCase();
        }
        return word.split('-').map((part) {
          if (part.isEmpty) return part;
          return part[0].toUpperCase() + part.substring(1).toLowerCase();
        }).join('-');
      }).join(' ');
    }
    return clean;
  }
}
