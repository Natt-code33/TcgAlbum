import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/pokemon_card.dart';
import 'ocr_service.dart';

/// Servicio de catálogo local basado en SQLite preempaquetado.
/// Permite búsquedas instantáneas (<1 ms) y 100% offline de cartas y colecciones.
class LocalCatalogService {
  static final LocalCatalogService instance = LocalCatalogService._internal();
  LocalCatalogService._internal();

  Database? _db;
  bool _isInitialized = false;
  Completer<void>? _initCompleter;

  /// Inicializa la base de datos local SQLite copiándola desde assets al almacenamiento interno
  /// si no existe o si ha sido actualizada. Seguro contra concurrencia.
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

      final data = await rootBundle.load('assets/database/tcg_catalog.db');
      final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);

      // Si no existe o el tamaño es diferente (base de datos actualizada), sobreescribir
      final shouldCopy = !await file.exists() || (await file.length()) != bytes.length;
      if (shouldCopy) {
        developer.log('Actualizando catálogo SQLite local (${bytes.length} bytes)...', name: 'LocalCatalogService');
        await Directory(dirname(path)).create(recursive: true);
        await file.writeAsBytes(bytes, flush: true);
        developer.log('tcg_catalog.db copiado con éxito (${bytes.length} bytes)', name: 'LocalCatalogService');
      }

      _db = await openDatabase(path, readOnly: false);
      _isInitialized = true;
      developer.log('Base de datos SQLite local conectada con éxito.', name: 'LocalCatalogService');
      _initCompleter!.complete();
    } catch (e) {
      developer.log('Error inicializando catálogo local: $e', name: 'LocalCatalogService');
      _initCompleter!.completeError(e);
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
      final ja = (row['name_ja'] as String? ?? '').toLowerCase();
      final en = (row['name_en'] as String? ?? '').toLowerCase();
      final es = (row['name_es'] as String? ?? '').toLowerCase();
      return ja.contains(cleanName) || cleanName.contains(ja) ||
             en.contains(cleanName) || cleanName.contains(en) ||
             es.contains(cleanName) || cleanName.contains(es);
    }

    // ── 1. Búsqueda por Total del Set + Número (ej: "113/094", "113/94", "013/028") ──
    // PRIORIDAD MÁXIMA: Si tenemos el total oficial del set (/094 o /94), la fracción matemática
    // es un identificador mucho más estricto y fiable que cualquier texto o prefijo OCR confuso (ej: PLF vs me02).
    if (totalInSet != null && totalInSet > 0) {
      final rows = await _db!.rawQuery('''
        SELECT c.*, s.name as set_name_text, s.official_count as set_official_count
        FROM cards c
        LEFT JOIN sets s ON c.set_id = s.id
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
    // Solo si no hubo fracción total o si el set explícito coincide. Si hay totalInSet pero el setCode
    // no coincide con ese total (ej: PLF con total 94), se descartará para evitar colisiones erróneas.
    if (setCode != null && setCode.isNotEmpty) {
      final cleanSet = setCode.toLowerCase().trim();
      final rows = await _db!.rawQuery('''
        SELECT c.*, s.name as set_name_text, s.official_count as set_official_count
        FROM cards c
        LEFT JOIN sets s ON c.set_id = s.id
        WHERE (c.set_id = ? OR c.id LIKE ?) 
          AND (c.local_id = ? OR c.local_id = ? OR c.local_id = ? OR c.number_int = ?)
      ''', [cleanSet, '%$cleanSet%', cleanCardNum, cleanNum, pad3, intNum]);

      for (final r in rows) {
        if (totalInSet != null && totalInSet > 0) {
          final official = r['set_official_count'] as int?;
          final total = r['total_in_set'] as int?;
          if (official != null && official != totalInSet && total != null && total != totalInSet) {
            continue; // Evitar sets que no cuadran con la fracción leída
          }
        }
        if (matchesCardName(r)) {
          developer.log('Encontrada en catálogo local por set_id ($cleanSet $cardNumber): ${r['id']}', name: 'LocalCatalogService');
          return _mapRowToCard(r, language);
        }
      }
    }

    // ── 3. Búsqueda por Nombre Y Número coincidentes ──
    // IMPORTANTE: NUNCA buscar solo por número sin nombre, porque el número "121" existe en docenas de sets.
    if (cleanName != null && cleanName.isNotEmpty && (cleanNum.isNotEmpty || cleanCardNum.isNotEmpty)) {
      final rows = await _db!.rawQuery('''
        SELECT c.*, s.name as set_name_text, s.official_count as set_official_count
        FROM cards c
        LEFT JOIN sets s ON c.set_id = s.id
        WHERE (c.local_id = ? OR c.local_id = ? OR c.local_id = ? OR c.number_int = ?)
          AND (c.name_ja LIKE ? OR c.name_en LIKE ? OR c.name_es LIKE ?)
        LIMIT 5
      ''', [cleanCardNum, cleanNum, pad3, intNum, '%$cleanName%', '%$cleanName%', '%$cleanName%']);

      if (rows.isNotEmpty) {
        developer.log('Encontrada en catálogo local por nombre+número ($cleanName #$cardNumber): ${rows.first['id']}', name: 'LocalCatalogService');
        return _mapRowToCard(rows.first, language);
      }
    }

    return null;
  }

  /// Busca cartas en el catálogo local por nombre en cualquier idioma (japonés, inglés o español).
  Future<List<PokemonCard>> searchByName(
    String query, {
    CardLanguage language = CardLanguage.auto,
    int limit = 15,
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
    } else {
      orderBy = 'c.number_int ASC';
    }

    final rows = await _db!.rawQuery('''
      SELECT c.*, s.name as set_name_text, s.official_count as set_official_count
      FROM cards c
      LEFT JOIN sets s ON c.set_id = s.id
      WHERE c.name_ja LIKE ? OR c.name_en LIKE ? OR c.name_es LIKE ?
      ORDER BY $orderBy
      LIMIT ?
    ''', ['%$clean%', '%$clean%', '%$clean%', limit]);

    return rows.map((r) => _mapRowToCard(r, language)).toList();
  }

  /// Retorna los IDs de las colecciones que tienen exactamente la cantidad de cartas indicada.
  Future<List<String>> findSetIdsByOfficialCount(int officialCount) async {
    if (!_isInitialized || _db == null) await init();
    if (_db == null) return [];

    try {
      final rows = await _db!.rawQuery(
        'SELECT id FROM sets WHERE official_count = ? OR total_count = ? LIMIT 5',
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
    final setId = (row['set_id'] as String? ?? '').toLowerCase();

    // Elegir el nombre según el idioma deseado o detectado de forma rigurosa
    String chosenName;
    String chosenLang;

    if (language == CardLanguage.ja) {
      chosenName = (nameJa != null && nameJa.isNotEmpty) ? nameJa : (nameEn ?? nameEs ?? 'Carta');
      chosenLang = (nameJa != null && nameJa.isNotEmpty) ? 'ja' : 'en';
    } else if (language == CardLanguage.es) {
      chosenName = (nameEs != null && nameEs.isNotEmpty) ? nameEs : (nameEn ?? nameJa ?? 'Carta');
      chosenLang = (nameEs != null && nameEs.isNotEmpty) ? 'es' : 'en';
    } else if (language == CardLanguage.en) {
      chosenName = (nameEn != null && nameEn.isNotEmpty) ? nameEn : (nameEs ?? nameJa ?? 'Card');
      chosenLang = 'en';
    } else if (language == CardLanguage.ko) {
      chosenName = nameEn ?? nameEs ?? nameJa ?? 'Carta';
      chosenLang = 'ko';
    } else if (language == CardLanguage.zh) {
      chosenName = nameEn ?? nameEs ?? nameJa ?? 'Carta';
      chosenLang = 'zh-tw';
    } else {
      // Auto: si tiene nombre en español, preferir español; si es set japonés, japonés; si no, inglés
      if (nameEs != null && nameEs.isNotEmpty && setId != 's8a' && setId != 's12a' && setId != 'sv2a') {
        chosenName = nameEs;
        chosenLang = 'es';
      } else if (nameJa != null && nameJa.isNotEmpty && (setId == 's8a' || setId == 's12a' || setId == 'sv2a' || setId == 'sv4a')) {
        chosenName = nameJa;
        chosenLang = 'ja';
      } else {
        chosenName = nameEn ?? nameEs ?? nameJa ?? 'Carta';
        chosenLang = nameEn != null ? 'en' : (nameEs != null ? 'es' : 'ja');
      }
    }

    final setName = (row['set_name_text'] as String?) ??
        (row['set_id'] as String? ?? 'Colección').toUpperCase();

    final localId = (row['local_id'] as String?) ?? '?';
    final totalInSet = (row['total_in_set'] as int?) ?? (row['set_official_count'] as int?);
    var imageUrl = (row['image_url'] as String?) ?? '';

    // Si se desea español o inglés, sincronizar la URL de la imagen si procede
    if (chosenLang == 'es' && imageUrl.contains('/en/')) {
      imageUrl = imageUrl.replaceAll('/en/', '/es/');
    } else if (chosenLang == 'en' && imageUrl.contains('/es/')) {
      imageUrl = imageUrl.replaceAll('/es/', '/en/');
    } else if (chosenLang == 'ja' && imageUrl.contains('/en/')) {
      imageUrl = imageUrl.replaceAll('/en/', '/ja/');
    }

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
