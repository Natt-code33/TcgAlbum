import 'package:flutter_test/flutter_test.dart';
import 'package:dashboard_personal/services/tcg_api_service.dart';
import 'package:dashboard_personal/services/ocr_service.dart';
import 'package:dashboard_personal/models/pokemon_card.dart';

void main() {
  test('Verify Pokemon search in English, Japanese, Korean, Chinese', () async {
    final api = TcgApiService();

    // 1. English
    print('Testing English: Pikachu...');
    final enResults = await api.searchUniversal(
      query: 'Pikachu',
      game: TcgGame.pokemon,
      language: CardLanguage.en,
    );
    print('  [EN] Pikachu: ${enResults.length} found. First: ${enResults.first.name}');
    expect(enResults.isNotEmpty, true);

    // 2. Japanese
    print('\nTesting Japanese: ピカチュウ (Pikachu)...');
    final jaPikachu = await api.searchUniversal(
      query: 'ピカチュウ',
      game: TcgGame.pokemon,
      language: CardLanguage.ja,
    );
    print('  [JA] ピカチュウ: ${jaPikachu.length} found. First: ${jaPikachu.first.name} (${jaPikachu.first.language})');
    expect(jaPikachu.isNotEmpty, true);

    print('Testing Japanese: リザードン (Charizard)...');
    final jaCharizard = await api.searchUniversal(
      query: 'リザードン',
      game: TcgGame.pokemon,
      language: CardLanguage.ja,
    );
    print('  [JA] リザードン: ${jaCharizard.length} found. First: ${jaCharizard.first.name}');
    expect(jaCharizard.isNotEmpty, true);

    // 3. Korean
    print('\nTesting Korean: 팬텀 (Gengar - Direct Korean Set)...');
    final koGengar = await api.searchUniversal(
      query: '팬텀',
      game: TcgGame.pokemon,
      language: CardLanguage.ko,
    );
    print('  [KO] 팬텀: ${koGengar.length} found. First: ${koGengar.first.name} (${koGengar.first.language})');
    expect(koGengar.isNotEmpty, true);

    print('Testing Korean: 피카츄 (Pikachu)...');
    final koPikachu = await api.searchUniversal(
      query: '피카츄',
      game: TcgGame.pokemon,
      language: CardLanguage.ko,
    );
    print('  [KO] 피카츄: ${koPikachu.length} found. First: ${koPikachu.first.name}');
    expect(koPikachu.isNotEmpty, true);

    print('Testing Korean: 리자몽 (Charizard)...');
    final koCharizard = await api.searchUniversal(
      query: '리자몽',
      game: TcgGame.pokemon,
      language: CardLanguage.ko,
    );
    print('  [KO] 리자몽: ${koCharizard.length} found. First: ${koCharizard.first.name}');
    expect(koCharizard.isNotEmpty, true);

    // 4. Chinese
    print('\nTesting Chinese: 皮卡丘 (Pikachu)...');
    final zhPikachu = await api.searchUniversal(
      query: '皮卡丘',
      game: TcgGame.pokemon,
      language: CardLanguage.zh,
    );
    print('  [ZH] 皮卡丘: ${zhPikachu.length} found. First: ${zhPikachu.first.name} (${zhPikachu.first.language})');
    expect(zhPikachu.isNotEmpty, true);

    print('Testing Chinese: 喷火龙 (Charizard)...');
    final zhCharizard = await api.searchUniversal(
      query: '喷火龙',
      game: TcgGame.pokemon,
      language: CardLanguage.zh,
    );
    print('  [ZH] 喷火龙: ${zhCharizard.length} found. First: ${zhCharizard.first.name}');
    expect(zhCharizard.isNotEmpty, true);

    // 5. Automatic Language Detection mode (CardLanguage.auto)
    print('\nTesting Auto-Detection with Japanese text: ピカチュウ...');
    final autoJa = await api.searchUniversal(
      query: 'ピカチュウ',
      game: TcgGame.pokemon,
      language: CardLanguage.auto,
    );
    print('  [AUTO -> JA] Found: ${autoJa.length}');
    expect(autoJa.isNotEmpty, true);

    print('Testing Auto-Detection with Korean text: 피카츄...');
    final autoKo = await api.searchUniversal(
      query: '피카츄',
      game: TcgGame.pokemon,
      language: CardLanguage.auto,
    );
    print('  [AUTO -> KO] Found: ${autoKo.length}');
    expect(autoKo.isNotEmpty, true);

    print('Testing Auto-Detection with Chinese text: 皮卡丘...');
    final autoZh = await api.searchUniversal(
      query: '皮卡丘',
      game: TcgGame.pokemon,
      language: CardLanguage.auto,
    );
    print('  [AUTO -> ZH] Found: ${autoZh.length}');
    expect(autoZh.isNotEmpty, true);
  });
}
