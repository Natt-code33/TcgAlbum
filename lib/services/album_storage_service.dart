// ============================================================
// services/album_storage_service.dart
// Servicio de persistencia local del álbum.
// Usa SharedPreferences para serializar la lista de cartas
// como JSON; así el álbum sobrevive al cierre de la app.
// ============================================================

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/pokemon_card.dart';

class AlbumStorageService {
  /// Clave bajo la que se guarda el álbum en SharedPreferences.
  static const _kAlbumKey = 'pokemon_album';

  /// Devuelve la lista de cartas guardadas localmente.
  Future<List<PokemonCard>> loadAlbum() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kAlbumKey);
    if (raw == null) return [];

    // Desserializamos el JSON guardado como string.
    final List<dynamic> decoded = json.decode(raw);
    return decoded
        .map((e) => PokemonCard.fromLocalJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Guarda la lista completa de cartas en SharedPreferences.
  Future<void> saveAlbum(List<PokemonCard> cards) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = json.encode(cards.map((c) => c.toJson()).toList());
    await prefs.setString(_kAlbumKey, encoded);
  }

  /// Añade una carta al álbum (carga, inserta y vuelve a guardar).
  Future<void> addCard(PokemonCard card) async {
    final album = await loadAlbum();
    // Evita duplicados por ID.
    if (album.any((c) => c.id == card.id)) return;
    album.add(card);
    await saveAlbum(album);
  }

  /// Alias de addCard para consistencia.
  Future<void> saveCard(PokemonCard card) => addCard(card);

  /// Actualiza una carta existente en el álbum (por su ID).
  Future<void> updateCard(PokemonCard updatedCard) async {
    final album = await loadAlbum();
    final index = album.indexWhere((c) => c.id == updatedCard.id);
    if (index != -1) {
      album[index] = updatedCard;
      await saveAlbum(album);
    }
  }

  /// Elimina una carta del álbum por su ID.
  Future<void> removeCard(String cardId) async {
    final album = await loadAlbum();
    album.removeWhere((c) => c.id == cardId);
    await saveAlbum(album);
  }
}
