import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:dashboard_personal/services/tcg_api_service.dart';
import 'package:dashboard_personal/services/ocr_service.dart';
import 'package:dashboard_personal/models/pokemon_card.dart';

void main() {
  late TcgApiService api;

  setUp(() {
    final mockClient = MockClient((http.Request request) async {
      final url = request.url.toString();

      if (url.contains('api.tcgdex.net') && url.contains('cards')) {
        final nameParam = request.url.queryParameters['name'] ?? 'Pikachu';
        return http.Response.bytes(
          utf8.encode(
            json.encode([
              {
                'id': 'sv01-025',
                'localId': '025',
                'name': nameParam,
                'image': 'https://assets.tcgdex.net/en/sv/sv01/025',
              },
            ]),
          ),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }

      if (url.contains('api.pokemontcg.io/v2/cards')) {
        return http.Response.bytes(
          utf8.encode(
            json.encode({
              'data': [
                {
                  'id': 'base1-58',
                  'name': 'Pikachu',
                  'number': '58',
                  'set': {'name': 'Base', 'printedTotal': 102, 'total': 102},
                  'images': {'large': 'https://images.pokemontcg.io/base1/58_hires.png'},
                  'cardmarket': {
                    'prices': {'averageSellPrice': 2.50, 'trendPrice': 2.75},
                  },
                },
              ],
            }),
          ),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }

      return http.Response('[]', 200);
    });

    api = TcgApiService(client: mockClient);
  });

  test('Verify Pokemon search in English, Japanese, Korean, Chinese', () async {
    // 1. English
    final enResults = await api.searchUniversal(
      query: 'Pikachu',
      game: TcgGame.pokemon,
      language: CardLanguage.en,
    );
    expect(enResults.isNotEmpty, true);

    // 2. Japanese
    final jaPikachu = await api.searchUniversal(
      query: 'ピカチュウ',
      game: TcgGame.pokemon,
      language: CardLanguage.ja,
    );
    expect(jaPikachu.isNotEmpty, true);

    final jaCharizard = await api.searchUniversal(
      query: 'リザードン',
      game: TcgGame.pokemon,
      language: CardLanguage.ja,
    );
    expect(jaCharizard.isNotEmpty, true);

    // 3. Korean
    final koGengar = await api.searchUniversal(
      query: '팬텀',
      game: TcgGame.pokemon,
      language: CardLanguage.ko,
    );
    expect(koGengar.isNotEmpty, true);

    final koPikachu = await api.searchUniversal(
      query: '피카츄',
      game: TcgGame.pokemon,
      language: CardLanguage.ko,
    );
    expect(koPikachu.isNotEmpty, true);

    // 4. Chinese
    final zhPikachu = await api.searchUniversal(
      query: '皮卡丘',
      game: TcgGame.pokemon,
      language: CardLanguage.zh,
    );
    expect(zhPikachu.isNotEmpty, true);

    // 5. Automatic Language Detection mode (CardLanguage.auto)
    final autoJa = await api.searchUniversal(
      query: 'ピカチュウ',
      game: TcgGame.pokemon,
      language: CardLanguage.auto,
    );
    expect(autoJa.isNotEmpty, true);

    final autoKo = await api.searchUniversal(
      query: '피카츄',
      game: TcgGame.pokemon,
      language: CardLanguage.auto,
    );
    expect(autoKo.isNotEmpty, true);

    final autoZh = await api.searchUniversal(
      query: '皮卡丘',
      game: TcgGame.pokemon,
      language: CardLanguage.auto,
    );
    expect(autoZh.isNotEmpty, true);
  });

  test('Verify URL validation and copyWith clearing behavior', () {
    expect(PokemonCard.isValidNetworkUrl('https://assets.tcgdex.net/en/sv01/001/high.webp'), true);
    expect(PokemonCard.isValidNetworkUrl('http://example.com/card.jpg'), true);
    expect(PokemonCard.isValidNetworkUrl('https://'), false);
    expect(PokemonCard.isValidNetworkUrl('/data/user/0/app/secret.txt'), false);
    expect(PokemonCard.isValidNetworkUrl('file:///etc/passwd'), false);

    final card = PokemonCard(
      id: 'test-1',
      name: 'Charizard',
      number: '4/102',
      setName: 'Base Set',
      imageUrl: 'https://images.pokemontcg.io/base1/4.png',
      cardmarketPrices: const CardmarketPrices(averageSellPrice: 150.0),
      psa10Price: 5000.0,
      purchasePrice: 100.0,
      purchaseDate: DateTime(2025, 1, 1),
    );

    final cleared = card.copyWith(
      clearCardmarketPrices: true,
      clearPsa10Price: true,
      clearPurchasePrice: true,
      clearPurchaseDate: true,
    );

    expect(cleared.cardmarketPrices, isNull);
    expect(cleared.psa10Price, isNull);
    expect(cleared.purchasePrice, isNull);
    expect(cleared.purchaseDate, isNull);

    // Thumbnail URL optimization check
    const tcgCard = PokemonCard(
      id: 'sv01-001',
      name: 'Sprigatito',
      number: '001',
      setName: 'Scarlet & Violet',
      imageUrl: 'https://assets.tcgdex.net/en/sv/sv01/001/high.webp',
      quantity: 3,
    );
    expect(tcgCard.thumbnailImageUrl, 'https://assets.tcgdex.net/en/sv/sv01/001/low.webp');
    expect(tcgCard.quantity, 3);
  });
}
