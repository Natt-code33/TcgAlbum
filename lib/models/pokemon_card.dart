// ============================================================
// models/pokemon_card.dart
// Modelo de datos para cartas coleccionables TCG.
// Soporta múltiples franquicias:
// - Pokémon TCG
// - Magic: The Gathering (MTG)
// - Yu-Gi-Oh!
// - Digimon Card Game
// - One Piece Card Game
// - Disney Lorcana
// - Otros TCG
// ============================================================

import 'package:flutter/material.dart';

/// Juegos TCG soportados en la aplicación.
enum TcgGame {
  all(id: 'all', label: 'Todo / Auto', iconData: Icons.public, colorHex: 0xFF00E5FF),
  pokemon(id: 'pokemon', label: 'Pokémon', iconData: Icons.bolt, colorHex: 0xFFFFB800),
  magic(id: 'magic', label: 'Magic (MTG)', iconData: Icons.auto_awesome, colorHex: 0xFFE67E22),
  yugioh(id: 'yugioh', label: 'Yu-Gi-Oh!', iconData: Icons.visibility, colorHex: 0xFF9B59B6),
  digimon(id: 'digimon', label: 'Digimon', iconData: Icons.memory, colorHex: 0xFF3498DB),
  onepiece(id: 'onepiece', label: 'One Piece', iconData: Icons.sailing, colorHex: 0xFFE74C3C),
  lorcana(id: 'lorcana', label: 'Lorcana', iconData: Icons.auto_fix_high, colorHex: 0xFF1ABC9C),
  other(id: 'other', label: 'Otro TCG', iconData: Icons.casino, colorHex: 0xFF95A5A6);

  final String id;
  final String label;
  final IconData iconData;
  final int colorHex;

  const TcgGame({
    required this.id,
    required this.label,
    required this.iconData,
    required this.colorHex,
  });

  static TcgGame fromId(String? id) {
    return TcgGame.values.firstWhere(
      (g) => g.id == id,
      orElse: () => TcgGame.pokemon,
    );
  }
}

/// Precios de mercado (Cardmarket en € y tendencias en $/€).
class CardmarketPrices {
  final double? averageSellPrice;
  final double? trendPrice;
  final double? psa10Price;

  const CardmarketPrices({
    this.averageSellPrice,
    this.trendPrice,
    this.psa10Price,
  });

  factory CardmarketPrices.fromJson(Map<String, dynamic> json) {
    return CardmarketPrices(
      averageSellPrice: (json['averageSellPrice'] as num?)?.toDouble() ??
          (json['avg'] as num?)?.toDouble(),
      trendPrice: (json['trendPrice'] as num?)?.toDouble() ??
          (json['trend'] as num?)?.toDouble(),
      psa10Price: (json['psa10Price'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'averageSellPrice': averageSellPrice,
        'trendPrice': trendPrice,
        'psa10Price': psa10Price,
      };
}

/// Modelo de un álbum de cartas (soporta múltiples álbumes).
class TcgAlbum {
  final String id;
  final String name;
  final DateTime createdAt;
  final List<PokemonCard> cards;

  TcgAlbum({
    required this.id,
    required this.name,
    DateTime? createdAt,
    List<PokemonCard>? cards,
  })  : createdAt = createdAt ?? DateTime.now(),
        cards = cards ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'cards': cards.map((c) => c.toJson()).toList(),
      };

  factory TcgAlbum.fromJson(Map<String, dynamic> json) {
    final cardsRaw = json['cards'] as List<dynamic>? ?? [];
    return TcgAlbum(
      id: json['id'] as String? ?? 'album_0',
      name: json['name'] as String? ?? 'Mi Álbum',
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      cards: cardsRaw
          .map((e) => PokemonCard.fromLocalJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  TcgAlbum copyWith({String? name}) {
    return TcgAlbum(
      id: id,
      name: name ?? this.name,
      createdAt: createdAt,
      cards: List.from(cards),
    );
  }
}

/// Estado o condición física de una carta coleccionable.
enum CardCondition {
  nm('Near Mint', 'NM', 0xFF4CAF50),
  lp('Lightly Played', 'LP', 0xFF8BC34A),
  mp('Moderately Played', 'MP', 0xFFFFC107),
  hp('Heavily Played', 'HP', 0xFFFF9800),
  graded('Graduada', 'Graded', 0xFF9C27B0);

  final String label;
  final String shortCode;
  final int colorHex;

  const CardCondition(this.label, this.shortCode, this.colorHex);

  static CardCondition? fromString(String? val) {
    if (val == null || val.isEmpty) return null;
    final lower = val.toLowerCase().trim();
    for (final c in CardCondition.values) {
      if (c.name == lower ||
          c.shortCode.toLowerCase() == lower ||
          c.label.toLowerCase() == lower) {
        return c;
      }
    }
    return null;
  }
}

/// Modelo universal para cartas de cualquier TCG en el álbum.
class PokemonCard {
  final String id;
  final String name;
  final String number;
  final String setName;
  final String imageUrl;
  final TcgGame game;
  final CardmarketPrices? cardmarketPrices;
  final double? psa10Price;
  final int? setPrintedTotal;
  final int? setTotal;
  final String? language;
  final double? purchasePrice;
  final DateTime? purchaseDate;
  final CardCondition? condition;
  final String? gradingScore;
  final int quantity;

  const PokemonCard({
    required this.id,
    required this.name,
    required this.number,
    required this.setName,
    required this.imageUrl,
    this.game = TcgGame.pokemon,
    this.cardmarketPrices,
    this.psa10Price,
    this.setPrintedTotal,
    this.setTotal,
    this.language,
    this.purchasePrice,
    this.purchaseDate,
    this.condition,
    this.gradingScore,
    this.quantity = 1,
  });

  static const double _usdToEurRate = 0.92;

  /// Verifica de forma segura si un string es una URL HTTP/HTTPS válida con host.
  static bool isValidNetworkUrl(String? url) {
    if (url == null || url.trim().isEmpty) return false;
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return false;
    return (uri.scheme == 'https' || uri.scheme == 'http') && uri.host.isNotEmpty;
  }

  /// Devuelve la URL de miniatura optimizada (~15 KB en lugar de ~200 KB)
  /// para listas y cuadrículas, reduciendo un 85% el uso de RAM y red.
  String get thumbnailImageUrl {
    if (imageUrl.isEmpty) return '';
    if (imageUrl.contains('assets.tcgdex.net') && imageUrl.endsWith('/high.webp')) {
      return '${imageUrl.substring(0, imageUrl.length - 10)}/low.webp';
    }
    if (imageUrl.contains('images.pokemontcg.io') && imageUrl.endsWith('_hires.png')) {
      return '${imageUrl.substring(0, imageUrl.length - 10)}.png';
    }
    return imageUrl;
  }

  // ──────────────────────────────────────────────────────────────
  // 1. Pokémon (TCGdex)
  // ──────────────────────────────────────────────────────────────
  factory PokemonCard.fromTcgdexSummary(
    Map<String, dynamic> json, {
    String? language,
  }) {
    final imageBase = json['image'] as String? ?? '';
    final imageUrl = imageBase.isNotEmpty ? '$imageBase/high.webp' : '';

    return PokemonCard(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Desconocido',
      number: json['localId'] as String? ?? '?',
      setName: '',
      imageUrl: imageUrl,
      game: TcgGame.pokemon,
      language: language ?? 'en',
    );
  }

  factory PokemonCard.fromTcgdexDetail(
    Map<String, dynamic> json, {
    String? language,
  }) {
    final setData = json['set'] as Map<String, dynamic>?;
    final cardCount = setData?['cardCount'] as Map<String, dynamic>?;
    final pricing = json['pricing'] as Map<String, dynamic>?;
    final cmData = pricing?['cardmarket'] as Map<String, dynamic>?;

    final imageBase = json['image'] as String? ?? '';
    final imageUrl = imageBase.isNotEmpty ? '$imageBase/high.webp' : '';

    return PokemonCard(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Desconocido',
      number: json['localId'] as String? ?? '?',
      setName: setData?['name'] as String? ?? 'Set desconocido',
      imageUrl: imageUrl,
      game: TcgGame.pokemon,
      cardmarketPrices: cmData != null
          ? CardmarketPrices(
              averageSellPrice: (cmData['avg'] as num?)?.toDouble() ??
                  (cmData['trend'] as num?)?.toDouble(),
              trendPrice: (cmData['trend'] as num?)?.toDouble(),
            )
          : null,
      setPrintedTotal: (cardCount?['official'] as num?)?.toInt(),
      setTotal: (cardCount?['total'] as num?)?.toInt(),
      language: language ?? 'en',
    );
  }

  // ──────────────────────────────────────────────────────────────
  // 1b. Pokémon (pokemontcg.io API oficial)
  // ──────────────────────────────────────────────────────────────
  factory PokemonCard.fromPokemonTcgIo(Map<String, dynamic> json) {
    final images = json['images'] as Map<String, dynamic>?;
    final img = images?['large'] as String? ??
        images?['small'] as String? ??
        '';

    final setData = json['set'] as Map<String, dynamic>?;
    final cmPrices = json['cardmarket'] as Map<String, dynamic>?;
    final cmPricesMap = cmPrices?['prices'] as Map<String, dynamic>?;

    return PokemonCard(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Carta Pokémon',
      number: json['number']?.toString() ?? '?',
      setName: setData?['name'] as String? ?? '',
      imageUrl: img,
      game: TcgGame.pokemon,
      cardmarketPrices: cmPricesMap != null
          ? CardmarketPrices(
              averageSellPrice:
                  (cmPricesMap['averageSellPrice'] as num?)?.toDouble(),
              trendPrice: (cmPricesMap['trendPrice'] as num?)?.toDouble(),
            )
          : null,
      setPrintedTotal: (setData?['printedTotal'] as num?)?.toInt(),
      setTotal: (setData?['total'] as num?)?.toInt(),
      language: 'en',
    );
  }

  // ──────────────────────────────────────────────────────────────
  // 2. Magic: The Gathering (Scryfall)
  // ──────────────────────────────────────────────────────────────
  factory PokemonCard.fromScryfall(Map<String, dynamic> json) {
    final imgUris = json['image_uris'] as Map<String, dynamic>?;
    final cardFaces = json['card_faces'] as List?;
    final faceImg =
        cardFaces?.firstOrNull?['image_uris'] as Map<String, dynamic>?;

    final img = imgUris?['normal'] as String? ??
        imgUris?['large'] as String? ??
        faceImg?['normal'] as String? ??
        '';

    final prices = json['prices'] as Map<String, dynamic>?;
    final eur = double.tryParse(prices?['eur']?.toString() ?? '');
    final eurFoil = double.tryParse(prices?['eur_foil']?.toString() ?? '');
    final usd = double.tryParse(prices?['usd']?.toString() ?? '');
    final usdInEur = usd != null
        ? double.parse((usd * _usdToEurRate).toStringAsFixed(2))
        : null;

    final effectiveAvgEur = eur ?? usdInEur;
    final effectiveTrendEur = eurFoil ?? eur ?? usdInEur;

    final printedName = json['printed_name'] as String?;
    final engName = json['name'] as String? ?? 'Carta Magic';
    final displayName = (printedName != null &&
            printedName.isNotEmpty &&
            printedName != engName)
        ? '$printedName ($engName)'
        : engName;

    return PokemonCard(
      id: 'mtg-${json['id']}',
      name: displayName,
      number: json['collector_number']?.toString() ?? '?',
      setName: json['set_name'] as String? ?? 'Magic: The Gathering',
      imageUrl: img,
      game: TcgGame.magic,
      cardmarketPrices: (effectiveAvgEur != null || effectiveTrendEur != null)
          ? CardmarketPrices(
              averageSellPrice: effectiveAvgEur,
              trendPrice: effectiveTrendEur,
            )
          : null,
      language: json['lang'] as String? ?? 'en',
    );
  }

  // ──────────────────────────────────────────────────────────────
  // 3. Yu-Gi-Oh! (YGOPRODeck)
  // ──────────────────────────────────────────────────────────────
  factory PokemonCard.fromYugioh(Map<String, dynamic> json,
      {String? language}) {
    final images = json['card_images'] as List?;
    final imgUrl = (images?.firstOrNull as Map<String, dynamic>?)?['image_url']
            as String? ??
        '';

    final sets = json['card_sets'] as List?;
    final firstSet = sets?.firstOrNull as Map<String, dynamic>?;

    final prices = json['card_prices'] as List?;
    final firstPrice = prices?.firstOrNull as Map<String, dynamic>?;
    final cmPrice = double.tryParse(
      firstPrice?['cardmarket_price']?.toString() ?? '',
    );

    return PokemonCard(
      id: 'ygo-${json['id']}',
      name: json['name'] as String? ?? 'Carta Yu-Gi-Oh!',
      number: firstSet?['set_code'] as String? ??
          json['id']?.toString() ??
          '?',
      setName: firstSet?['set_name'] as String? ?? 'Yu-Gi-Oh!',
      imageUrl: imgUrl,
      game: TcgGame.yugioh,
      cardmarketPrices:
          cmPrice != null ? CardmarketPrices(averageSellPrice: cmPrice) : null,
      language: language ?? 'en',
    );
  }

  // ──────────────────────────────────────────────────────────────
  // 4. Digimon Card Game (DigimonCard.io)
  // ──────────────────────────────────────────────────────────────
  factory PokemonCard.fromDigimon(Map<String, dynamic> json) {
    final cardId = json['id']?.toString() ?? '';
    final directImg = json['cardimage'] as String?;
    final img = (directImg != null && directImg.isNotEmpty)
        ? directImg
        : (cardId.isNotEmpty
            ? 'https://images.digimoncard.io/images/cards/$cardId.jpg'
            : '');

    final sets = json['set_name'];
    final setName = sets is List
        ? (sets.firstOrNull?.toString() ?? 'Digimon')
        : (sets?.toString() ?? 'Digimon');

    return PokemonCard(
      id: 'digi-$cardId',
      name: json['name'] as String? ?? 'Carta Digimon',
      number: cardId.isNotEmpty ? cardId : '?',
      setName: setName,
      imageUrl: img,
      game: TcgGame.digimon,
      language: 'en',
    );
  }

  // ──────────────────────────────────────────────────────────────
  // 5. One Piece Card Game (OPTCG API)
  // ──────────────────────────────────────────────────────────────
  factory PokemonCard.fromOnePiece(Map<String, dynamic> json) {
    final img = json['card_image'] as String? ?? '';
    final cardSetId = json['card_set_id'] as String? ??
        json['card_image_id'] as String? ??
        '?';
    final uniqueImageId = json['card_image_id'] as String? ?? cardSetId;
    final usdPrice = double.tryParse(json['market_price']?.toString() ?? '') ??
        double.tryParse(json['inventory_price']?.toString() ?? '');
    final eurPrice = usdPrice != null
        ? double.parse((usdPrice * _usdToEurRate).toStringAsFixed(2))
        : null;

    return PokemonCard(
      id: 'op-$uniqueImageId',
      name: json['card_name'] as String? ?? 'Carta One Piece',
      number: cardSetId,
      setName: json['set_name'] as String? ?? 'One Piece Card Game',
      imageUrl: img,
      game: TcgGame.onepiece,
      cardmarketPrices:
          eurPrice != null ? CardmarketPrices(averageSellPrice: eurPrice) : null,
      language: 'en',
    );
  }

  // ──────────────────────────────────────────────────────────────
  // 6. Disney Lorcana (Lorcana API)
  // ──────────────────────────────────────────────────────────────
  factory PokemonCard.fromLorcana(Map<String, dynamic> json) {
    final setKey = json['Set_ID'] ?? json['Set_Num'] ?? 'lor';
    final numKey = json['Card_Num'] ?? json['Name'] ?? '?';
    final uniqueId = json['Unique_ID'] ?? '$setKey-$numKey';

    return PokemonCard(
      id: 'lor-$uniqueId',
      name: json['Name'] as String? ?? 'Carta Lorcana',
      number: json['Card_Num']?.toString() ??
          json['Unique_ID']?.toString() ??
          '?',
      setName: json['Set_Name'] as String? ?? 'Disney Lorcana',
      imageUrl: json['Image'] as String? ?? '',
      game: TcgGame.lorcana,
      language: 'en',
    );
  }

  PokemonCard copyWith({
    String? id,
    String? name,
    String? number,
    String? setName,
    String? imageUrl,
    TcgGame? game,
    CardmarketPrices? cardmarketPrices,
    double? psa10Price,
    int? setPrintedTotal,
    int? setTotal,
    String? language,
    double? purchasePrice,
    DateTime? purchaseDate,
    CardCondition? condition,
    String? gradingScore,
    int? quantity,
    bool clearPsa10Price = false,
    bool clearCardmarketPrices = false,
    bool clearLanguage = false,
    bool clearPurchasePrice = false,
    bool clearPurchaseDate = false,
    bool clearCondition = false,
    bool clearGradingScore = false,
  }) {
    return PokemonCard(
      id: id ?? this.id,
      name: name ?? this.name,
      number: number ?? this.number,
      setName: setName ?? this.setName,
      imageUrl: imageUrl ?? this.imageUrl,
      game: game ?? this.game,
      cardmarketPrices: clearCardmarketPrices ? null : (cardmarketPrices ?? this.cardmarketPrices),
      psa10Price: clearPsa10Price ? null : (psa10Price ?? this.psa10Price),
      setPrintedTotal: setPrintedTotal ?? this.setPrintedTotal,
      setTotal: setTotal ?? this.setTotal,
      language: clearLanguage ? null : (language ?? this.language),
      purchasePrice: clearPurchasePrice ? null : (purchasePrice ?? this.purchasePrice),
      purchaseDate: clearPurchaseDate ? null : (purchaseDate ?? this.purchaseDate),
      condition: clearCondition ? null : (condition ?? this.condition),
      gradingScore: clearGradingScore ? null : (gradingScore ?? this.gradingScore),
      quantity: (quantity ?? this.quantity).clamp(1, 9999),
    );
  }

  PokemonCard copyWithDetail({
    String? setName,
    CardmarketPrices? cardmarketPrices,
    int? setPrintedTotal,
    int? setTotal,
    String? language,
    TcgGame? game,
    double? purchasePrice,
    DateTime? purchaseDate,
    CardCondition? condition,
    String? gradingScore,
  }) {
    return copyWith(
      setName: setName,
      cardmarketPrices: cardmarketPrices,
      setPrintedTotal: setPrintedTotal,
      setTotal: setTotal,
      language: language,
      game: game,
      purchasePrice: purchasePrice,
      purchaseDate: purchaseDate,
      condition: condition,
      gradingScore: gradingScore,
    );
  }

  // ──────────────────────────────────────────────────────────────
  // toJson / fromLocalJson
  // ──────────────────────────────────────────────────────────────
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'number': number,
        'setName': setName,
        'imageUrl': imageUrl,
        'game': game.id,
        'cardmarketPrices': cardmarketPrices?.toJson(),
        'psa10Price': psa10Price,
        'setPrintedTotal': setPrintedTotal,
        'setTotal': setTotal,
        'language': language,
        'purchasePrice': purchasePrice,
        'purchaseDate': purchaseDate?.toIso8601String(),
        'condition': condition?.name,
        'gradingScore': gradingScore,
        'quantity': quantity,
      };

  factory PokemonCard.fromJson(Map<String, dynamic> json) =>
      PokemonCard.fromLocalJson(json);

  factory PokemonCard.fromLocalJson(Map<String, dynamic> json) {
    final pricesData = json['cardmarketPrices'] as Map<String, dynamic>?;

    return PokemonCard(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Desconocido',
      number: json['number'] as String? ?? '?',
      setName: json['setName'] as String? ?? 'Set desconocido',
      imageUrl: json['imageUrl'] as String? ?? '',
      game: TcgGame.fromId(json['game'] as String?),
      cardmarketPrices:
          pricesData != null ? CardmarketPrices.fromJson(pricesData) : null,
      psa10Price: (json['psa10Price'] as num?)?.toDouble(),
      setPrintedTotal: (json['setPrintedTotal'] as num?)?.toInt(),
      setTotal: (json['setTotal'] as num?)?.toInt(),
      language: json['language'] as String?,
      purchasePrice: (json['purchasePrice'] as num?)?.toDouble(),
      purchaseDate: json['purchaseDate'] != null
          ? DateTime.tryParse(json['purchaseDate'] as String)
          : null,
      condition: CardCondition.fromString(json['condition'] as String?),
      gradingScore: json['gradingScore'] as String?,
      quantity: ((json['quantity'] as num?)?.toInt() ?? 1).clamp(1, 9999),
    );
  }

  PokemonCard copyWithPsa10(double price) {
    return copyWith(psa10Price: price);
  }
}

typedef TcgCard = PokemonCard;
