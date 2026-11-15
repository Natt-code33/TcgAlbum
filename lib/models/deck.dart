/// Un Mazo (deck) competitivo de Pokémon TCG.
/// Reglas estándar de juego: 60 cartas exactas, máximo 4 copias del mismo nombre
/// (excepto Energía Básica y cartas ilimitadas).
class TcgDeck {
  final String id;
  final String name;
  final String? format; // Ej: "Estándar", "Expandido", "Unlimited"
  final DateTime createdAt;
  final List<DeckCardEntry> entries;

  TcgDeck({
    required this.id,
    required this.name,
    this.format,
    DateTime? createdAt,
    List<DeckCardEntry>? entries,
  })  : createdAt = createdAt ?? DateTime.now(),
        entries = entries ?? [];

  int get totalCards => entries.fold<int>(0, (sum, e) => sum + e.quantity);

  /// Comprueba si el mazo cumple las reglas de 60 cartas del TCG competitivo.
  bool get isLegalSize => totalCards == 60;

  /// Mapa de cantidades por ID de carta.
  Map<String, int> get cardCountsById {
    final map = <String, int>{};
    for (final e in entries) {
      map[e.cardId] = (map[e.cardId] ?? 0) + e.quantity;
    }
    return map;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'format': format,
        'createdAt': createdAt.toIso8601String(),
        'entries': entries.map((e) => e.toJson()).toList(),
      };

  factory TcgDeck.fromJson(Map<String, dynamic> json) {
    final rawEntries = json['entries'] as List<dynamic>? ?? [];
    return TcgDeck(
      id: json['id'] as String? ?? 'deck_0',
      name: json['name'] as String? ?? 'Mi Mazo',
      format: json['format'] as String?,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      entries: rawEntries
          .map((e) => DeckCardEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  TcgDeck copyWith({
    String? name,
    String? format,
    List<DeckCardEntry>? entries,
  }) {
    return TcgDeck(
      id: id,
      name: name ?? this.name,
      format: format ?? this.format,
      createdAt: createdAt,
      entries: entries ?? List.from(this.entries),
    );
  }
}

/// Entrada de una carta dentro de un mazo (con cantidad de copias).
class DeckCardEntry {
  final String cardId;
  final int quantity;
  final String? cardName;
  final String? imageUrl;
  final String? setName;
  final String? number;

  const DeckCardEntry({
    required this.cardId,
    this.quantity = 1,
    this.cardName,
    this.imageUrl,
    this.setName,
    this.number,
  });

  DeckCardEntry copyWith({int? quantity}) => DeckCardEntry(
        cardId: cardId,
        quantity: quantity ?? this.quantity,
        cardName: cardName,
        imageUrl: imageUrl,
        setName: setName,
        number: number,
      );

  Map<String, dynamic> toJson() => {
        'cardId': cardId,
        'quantity': quantity,
        'cardName': cardName,
        'imageUrl': imageUrl,
        'setName': setName,
        'number': number,
      };

  factory DeckCardEntry.fromJson(Map<String, dynamic> json) {
    return DeckCardEntry(
      cardId: json['cardId'] as String? ?? '',
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      cardName: json['cardName'] as String?,
      imageUrl: json['imageUrl'] as String?,
      setName: json['setName'] as String?,
      number: json['number'] as String?,
    );
  }
}
