import 'package:flutter_test/flutter_test.dart';
import 'package:dashboard_personal/services/name_matcher.dart';

void main() {
  group('nameSimilarity', () {
    test('exactos y sufijos', () {
      expect(nameSimilarity('Mew', 'Mew'), 1);
      expect(nameSimilarity('Charizard ex', 'Charizard'), 1);
      expect(nameSimilarity('Pikachu VMAX', 'Pikachu'), 1);
    });

    test('no confunde nombres cortos', () {
      expect(nameSimilarity('Mew', 'Mewtwo'), 0);
      expect(nameSimilarity('Porygon', 'Porygon2'), 0);
    });

    test('tolera un error de OCR', () {
      expect(nameSimilarity('Char1zard', 'Charizard'), greaterThan(0.8));
      expect(nameSimilarity('Gardevo1r', 'Gardevoir'), greaterThan(0.8));
    });
  });

  test('normalizeName conserva entrenadores', () {
    expect(normalizeName("Professor's Research"), 'professors research');
    expect(normalizeName('Pokémon Catcher'), 'pokemon catcher');
    expect(normalizeName('Energy Switch'), 'energy switch');
  });
}
