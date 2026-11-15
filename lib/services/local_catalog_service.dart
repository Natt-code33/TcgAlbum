import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import '../models/pokemon_card.dart';
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

  /// Busca una carta de forma unívoca e instantánea en el catálogo local por Set, Número y/o Nombre.
  Future<PokemonCard?> findCard({
    String? cardName,
    String? setCode,
    required String cardNumber,
    int? totalInSet,
    CardLanguage language = CardLanguage.auto,
  }) async {
    if (!_isInitialized || _db == null) {
      await init();
    }
    if (_db == null) return null;

    final cleanNum = cardNumber.replaceAll(RegExp(r'[^\d]'), '').trim();
    final intNum = int.tryParse(cleanNum);
    final pad3 = cleanNum.isNotEmpty ? cleanNum.padLeft(3, '0') : cleanNum;
    final cleanCardNum = cardNumber.trim();
    final cleanName = cardName?.trim().toLowerCase();

    bool matchesCardName(Map<String, dynamic> row) {
      if (cleanName == null || cleanName.isEmpty) return true;
      for (final col in ['name_ja', 'name_en', 'name_es', 'name_ko', 'name_zh', 'name_fr', 'name_de', 'name_it', 'name_pt', 'name_th', 'name_id']) {
        final val = (row[col] as String? ?? '').toLowerCase();
        if (val.isNotEmpty && (val.contains(cleanName) || cleanName.contains(val))) {
          return true;
        }
      }
      return false;
    }

    const selectClause = '''
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

    // ── 1. Búsqueda por Total del Set + Número (ej: "113/094", "113/94", "013/028") ──
    // PRIORIDAD MÁXIMA: Si tenemos el total oficial del set (/094 o /94), la fracción matemática
    // es un identificador mucho más estricto y fiable que cualquier texto o prefijo OCR confuso (ej: PLF vs me02).
    if (totalInSet != null && totalInSet > 0) {
      final rows = await _db!.rawQuery('''
        $selectClause
        WHERE (c.total_in_set = ? OR s.official_count = ? OR s.total_count = ?) 
          AND (c.local_id = ? OR c.local_id = ? OR c.local_id = ? OR c.number_int = ?)
        ORDER BY CASE WHEN s.official_count = ? THEN 0 ELSE 1 END
      ''', [totalInSet, totalInSet, totalInSet, cleanCardNum, cleanNum, pad3, intNum, totalInSet]);

      for (final r in rows) {
        if (matchesCardName(r)) {
          developer.log('⚡ Encontrada en catálogo local por total ($totalInSet / $cardNumber): ${r['id']}', name: 'LocalCatalogService');
          return _mapRowToCard(r, language);
        }
      }
    }

    // ── 2. Búsqueda por Código de Set exacto (ej: "s8a", "sv2a", "cel25", "swsh12", "tg") ──
    if (setCode != null && setCode.isNotEmpty) {
      final cleanSet = setCode.toLowerCase().trim();
      final rows = await _db!.rawQuery('''
        $selectClause
        WHERE (c.set_id = ? OR c.id LIKE ?) 
          AND (c.local_id = ? OR c.local_id = ? OR c.local_id = ? OR c.number_int = ?)
      ''', [cleanSet, '%$cleanSet%', cleanCardNum, cleanNum, pad3, intNum]);

      for (final r in rows) {
        if (totalInSet != null && totalInSet > 0) {
          final official = r['set_official_count'] as int?;
          final total = r['total_in_set'] as int?;
          if (official != null && official != totalInSet && total != null && total != totalInSet) {
            continue;
          }
        }
        if (matchesCardName(r)) {
          developer.log('Encontrada en catálogo local por set_id ($cleanSet $cardNumber): ${r['id']}', name: 'LocalCatalogService');
          return _mapRowToCard(r, language);
        }
      }
    }

    // ── 3. Búsqueda por Nombre Y Número coincidentes en cualquiera de los idiomas ──
    if (cleanName != null && cleanName.isNotEmpty && (cleanNum.isNotEmpty || cleanCardNum.isNotEmpty)) {
      final likeParam = '%$cleanName%';
      final rows = await _db!.rawQuery('''
        $selectClause
        WHERE (c.local_id = ? OR c.local_id = ? OR c.local_id = ? OR c.number_int = ?)
          AND (
            c.name_ja LIKE ? OR
            c.name_en LIKE ? OR
            c.name_es LIKE ? OR
            c.name_ko LIKE ? OR
            c.name_zh LIKE ? OR
            c.name_fr LIKE ? OR
            c.name_de LIKE ? OR
            c.name_it LIKE ?
          )
        LIMIT 5
      ''', [
        cleanCardNum,
        cleanNum,
        pad3,
        intNum,
        likeParam,
        likeParam,
        likeParam,
        likeParam,
        likeParam,
        likeParam,
        likeParam,
        likeParam,
      ]);

      if (rows.isNotEmpty) {
        developer.log('Encontrada en catálogo local por nombre+número ($cleanName #$cardNumber): ${rows.first['id']}', name: 'LocalCatalogService');
        return _mapRowToCard(rows.first, language);
      }
    }

    return null;
  }

  /// Busca cartas en el catálogo local por nombre en cualquier idioma (ES, EN, JA, KO, ZH, FR, DE, IT).
  Future<List<PokemonCard>> searchByName(
    String query, {
    CardLanguage language = CardLanguage.auto,
    int limit = 20,
  }) async {
    if (!_isInitialized || _db == null) await init();
    if (_db == null) return [];

    final clean = query.trim();
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
