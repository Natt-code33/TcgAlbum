import 'package:flutter_test/flutter_test.dart';
import 'package:dashboard_personal/services/catalog_sync_service.dart';

void main() {
  test('buildRows fusiona ja/en y construye filas válidas', () {
    final ja = <String, dynamic>{
      'id': 'TEST1',
      'name': 'テストセット',
      'cardCount': {'official': 2, 'total': 3},
      'serie': {'id': 'T'},
      'cards': [
        {'id': 'TEST1-001', 'localId': '001', 'name': 'ピカチュウ'},
        {'id': 'TEST1-002', 'localId': '002', 'name': 'ライチュウ'},
      ],
    };
    final en = <String, dynamic>{
      'id': 'TEST1',
      'name': 'Test Set',
      'cardCount': {'official': 2, 'total': 3},
      'serie': {'id': 'T'},
      'cards': [
        {'id': 'TEST1-001', 'localId': '001', 'name': 'Pikachu'},
        {'id': 'TEST1-002', 'localId': '002', 'name': 'Raichu'},
      ],
    };

    final rows = CatalogSyncService.instance.buildRows('test1', ja, en);
    expect(rows, isNotNull);

    final sets = rows!.$1;
    final cards = rows.$2;
    expect(sets, hasLength(1));
    expect(sets.single['id'], 'test1');
    expect(sets.single['name_ja'], 'テストセット');
    expect(sets.single['name_en'], 'Test Set');
    expect(sets.single['official_count'], 2);
    expect(cards, hasLength(2));

    final first = cards.firstWhere((card) => card['local_id'] == '001');
    expect(first['name_ja'], 'ピカチュウ');
    expect(first['name_en'], 'Pikachu');
    expect(first['number_int'], 1);
    expect(first['total_in_set'], 2);
    expect(first['image_url'], contains('/T/TEST1/001/high.webp'));
  });

  test('buildRows funciona con un solo idioma', () {
    final ja = <String, dynamic>{
      'id': 'TEST2',
      'name': 'セット',
      'cardCount': {'official': 1, 'total': 1},
      'serie': {'id': 'T'},
      'cards': [
        {'id': 'TEST2-001', 'localId': '001', 'name': 'フシギダネ'},
      ],
    };
    final rows = CatalogSyncService.instance.buildRows('test2', ja, null);
    expect(rows, isNotNull);
    expect(rows!.$1.single['name_en'], isNull);
    expect(rows.$2.single['name_ja'], 'フシギダネ');
    expect(rows.$2.single['name_en'], isNull);
  });
}
