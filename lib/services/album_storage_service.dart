// ============================================================
// services/album_storage_service.dart
// Servicio de persistencia local con soporte para múltiples álbumes.
// Usa SharedPreferences con versionado de datos y migración.
// ============================================================

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/pokemon_card.dart';

class AlbumStorageService {
  static const _kDataVersion = 'tcg_data_version';
  static const _kAlbumsKey = 'tcg_albums_v2';
  static const _kActiveAlbumKey = 'tcg_active_album';
  static const _kLegacyAlbumKey = 'pokemon_album';

  static const int _currentVersion = 2;

  // ── Migración automática ────────────────────────────────────────────────
  Future<void> migrateIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final version = prefs.getInt(_kDataVersion) ?? 1;

    if (version < 2) {
      // Migrar de v1 (álbum único) a v2 (múltiples álbumes)
      final legacyRaw = prefs.getString(_kLegacyAlbumKey);
      if (legacyRaw != null) {
        final List<dynamic> decoded = json.decode(legacyRaw);
        final cards = decoded
            .map((e) => PokemonCard.fromLocalJson(e as Map<String, dynamic>))
            .toList();

        final defaultAlbum = TcgAlbum(
          id: 'album_0',
          name: 'Mi Álbum',
          cards: cards,
        );

        final encoded = json.encode([defaultAlbum.toJson()]);
        await prefs.setString(_kAlbumsKey, encoded);
        await prefs.setString(_kActiveAlbumKey, 'album_0');
      }

      await prefs.setInt(_kDataVersion, _currentVersion);
    }
  }

  // ── Gestión de Álbumes ──────────────────────────────────────────────────
  Future<List<TcgAlbum>> loadAllAlbums() async {
    await migrateIfNeeded();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kAlbumsKey);
    if (raw == null) return [];

    final List<dynamic> decoded = json.decode(raw);
    return decoded
        .map((e) => TcgAlbum.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveAllAlbums(List<TcgAlbum> albums) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = json.encode(albums.map((a) => a.toJson()).toList());
    await prefs.setString(_kAlbumsKey, encoded);
  }

  Future<String> getActiveAlbumId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kActiveAlbumKey) ?? 'album_0';
  }

  Future<void> setActiveAlbumId(String albumId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kActiveAlbumKey, albumId);
  }

  Future<TcgAlbum> getActiveAlbum() async {
    final albums = await loadAllAlbums();
    final activeId = await getActiveAlbumId();
    return albums.firstWhere(
      (a) => a.id == activeId,
      orElse: () {
        if (albums.isNotEmpty) return albums.first;
        return TcgAlbum(id: 'album_0', name: 'Mi Álbum');
      },
    );
  }

  Future<TcgAlbum> createAlbum(String name) async {
    final albums = await loadAllAlbums();
    final newAlbum = TcgAlbum(
      id: 'album_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
    );
    albums.add(newAlbum);
    await saveAllAlbums(albums);
    return newAlbum;
  }

  Future<void> renameAlbum(String albumId, String newName) async {
    final albums = await loadAllAlbums();
    final index = albums.indexWhere((a) => a.id == albumId);
    if (index != -1) {
      albums[index] = albums[index].copyWith(name: newName);
      await saveAllAlbums(albums);
    }
  }

  Future<void> deleteAlbum(String albumId) async {
    final albums = await loadAllAlbums();
    albums.removeWhere((a) => a.id == albumId);
    await saveAllAlbums(albums);

    // Si se borró el álbum activo, cambiar al primero disponible
    final activeId = await getActiveAlbumId();
    if (activeId == albumId && albums.isNotEmpty) {
      await setActiveAlbumId(albums.first.id);
    }
  }

  // ── Gestión de cartas en el álbum activo ─────────────────────────────────
  Future<List<PokemonCard>> loadAlbum() async {
    final album = await getActiveAlbum();
    return album.cards;
  }

  Future<void> saveAlbum(List<PokemonCard> cards) async {
    final albums = await loadAllAlbums();
    final activeId = await getActiveAlbumId();
    final index = albums.indexWhere((a) => a.id == activeId);

    if (index != -1) {
      albums[index] = TcgAlbum(
        id: albums[index].id,
        name: albums[index].name,
        createdAt: albums[index].createdAt,
        cards: cards,
      );
    } else {
      albums.add(TcgAlbum(id: activeId, name: 'Mi Álbum', cards: cards));
    }
    await saveAllAlbums(albums);
  }

  Future<void> addCard(PokemonCard card) async {
    final album = await loadAlbum();
    if (album.any((c) => c.id == card.id)) return;
    album.add(card);
    await saveAlbum(album);
  }

  Future<void> saveCard(PokemonCard card) => addCard(card);

  Future<void> updateCard(PokemonCard updatedCard) async {
    final album = await loadAlbum();
    final index = album.indexWhere((c) => c.id == updatedCard.id);
    if (index != -1) {
      album[index] = updatedCard;
      await saveAlbum(album);
    }
  }

  Future<void> removeCard(String cardId) async {
    final album = await loadAlbum();
    album.removeWhere((c) => c.id == cardId);
    await saveAlbum(album);
  }

  // ── Exportar / Importar ─────────────────────────────────────────────────
  Future<String> exportAllAlbumsJson() async {
    final albums = await loadAllAlbums();
    return json.encode({
      'version': _currentVersion,
      'exportDate': DateTime.now().toIso8601String(),
      'albums': albums.map((a) => a.toJson()).toList(),
    });
  }

  Future<int> importAlbumsJson(String jsonStr) async {
    final decoded = json.decode(jsonStr) as Map<String, dynamic>;
    final albumsRaw = decoded['albums'] as List<dynamic>? ?? [];
    final imported = albumsRaw
        .map((e) => TcgAlbum.fromJson(e as Map<String, dynamic>))
        .toList();

    if (imported.isEmpty) return 0;

    final existing = await loadAllAlbums();
    final existingIds = existing.map((a) => a.id).toSet();

    int count = 0;
    for (final album in imported) {
      if (!existingIds.contains(album.id)) {
        existing.add(album);
        count++;
      } else {
        // Merge: añadir cartas que no existan
        final idx = existing.indexWhere((a) => a.id == album.id);
        if (idx != -1) {
          final existingCardIds =
              existing[idx].cards.map((c) => c.id).toSet();
          final newCards = album.cards
              .where((c) => !existingCardIds.contains(c.id))
              .toList();
          existing[idx].cards.addAll(newCards);
          count += newCards.length;
        }
      }
    }

    await saveAllAlbums(existing);
    return count;
  }
}
