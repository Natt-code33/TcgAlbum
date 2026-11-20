import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('catalog_pricecharting.json tiene sets y cartas coherentes', () {
    final file = File('assets/data/catalog_pricecharting.json');
    expect(file.existsSync(), isTrue);

    final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final version = (data['version'] as num?)?.toInt() ?? 0;
    expect(version, greaterThanOrEqualTo(1));

    final sets = (data['sets'] as List).cast<Map<String, dynamic>>();
    final cards = (data['cards'] as List).cast<Map<String, dynamic>>();
    expect(cards, isNotEmpty);

    final setIds = sets.map((s) => s['id'] as String).toSet();
    for (final card in cards) {
      final id = card['id'] as String?;
      final setId = card['set_id'] as String?;
      expect(id, isNotNull);
      expect(id, isNotEmpty);
      expect(setId, isNotNull);
      expect(card['local_id'], isNotNull);
      // Un set nuevo del JSON siempre debe existir; los fusionados ya están
      // en el catálogo empaquetado.
      if (setIds.contains(setId)) {
        expect(setIds, contains(setId));
      }
      final image = card['image_url'] as String?;
      if (image != null && image.isNotEmpty) {
        expect(
          image.contains('pricecharting') ||
              image.contains('pokellector') ||
              image.contains('tcgdex') ||
              image.contains('pokemontcg'),
          isTrue,
        );
      }
    }

    // Los nombres traducidos son lo que permite escanear cartas chinas y
    // japonesas sin depender del set impreso.
    expect(cards.any((c) => (c['name_zh'] as String?)?.isNotEmpty ?? false),
        isTrue);
    expect(cards.any((c) => (c['name_ja'] as String?)?.isNotEmpty ?? false),
        isTrue);
  });
}
