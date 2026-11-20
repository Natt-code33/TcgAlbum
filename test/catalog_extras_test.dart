import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('catalog_extras.json contiene sets y cartas válidos', () {
    final file = File('assets/data/catalog_extras.json');
    expect(file.existsSync(), isTrue);

    final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final sets = (data['sets'] as List).cast<Map<String, dynamic>>();
    final cards = (data['cards'] as List).cast<Map<String, dynamic>>();

    expect(sets, isNotEmpty);
    expect(cards, isNotEmpty);

    final setIds = <String>{};
    for (final set in sets) {
      final id = set['id'] as String?;
      expect(id, isNotNull);
      expect(id, isNotEmpty);
      setIds.add(id!);
    }

    for (final card in cards) {
      expect(card['id'], isNotEmpty);
      final setId = card['set_id'] as String?;
      expect(setIds, contains(setId));
      expect(card['local_id'], isNotEmpty);
      expect(card['name_ja'], isNotEmpty);
    }

    expect(cards.any((card) => card['id'] == 's8a-g-003'), isTrue);
  });
}
