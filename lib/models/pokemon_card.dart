// ============================================================
// models/pokemon_card.dart
// Modelo de datos exclusivo para cartas coleccionables Pokémon TCG.
// ============================================================

import 'package:flutter/material.dart';

/// Franquicia soportada (exclusivamente Pokémon TCG).
enum TcgGame {
  pokemon(id: 'pokemon', label: 'Pokémon TCG', iconData: Icons.catching_pokemon, colorHex: 0xFF38BDF8);

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

  static TcgGame fromId(String? id) => TcgGame.pokemon;
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
  nm('Near Mint', 'NM', 0xFF34D399),
  lp('Lightly Played', 'LP', 0xFF2DD4BF),
  mp('Moderately Played', 'MP', 0xFF38BDF8),
  hp('Heavily Played', 'HP', 0xFFFB7185),
  graded('Graduada', 'Graded', 0xFFA78BFA);

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
