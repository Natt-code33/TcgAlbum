import 'package:flutter_test/flutter_test.dart';
import 'package:dashboard_personal/models/card_number.dart';

void main() {
  group('CardNumber.parse', () {
    final cases = <String, (String, String?, String?)>{
      '140/195': ('140', '195', null),
      '025/165': ('025', '165', null),
      '25/165': ('25', '165', null),
      '025 / 165': ('025', '165', null),
      '025|165': ('025', '165', null),
      'O25/165': ('025', '165', null),
      'l40/195': ('140', '195', null),
      '1O5/165': ('105', '165', null),
      '14O/195': ('140', '195', null),
      'O2S/l6S': ('025', '165', null),
      '025/16S': ('025', '165', null),
      '1B5/198': ('185', '198', null),
      '205/198': ('205', '198', null),
      '301/288': ('301', '288', null),
      '001/070': ('001', '070', null),
      '001/078': ('001', '078', null),
      '0/12/028': ('012', '028', null),
      'TG14/TG30': ('TG14', '30', null),
      'TG14/30': ('TG14', '30', null),
      'GG05/GG70': ('GG05', '70', null),
      'GG05': ('GG05', null, null),
      'SWSH001': ('SWSH001', null, null),
      'SWSH0O1': ('SWSH001', null, null),
      'SWSH025/SWSH100': ('SWSH025', '100', null),
      'SV001': ('SV001', null, null),
      'S8a 001/028': ('001', '028', 'S8a'),
      'S8a-012': ('012', null, 'S8a'),
      'SV4a 025/190': ('025', '190', 'SV4a'),
      'SV2a 025/165': ('025', '165', 'SV2a'),
      'GSv2a 025/165': ('025', '165', 'Sv2a'),
      'GSv2a025/165': ('025', '165', 'Sv2a'),
      'SV2a025/165': ('025', '165', 'SV2a'),
      'S12a 001/172': ('001', '172', 'S12a'),
      'sv-p 001/288': ('001', '288', 'sv-p'),
      'SV-P 001': ('001', null, 'SV-P'),
      'AR 025/165': ('025', '165', null),
      'AKRA 100/086': ('100', '086', null),
      'SV11B 104/086 AR': ('104', '086', 'SV11B'),
      // El OCR japonés lee el 4 del pie como "a" y la rareza AR como "A".
      '10a/086': ('104', '086', null),
      'DBB 10a/086AR': ('104', '086', null),
      'Pikachu 025/165': ('025', '165', null),
      'Ho-Oh 140/195': ('140', '195', null),
      'No. 025': ('025', null, null),
      '#025': ('025', null, null),
    };

    cases.forEach((input, expected) {
      test(input, () {
        final parsed = CardNumber.parse(input);
        expect(parsed, isNotNull, reason: input);
        expect(parsed!.localId, expected.$1, reason: input);
        expect(parsed.total, expected.$2, reason: input);
        expect(parsed.setCode, expected.$3, reason: input);
      });
    });

    test('HP/PS no son números de carta', () {
      expect(CardNumber.parse('HP 120'), isNull);
      expect(CardNumber.parse('PS 120/200'), isNull);
      expect(CardNumber.parse('SV4a'), isNull);
    });
  });
}
