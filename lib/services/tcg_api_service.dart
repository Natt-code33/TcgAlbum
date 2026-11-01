// ============================================================
// services/tcg_api_service.dart
// Servicio universal de consulta para juegos de cartas coleccionables:
// - Pokémon TCG (TCGdex API)
// - Magic: The Gathering (Scryfall API)
// - Yu-Gi-Oh! (YGOPRODeck API)
// - Digimon Card Game (DigimonCard.io API)
// - One Piece Card Game (OPTCG API)
// - Disney Lorcana (Lorcana API)
// ============================================================

import 'dart:convert';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import '../models/pokemon_card.dart';
import 'ocr_service.dart';

class TcgApiException implements Exception {
  final String message;
  const TcgApiException(this.message);

  @override
  String toString() => message;
}

class TcgApiService {
  static const _tcgdexBase = 'https://api.tcgdex.net/v2';

  static const Map<String, String> _headers = {
    'Accept': 'application/json',
    'User-Agent': 'TcgAlbum/1.0 (Android; Flutter)',
  };

  // ──────────────────────────────────────────────────────────────────────────
  // BÚSQUEDA UNIVERSAL (Multi-TCG)
  // ──────────────────────────────────────────────────────────────────────────
  Future<List<PokemonCard>> searchUniversal({
    required String query,
    String? number,
    TcgGame game = TcgGame.all,
    CardLanguage language = CardLanguage.auto,
  }) async {
    final cleanQuery = _extractCoreName(query);

    switch (game) {
      case TcgGame.pokemon:
        return _searchPokemonSafe(cleanQuery, number: number, language: language);
      case TcgGame.magic:
        return _searchMagicSafe(cleanQuery.isNotEmpty ? cleanQuery : (number ?? ''), language: language);
      case TcgGame.yugioh:
        return _searchYugiohSafe(cleanQuery.isNotEmpty ? cleanQuery : (number ?? ''), language: language);
      case TcgGame.digimon:
        return _searchDigimonSafe(cleanQuery.isNotEmpty ? cleanQuery : (number ?? ''), language: language);
      case TcgGame.onepiece:
        return _searchOnePieceSafe(cleanQuery.isNotEmpty ? cleanQuery : (number ?? ''), language: language);
      case TcgGame.lorcana:
        return _searchLorcanaSafe(cleanQuery.isNotEmpty ? cleanQuery : (number ?? ''), language: language);
      case TcgGame.all:
      default:
        // Consulta todos los TCGs en paralelo con límite de tiempo
        final futures = <Future<List<PokemonCard>>>[
          _searchPokemonSafe(cleanQuery, number: number, language: language),
          _searchMagicSafe(cleanQuery.isNotEmpty ? cleanQuery : (number ?? ''), language: language),
          _searchYugiohSafe(cleanQuery.isNotEmpty ? cleanQuery : (number ?? ''), language: language),
          _searchDigimonSafe(cleanQuery.isNotEmpty ? cleanQuery : (number ?? ''), language: language),
          _searchOnePieceSafe(cleanQuery.isNotEmpty ? cleanQuery : (number ?? ''), language: language),
          _searchLorcanaSafe(cleanQuery.isNotEmpty ? cleanQuery : (number ?? ''), language: language),
        ];

        final resultsList = await Future.wait(futures);
        final combined = <PokemonCard>[];
        for (final list in resultsList) {
          combined.addAll(list);
        }
        return combined;
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 1. POKÉMON (TCGdex)
  // ──────────────────────────────────────────────────────────────────────────
  Future<List<PokemonCard>> _searchPokemonSafe(
    String query, {
    String? number,
    CardLanguage language = CardLanguage.auto,
  }) async {
    try {
      if (query.isNotEmpty && number != null) {
        return await searchByNameAndNumber(query, number, language: language);
      } else if (query.isNotEmpty) {
        return await searchByName(query, language: language);
      } else if (number != null) {
        return await searchByCollectionNumber(number, language: language);
      }
      return [];
    } catch (e) {
      developer.log('Error buscando Pokémon: $e', name: 'TcgApiService');
      return [];
    }
  }

  Future<List<PokemonCard>> searchByName(
    String query, {
    CardLanguage language = CardLanguage.auto,
  }) async {
    final effectiveLang = _detectLanguage(query, language);
    final coreName = _extractCoreName(query);
    if (coreName.isEmpty) return [];

    final encodedName = Uri.encodeComponent(coreName);
    final langCode =
        effectiveLang.apiCode == 'auto' ? 'en' : effectiveLang.apiCode;
    final url = Uri.parse('$_tcgdexBase/$langCode/cards?name=$encodedName');

    try {
      final res = await http.get(url, headers: _headers).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final List<dynamic> data = json.decode(res.body);
        final cards = data
            .map((item) => PokemonCard.fromTcgdexSummary(
                  item as Map<String, dynamic>,
                  language: langCode,
                ))
            .toList();

        if (cards.isNotEmpty) return cards;
      }

      if (langCode != 'en') {
        final fallbackUrl =
            Uri.parse('$_tcgdexBase/en/cards?name=$encodedName');
        final fallbackRes = await http.get(fallbackUrl, headers: _headers).timeout(const Duration(seconds: 4));
        if (fallbackRes.statusCode == 200) {
          final List<dynamic> data = json.decode(fallbackRes.body);
          return data
              .map((item) => PokemonCard.fromTcgdexSummary(
                    item as Map<String, dynamic>,
                    language: 'en',
                  ))
              .toList();
        }
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<List<PokemonCard>> searchByNameAndNumber(
    String pokemonName,
    String collectionNumber, {
    CardLanguage language = CardLanguage.auto,
  }) async {
    final nameResults =
        await searchByName(pokemonName, language: language);
    final parts = collectionNumber.split('/');
    final rawNumber = parts[0].replaceAll(RegExp(r'[^\d]'), '').trim();
    final intNumber = int.tryParse(rawNumber);
    final totalInSet = parts.length > 1 ? int.tryParse(parts[1].trim()) : null;

    final exactMatches = <PokemonCard>[];
    final otherResults = <PokemonCard>[];

    for (final card in nameResults) {
      final cardRaw = card.number.replaceAll(RegExp(r'[^\d]'), '').trim();
      final cardInt = int.tryParse(cardRaw);

      if (card.number == collectionNumber ||
          card.number == rawNumber ||
          (intNumber != null && cardInt == intNumber)) {
        if (totalInSet != null && card.setPrintedTotal == totalInSet) {
          exactMatches.insert(0, card);
        } else {
          exactMatches.add(card);
        }
      } else {
        otherResults.add(card);
      }
    }

    if (exactMatches.isNotEmpty) {
      final detail = await fetchCardDetail(
        exactMatches.first.id,
        lang: exactMatches.first.language ?? 'en',
      );
      final finalFirst = detail ?? exactMatches.first;
      final remainingExact =
          exactMatches.skip(1).toList();
      return [finalFirst, ...remainingExact, ...otherResults];
    }

    if (nameResults.isEmpty && rawNumber.isNotEmpty) {
      return searchByCollectionNumber(collectionNumber, language: language);
    }

    return nameResults;
  }

  Future<List<PokemonCard>> searchByCollectionNumber(
    String collectionNumber, {
    CardLanguage language = CardLanguage.auto,
  }) async {
    final parts = collectionNumber.split('/');
    final rawNumber = parts[0].trim();
    final intNumber = int.tryParse(rawNumber.replaceAll(RegExp(r'[^\d]'), ''));
    final totalInSet = parts.length > 1
        ? int.tryParse(parts[1].replaceAll(RegExp(r'[^\d]'), '').trim())
        : null;

    if (rawNumber.isEmpty) return [];

    final langCode =
        language.apiCode == 'auto' ? 'en' : language.apiCode;

    final candidateNumbers = <String>{rawNumber};
    if (intNumber != null) {
      candidateNumbers.add(intNumber.toString());
      candidateNumbers.add(intNumber.toString().padLeft(3, '0'));
    }

    final allMatchedCards = <PokemonCard>[];
    final seenIds = <String>{};

    for (final numCandidate in candidateNumbers) {
      final url =
          Uri.parse('$_tcgdexBase/$langCode/cards?localId=$numCandidate');

      try {
        final res = await http.get(url, headers: _headers).timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          final List<dynamic> data = json.decode(res.body);
          for (final item in data) {
            final card = PokemonCard.fromTcgdexSummary(
              item as Map<String, dynamic>,
              language: langCode,
            );
            if (!seenIds.contains(card.id)) {
              seenIds.add(card.id);
              allMatchedCards.add(card);
            }
          }
        }
      } catch (_) {}
    }

    if (totalInSet != null) {
      final setIds = await _findSetsByOfficialCount(totalInSet, lang: langCode);
      PokemonCard? exactMatch;
      for (final card in allMatchedCards) {
        if (setIds.any((sId) => card.id.startsWith('$sId-'))) {
          exactMatch = card;
          break;
        }
      }

      if (exactMatch == null && setIds.isNotEmpty) {
        for (final sId in setIds) {
          final directCard =
              await _fetchCardBySetAndNumber(sId, rawNumber, lang: langCode);
          if (directCard != null) {
            exactMatch = directCard;
            break;
          }
        }
      }

      if (exactMatch != null) {
        final detail = await fetchCardDetail(exactMatch.id, lang: langCode);
        final finalCard = detail ?? exactMatch;
        final others =
            allMatchedCards.where((c) => c.id != exactMatch!.id).toList();
        return [finalCard, ...others];
      }
    }

    if (allMatchedCards.isEmpty && langCode != 'en') {
      return searchByCollectionNumber(collectionNumber,
          language: CardLanguage.en);
    }

    return allMatchedCards;
  }

  Future<PokemonCard?> fetchCardDetail(String cardId, {String lang = 'en'}) async {
    final url = Uri.parse('$_tcgdexBase/$lang/cards/$cardId');
    try {
      final response = await http.get(url, headers: _headers).timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) {
        if (lang != 'en') {
          final fallbackUrl = Uri.parse('$_tcgdexBase/en/cards/$cardId');
          final fallbackRes = await http.get(fallbackUrl, headers: _headers).timeout(const Duration(seconds: 4));
          if (fallbackRes.statusCode == 200) {
            final Map<String, dynamic> data = json.decode(fallbackRes.body);
            return PokemonCard.fromTcgdexDetail(data, language: 'en');
          }
        }
        return null;
      }

      final Map<String, dynamic> data = json.decode(response.body);
      return PokemonCard.fromTcgdexDetail(data, language: lang);
    } catch (_) {
      return null;
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 2. MAGIC: THE GATHERING (Scryfall API)
  // ──────────────────────────────────────────────────────────────────────────
  Future<List<PokemonCard>> _searchMagicSafe(
    String query, {
    CardLanguage language = CardLanguage.auto,
  }) async {
    final clean = query.trim();
    if (clean.isEmpty) return [];

    final isNumeric = RegExp(r'^\d+$').hasMatch(clean);

    String langFilter = '';
    switch (language) {
      case CardLanguage.es:
        langFilter = 'lang:es';
        break;
      case CardLanguage.ja:
        langFilter = 'lang:ja';
        break;
      case CardLanguage.ko:
        langFilter = 'lang:ko';
        break;
      case CardLanguage.zh:
        langFilter = '(lang:zhs or lang:zht)';
        break;
      case CardLanguage.en:
        langFilter = 'lang:en';
        break;
      case CardLanguage.auto:
        if (RegExp(r'[\u3040-\u30FF]').hasMatch(clean)) {
          langFilter = 'lang:ja';
        } else if (RegExp(r'[\uAC00-\uD7AF]').hasMatch(clean)) {
          langFilter = 'lang:ko';
        } else if (RegExp(r'[\u4E00-\u9FFF]').hasMatch(clean)) {
          langFilter = '(lang:zhs or lang:zht)';
        } else {
          langFilter = 'lang:any';
        }
        break;
    }

    String scryfallQuery = isNumeric ? 'number:$clean' : clean;
    if (langFilter.isNotEmpty) {
      scryfallQuery = '$scryfallQuery $langFilter';
    }

    final url = Uri.parse(
      'https://api.scryfall.com/cards/search?q=${Uri.encodeComponent(scryfallQuery)}',
    );

    try {
      final res = await http.get(
        url,
        headers: {
          'User-Agent': 'TcgAlbum/1.0',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final Map<String, dynamic> body = json.decode(res.body);
        final List<dynamic>? data = body['data'] as List?;
        if (data != null && data.isNotEmpty) {
          return data
              .take(25)
              .map((item) =>
                  PokemonCard.fromScryfall(item as Map<String, dynamic>))
              .toList();
        }
      }

      // Si no hubo resultados con el filtro específico de idioma, reintentar con lang:any
      if (langFilter != 'lang:any') {
        final fallbackQuery = isNumeric ? 'number:$clean' : '$clean lang:any';
        final fallbackUrl = Uri.parse(
          'https://api.scryfall.com/cards/search?q=${Uri.encodeComponent(fallbackQuery)}',
        );
        final fallbackRes = await http.get(fallbackUrl, headers: {
          'User-Agent': 'TcgAlbum/1.0',
          'Accept': 'application/json',
        }).timeout(const Duration(seconds: 4));

        if (fallbackRes.statusCode == 200) {
          final Map<String, dynamic> body = json.decode(fallbackRes.body);
          final List<dynamic>? data = body['data'] as List?;
          if (data != null) {
            return data
                .take(25)
                .map((item) =>
                    PokemonCard.fromScryfall(item as Map<String, dynamic>))
                .toList();
          }
        }
      }
      return [];
    } catch (e) {
      developer.log('Error buscando Magic: $e', name: 'TcgApiService');
      return [];
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 3. YU-GI-OH! (YGOPRODeck API)
  // ──────────────────────────────────────────────────────────────────────────
  Future<List<PokemonCard>> _searchYugiohSafe(
    String query, {
    CardLanguage language = CardLanguage.auto,
  }) async {
    final clean = query.trim();
    if (clean.isEmpty) return [];

    final isPasscode = RegExp(r'^\d{7,8}$').hasMatch(clean);
    final langParam = language == CardLanguage.es ? '&language=es' : '';

    final url = isPasscode
        ? Uri.parse('https://db.ygoprodeck.com/api/v7/cardinfo.php?id=$clean$langParam')
        : Uri.parse(
            'https://db.ygoprodeck.com/api/v7/cardinfo.php?fname=${Uri.encodeComponent(clean)}$langParam');

    try {
      final res = await http.get(url, headers: _headers).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final Map<String, dynamic> body = json.decode(res.body);
        final List<dynamic>? data = body['data'] as List?;
        if (data != null && data.isNotEmpty) {
          return data
              .take(25)
              .map((item) => PokemonCard.fromYugioh(
                    item as Map<String, dynamic>,
                    language: language.apiCode,
                  ))
              .toList();
        }
      }

      // Si no encuentra con el parámetro de idioma, reintentar sin él (inglés / universal)
      if (langParam.isNotEmpty) {
        final fallbackUrl = isPasscode
            ? Uri.parse('https://db.ygoprodeck.com/api/v7/cardinfo.php?id=$clean')
            : Uri.parse(
                'https://db.ygoprodeck.com/api/v7/cardinfo.php?fname=${Uri.encodeComponent(clean)}');
        final fallbackRes = await http.get(fallbackUrl, headers: _headers).timeout(const Duration(seconds: 4));
        if (fallbackRes.statusCode == 200) {
          final Map<String, dynamic> body = json.decode(fallbackRes.body);
          final List<dynamic>? data = body['data'] as List?;
          if (data != null) {
            return data
                .take(25)
                .map((item) => PokemonCard.fromYugioh(
                      item as Map<String, dynamic>,
                      language: 'en',
                    ))
                .toList();
          }
        }
      }
      return [];
    } catch (e) {
      developer.log('Error buscando Yu-Gi-Oh!: $e', name: 'TcgApiService');
      return [];
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 4. DIGIMON CARD GAME (DigimonCard.io API)
  // ──────────────────────────────────────────────────────────────────────────
  Future<List<PokemonCard>> _searchDigimonSafe(
    String query, {
    CardLanguage language = CardLanguage.auto,
  }) async {
    final clean = query.trim();
    if (clean.isEmpty) return [];

    // Si tiene formato de set (ej: ST1-03, BT4-008, EX8-038)
    final isCardCode = RegExp(r'^[A-Za-z0-9]{2,6}[-–]\d{1,4}$').hasMatch(clean);
    final url = isCardCode
        ? Uri.parse(
            'https://digimoncard.io/api-public/search.php?card=${Uri.encodeComponent(clean)}')
        : Uri.parse(
            'https://digimoncard.io/api-public/search.php?n=${Uri.encodeComponent(clean)}');

    try {
      final res = await http.get(url, headers: _headers).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final dynamic decoded = json.decode(res.body);
        if (decoded is List) {
          return decoded
              .take(25)
              .map((item) =>
                  PokemonCard.fromDigimon(item as Map<String, dynamic>))
              .toList();
        }
      }
      return [];
    } catch (e) {
      developer.log('Error buscando Digimon: $e', name: 'TcgApiService');
      return [];
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 5. ONE PIECE CARD GAME (OPTCG API)
  // ──────────────────────────────────────────────────────────────────────────
  Future<List<PokemonCard>> _searchOnePieceSafe(
    String query, {
    CardLanguage language = CardLanguage.auto,
  }) async {
    final clean = query.trim();
    if (clean.isEmpty) return [];

    final isSetId = RegExp(r'^[A-Za-z0-9]{2,6}[-–]\d{1,4}$').hasMatch(clean);
    final url = isSetId
        ? Uri.parse('https://optcgapi.com/api/sets/card/${Uri.encodeComponent(clean)}/')
        : Uri.parse('https://optcgapi.com/api/sets/filtered/?card_name=${Uri.encodeComponent(clean)}');

    try {
      final res = await http.get(url, headers: _headers).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final dynamic decoded = json.decode(res.body);
        if (decoded is List) {
          return decoded
              .take(25)
              .map((item) =>
                  PokemonCard.fromOnePiece(item as Map<String, dynamic>))
              .toList();
        } else if (decoded is Map<String, dynamic>) {
          return [PokemonCard.fromOnePiece(decoded)];
        }
      }
      return [];
    } catch (e) {
      developer.log('Error buscando One Piece: $e', name: 'TcgApiService');
      return [];
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 6. DISNEY LORCANA (Lorcana API)
  // ──────────────────────────────────────────────────────────────────────────
  Future<List<PokemonCard>> _searchLorcanaSafe(
    String query, {
    CardLanguage language = CardLanguage.auto,
  }) async {
    final clean = query.trim();
    if (clean.isEmpty) return [];

    final url = Uri.parse(
      'https://api.lorcana-api.com/cards/fetch?name=${Uri.encodeComponent(clean)}',
    );

    try {
      final res = await http.get(url, headers: _headers).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final dynamic decoded = json.decode(res.body);
        if (decoded is List) {
          return decoded
              .take(20)
              .map((item) =>
                  PokemonCard.fromLorcana(item as Map<String, dynamic>))
              .toList();
        }
      }
      return [];
    } catch (e) {
      developer.log('Error buscando Lorcana: $e', name: 'TcgApiService');
      return [];
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // UTILIDADES
  // ──────────────────────────────────────────────────────────────────────────
  CardLanguage _detectLanguage(String text, CardLanguage userSelected) {
    if (userSelected != CardLanguage.auto) return userSelected;
    if (RegExp(r'[\uAC00-\uD7AF]').hasMatch(text)) return CardLanguage.ko;
    if (RegExp(r'[\u3040-\u30FF]').hasMatch(text)) return CardLanguage.ja;
    if (RegExp(r'[\u4E00-\u9FFF]').hasMatch(text)) return CardLanguage.zh;
    return CardLanguage.en;
  }

  String _extractCoreName(String input) {
    var name = input.replaceAll(RegExp(r'["״“”«»' "'" r']'), ' ').trim();
    name = name.replaceAll(RegExp(r'\b\d{1,4}/\d{1,4}\b'), ' ');
    name = name.replaceAll(RegExp(r'#\d+\b'), ' ');

    name = name.replaceAll(
      RegExp(r'\b(pok[eé]mon\s+)?(b[aá]sico|g[aá]sico|c[aá]sico|p[aá]sico|fase\s*\d*|stage\s*\d*|basic|creature|instant|sorcery|trap|spell|monster)\b',
          caseSensitive: false),
      ' ',
    );

    name = name.replaceAll(RegExp(r'(たね|1進化|2進化|기본|1진화|2진화|基础|1阶进化|2阶进化)'), ' ');

    name = name.replaceAll(
      RegExp(r'(vmax|vstar|ex|gx|break|v)$', caseSensitive: false),
      '',
    );
    name = name.replaceAll(
      RegExp(r'\b(VMAX|VSTAR|ex|EX|GX|BREAK|Prime|STAR|\bV\b)\b',
          caseSensitive: false),
      ' ',
    );

    name = name.replaceAll(RegExp(r'\b\d+\b'), ' ');
    name = name.replaceAll(RegExp(r'\s+'), ' ').trim();

    return name;
  }

  Future<List<String>> _findSetsByOfficialCount(int officialCount, {String lang = 'en'}) async {
    final url = Uri.parse('$_tcgdexBase/$lang/sets');
    try {
      final response = await http.get(url, headers: _headers).timeout(const Duration(seconds: 4));
      if (response.statusCode != 200) return [];

      final List<dynamic> sets = json.decode(response.body);
      final List<String> matching = [];
      for (final s in sets) {
        if (s is Map<String, dynamic>) {
          final count = s['cardCount'] as Map<String, dynamic>?;
          if (count?['official'] == officialCount) {
            final id = s['id'] as String?;
            if (id != null) matching.add(id);
          }
        }
      }
      return matching;
    } catch (_) {
      return [];
    }
  }

  Future<PokemonCard?> _fetchCardBySetAndNumber(
      String setId, String number, {String lang = 'en'}) async {
    final url = Uri.parse('$_tcgdexBase/$lang/sets/$setId/$number');
    try {
      final response = await http.get(url, headers: _headers).timeout(const Duration(seconds: 4));
      if (response.statusCode != 200) return null;

      final Map<String, dynamic> data = json.decode(response.body);
      return PokemonCard.fromTcgdexDetail(data, language: lang);
    } catch (_) {
      return null;
    }
  }
}
