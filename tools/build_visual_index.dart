// Genera assets/data/card_hashes.json: índice dHash de todas las cartas del
// catálogo que tienen imagen. Usa EXACTAMENTE la misma firma que la app.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dashboard_personal/services/visual_signature.dart';
import 'package:http/http.dart' as http;

const int _concurrency = 40;
const Duration _timeout = Duration(seconds: 10);

final _client = http.Client();

String thumbnailUrl(String url) {
  if (url.contains('assets.tcgdex.net') && url.endsWith('/high.webp')) {
    return '${url.substring(0, url.length - 10)}/low.webp';
  }
  if (url.contains('images.pokemontcg.io') && url.endsWith('_hires.png')) {
    return url.replaceAll('_hires.png', '.png');
  }
  return url;
}

String bitsToBase64(List<bool> bits) {
  final bytes = Uint8List((bits.length + 7) ~/ 8);
  for (var i = 0; i < bits.length; i++) {
    if (bits[i]) bytes[i >> 3] |= 1 << (7 - (i % 8));
  }
  return base64Encode(bytes);
}

Future<void> main(List<String> args) async {
  final root = Directory.current.path;
  final input = File(args.isNotEmpty ? args[0] : '$root/tools/card_images.json');
  if (!input.existsSync()) {
    stderr.writeln('Falta tools/card_images.json: ejecuta export_card_images.py');
    exit(1);
  }

  final decoded = jsonDecode(await input.readAsString()) as List<dynamic>;
  final rows = decoded
      .whereType<Map<String, dynamic>>()
      .map((row) => (row['id'] as String, row['image_url'] as String))
      .where((row) => row.$2.isNotEmpty)
      .toList();
  stdout.writeln('Cartas a indexar: ${rows.length}');

  final hashes = <List<String>>[];
  var failed = 0;

  for (var start = 0; start < rows.length; start += _concurrency) {
    final chunk = rows.skip(start).take(_concurrency).toList();
    final results = await Future.wait(
      chunk.map((row) async {
        try {
          final response = await _client
              .get(Uri.parse(thumbnailUrl(row.$2)))
              .timeout(_timeout);
          if (response.statusCode != 200) return null;
          final signature = computeVisualSignature(response.bodyBytes);
          if (signature == null) return null;
          return <String>[row.$1, bitsToBase64(signature.hash)];
        } catch (_) {
          return null;
        }
      }),
    );

    for (final result in results) {
      if (result == null) {
        failed++;
      } else {
        hashes.add(result);
      }
    }
    if ((start + chunk.length) % 2000 < _concurrency) {
      stdout.writeln('  ${start + chunk.length}/${rows.length} (ok ${hashes.length})');
    }
  }

  final output = File(args.length > 1
      ? args[1]
      : '$root/assets/data/card_hashes.json');
  await output.writeAsString(
    jsonEncode({
      'version': 1,
      'count': hashes.length,
      'hashes': hashes,
    }),
  );
  stdout.writeln(
    'Índice: ${hashes.length} cartas, $failed fallos -> ${output.path} '
    '(${(await output.length()) / 1024 / 1024} MB)',
  );
  _client.close();
}
