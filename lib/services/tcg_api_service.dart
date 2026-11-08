// ============================================================
// services/tcg_api_service.dart
// Servicio universal de consulta para juegos de cartas coleccionables:
// - Pokémon TCG (TCGdex API + Pokémon TCG API oficial pokemontcg.io)
// - Magic: The Gathering (Scryfall API con soporte multidioma)
// - Yu-Gi-Oh! (YGOPRODeck API con traducción)
// - Digimon Card Game (DigimonCard.io API)
// - One Piece Card Game (OPTCG API)
// - Disney Lorcana (Lorcana API)
// ============================================================

import 'dart:convert';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import '../models/pokemon_card.dart';
import 'ocr_service.dart';
import 'local_catalog_service.dart';

class TcgApiException implements Exception {
  final String message;
  const TcgApiException(this.message);

  @override
  String toString() => message;
}

class TcgApiService {
  static const _tcgdexBase = 'https://api.tcgdex.net/v2';
  static const _pokemonTcgIoBase = 'https://api.pokemontcg.io/v2';

  static const Map<String, String> _headers = {
    'Accept': 'application/json',
    'User-Agent': 'TcgAlbum/1.0 (Android; Flutter)',
  };

  // ──────────────────────────────────────────────────────────────────────────
  // BÚSQUEDA UNIVERSAL (Multi-TCG)
  // Cuando se selecciona un juego específico, SOLAMENTE consulta ese juego
  // para evitar confusiones de TCG.
  // ──────────────────────────────────────────────────────────────────────────
  Future<List<PokemonCard>> searchUniversal({
    required String query,
    String? number,
    TcgGame game = TcgGame.all,
    CardLanguage language = CardLanguage.auto,
  }) async {
    final cleanQuery = _extractCoreName(query);

    // ── 0. BÚSQUEDA INSTANTÁNEA EN CATÁLOGO LOCAL SQLITE (OFFLINE 1 ms) ──
    if (game == TcgGame.pokemon || game == TcgGame.all) {
      if (number != null && number.isNotEmpty) {
        final parts = number.split('/');
        final rawNumber = parts[0].trim();
        final totalInSet = parts.length > 1
            ? int.tryParse(parts[1].replaceAll(RegExp(r'[^\d]'), '').trim())
            : null;

        // Extraer set y número permitiendo prefijos directos como "TG14", "GG54", "s8a-013" o "s8a 013"
        final setMatch = RegExp(r'(?:^|\b)([A-Za-z0-9]{2,6})\s*[-–_\s]?\s*(\d{1,4})(?:/\d{1,4})?')
            .firstMatch(number.trim());
        final setCode = setMatch?.group(1);
        final cardNum = setMatch != null ? '${setMatch.group(1)}${setMatch.group(2)}' : rawNumber;

        final localCard = await LocalCatalogService.instance.findCard(
          cardName: cleanQuery.isNotEmpty ? cleanQuery : null,
          setCode: setCode,
          cardNumber: cardNum,
          totalInSet: totalInSet,
          language: language,
        );

        if (localCard != null) {
          developer.log('⚡ Carta encontrada al instante en SQLite local: ${localCard.name} (${localCard.id})', name: 'TcgApiService');
          // Enriquecer con Cardmarket prices rápidamente sin bloquear si la red falla
          try {
            final detail = await fetchCardDetail(
              localCard.id,
              lang: localCard.language ?? (language == CardLanguage.es ? 'es' : 'en'),
            ).timeout(const Duration(milliseconds: 1500));
            if (detail != null) {
              return [detail];
            }
          } catch (_) {}
          return [localCard];
        }
      }
    }

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
  // 1. POKÉMON (TCGdex multidioma + fallback pokemontcg.io oficial)
  // ──────────────────────────────────────────────────────────────────────────
  Future<List<PokemonCard>> _searchPokemonSafe(
    String query, {
    String? number,
    CardLanguage language = CardLanguage.auto,
  }) async {
    try {
      List<PokemonCard> results = [];

      // 1. PRIORIDAD MÁXIMA: Si hay número de colección (ej: "TG14/TG30", "012/028"), buscar primero por número/set
      if (number != null && number.isNotEmpty) {
        results = await searchByCollectionNumber(number, language: language);
        if (results.isNotEmpty) {
          // Si además hay un nombre detectado, ordenar/filtrar priorizando las que coincidan con el nombre
          final coreQuery = _extractCoreName(query).toLowerCase();
          if (coreQuery.isNotEmpty) {
            final matches = results.where((c) =>
                c.name.toLowerCase().contains(coreQuery) ||
                coreQuery.contains(c.name.toLowerCase())).toList();
            if (matches.isNotEmpty) {
              final rest = results.where((c) => !matches.contains(c)).toList();
              return [...matches, ...rest];
            }
          }
          return results;
        }

        // Si la búsqueda por número directo no arrojó resultados y hay nombre, probar nombre + número
        if (query.isNotEmpty) {
          results = await searchByNameAndNumber(query, number, language: language);
          if (results.isNotEmpty) return results;
        }
      }

      // 2. Solo si no hay número o no devolvió resultados, buscar por nombre
      if (query.isNotEmpty) {
        results = await searchByName(query, language: language);
      }

      // Si TCGdex no arrojó resultados o arrojó muy pocos, consultar pokemontcg.io (Base completa)
      if (results.isEmpty) {
        final translatedQuery = _translateAsianPokemonName(query);
        final ioQuery = translatedQuery.isNotEmpty ? translatedQuery : query;
        var ioResults = await _searchPokemonTcgIo(query: ioQuery, number: number);
        // Si falló con nombre + número (porque el nombre estaba mal leído), probar solo por número
        if (ioResults.isEmpty && number != null && number.isNotEmpty) {
          ioResults = await _searchPokemonTcgIo(number: number);
        }
        if (ioResults.isNotEmpty) return ioResults;
      }

      // Si las APIs remotas están caídas o no encontraron resultados, buscar en catálogo local por nombre
      if (results.isEmpty && query.isNotEmpty) {
        final localByName = await LocalCatalogService.instance.searchByName(query, language: language);
        if (localByName.isNotEmpty) return localByName;
      }

      return results;
    } catch (e) {
      developer.log('Error buscando Pokémon: $e', name: 'TcgApiService');
      return [];
    }
  }

  /// Búsqueda robusta por nombre: consulta el idioma solicitado y simultáneamente inglés
  /// para evitar que cartas en japonés, coreano, chino, etc. no aparezcan.
  Future<List<PokemonCard>> searchByName(
    String query, {
    CardLanguage language = CardLanguage.auto,
  }) async {
    final effectiveLang = _detectLanguage(query, language);
    final coreName = _extractCoreName(query);
    if (coreName.isEmpty) return [];

    final encodedName = Uri.encodeComponent(coreName);
    final targetLang = effectiveLang.apiCode == 'auto' ? 'es' : effectiveLang.apiCode;

    final urlsToTry = <String>{
      '$_tcgdexBase/$targetLang/cards?name=$encodedName',
      '$_tcgdexBase/en/cards?name=$encodedName',
    };

    if (targetLang != 'es') {
      urlsToTry.add('$_tcgdexBase/es/cards?name=$encodedName');
    }

    final allCards = <PokemonCard>[];
    final seenIds = <String>{};

    for (final urlStr in urlsToTry) {
      try {
        final res = await http.get(Uri.parse(urlStr), headers: _headers).timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          final List<dynamic> data = json.decode(res.body);
          for (final item in data) {
            final card = PokemonCard.fromTcgdexSummary(
              item as Map<String, dynamic>,
              language: targetLang,
            );
            if (!seenIds.contains(card.id)) {
              seenIds.add(card.id);
              allCards.add(card);
            }
          }
          if (allCards.isNotEmpty) break;
        }
      } catch (_) {}
    }

    // Si no encontró resultados con el nombre asiático en TCGdex, intentar traducir a inglés
    if (allCards.isEmpty) {
      final translated = _translateAsianPokemonName(coreName);
      if (translated.isNotEmpty && translated.toLowerCase() != coreName.toLowerCase()) {
        final enCards = await searchByName(translated, language: CardLanguage.en);
        if (enCards.isNotEmpty) return enCards;
      }
    }

    return allCards;
  }

  Future<List<PokemonCard>> searchByNameAndNumber(
    String pokemonName,
    String collectionNumber, {
    CardLanguage language = CardLanguage.auto,
  }) async {
    // 1. Buscar PRIMERO por número / código de set:
    // El código de set + número (ej: "s8a 012/028", "s8a-012", "012/028")
    // identifica la carta de forma unívoca y exacta.
    final numberResults = await searchByCollectionNumber(collectionNumber, language: language);
    if (numberResults.isNotEmpty) {
      // Si el nombre buscado coincide con alguna de las cartas del set, priorizarla
      final coreQuery = _extractCoreName(pokemonName).toLowerCase();
      if (coreQuery.isNotEmpty) {
        final matches = numberResults.where((c) =>
            c.name.toLowerCase().contains(coreQuery) ||
            coreQuery.contains(c.name.toLowerCase())).toList();
        if (matches.isNotEmpty) {
          final rest = numberResults.where((c) => !matches.contains(c)).toList();
          return [...matches, ...rest];
        }
      }
      return numberResults;
    }

    // 2. Si no se encontró por set/número directo, buscar por nombre
    final nameResults = await searchByName(pokemonName, language: language);
    return nameResults;
  }

  Future<List<PokemonCard>> searchByCollectionNumber(
    String collectionNumber, {
    CardLanguage language = CardLanguage.auto,
  }) async {
    final langCode = language.apiCode == 'auto' ? 'en' : language.apiCode;

    // 1. Extraer número y total del set de la fracción (ej: "113/094" o "113/94")
    final parts = collectionNumber.split('/');
    final rawFull = parts[0].trim();
    final rawDigits = rawFull.replaceAll(RegExp(r'[^\d]'), '').trim();
    final intNumber = int.tryParse(rawDigits);
    final totalInSet = parts.length > 1
        ? int.tryParse(parts[1].replaceAll(RegExp(r'[^\d]'), '').trim())
        : null;

    final candidateNumbers = <String>{rawFull};
    if (rawDigits.isNotEmpty) {
      candidateNumbers.add(rawDigits);
    }
    if (intNumber != null) {
      candidateNumbers.add(intNumber.toString());
      candidateNumbers.add(intNumber.toString().padLeft(3, '0'));
    }

    // 2. PRIORIDAD 1: Si tenemos el total del set (ej: /094 o /94), la fracción matemática
    // es la clave inequívoca del set (ej: 94 cartas en "Phantasmal Flames" me02 para Mega-Sharpedo ex).
    // Consultar primero estrictamente en el idioma elegido (ej: español) para que el nombre y set coincidan con el idioma.
    if (totalInSet != null && totalInSet > 0) {
      final setLangs = [langCode, if (langCode != 'es') 'es', if (langCode != 'en') 'en', 'ja'];
      for (final l in setLangs) {
        final setIds = await _findSetsByOfficialCount(totalInSet, lang: l);
        for (final sId in setIds.take(4)) {
          for (final numCand in candidateNumbers) {
            final directCard = await _fetchCardBySetAndNumber(sId, numCand, lang: l);
            if (directCard != null) {
              final detail = await fetchCardDetail(directCard.id, lang: l);
              return [detail ?? directCard];
            }
          }
        }
      }
    }

    // 3. PRIORIDAD 2: Prefijo explícito de set con número (ej: "TG14/TG30", "GG54/GG70", "s8a-012")
    final setWithNumberMatch = RegExp(r'(?:^|\b)([A-Za-z0-9]{2,6})\s*[-–_\s]?\s*(\d{1,4})(?:/\d{1,4})?')
        .firstMatch(collectionNumber.trim());

    if (setWithNumberMatch != null) {
      final setCode = setWithNumberMatch.group(1)!;
      final setId = setCode.toLowerCase();
      final rawNum = setWithNumberMatch.group(2)!;
      final intNum = int.tryParse(rawNum);

      final candidateNums = <String>{
        '$setCode$rawNum',
        '${setCode.toUpperCase()}$rawNum',
        rawNum,
      };
      if (intNum != null) {
        candidateNums.add(intNum.toString());
        candidateNums.add(intNum.toString().padLeft(3, '0'));
        candidateNums.add('${setCode.toUpperCase()}${intNum.toString().padLeft(2, '0')}');
      }

      // Probar prioritariamente en el idioma solicitado
      final langsToTry = [langCode, if (langCode != 'es') 'es', if (langCode != 'en') 'en', 'ja'];
      for (final l in langsToTry) {
        for (final numCandidate in candidateNums) {
          final directCard = await _fetchCardBySetAndNumber(setId, numCandidate, lang: l);
          if (directCard != null) {
            final detail = await fetchCardDetail(directCard.id, lang: l);
            return [detail ?? directCard];
          }
        }
      }
    }

    // 4. Búsqueda amplia por localId en TCGdex respetando el idioma elegido
    final allMatchedCards = <PokemonCard>[];
    final seenIds = <String>{};
    final langsToSearch = [langCode, if (langCode != 'es') 'es', if (langCode != 'en') 'en'];

    for (final l in langsToSearch) {
      for (final numCandidate in candidateNumbers) {
        final url = Uri.parse('$_tcgdexBase/$l/cards?localId=$numCandidate');
        try {
          final res = await http.get(url, headers: _headers).timeout(const Duration(seconds: 4));
          if (res.statusCode == 200) {
            final List<dynamic> data = json.decode(res.body);
            for (final item in data) {
              final card = PokemonCard.fromTcgdexSummary(
                item as Map<String, dynamic>,
                language: l,
              );
              if (!seenIds.contains(card.id)) {
                seenIds.add(card.id);
                allMatchedCards.add(card);
              }
            }
          }
        } catch (_) {}
      }
      if (allMatchedCards.isNotEmpty) break;
    }

    return allMatchedCards;
  }

  /// Consulta fallback a pokemontcg.io (Base de datos oficial completa con Cardmarket prices)
  Future<List<PokemonCard>> _searchPokemonTcgIo({
    String? query,
    String? number,
  }) async {
    try {
      final queryParts = <String>[];
      if (query != null && query.isNotEmpty) {
        queryParts.add('name:"*${query.trim()}*"');
      }
      if (number != null && number.isNotEmpty) {
        final rawNum = number.split('/')[0].replaceAll(RegExp(r'[^\d]'), '').trim();
        if (rawNum.isNotEmpty) {
          queryParts.add('number:"$rawNum"');
        }
      }

      if (queryParts.isEmpty) return [];

      final q = queryParts.join(' ');
      final url = Uri.parse('$_pokemonTcgIoBase/cards?q=${Uri.encodeComponent(q)}&pageSize=25');

      final res = await http.get(url, headers: _headers).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final Map<String, dynamic> body = json.decode(res.body);
        final List<dynamic>? data = body['data'] as List?;
        if (data != null) {
          return data
              .map((item) => PokemonCard.fromPokemonTcgIo(item as Map<String, dynamic>))
              .toList();
        }
      }
      return [];
    } catch (_) {
      return [];
    }
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
    return CardLanguage.es;
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

    // Solo recortar sufijos como V, EX, GX, VMAX si el texto contiene caracteres asiáticos (CJK/Kana/Hangul)
    // En texto latino se deben conservar porque son parte fundamental del nombre (ej: "Blaziken V", "Lugia VSTAR")
    final hasAsianChars = RegExp(r'[\u3040-\u30FF\uAC00-\uD7AF\u4E00-\u9FFF]').hasMatch(name);
    if (hasAsianChars) {
      name = name.replaceAll(
        RegExp(r'(vmax|vstar|ex|gx|break|v)$', caseSensitive: false),
        '',
      );
      name = name.replaceAll(
        RegExp(r'\b(VMAX|VSTAR|ex|EX|GX|BREAK|Prime|STAR|\bV\b)\b',
            caseSensitive: false),
        ' ',
      );
    }

    name = name.replaceAll(RegExp(r'\b\d+\b'), ' ');
    name = name.replaceAll(RegExp(r'\s+'), ' ').trim();

    return name;
  }

  static final Map<String, List<Map<String, dynamic>>> _setsCache = {};

  Future<List<String>> _findSetsByOfficialCount(int officialCount, {String lang = 'en'}) async {
    // 1. Consultar primero catálogo local SQLite si está disponible (<1 ms)
    try {
      final localSets = await LocalCatalogService.instance.findSetIdsByOfficialCount(officialCount);
      if (localSets.isNotEmpty) {
        return localSets;
      }
    } catch (_) {}

    // 2. Fallback a caché en memoria de TCGdex
    final url = Uri.parse('$_tcgdexBase/$lang/sets');
    try {
      if (!_setsCache.containsKey(lang)) {
        final response = await http.get(url, headers: _headers).timeout(const Duration(seconds: 4));
        if (response.statusCode == 200) {
          final List<dynamic> sets = json.decode(response.body);
          _setsCache[lang] = sets.whereType<Map<String, dynamic>>().toList();
        }
      }

      final cachedSets = _setsCache[lang] ?? [];
      final List<String> matching = [];
      for (final s in cachedSets) {
        final count = s['cardCount'] as Map<String, dynamic>?;
        if (count?['official'] == officialCount) {
          final id = s['id'] as String?;
          if (id != null) matching.add(id);
        }
      }
      return matching.take(4).toList();
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

  /// Traductor directo de nombres de Pokémon en Coreano, Japonés y Chino a su nombre en inglés.
  /// Permite encontrar cartas cuando el endpoint local no tiene indexado el nombre o en pokemontcg.io.
  String _translateAsianPokemonName(String name) {
    final clean = name.trim();
    if (clean.isEmpty) return '';

    // Coincidencia exacta en el diccionario multilingüe
    if (_pokemonMultilangMap.containsKey(clean)) {
      return _pokemonMultilangMap[clean]!;
    }

    // Coincidencia parcial (por ejemplo si contiene "ex", "vmax", sufijos o espacios)
    for (final entry in _pokemonMultilangMap.entries) {
      if (clean.contains(entry.key)) {
        return entry.value;
      }
    }

    return '';
  }

  static const Map<String, String> _pokemonMultilangMap = {
    // ── KOREAN (한국어) ─────────────────────────────────────────────────────────
    '피카츄': 'Pikachu',
    '라이츄': 'Raichu',
    '피츄': 'Pichu',
    '파이리': 'Charmander',
    '리자드': 'Charmeleon',
    '리자몽': 'Charizard',
    '꼬부기': 'Squirtle',
    '어니부기': 'Wartortle',
    '거북왕': 'Blastoise',
    '이상해씨': 'Bulbasaur',
    '이상해풀': 'Ivysaur',
    '이상해꽃': 'Venusaur',
    '이브이': 'Eevee',
    '샤미드': 'Vaporeon',
    '쥬피썬더': 'Jolteon',
    '부스터': 'Flareon',
    '에브이': 'Espeon',
    '블래키': 'Umbreon',
    '리피아': 'Leafeon',
    '글레이시아': 'Glaceon',
    '님피아': 'Sylveon',
    '뮤': 'Mew',
    '뮤츠': 'Mewtwo',
    '팬텀': 'Gengar',
    '고오스': 'Gastly',
    '고우스트': 'Haunter',
    '잠만보': 'Snorlax',
    '망나뇽': 'Dragonite',
    '미뇽': 'Dratini',
    '신뇽': 'Dragonair',
    '루카리오': 'Lucario',
    '리오르': 'Riolu',
    '레쿠쟈': 'Rayquaza',
    '그란돈': 'Groudon',
    '가이오가': 'Kyogre',
    '루기아': 'Lugia',
    '칠색조': 'Ho-Oh',
    '아르세우스': 'Arceus',
    '디아루가': 'Dialga',
    '펄기아': 'Palkia',
    '기라티나': 'Giratina',
    '개굴닌자': 'Greninja',
    '따라큐': 'Mimikyu',
    '모르페코': 'Morpeko',
    '잉어킹': 'Magikarp',
    '갸라도스': 'Gyarados',
    '라프라스': 'Lapras',
    '토게피': 'Togepi',
    '마릴': 'Marill',
    '우츠보트': 'Victreebel',
    '푸린': 'Jigglypuff',
    '푸크린': 'Wigglytuff',
    '냐옹': 'Meowth',
    '가디': 'Growlithe',
    '윈디': 'Arcanine',
    '알통몬': 'Machop',
    '근육몬': 'Machoke',
    '괴력몬': 'Machamp',
    '포니타': 'Ponyta',
    '날쌩마': 'Rapidash',
    '야돈': 'Slowpoke',
    '야도란': 'Slowbro',
    '팬텀 ex': 'Gengar ex',

    // ── JAPANESE (日本語 - カタカナ/漢字) ──────────────────────────────────────────
    'ピカチュウ': 'Pikachu',
    'ライチュウ': 'Raichu',
    'ピチュー': 'Pichu',
    'ヒトカゲ': 'Charmander',
    'リザード': 'Charmeleon',
    'リザードン': 'Charizard',
    'ゼニガメ': 'Squirtle',
    'カメール': 'Wartortle',
    'カメックス': 'Blastoise',
    'フシギダネ': 'Bulbasaur',
    'フシギソウ': 'Ivysaur',
    'フシギバナ': 'Venusaur',
    'イーブイ': 'Eevee',
    'シャワーズ': 'Vaporeon',
    'サンダース': 'Jolteon',
    'ブースター': 'Flareon',
    'エーフィ': 'Espeon',
    'ブラッキー': 'Umbreon',
    'リーフィア': 'Leafeon',
    'グレイシア': 'Glaceon',
    'ニンフィア': 'Sylveon',
    'ミュウ': 'Mew',
    'ミュウツー': 'Mewtwo',
    'ゲンガー': 'Gengar',
    'カビゴン': 'Snorlax',
    'カイリュー': 'Dragonite',
    'ルカリオ': 'Lucario',
    'レックウザ': 'Rayquaza',
    'グラードン': 'Groudon',
    'カイオーガ': 'Kyogre',
    'ルギア': 'Lugia',
    'ホウオウ': 'Ho-Oh',
    'アルセウス': 'Arceus',
    'ディアルガ': 'Dialga',
    'パルキア': 'Palkia',
    'ギラティナ': 'Giratina',
    'ゲッコウガ': 'Greninja',
    'ミミッキュ': 'Mimikyu',
    'コイキング': 'Magikarp',
    'ギャラドス': 'Gyarados',
    'ラプラス': 'Lapras',
    'ゼルネアス': 'Xerneas',
    'イベルタル': 'Yveltal',
    'ジガルデ': 'Zygarde',
    'レシラム': 'Reshiram',
    'ゼクロム': 'Zekrom',
    'キュレム': 'Kyurem',
    'ザシアン': 'Zacian',
    'ザマゼンタ': 'Zamazenta',
    'コライドン': 'Koraidon',
    'ミライドン': 'Miraidon',
    'トドロクツキ': 'Roaring Moon',
    'テツノブジン': 'Iron Valiant',
    'フーディン': 'Alakazam',

    // ── CHINESE (中文 - 简体/繁体) ──────────────────────────────────────────────
    '皮卡丘': 'Pikachu',
    '雷丘': 'Raichu',
    '皮丘': 'Pichu',
    '小火龙': 'Charmander',
    '小火龍': 'Charmander',
    '火恐龙': 'Charmeleon',
    '火恐龍': 'Charmeleon',
    '喷火龙': 'Charizard',
    '噴火龍': 'Charizard',
    '杰尼龟': 'Squirtle',
    '傑尼龜': 'Squirtle',
    '卡咪龟': 'Wartortle',
    '卡咪龜': 'Wartortle',
    '水箭龟': 'Blastoise',
    '水箭龜': 'Blastoise',
    '妙蛙种子': 'Bulbasaur',
    '妙蛙種子': 'Bulbasaur',
    '妙蛙草': 'Ivysaur',
    '妙蛙花': 'Venusaur',
    '伊布': 'Eevee',
    '水伊布': 'Vaporeon',
    '雷伊布': 'Jolteon',
    '火伊布': 'Flareon',
    '太阳伊布': 'Espeon',
    '太陽伊布': 'Espeon',
    '月亮伊布': 'Umbreon',
    '叶伊布': 'Leafeon',
    '葉伊布': 'Leafeon',
    '冰伊布': 'Glaceon',
    '仙子伊布': 'Sylveon',
    '梦幻': 'Mew',
    '夢幻': 'Mew',
    '超梦': 'Mewtwo',
    '超夢': 'Mewtwo',
    '耿鬼': 'Gengar',
    '卡比兽': 'Snorlax',
    '卡比獸': 'Snorlax',
    '快龙': 'Dragonite',
    '快龍': 'Dragonite',
    '路卡利欧': 'Lucario',
    '路卡利歐': 'Lucario',
    '烈空坐': 'Rayquaza',
    '固拉多': 'Groudon',
    '盖欧卡': 'Kyogre',
    '蓋歐卡': 'Kyogre',
    '洛奇亚': 'Lugia',
    '洛奇亞': 'Lugia',
    '凤王': 'Ho-Oh',
    '鳳王': 'Ho-Oh',
    '阿尔宙斯': 'Arceus',
    '阿爾宙斯': 'Arceus',
    '帝牙卢卡': 'Dialga',
    '帝牙盧卡': 'Dialga',
    '帕路奇亚': 'Palkia',
    '帕路奇亞': 'Palkia',
    '骑拉帝纳': 'Giratina',
    '騎拉帝納': 'Giratina',
    '甲贺忍蛙': 'Greninja',
    '甲賀忍蛙': 'Greninja',
    '谜拟丘': 'Mimikyu',
    '謎擬丘': 'Mimikyu',
    '鲤鱼王': 'Magikarp',
    '鯉魚王': 'Magikarp',
    '暴鲤龙': 'Gyarados',
    '暴鯉龍': 'Gyarados',
    '拉普拉斯': 'Lapras',
  };
}

