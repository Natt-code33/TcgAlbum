import 'package:flutter_test/flutter_test.dart';
import 'package:dashboard_personal/models/card_number.dart';
import 'package:dashboard_personal/models/pokemon_card.dart';
import 'package:dashboard_personal/services/card_matcher.dart';

void main() {
  test('total + número empatado no auto-selecciona', () {
    final number = CardNumber.parse('025/165')!;

    final rowA = <String, dynamic>{
      'local_id': '025',
      'number_int': 25,
      'total_in_set': 165,
      'set_id': 'sv03.5',
      'set_official_count': 165,
      'name_en': 'Pikachu',
    };
    final rowB = <String, dynamic>{
      'local_id': '025',
      'number_int': 25,
      'total_in_set': 165,
      'set_id': 'sv2a',
      'set_official_count': 165,
      'name_en': 'Pikachu',
    };

    final a = ScoredCard(
      card: const _FakeCard(),
      score: CardMatcher.scoreRow(row: rowA, number: number, ocrName: 'Pikachu'),
    );
    final b = ScoredCard(
      card: const _FakeCard(),
      score: CardMatcher.scoreRow(row: rowB, number: number, ocrName: 'Pikachu'),
    );

    expect(CardMatcher.shouldAutoSelect([a, b]), isFalse);
  });

  test('un total distinto descarta la candidata', () {
    final number = CardNumber.parse('025/165')!;
    final row = <String, dynamic>{
      'local_id': '025',
      'number_int': 25,
      'total_in_set': 198,
      'set_id': 'sv01',
      'set_official_count': 198,
      'name_en': 'Pikachu',
    };
    expect(
      CardMatcher.scoreRow(row: row, number: number, ocrName: 'Pikachu'),
      0,
    );
  });

  test('un set code distinto descarta la candidata', () {
    final number = CardNumber.parse('Sv2a 025/165')!;
    final row = <String, dynamic>{
      'local_id': '025',
      'number_int': 25,
      'total_in_set': 165,
      'set_id': 'sv03.5',
      'set_official_count': 165,
      'name_en': 'Pikachu',
    };
    expect(
      CardMatcher.scoreRow(row: row, number: number, ocrName: 'Pikachu'),
      0,
    );
  });

  test('número sin set y nombre distinto descarta la candidata', () {
    // Caso real: base set Pikachu 58/102 frente a Litwick #58 de otro set.
    final number = CardNumber.parse('58/102')!;
    final row = <String, dynamic>{
      'local_id': '58',
      'number_int': 58,
      'total_in_set': 102,
      'set_id': 'nv',
      'set_official_count': 102,
      'name_en': 'Litwick',
    };
    expect(
      CardMatcher.scoreRow(row: row, number: number, ocrName: 'Pikachu LV'),
      0,
    );
  });

  test('nombre correcto con número sin set sí puntúa', () {
    final number = CardNumber.parse('58/102')!;
    final row = <String, dynamic>{
      'local_id': '58',
      'number_int': 58,
      'total_in_set': 102,
      'set_id': 'base1',
      'set_official_count': 102,
      'name_en': 'Pikachu',
    };
    final score =
        CardMatcher.scoreRow(row: row, number: number, ocrName: 'Pikachu LV');
    expect(score, greaterThan(0.80));
  });

  test('set code explícito manda aunque el nombre venga con ruido', () {
    final number = CardNumber.parse('Sv2a 025/165')!;
    final row = <String, dynamic>{
      'local_id': '025',
      'number_int': 25,
      'total_in_set': 165,
      'set_id': 'sv2a',
      'set_official_count': 165,
      'name_en': 'Pikachu',
    };
    final score = CardMatcher.scoreRow(
      row: row,
      number: number,
      ocrName: 'Pika',
    );
    expect(score, greaterThan(0.80));
  });

  test('un dígito mal leído se corrige por set + nombre exacto', () {
    // Caso real: Volcarona japonesa sv11b 104 leída como 100/086.
    final number = CardNumber.parse('SV11B 100/086')!;
    final row = <String, dynamic>{
      'local_id': '104',
      'number_int': 104,
      'total_in_set': 86,
      'set_id': 'sv11b',
      'set_official_count': 86,
      'name_ja': 'ウルガモス',
      'name_en': 'Volcarona',
    };
    final score = CardMatcher.scoreRow(
      row: row,
      number: number,
      ocrName: 'ウルガモス',
    );
    expect(score, greaterThan(0.90));
  });

  test('un número lejano no se corrige por set + nombre', () {
    final number = CardNumber.parse('SV11B 100/086')!;
    final row = <String, dynamic>{
      'local_id': '090',
      'number_int': 90,
      'total_in_set': 86,
      'set_id': 'sv11b',
      'set_official_count': 86,
      'name_ja': 'ウルガモス',
    };
    expect(
      CardMatcher.scoreRow(row: row, number: number, ocrName: 'ウルガモス'),
      0,
    );
  });
}

class _FakeCard extends PokemonCard {
  const _FakeCard()
      : super(
          id: 'fake',
          name: 'Pikachu',
          number: '025',
          setName: 'Fake',
          imageUrl: '',
        );
}
