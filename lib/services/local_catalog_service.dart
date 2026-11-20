import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import '../models/card_number.dart';
import '../models/pokemon_card.dart';
import 'card_matcher.dart';
import 'name_matcher.dart';
import 'ocr_service.dart';

/// Servicio de catálogo local basado en SQLite preempaquetado.
/// Permite búsquedas instantáneas (<1 ms) y 100% offline de cartas y colecciones.
class LocalCatalogService {
  static final LocalCatalogService instance = LocalCatalogService._internal();
  LocalCatalogService._internal();

  static const String _kCatalogVersionKey = 'tcg_catalog_db_version';
  static const int _currentCatalogVersion = 4;

  Database? _db;
  bool _isInitialized = false;
  Completer<void>? _initCompleter;
  final List<String> _latinSpeciesCache = [];
  final List<String> _cjkSpeciesCache = [];
  final Set<String> _exactSpeciesLower = {};
  Map<String, Set<int>>? _setTotalsCache;

  bool get isReady => _isInitialized && _db != null;

  static const String _cardSelect = '''
      SELECT c.*,
             s.name as set_name_text,
             s.name_es as set_name_es,
             s.name_en as set_name_en,
             s.name_ja as set_name_ja,
             s.name_ko as set_name_ko,
             s.name_zh as set_name_zh,
             s.official_count as set_official_count
      FROM cards c
      LEFT JOIN sets s ON c.set_id = s.id
    ''';

  /// Inicializa la base de datos local SQLite copiándola desde assets al almacenamiento interno
  /// solo si no existe o si la versión del catálogo ha cambiado. Seguro contra concurrencia.
  Future<void> init() async {
    if (_isInitialized && _db != null && _db!.isOpen) return;

    if (_initCompleter != null) {
      return _initCompleter!.future;
    }

    _initCompleter = Completer<void>();
    try {
      final databasesPath = await getDatabasesPath();
      final path = join(databasesPath, 'tcg_catalog.db');
      final file = File(path);

      final prefs = await SharedPreferences.getInstance();
      final installedVersion = prefs.getInt(_kCatalogVersionKey) ?? 0;
      final fileExists = await file.exists() && (await file.length()) > 0;

      if (!fileExists || installedVersion != _currentCatalogVersion) {
        final data = await rootBundle.load('assets/database/tcg_catalog.db');
        final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);

        developer.log('Actualizando catálogo SQLite local (${bytes.length} bytes)...', name: 'LocalCatalogService');
        await Directory(dirname(path)).create(recursive: true);
        await file.writeAsBytes(bytes, flush: true);
        await prefs.setInt(_kCatalogVersionKey, _currentCatalogVersion);
        developer.log('tcg_catalog.db copiado con éxito (${bytes.length} bytes)', name: 'LocalCatalogService');
      }

      _db = await openDatabase(path, readOnly: true);
      await _loadSpeciesCache();
      _isInitialized = true;
      developer.log('Base de datos SQLite local conectada con éxito.', name: 'LocalCatalogService');
      _initCompleter!.complete();
    } catch (e) {
      developer.log('Error inicializando catálogo local: $e', name: 'LocalCatalogService');
      if (!_initCompleter!.isCompleted) {
        _initCompleter!.complete();
      }
    } finally {
      _initCompleter = null;
    }
  }

  Future<void> _loadSpeciesCache() async {
    if (_db == null || _latinSpeciesCache.isNotEmpty) return;
    try {
      final rows = await _db!.rawQuery(
        'SELECT name_en, name_es, name_ja, name_ko, name_zh_tw, name_zh_cn FROM species_translations',
      );
      final seenLatin = <String>{};
      final seenCjk = <String>{};
      for (final r in rows) {
        for (final col in ['name_en', 'name_es', 'name_ja', 'name_ko', 'name_zh_tw', 'name_zh_cn']) {
          final val = (r[col] as String?)?.trim();
          if (val != null && val.isNotEmpty) {
            _exactSpeciesLower.add(val.toLowerCase());
            if ((col == 'name_en' || col == 'name_es') && seenLatin.add(val.toLowerCase())) {
              _latinSpeciesCache.add(val);
            }
            if ((col == 'name_ja' || col == 'name_ko' ||
                    col == 'name_zh_tw' || col == 'name_zh_cn') &&
                seenCjk.add(val.toLowerCase())) {
              _cjkSpeciesCache.add(val);
            }
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _loadSetIndex() async {
    if (_setTotalsCache != null) return;
    final rows = await _db!.rawQuery(
      'SELECT id, official_count, total_count FROM sets',
    );
    final totals = <String, Set<int>>{};
    for (final row in rows) {
      final id = (row['id'] as String?)?.trim().toLowerCase();
      if (id == null || id.isEmpty) continue;
      final counts = <int>{};
      final official = row['official_count'] as int?;
      final total = row['total_count'] as int?;
      if (official != null) counts.add(official);
      if (total != null) counts.add(total);
      totals[id] = counts;
    }
    _setTotalsCache = totals;
  }

  /// Extrae posibles códigos de set del texto OCR. No valida nada aquí:
  /// el filtro real es la distancia contra los sets del catálogo.
  static Iterable<String> _setCodeTokens(String text) sync* {
    final seen = <String>{};
    for (final match in RegExp(r'[A-Za-z][A-Za-z0-9]{2,7}').allMatches(text)) {
      final token = match.group(0)!;
      if (!RegExp(r'[A-Za-z]').hasMatch(token)) continue;
      if (token.length < 3 || token.length > 8) continue;
      if (seen.add(token.toLowerCase())) yield token;
    }
  }

  /// Resuelve el código de set que el OCR leyó mal ("SV118", "DSM1B",
  /// "svlB"...) contra los sets reales del catálogo.
  ///
  /// En cartas japonesas el nombre de la especie suele leerse bien aunque el
  /// set y el número no. Por eso se restringe a sets que contienen esa
  /// especie y se puntúa con: distancia del token al id del set, total
  /// impreso y número más cercano dentro del set.
  Future<String?> resolveSetCode(
    String rawText, {
    String? cardName,
    int? totalInSet,
    String? numberText,
  }) async {
    if (!_isInitialized || _db == null) await init();
    if (_db == null) return null;
    await _loadSetIndex();

    final name = cardName?.trim() ?? '';
    if (name.length < 2) return null;

    final tokens = _setCodeTokens(rawText)
        .map((token) => token.toLowerCase())
        .toList(growable: false);
    if (tokens.isEmpty) return null;

    final like = '%$name%';
    final allowedRows = await _db!.rawQuery(
      'SELECT DISTINCT set_id FROM cards WHERE name_ja LIKE ? '
      'OR name_en LIKE ? OR name_es LIKE ? OR name_ko LIKE ? OR name_zh LIKE ?',
      [like, like, like, like, like],
    );
    final allowed = <String>{};
    for (final row in allowedRows) {
      final id = (row['set_id'] as String?)?.trim().toLowerCase();
      if (id != null && id.isNotEmpty) allowed.add(id);
    }
    if (allowed.isEmpty) return null;

    // Sin total impreso no hay suficiente evidencia para elegir set: un
    // código mal leído puede apuntar a varios sets con la misma especie.
    if (totalInSet == null) return null;

    final totals = _setTotalsCache ?? const <String, Set<int>>{};
    final number = numberText?.trim().toLowerCase() ?? '';
    String? best;
    String? second;
    var bestScore = double.infinity;
    var secondScore = double.infinity;

    for (final set in allowed) {
      // El total impreso es la restricción más fiable: descarta sets que no
      // pueden ser esta carta aunque el token se parezca.
      final setTotals = totals[set];
      if (setTotals == null || !setTotals.contains(totalInSet)) continue;

      var minDistance = 99;
      for (final token in tokens) {
        final distance = damerauLevenshtein(token, set, maxDist: 5);
        if (distance < minDistance) minDistance = distance;
        if (minDistance == 0) break;
      }
      if (minDistance > 5) continue;

      var numberFit = false;
      var exactNumberFit = false;
      if (number.isNotEmpty) {
        final numberRows = await _db!.rawQuery(
          'SELECT local_id FROM cards WHERE lower(set_id) = ? AND '
          '(name_ja LIKE ? OR name_en LIKE ? OR name_es LIKE ? '
          'OR name_ko LIKE ? OR name_zh LIKE ?)',
          [set, like, like, like, like, like],
        );
        for (final row in numberRows) {
          final local = (row['local_id'] as String? ?? '').toLowerCase();
          if (local.isEmpty) continue;
          final distance = damerauLevenshtein(local, number, maxDist: 1);
          if (distance == 0) {
            exactNumberFit = true;
            numberFit = true;
            break;
          }
          if (distance <= 1) numberFit = true;
        }
      }

      final score = minDistance * 10.0 -
          (exactNumberFit ? 3.0 : (numberFit ? 1.0 : 0.0));
      if (score < bestScore) {
        secondScore = bestScore;
        second = best;
        bestScore = score;
        best = set;
      } else if (score < secondScore) {
        secondScore = score;
        second = set;
      }
    }

    if (best == null) return null;
    // Si dos sets empatan, es mejor no adivinar y dejar que la UI muestre
    // candidatas.
    if (second != null && secondScore - bestScore < 1.0) return null;
    return best;
  }

  /// Corrige errores típicos de OCR en nombres de Pokémon usando distancia Levenshtein
  /// contra las 1.025 especies oficiales (ej: "Char1zard ex" -> "Charizard ex", "Gardevo1r" -> "Gardevoir").
  String repairOcrPokemonName(String rawName) {
    final trimmed = rawName.trim();
    if (trimmed.isEmpty ||
        (_latinSpeciesCache.isEmpty && _cjkSpeciesCache.isEmpty)) {
      return trimmed;
    }

    // ── Nombres japoneses/coreanos/chinos ────────────────────────────────
    // El OCR confunde kana pequeños: "ウレモス" -> "ウルガモス".
    if (RegExp(r'[\u3040-\u30FF\uAC00-\uD7AF\u4E00-\u9FFF]')
        .hasMatch(trimmed)) {
      final lower = trimmed.toLowerCase();
      if (_exactSpeciesLower.contains(lower)) return trimmed;

      final cjkSuffix = RegExp(r'^(.*?)\s*(ex|EX|GX|VMAX|VSTAR|V)$')
          .firstMatch(trimmed);
      final cjkBase =
          (cjkSuffix?.group(1) ?? trimmed).trim();
      final cjkSuffixPart =
          cjkSuffix == null ? '' : ' ${cjkSuffix.group(2)!}';

      final baseLower = cjkBase.toLowerCase();
      if (_exactSpeciesLower.contains(baseLower)) return trimmed;
      if (cjkBase.length < 2) return trimmed;

      final maxDist = cjkBase.length >= 4 ? 2 : 1;
      String? bestSpecies;
      var bestDist = maxDist + 1;
      for (final candidate in _cjkSpeciesCache) {
        final candLower = candidate.toLowerCase();
        if ((candLower.length - baseLower.length).abs() > maxDist) continue;
        final dist = damerauLevenshtein(baseLower, candLower, maxDist: maxDist);
        // Con distancia 2 exigimos misma inicial y longitud casi igual;
        // así "ウレモス" llega a "ウルガモス" sin saltar a otra especie.
        if (dist == 2 &&
            (candLower.isEmpty ||
                baseLower.isEmpty ||
                candLower[0] != baseLower[0] ||
                (candLower.length - baseLower.length).abs() > 1)) {
          continue;
        }
        if (dist < bestDist) {
          bestDist = dist;
          bestSpecies = candidate;
          if (dist == 1) break;
        }
      }
      if (bestSpecies != null && bestDist <= maxDist) {
        return '$bestSpecies$cjkSuffixPart';
      }
      return trimmed;
    }

    // Separar sufijo de mecánica (ex, EX, GX, V, VMAX, VSTAR)
    final suffixMatch = RegExp(
      r'^(.+?)\s+(ex|EX|GX|VMAX|VSTAR|V|BREAK|LV\.X)$',
      caseSensitive: false,
    ).firstMatch(trimmed);

    final basePart = suffixMatch != null ? suffixMatch.group(1)!.trim() : trimmed;
    final suffixPart = suffixMatch != null ? ' ${suffixMatch.group(2)!}' : '';

    final lowerBase = basePart.toLowerCase();
    if (_exactSpeciesLower.contains(lowerBase)) {
      return trimmed;
    }

    // Normalizar dígitos confundidos con letras (ej. "Char1zard" -> "charizard") exceptuando Porygon2
    final normalizedBase = lowerBase == 'porygon2'
        ? lowerBase
        : lowerBase
            .replaceAll('0', 'o')
            .replaceAll('1', 'i')
            .replaceAll('5', 's');

    if (_exactSpeciesLower.contains(normalizedBase)) {
      final match = _latinSpeciesCache.firstWhere(
        (s) => s.toLowerCase() == normalizedBase,
        orElse: () => basePart,
      );
      return '$match$suffixPart';
    }

    if (normalizedBase.length < 4) return trimmed;
    final maxAllowedDist = normalizedBase.length >= 7 ? 2 : 1;
    String? bestSpecies;
    int bestDist = maxAllowedDist + 1;

    for (final candidate in _latinSpeciesCache) {
      final candLower = candidate.toLowerCase();
      if ((candLower.length - normalizedBase.length).abs() > maxAllowedDist) {
        continue;
      }
      final dist = _levenshtein(normalizedBase, candLower);
      if (dist < bestDist) {
        bestDist = dist;
        bestSpecies = candidate;
        if (dist == 1) break;
      }
    }

    if (bestSpecies != null && bestDist <= maxAllowedDist) {
      return '$bestSpecies$suffixPart';
    }
    return trimmed;
  }

  static int _levenshtein(String s, String t) {
    final n = s.length;
    final m = t.length;
    if (n == 0) return m;
    if (m == 0) return n;

    var prev = List<int>.generate(m + 1, (j) => j);
    var curr = List<int>.filled(m + 1, 0);

    for (int i = 1; i <= n; i++) {
      curr[0] = i;
      for (int j = 1; j <= m; j++) {
        final cost = s.codeUnitAt(i - 1) == t.codeUnitAt(j - 1) ? 0 : 1;
        final del = prev[j] + 1;
        final ins = curr[j - 1] + 1;
        final sub = prev[j - 1] + cost;
        curr[j] = del < ins ? (del < sub ? del : sub) : (ins < sub ? ins : sub);
      }
      final tmp = prev;
      prev = curr;
      curr = tmp;
    }
    return prev[m];
  }

  /// Busca una carta de forma unívoca e instantánea en el catálogo local.
  /// El número se parsea una sola vez y el nombre solo puntúa: no descarta
  /// candidatas que ya están identificadas por set/número.
  Future<PokemonCard?> findCard({
    String? cardName,
    String? setCode,
    required String cardNumber,
    int? totalInSet,
    CardLanguage language = CardLanguage.auto,
    CardNumber? parsedNumber,
  }) async {
    final base = parsedNumber ?? CardNumber.parse(cardNumber);
    final number = base == null
        ? CardNumber(
            kind: CardNumberKind.fraction,
            setCode: setCode,
            number: cardNumber.replaceAll(RegExp(r'[^\d]'), ''),
            total: totalInSet?.toString(),
          )
        : CardNumber(
            kind: base.kind,
            setCode: base.setCode ?? setCode,
            prefix: base.prefix,
            number: base.number,
            total: base.total ?? totalInSet?.toString(),
          );

    final ranked = await findCandidates(
      cardName: cardName,
      number: number,
      language: language,
    );

    if (ranked.isEmpty) return null;
    return ranked.first.score >= 0.55 ? ranked.first.card : null;
  }

  /// Devuelve candidatas ordenadas por puntuación. La UI decide si
  /// auto-selecciona o muestra la lista.
  Future<List<ScoredCard>> findCandidates({
    String? cardName,
    CardNumber? number,
    CardLanguage language = CardLanguage.auto,
    int limit = 20,
  }) async {
    if (!_isInitialized || _db == null) {
      await init();
    }
    if (_db == null) return <ScoredCard>[];

    final rows = <String, Map<String, dynamic>>{};

    Future<void> run(String where, List<Object?> args) async {
      final result = await _db!.rawQuery('$_cardSelect $where', args);
      for (final row in result) {
        final id = row['id'] as String?;
        if (id != null) rows[id] = row;
      }
    }

    if (number != null) {
      if (number.setCode != null && number.setCode!.isNotEmpty) {
        await run(
          'WHERE lower(c.set_id) = ? AND (c.local_id = ? COLLATE NOCASE OR c.number_int = ?)',
          [number.setCode!.toLowerCase(), number.localId, number.numberInt],
        );
      }
      await run(
        'WHERE c.local_id = ? COLLATE NOCASE OR (c.number_int = ? AND c.local_id = ?)',
        [number.localId, number.numberInt, number.number],
      );

      if (number.totalInt != null) {
        await run(
          'WHERE (c.total_in_set = ? OR s.official_count = ? OR s.total_count = ?) '
          'AND (c.local_id = ? OR c.local_id = ? OR c.number_int = ?)',
          [
            number.totalInt,
            number.totalInt,
            number.totalInt,
            number.number,
            number.number.padLeft(3, '0'),
            number.numberInt,
          ],
        );
      }

      // Set + nombre: si el OCR confundió un dígito del número, el nombre
      // exacto dentro del set sigue identificando la carta. Se prueban el
      // nombre completo y sus palabras para tolerar ruido pegado ("AKRA").
      final setCode = number.setCode?.trim().toLowerCase();
      final nameForSet = cardName?.trim() ?? '';
      if (setCode != null && setCode.isNotEmpty && nameForSet.isNotEmpty) {
        final tokens = <String>{nameForSet};
        for (final token in nameForSet.split(RegExp(r'\s+'))) {
          if (token.length >= 2) tokens.add(token);
        }
        for (final token in tokens.take(4)) {
          final like = '%$token%';
          await run(
            'WHERE lower(c.set_id) = ? AND (c.name_ja LIKE ? OR c.name_en LIKE ? '
            'OR c.name_es LIKE ? OR c.name_ko LIKE ? OR c.name_zh LIKE ? '
            'OR c.name_fr LIKE ? OR c.name_de LIKE ? OR c.name_it LIKE ?) LIMIT 30',
            [setCode, like, like, like, like, like, like, like, like],
          );
        }
      }
    }

    final cleanName = cardName?.trim() ?? '';
    if (cleanName.isNotEmpty) {
      final like = '%$cleanName%';
      await run(
        'WHERE c.name_ja LIKE ? OR c.name_en LIKE ? OR c.name_es LIKE ? '
        'OR c.name_ko LIKE ? OR c.name_zh LIKE ? OR c.name_fr LIKE ? '
        'OR c.name_de LIKE ? OR c.name_it LIKE ? LIMIT 30',
        [like, like, like, like, like, like, like, like],
      );
    }

    final scored = <ScoredCard>[];
    for (final row in rows.values) {
      final score = CardMatcher.scoreRow(
        row: row,
        number: number,
        ocrName: cardName,
      );
      if (score <= 0) continue;
      scored.add(ScoredCard(card: _mapRowToCard(row, language), score: score));
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(limit).toList(growable: false);
  }

  /// Busca cartas en el catálogo local por nombre en cualquier idioma (ES, EN, JA, KO, ZH, FR, DE, IT).
  Future<List<PokemonCard>> searchByName(
    String query, {
    CardLanguage language = CardLanguage.auto,
    int limit = 20,
  }) async {
    if (!_isInitialized || _db == null) await init();
    if (_db == null) return [];

    final clean = repairOcrPokemonName(query.trim());
    if (clean.isEmpty) return [];

    // Priorizar resultados según el idioma deseado
    String orderBy;
    if (language == CardLanguage.es) {
      orderBy = 'CASE WHEN c.name_es IS NOT NULL THEN 0 ELSE 1 END, c.number_int ASC';
    } else if (language == CardLanguage.en) {
      orderBy = 'CASE WHEN c.name_en IS NOT NULL THEN 0 ELSE 1 END, c.number_int ASC';
    } else if (language == CardLanguage.ja) {
      orderBy = 'CASE WHEN c.name_ja IS NOT NULL THEN 0 ELSE 1 END, c.number_int ASC';
    } else if (language == CardLanguage.ko) {
      orderBy = 'CASE WHEN c.name_ko IS NOT NULL THEN 0 ELSE 1 END, c.number_int ASC';
    } else if (language == CardLanguage.zh) {
      orderBy = 'CASE WHEN c.name_zh IS NOT NULL THEN 0 ELSE 1 END, c.number_int ASC';
    } else {
      orderBy = 'c.number_int ASC';
    }

    final likeParam = '%$clean%';
    final rows = await _db!.rawQuery('''
      SELECT c.*,
             s.name as set_name_text,
             s.name_es as set_name_es,
             s.name_en as set_name_en,
             s.name_ja as set_name_ja,
             s.name_ko as set_name_ko,
             s.name_zh as set_name_zh,
             s.official_count as set_official_count
      FROM cards c
      LEFT JOIN sets s ON c.set_id = s.id
      WHERE c.name_ja LIKE ?
         OR c.name_en LIKE ?
         OR c.name_es LIKE ?
         OR c.name_ko LIKE ?
         OR c.name_zh LIKE ?
         OR c.name_fr LIKE ?
         OR c.name_de LIKE ?
         OR c.name_it LIKE ?
      ORDER BY $orderBy
      LIMIT ?
    ''', [
      likeParam,
      likeParam,
      likeParam,
      likeParam,
      likeParam,
      likeParam,
      likeParam,
      likeParam,
      limit,
    ]);

    return rows.map((r) => _mapRowToCard(r, language)).toList();
  }

  /// Traduce el nombre de una especie Pokémon de cualquier idioma (JA, KO, ZH, ES, FR, DE, IT) a Inglés
  /// consultando las 1.025 especies oficiales precargadas en SQLite.
  Future<String?> translatePokemonSpeciesToEnglish(String name) async {
    if (!_isInitialized || _db == null) await init();
    if (_db == null) return null;

    final clean = name.trim();
    if (clean.isEmpty) return null;

    try {
      final rows = await _db!.rawQuery('''
        SELECT name_en FROM species_translations
        WHERE name_ja = ? OR name_ko = ? OR name_zh_tw = ? OR name_zh_cn = ?
           OR name_es = ? OR name_fr = ? OR name_de = ? OR name_it = ?
        LIMIT 1
      ''', [clean, clean, clean, clean, clean, clean, clean, clean]);

      if (rows.isNotEmpty) {
        return rows.first['name_en'] as String?;
      }
    } catch (_) {}
    return null;
  }

  /// Retorna los IDs de las colecciones que tienen exactamente la cantidad de cartas indicada.
  Future<List<String>> findSetIdsByOfficialCount(int officialCount) async {
    if (!_isInitialized || _db == null) await init();
    if (_db == null) return [];

    try {
      final rows = await _db!.rawQuery(
        'SELECT id FROM sets WHERE official_count = ? OR total_count = ? ORDER BY CASE WHEN id LIKE "%tg" OR id LIKE "%gg" THEN 0 ELSE 1 END, id DESC LIMIT 15',
        [officialCount, officialCount],
      );
      return rows.map((r) => r['id'] as String).toList();
    } catch (_) {
      return [];
    }
  }

  PokemonCard _mapRowToCard(Map<String, dynamic> row, CardLanguage language) {
    final nameJa = row['name_ja'] as String?;
    final nameEn = row['name_en'] as String?;
    final nameEs = row['name_es'] as String?;
    final nameKo = row['name_ko'] as String?;
    final nameZh = row['name_zh'] as String?;
    final setId = (row['set_id'] as String? ?? '').toLowerCase();

    // Elegir el nombre de la carta y colección según el idioma deseado o detectado
    String chosenName;
    String chosenLang;
    String? chosenSetName;

    if (language == CardLanguage.ja) {
      chosenName = (nameJa != null && nameJa.isNotEmpty) ? nameJa : (nameEn ?? nameEs ?? 'Carta');
      chosenLang = (nameJa != null && nameJa.isNotEmpty) ? 'ja' : 'en';
      chosenSetName = (row['set_name_ja'] as String?) ?? (row['set_name_en'] as String?);
    } else if (language == CardLanguage.es) {
      chosenName = (nameEs != null && nameEs.isNotEmpty) ? nameEs : (nameEn ?? nameJa ?? 'Carta');
      chosenLang = (nameEs != null && nameEs.isNotEmpty) ? 'es' : 'en';
      chosenSetName = (row['set_name_es'] as String?) ?? (row['set_name_en'] as String?);
    } else if (language == CardLanguage.en) {
      chosenName = (nameEn != null && nameEn.isNotEmpty) ? nameEn : (nameEs ?? nameJa ?? 'Card');
      chosenLang = 'en';
      chosenSetName = (row['set_name_en'] as String?) ?? (row['set_name_es'] as String?);
    } else if (language == CardLanguage.ko) {
      chosenName = (nameKo != null && nameKo.isNotEmpty) ? nameKo : (nameEn ?? nameEs ?? nameJa ?? 'Carta');
      chosenLang = 'ko';
      chosenSetName = (row['set_name_ko'] as String?) ?? (row['set_name_en'] as String?);
    } else if (language == CardLanguage.zh) {
      chosenName = (nameZh != null && nameZh.isNotEmpty) ? nameZh : (nameEn ?? nameEs ?? nameJa ?? 'Carta');
      chosenLang = 'zh-tw';
      chosenSetName = (row['set_name_zh'] as String?) ?? (row['set_name_en'] as String?);
    } else {
      // Auto: si tiene nombre en español, preferir español; si es set japonés exclusivo, japonés; si no, inglés
      if (nameEs != null && nameEs.isNotEmpty && setId != 's8a' && setId != 's12a' && setId != 'sv2a') {
        chosenName = nameEs;
        chosenLang = 'es';
        chosenSetName = (row['set_name_es'] as String?) ?? (row['set_name_en'] as String?);
      } else if (nameJa != null && nameJa.isNotEmpty && (setId == 's8a' || setId == 's12a' || setId == 'sv2a' || setId == 'sv4a')) {
        chosenName = nameJa;
        chosenLang = 'ja';
        chosenSetName = (row['set_name_ja'] as String?) ?? (row['set_name_en'] as String?);
      } else {
        chosenName = nameEn ?? nameEs ?? nameJa ?? nameKo ?? nameZh ?? 'Carta';
        chosenLang = nameEn != null ? 'en' : (nameEs != null ? 'es' : 'ja');
        chosenSetName = (row['set_name_en'] as String?) ?? (row['set_name_es'] as String?);
      }
    }

    final setName = chosenSetName ??
        (row['set_name_text'] as String?) ??
        (row['set_id'] as String? ?? 'Colección').toUpperCase();

    final localId = (row['local_id'] as String?) ?? '?';
    final totalInSet = (row['total_in_set'] as int?) ?? (row['set_official_count'] as int?);
    final imageUrl = (row['image_url'] as String?) ?? '';

    return PokemonCard(
      id: row['id'] as String,
      name: chosenName,
      number: localId,
      setName: setName,
      imageUrl: imageUrl,
      game: TcgGame.pokemon,
      setPrintedTotal: totalInSet,
      language: chosenLang,
    );
  }
}
