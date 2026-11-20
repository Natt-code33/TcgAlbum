import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'local_catalog_service.dart';

/// Descubre sets nuevos en TCGdex y los añade a la copia local del catálogo.
///
/// No sustituye al catálogo empaquetado: sólo inserta lo que falte. Así los
/// sets que salgan después de publicar la app aparecen sin actualizar la APK.
class CatalogSyncService {
  CatalogSyncService._();
  static final CatalogSyncService instance = CatalogSyncService._();

  static const String _base = 'https://api.tcgdex.net/v2';
  static const String _kLastSyncKey = 'tcg_catalog_sync_last';
  static const Duration _syncInterval = Duration(hours: 12);
  static const int _maxSetsPerRun = 6;

  /// Sincroniza como máximo una vez cada 12 h. `force` ignora el intervalo
  /// (botón manual de Ajustes).
  Future<int> syncIfDue({bool force = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = prefs.getInt(_kLastSyncKey) ?? 0;
    if (!force && now - last < _syncInterval.inMilliseconds) return 0;

    final added = await syncNewSets();
    if (added >= 0) {
      await prefs.setInt(_kLastSyncKey, now);
    }
    return added;
  }

  /// Devuelve cuántos sets añadió, 0 si no hay novedades y -1 si no se pudo
  /// consultar TCGdex.
  Future<int> syncNewSets() async {
    await LocalCatalogService.instance.init();

    final localIds = await LocalCatalogService.instance.allSetIds();
    final briefs = <String, Map<String, dynamic>>{};
    var reachable = false;
    for (final lang in const ['ja', 'en']) {
      final sets = await _fetchSets(lang);
      if (sets.isNotEmpty) reachable = true;
      for (final set in sets) {
        final id = (set['id'] as String?)?.toLowerCase();
        if (id == null || id.isEmpty) continue;
        briefs.putIfAbsent(id, () => set);
      }
    }
    if (!reachable) return -1;
    if (briefs.isEmpty) return 0;

    final missing = briefs.keys
        .where((id) => !localIds.contains(id))
        .take(_maxSetsPerRun)
        .toList(growable: false);
    if (missing.isEmpty) return 0;

    var added = 0;
    for (final id in missing) {
      final ja = await _fetchSet('ja', id);
      final en = await _fetchSet('en', id);
      if (ja == null && en == null) continue;

      final rows = buildRows(id, ja, en);
      if (rows == null || (rows.$1.isEmpty && rows.$2.isEmpty)) continue;
      await LocalCatalogService.instance.mergeSyncedCatalog(rows.$1, rows.$2);
      added++;
    }

    developer.log(
      'Sync TCGdex: ${missing.length} sets nuevos detectados, $added añadidos.',
      name: 'CatalogSyncService',
    );
    return added;
  }

  Future<List<Map<String, dynamic>>> _fetchSets(String lang) async {
    try {
      final response = await http
          .get(Uri.parse('$_base/$lang/sets'))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return const [];
      final decoded = jsonDecode(response.body);
      if (decoded is! List) return const [];
      return decoded.whereType<Map<String, dynamic>>().toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<Map<String, dynamic>?> _fetchSet(String lang, String id) async {
    try {
      final response = await http
          .get(Uri.parse('$_base/$lang/sets/$id'))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  /// Convierte un set de TCGdex (en uno o dos idiomas) en filas para `sets`
  /// y `cards`. Los nombres se fusionan por id de carta.
  ///
  /// Es público para poder probar el mapeo sin red ni SQLite.
  (List<Map<String, dynamic>>, List<Map<String, dynamic>>)? buildRows(
    String id,
    Map<String, dynamic>? ja,
    Map<String, dynamic>? en,
  ) {
    final base = ja ?? en;
    if (base == null) return null;

    final setCode = (base['id'] as String?) ?? id;
    final cardCount = base['cardCount'];
    final official = cardCount is Map ? (cardCount['official'] as int?) : null;
    final total = cardCount is Map ? (cardCount['total'] as int?) : null;

    final setRow = <String, dynamic>{
      'id': id.toLowerCase(),
      'name': base['name'],
      'name_ja': ja?['name'],
      'name_en': en?['name'],
      'code': setCode,
      'official_count': official,
      'total_count': total,
      'language': ja != null ? 'ja' : 'en',
    }..removeWhere((_, value) => value == null);

    final cards = <String, Map<String, dynamic>>{};
    void mergeCards(Map<String, dynamic>? detail, String lang) {
      if (detail == null) return;
      final list = detail['cards'];
      if (list is! List) return;
      final serie = detail['serie'];
      final serieId = serie is Map ? (serie['id'] as String?) : null;
      final detailSetId = (detail['id'] as String?) ?? setCode;

      for (final item in list) {
        if (item is! Map) continue;
        final cardId = (item['id'] as String?)?.toLowerCase();
        final localId = item['localId'] as String?;
        if (cardId == null || localId == null) continue;

        final row = cards.putIfAbsent(
          cardId,
          () => <String, dynamic>{
            'id': cardId,
            'set_id': id.toLowerCase(),
            'local_id': localId,
            'number_int': int.tryParse(localId.replaceAll(RegExp(r'[^0-9]'), '')),
            'total_in_set': official,
            'game': 'pokemon',
          }..removeWhere((_, value) => value == null),
        );
        row['name_$lang'] = item['name'];

        if (serieId != null) {
          row['image_url'] =
              'https://assets.tcgdex.net/$lang/$serieId/$detailSetId/'
              '${Uri.encodeComponent(localId)}/high.webp';
        }
      }
    }

    mergeCards(ja, 'ja');
    mergeCards(en, 'en');

    return ([setRow], cards.values.toList());
  }
}
