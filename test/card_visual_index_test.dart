import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:dashboard_personal/services/card_visual_index_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('índice visual identifica la carta china por su imagen', () async {
    final photo = File('test/fixtures/togepi_cn.jpg');
    expect(photo.existsSync(), isTrue);

    final ids = await CardVisualIndexService.instance.nearest(photo, limit: 5);
    expect(ids, isNotEmpty);
    expect(ids.first, 'csm2cc-165');
  });
}
