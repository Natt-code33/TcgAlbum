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

/// Juegos TCG soportados en la aplicación.
enum TcgGame {
  all(id: 'all', label: 'Todo / Auto', icon: '🌐', colorHex: 0xFF00B4D8),
  pokemon(id: 'pokemon', label: 'Pokémon', icon: '⚡', colorHex: 0xFFFFCB05),
  magic(id: 'magic', label: 'Magic (MTG)', icon: '🔮', colorHex: 0xFFE67E22),
  yugioh(id: 'yugioh', label: 'Yu-Gi-Oh!', icon: '👁️', colorHex: 0xFF9B59B6),
  digimon(id: 'digimon', label: 'Digimon', icon: '🦖', colorHex: 0xFF3498DB),
  onepiece(id: 'onepiece', label: 'One Piece', icon: '🏴‍☠️', colorHex: 0xFFE74C3C),
  lorcana(id: 'lorcana', label: 'Lorcana', icon: '✨', colorHex: 0xFF1ABC9C),
  other(id: 'other', label: 'Otro TCG', icon: '🃏', colorHex: 0xFF95A5A6);

  final String id;
  final String label;
  final String icon;
  final int colorHex;

  const TcgGame({
    required this.id,
    required this.label,
    required this.icon,
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
  /// Precio medio en euros (Raw).
  final double? averageSellPrice;

  /// Precio tendencia.
  final double? trendPrice;

  /// Precio estimado de PSA 10.
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

/// Modelo universal para cartas de cualquier TCG en el álbum.
class PokemonCard {
  /// ID único de la carta.
  final String id;

  /// Nombre del personaje, carta o hechizo.
  final String name;

  /// Número de colección o referencia (ej. "140/195", "070/280", "LOB-005", "ST1-03").
  final String number;

  /// Nombre del set o expansión.
  final String setName;

  /// URL de la imagen en alta resolución o ruta de archivo local.
  final String imageUrl;

  /// Franquicia / Juego TCG al que pertenece la carta.
  final TcgGame game;

  /// Precios de Cardmarket (en €).
  final CardmarketPrices? cardmarketPrices;

  /// Precio PSA 10 estimado.
  final double? psa10Price;

  /// Total de cartas impresas en el set (ej: 195 en 140/195).
  final int? setPrintedTotal;
  final int? setTotal;

  /// Idioma de la carta ('en', 'es', 'ja', 'ko', 'zh-tw').
  final String? language;

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
  });

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
    final usd = double.tryParse(prices?['usd']?.toString() ?? '');

    return PokemonCard(
      id: 'mtg-${json['id']}',
      name: json['name'] as String? ?? 'Carta Magic',
      number: json['collector_number']?.toString() ?? '?',
      setName: json['set_name'] as String? ?? 'Magic: The Gathering',
      imageUrl: img,
      game: TcgGame.magic,
      cardmarketPrices: (eur != null || usd != null)
          ? CardmarketPrices(averageSellPrice: eur, trendPrice: usd)
          : null,
      language: json['lang'] as String? ?? 'en',
    );
  }

  // ──────────────────────────────────────────────────────────────
  // 3. Yu-Gi-Oh! (YGOPRODeck)
  // ──────────────────────────────────────────────────────────────
  factory PokemonCard.fromYugioh(Map<String, dynamic> json) {
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
      number: firstSet?['set_code'] as String? ?? json['id']?.toString() ?? '?',
      setName: firstSet?['set_name'] as String? ?? 'Yu-Gi-Oh!',
      imageUrl: imgUrl,
      game: TcgGame.yugioh,
      cardmarketPrices: cmPrice != null
          ? CardmarketPrices(averageSellPrice: cmPrice)
          : null,
      language: 'en',
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
    final price = double.tryParse(json['market_price']?.toString() ?? '') ??
        double.tryParse(json['inventory_price']?.toString() ?? '');

    return PokemonCard(
      id: 'op-$cardSetId',
      name: json['card_name'] as String? ?? 'Carta One Piece',
      number: cardSetId,
      setName: json['set_name'] as String? ?? 'One Piece Card Game',
      imageUrl: img,
      game: TcgGame.onepiece,
      cardmarketPrices: price != null
          ? CardmarketPrices(averageSellPrice: price)
          : null,
      language: 'en',
    );
  }

  // ──────────────────────────────────────────────────────────────
  // 6. Disney Lorcana (Lorcana API)
  // ──────────────────────────────────────────────────────────────
  factory PokemonCard.fromLorcana(Map<String, dynamic> json) {
    return PokemonCard(
      id: 'lor-${json['Unique_ID'] ?? json['Name']}',
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

  PokemonCard copyWithDetail({
    String? setName,
    CardmarketPrices? cardmarketPrices,
    int? setPrintedTotal,
    int? setTotal,
    String? language,
    TcgGame? game,
  }) {
    return PokemonCard(
      id: id,
      name: name,
      number: number,
      setName: setName ?? this.setName,
      imageUrl: imageUrl,
      game: game ?? this.game,
      cardmarketPrices: cardmarketPrices ?? this.cardmarketPrices,
      psa10Price: psa10Price,
      setPrintedTotal: setPrintedTotal ?? this.setPrintedTotal,
      setTotal: setTotal ?? this.setTotal,
      language: language ?? this.language,
    );
  }

  // ──────────────────────────────────────────────────────────────
  // toJson: serializa la carta para guardarla en SharedPreferences.
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
      };

  /// Construye una [PokemonCard] desde el JSON guardado localmente.
  factory PokemonCard.fromLocalJson(Map<String, dynamic> json) {
    final pricesData =
        json['cardmarketPrices'] as Map<String, dynamic>?;

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
    );
  }

  /// Crea una copia de la carta con el precio PSA 10 actualizado.
  PokemonCard copyWithPsa10(double price) {
    return PokemonCard(
      id: id,
      name: name,
      number: number,
      setName: setName,
      imageUrl: imageUrl,
      game: game,
      cardmarketPrices: cardmarketPrices,
      psa10Price: price,
      setPrintedTotal: setPrintedTotal,
      setTotal: setTotal,
      language: language,
    );
  }
}

/// Alias para uso universal en cualquier juego TCG.
typedef TcgCard = PokemonCard;
