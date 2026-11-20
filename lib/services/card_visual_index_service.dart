import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'visual_signature.dart';

/// Índice local de dHash de las cartas del catálogo.
///
/// Generado por tools/build_visual_index.dart con la MISMA firma que usa la
/// app. Permite encontrar candidatas aunque el OCR no lea nombre ni número.
class CardVisualIndexService {
  CardVisualIndexService._();
  static final CardVisualIndexService instance = CardVisualIndexService._();

  static const String _asset = 'assets/data/card_hashes.json';

  static final List<int> _popcount = List<int>.generate(256, (value) {
    var current = value;
    var count = 0;
    while (current > 0) {
      count += current & 1;
      current >>= 1;
    }
    return count;
  });

  List<String> _ids = const <String>[];
  List<Uint8List> _hashes = const <Uint8List>[];
  Map<String, Uint8List> _byId = const <String, Uint8List>{};
  Future<void>? _loading;

  bool get isReady => _ids.isNotEmpty;

  Future<void> init() {
    if (_ids.isNotEmpty) return Future.value();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    try {
      final raw = await rootBundle.loadString(_asset);
      final decoded = jsonDecode(raw);
      final rows = decoded['hashes'] as List<dynamic>;
      final ids = <String>[];
      final hashes = <Uint8List>[];
      for (final row in rows) {
        final id = row[0] as String?;
        final encoded = row[1] as String?;
        if (id == null || encoded == null) continue;
        final bytes = base64.decode(encoded);
        if (bytes.length != 32) continue;
        ids.add(id);
        hashes.add(Uint8List.fromList(bytes));
      }
      _ids = ids;
      _hashes = hashes;
      _byId = Map<String, Uint8List>.fromIterables(ids, hashes);
    } catch (_) {
      _ids = const <String>[];
      _hashes = const <Uint8List>[];
      _byId = const <String, Uint8List>{};
    }
  }

  Future<Uint8List?> _signatureOf(File photo) async {
    try {
      final visual = computeVisualSignature(await photo.readAsBytes());
      if (visual == null) return null;
      final packed = Uint8List(32);
      for (var i = 0; i < visual.hash.length; i++) {
        if (visual.hash[i]) packed[i >> 3] |= 1 << (7 - (i % 8));
      }
      return packed;
    } catch (_) {
      return null;
    }
  }

  /// Distancia Hamming de la foto a cada una de las cartas dadas.
  /// 0 = imagen idéntica (mismo arte impreso).
  Future<Map<String, int>> distances(
    File photo,
    Iterable<String> ids,
  ) async {
    await init();
    final signature = await _signatureOf(photo);
    if (signature == null) return <String, int>{};
    final result = <String, int>{};
    for (final id in ids) {
      final hash = _byId[id];
      if (hash == null) continue;
      var distance = 0;
      for (var i = 0; i < 32; i++) {
        distance += _popcount[hash[i] ^ signature[i]];
      }
      result[id] = distance;
    }
    return result;
  }

  /// IDs de las cartas visualmente más parecidas a la foto, ordenadas por
  /// distancia Hamming (menor primero).
  Future<List<String>> nearest(File photo, {int limit = 12}) async {
    await init();
    if (_ids.isEmpty) return const <String>[];

    final signature = await _signatureOf(photo);
    if (signature == null) return const <String>[];

    final best = List<int>.filled(limit, 0xffff);
    final bestIds = List<String>.filled(limit, '');
    for (var index = 0; index < _hashes.length; index++) {
      final hash = _hashes[index];
      var distance = 0;
      for (var i = 0; i < 32; i++) {
        distance += _popcount[hash[i] ^ signature[i]];
      }
      if (distance >= best[limit - 1]) continue;
      var pos = limit - 1;
      while (pos > 0 && distance < best[pos - 1]) {
        best[pos] = best[pos - 1];
        bestIds[pos] = bestIds[pos - 1];
        pos--;
      }
      best[pos] = distance;
      bestIds[pos] = _ids[index];
    }
    return bestIds.where((id) => id.isNotEmpty).toList(growable: false);
  }
}
