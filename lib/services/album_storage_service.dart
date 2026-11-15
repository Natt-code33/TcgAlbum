// ============================================================
// services/album_storage_service.dart
// Servicio de persistencia local con soporte para múltiples álbumes.
// Usa SharedPreferences con versionado de datos y migración.
// ============================================================

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/pokemon_card.dart';
import '../models/deck.dart';

class AlbumStorageService {
  static const _kDataVersion = 'tcg_data_version';
  static const _kAlbumsKey = 'tcg_albums_v2';
  static const _kActiveAlbumKey = 'tcg_active_album';
  static const _kLegacyAlbumKey = 'pokemon_album';
  static const _kDecksKey = 'tcg_decks_v1';

  static const int _currentVersion = 2;

  /// Fallback en Isolate secundario para plataformas donde el compresor nativo no esté activo.
  static Uint8List? _compressCardPhotoIsolate(Uint8List rawBytes) {
    try {
      final decoded = img.decodeImage(rawBytes);
      if (decoded == null) return null;
      final resized = decoded.width > 600
          ? img.copyResize(
              decoded,
              width: 600,
              interpolation: img.Interpolation.linear,
            )
          : decoded;
      return Uint8List.fromList(img.encodeJpg(resized, quality: 78));
    } catch (_) {
      return null;
    }
  }

  /// Comprime una imagen en formato WebP ultraligero (~20 KB por carta) usando aceleración
  /// por hardware nativa (Android/iOS) y la guarda en el directorio permanente `card_images/`.
  Future<String> persistCardImage(File sourceFile) async {
    if (!await sourceFile.exists()) return sourceFile.path;

    final docsDir = await getApplicationDocumentsDirectory();
    final imagesDir = Directory(p.join(docsDir.path, 'card_images'));
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }

    // Si ya está dentro de card_images y ya es .webp, no duplicar
    if (p.isWithin(imagesDir.path, sourceFile.path) &&
        sourceFile.path.toLowerCase().endsWith('.webp')) {
      return sourceFile.path;
    }

    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final webpDestPath = p.join(imagesDir.path, 'card_$timestamp.webp');

    // 1. Intentar compresión nativa acelerada por hardware a formato WebP (~20 KB)
    try {
      final XFile? compressedXFile = await FlutterImageCompress.compressAndGetFile(
        sourceFile.absolute.path,
        webpDestPath,
        minWidth: 600,
        minHeight: 840,
        quality: 78,
        format: CompressFormat.webp,
      );

      if (compressedXFile != null) {
        final outFile = File(compressedXFile.path);
        if (await outFile.exists() && (await outFile.length()) > 0) {
          try {
            if (!p.isWithin(docsDir.path, sourceFile.path)) {
              await sourceFile.delete();
            }
          } catch (_) {}
          return outFile.path;
        }
      }
    } catch (_) {}

    // 2. Fallback en Isolate si la plataforma no soporta el canal nativo (ej. tests/desktop)
    final jpgDestPath = p.join(imagesDir.path, 'card_$timestamp.jpg');
    try {
      final rawBytes = await sourceFile.readAsBytes();
      final compressedBytes = await Isolate.run(
        () => _compressCardPhotoIsolate(rawBytes),
      );
      if (compressedBytes != null && compressedBytes.isNotEmpty) {
        final destFile = File(jpgDestPath);
        await destFile.writeAsBytes(compressedBytes, flush: true);
        try {
          if (!p.isWithin(docsDir.path, sourceFile.path)) {
            await sourceFile.delete();
          }
        } catch (_) {}
        return destFile.path;
      }
    } catch (_) {}

    final savedFile = await sourceFile.copy(jpgDestPath);
    return savedFile.path;
  }

  /// Elimina de disco las fotos locales en `card_images/` que ya no estén
  /// referenciadas por ninguna carta en ningún álbum (Garbage Collection).
  Future<void> _cleanupOrphanedImages(List<TcgAlbum> albums) async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final imagesDir = Directory(p.join(docsDir.path, 'card_images'));
      if (!await imagesDir.exists()) return;

      final usedPaths = <String>{};
      for (final album in albums) {
        for (final card in album.cards) {
          if (card.imageUrl.isNotEmpty &&
              !PokemonCard.isValidNetworkUrl(card.imageUrl)) {
            usedPaths.add(p.normalize(card.imageUrl));
          }
        }
      }

      await for (final entity in imagesDir.list()) {
        if (entity is File) {
          final normPath = p.normalize(entity.path);
          if (!usedPaths.contains(normPath)) {
            try {
              await entity.delete();
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
  }

  // ── Migración automática ────────────────────────────────────────────────
  Future<void> migrateIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final version = prefs.getInt(_kDataVersion) ?? 1;

    if (version < 2) {
      // Migrar de v1 (álbum único) a v2 (múltiples álbumes)
      final legacyRaw = prefs.getString(_kLegacyAlbumKey);
      if (legacyRaw != null) {
        try {
          final List<dynamic> decoded = json.decode(legacyRaw);
          final cards = decoded
              .whereType<Map<String, dynamic>>()
              .map(PokemonCard.fromLocalJson)
              .toList();

          final defaultAlbum = TcgAlbum(
            id: 'album_0',
            name: 'Mi Álbum',
            cards: cards,
          );

          final encoded = json.encode([defaultAlbum.toJson()]);
          await prefs.setString(_kAlbumsKey, encoded);
          await prefs.setString(_kActiveAlbumKey, 'album_0');
        } catch (_) {}
      }

      await prefs.setInt(_kDataVersion, _currentVersion);
    }
  }

  // ── Gestión de Álbumes ──────────────────────────────────────────────────
  Future<List<TcgAlbum>> loadAllAlbums() async {
    await migrateIfNeeded();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kAlbumsKey);

    if (raw != null && raw.isNotEmpty) {
      try {
        final List<dynamic> decoded = json.decode(raw);
        final albums = decoded
            .whereType<Map<String, dynamic>>()
            .map(TcgAlbum.fromJson)
            .toList();
        if (albums.isNotEmpty) {
          return albums;
        }
      } catch (_) {}
    }

    // Si no existe ningún álbum aún, crear y persistir el álbum por defecto
    final defaultAlbum = TcgAlbum(id: 'album_0', name: 'Mi Álbum');
    await saveAllAlbums([defaultAlbum]);
    await setActiveAlbumId(defaultAlbum.id);
    return [defaultAlbum];
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
      id: 'album_${DateTime.now().microsecondsSinceEpoch}',
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
    await _cleanupOrphanedImages(albums);

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

  /// Añade una carta al álbum activo.
  /// Si la carta ya existe en el álbum, incrementa su contador de copias (`quantity + 1`)
  /// y devuelve `false` (indicando que era repetida y se sumó una copia).
  /// Si es una carta nueva en el álbum, la añade y devuelve `true`.
  Future<bool> addCard(PokemonCard card) async {
    final album = await loadAlbum();
    final existingIdx = album.indexWhere((c) => c.id == card.id);
    if (existingIdx != -1) {
      final current = album[existingIdx];
      album[existingIdx] = current.copyWith(quantity: current.quantity + 1);
      await saveAlbum(album);
      return false;
    }
    album.add(card);
    await saveAlbum(album);
    return true;
  }

  Future<bool> saveCard(PokemonCard card) => addCard(card);

  Future<void> updateCard(PokemonCard updatedCard) async {
    final albums = await loadAllAlbums();
    final activeId = await getActiveAlbumId();
    final albumIdx = albums.indexWhere((a) => a.id == activeId);
    if (albumIdx != -1) {
      final cards = albums[albumIdx].cards;
      final cardIdx = cards.indexWhere((c) => c.id == updatedCard.id);
      if (cardIdx != -1) {
        cards[cardIdx] = updatedCard;
        await saveAllAlbums(albums);
        await _cleanupOrphanedImages(albums);
      }
    }
  }

  Future<void> removeCard(String cardId) async {
    final albums = await loadAllAlbums();
    final activeId = await getActiveAlbumId();
    final albumIdx = albums.indexWhere((a) => a.id == activeId);
    if (albumIdx != -1) {
      albums[albumIdx].cards.removeWhere((c) => c.id == cardId);
      await saveAllAlbums(albums);
      await _cleanupOrphanedImages(albums);
    }
  }

  // ── Exportar / Importar ─────────────────────────────────────────────────
  Future<String> exportAllAlbumsJson() async {
    final albums = await loadAllAlbums();
    final serializedAlbums = <Map<String, dynamic>>[];
    int totalBase64Bytes = 0;
    const int maxClipboardBase64Bytes = 750 * 1024; // Límite seguro (< 1 MB Binder de Android)

    for (final album in albums) {
      final albumMap = album.toJson();
      final serializedCards = <Map<String, dynamic>>[];

      for (final card in album.cards) {
        final cardMap = card.toJson();
        if (card.imageUrl.isNotEmpty &&
            !PokemonCard.isValidNetworkUrl(card.imageUrl) &&
            totalBase64Bytes < maxClipboardBase64Bytes) {
          try {
            final file = File(card.imageUrl);
            if (await file.exists()) {
              final bytes = await file.readAsBytes();
              if (totalBase64Bytes + bytes.length <= maxClipboardBase64Bytes) {
                cardMap['imageBase64'] = base64Encode(bytes);
                totalBase64Bytes += bytes.length;
              }
            }
          } catch (_) {}
        }
        serializedCards.add(cardMap);
      }

      albumMap['cards'] = serializedCards;
      serializedAlbums.add(albumMap);
    }

    return json.encode({
      'version': _currentVersion,
      'exportDate': DateTime.now().toIso8601String(),
      'albums': serializedAlbums,
    });
  }

  Future<int> importAlbumsJson(String jsonStr) async {
    final dynamic rawDecoded = json.decode(jsonStr);
    if (rawDecoded is! Map<String, dynamic>) {
      throw const FormatException('El formato de la copia de seguridad no es válido (debe ser un objeto JSON).');
    }

    final albumsRaw = rawDecoded['albums'];
    if (albumsRaw is! List) {
      throw const FormatException('La copia de seguridad no contiene una lista de álbumes válida.');
    }

    Directory? imagesDir;
    Future<Directory> getImagesDir() async {
      if (imagesDir != null) return imagesDir!;
      final docsDir = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(docsDir.path, 'card_images'));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      imagesDir = dir;
      return dir;
    }

    final imported = <TcgAlbum>[];
    for (final rawAlbum in albumsRaw) {
      if (rawAlbum is! Map<String, dynamic>) continue;
      try {
        final albumId = (rawAlbum['id'] as String?) ?? 'album_${DateTime.now().microsecondsSinceEpoch}';
        final albumName = (rawAlbum['name'] as String?) ?? 'Álbum Importado';
        final rawCards = rawAlbum['cards'];
        final validCards = <PokemonCard>[];

        if (rawCards is List) {
          for (final rawCard in rawCards) {
            if (rawCard is! Map<String, dynamic>) continue;
            try {
              var card = PokemonCard.fromLocalJson(rawCard);

              // Restaurar imagen local desde Base64 si viene incluida en el backup (convirtiéndola a WebP si es posible)
              final imgB64 = rawCard['imageBase64'] as String?;
              if (imgB64 != null && imgB64.isNotEmpty) {
                try {
                  final rawBytes = base64Decode(imgB64);
                  final dir = await getImagesDir();
                  Uint8List finalBytes = rawBytes;
                  String ext = '.webp';
                  try {
                    final webpBytes = await FlutterImageCompress.compressWithList(
                      rawBytes,
                      minWidth: 600,
                      minHeight: 840,
                      quality: 78,
                      format: CompressFormat.webp,
                    );
                    if (webpBytes.isNotEmpty) {
                      finalBytes = webpBytes;
                    } else {
                      ext = '.jpg';
                    }
                  } catch (_) {
                    ext = '.jpg';
                  }
                  final filePath = p.join(
                    dir.path,
                    'restored_${DateTime.now().microsecondsSinceEpoch}$ext',
                  );
                  await File(filePath).writeAsBytes(finalBytes, flush: true);
                  card = card.copyWith(imageUrl: filePath);
                } catch (_) {
                  card = card.copyWith(imageUrl: '');
                }
              } else if (card.imageUrl.isNotEmpty &&
                  !PokemonCard.isValidNetworkUrl(card.imageUrl)) {
                // Seguridad: impedir que un JSON importado apunte a rutas locales arbitrarias del sistema
                card = card.copyWith(imageUrl: '');
              }

              validCards.add(card);
            } catch (_) {
              // Si una carta tiene un formato corrupto, ignorarla sin romper todo el álbum
            }
          }
        }

        imported.add(TcgAlbum(
          id: albumId,
          name: albumName,
          cards: validCards,
        ));
      } catch (_) {
        // Ignorar álbum corrupto sin abortar toda la importación
      }
    }

    if (imported.isEmpty) return 0;

    final existing = await loadAllAlbums();
    final existingIds = existing.map((a) => a.id).toSet();

    int count = 0;
    for (final album in imported) {
      if (!existingIds.contains(album.id)) {
        existing.add(album);
        count += album.cards.length;
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

  // ── Gestión de Mazos (Decks) virtuales ────────────────────────────────────
  Future<List<TcgDeck>> loadAllDecks() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kDecksKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final List<dynamic> decoded = json.decode(raw);
        return decoded
            .whereType<Map<String, dynamic>>()
            .map(TcgDeck.fromJson)
            .toList();
      } catch (_) {}
    }
    return [];
  }

  Future<void> saveAllDecks(List<TcgDeck> decks) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = json.encode(decks.map((d) => d.toJson()).toList());
    await prefs.setString(_kDecksKey, encoded);
  }

  Future<TcgDeck> createDeck(String name, {String? format}) async {
    final decks = await loadAllDecks();
    final newDeck = TcgDeck(
      id: 'deck_${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      format: format ?? 'Estándar',
    );
    decks.add(newDeck);
    await saveAllDecks(decks);
    return newDeck;
  }

  Future<void> renameDeck(String deckId, String newName) async {
    final decks = await loadAllDecks();
    final index = decks.indexWhere((d) => d.id == deckId);
    if (index != -1) {
      decks[index] = decks[index].copyWith(name: newName);
      await saveAllDecks(decks);
    }
  }

  Future<void> deleteDeck(String deckId) async {
    final decks = await loadAllDecks();
    decks.removeWhere((d) => d.id == deckId);
    await saveAllDecks(decks);
  }

  Future<void> saveDeck(TcgDeck deck) async {
    final decks = await loadAllDecks();
    final index = decks.indexWhere((d) => d.id == deck.id);
    if (index != -1) {
      decks[index] = deck;
    } else {
      decks.add(deck);
    }
    await saveAllDecks(decks);
  }

  /// Añade una carta al mazo. Devuelve false si se superó el máximo de 4 copias
  /// del mismo nombre (regla estándar del TCG, salvo Energía Básica).
  Future<bool> addCardToDeck(String deckId, PokemonCard card,
      {bool isBasicEnergy = false}) async {
    final decks = await loadAllDecks();
    final index = decks.indexWhere((d) => d.id == deckId);
    if (index == -1) return false;

    final deck = decks[index];
    final entries = List<DeckCardEntry>.from(deck.entries);
    final existingIdx = entries.indexWhere((e) => e.cardId == card.id);

    final currentCount = existingIdx != -1 ? entries[existingIdx].quantity : 0;
    final maxCopies = isBasicEnergy ? 60 : 4;
    if (currentCount >= maxCopies) return false;

    if (existingIdx != -1) {
      entries[existingIdx] = entries[existingIdx].copyWith(
        quantity: currentCount + 1,
      );
    } else {
      entries.add(DeckCardEntry(
        cardId: card.id,
        quantity: 1,
        cardName: card.name,
        imageUrl: card.thumbnailImageUrl,
        setName: card.setName,
        number: card.number,
      ));
    }

    decks[index] = deck.copyWith(entries: entries);
    await saveAllDecks(decks);
    return true;
  }

  /// Elimina una copia de la carta del mazo (o la entrada completa si llega a 0).
  Future<void> removeCardFromDeck(String deckId, String cardId) async {
    final decks = await loadAllDecks();
    final index = decks.indexWhere((d) => d.id == deckId);
    if (index == -1) return;

    final deck = decks[index];
    final entries = List<DeckCardEntry>.from(deck.entries);
    final entryIdx = entries.indexWhere((e) => e.cardId == cardId);
    if (entryIdx == -1) return;

    final entry = entries[entryIdx];
    if (entry.quantity > 1) {
      entries[entryIdx] = entry.copyWith(quantity: entry.quantity - 1);
    } else {
      entries.removeAt(entryIdx);
    }

    decks[index] = deck.copyWith(entries: entries);
    await saveAllDecks(decks);
  }
}
