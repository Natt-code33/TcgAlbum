// ============================================================
// views/deck_builder_view.dart
// Constructor de Mazos (Decks) virtuales de Pokémon TCG.
// Reglas competitivas: 60 cartas, máximo 4 copias por nombre.
// ============================================================

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/deck.dart';
import '../models/pokemon_card.dart';
import '../services/album_storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/pokemon_scanner_hud.dart';

class DeckBuilderView extends StatefulWidget {
  const DeckBuilderView({super.key});

  @override
  State<DeckBuilderView> createState() => _DeckBuilderViewState();
}

class _DeckBuilderViewState extends State<DeckBuilderView> {
  final AlbumStorageService _storage = AlbumStorageService();

  List<TcgDeck> _decks = [];
  TcgDeck? _activeDeck;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final decks = await _storage.loadAllDecks();
    if (!mounted) return;
    setState(() {
      _decks = decks;
      if (_activeDeck != null) {
        _activeDeck = decks.firstWhere(
          (d) => d.id == _activeDeck!.id,
          orElse: () => _activeDeck!,
        );
      }
      _isLoading = false;
    });
  }

  Future<void> _createDeck() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nuevo Mazo'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Ej: Charizard ex Aggro, Pikachu Stall...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Crear'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final deck = await _storage.createDeck(name);
    await _load();
    setState(() => _activeDeck = deck);
  }

  Future<void> _renameDeck(TcgDeck deck) async {
    final controller = TextEditingController(text: deck.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Renombrar Mazo'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await _storage.renameDeck(deck.id, name);
    await _load();
  }

  Future<void> _deleteDeck(TcgDeck deck) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar Mazo'),
        content: Text('¿Eliminar "${deck.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar',
                style: TextStyle(color: AppTheme.loss)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await _storage.deleteDeck(deck.id);
    if (_activeDeck?.id == deck.id) {
      _activeDeck = null;
    }
    await _load();
  }

  Future<void> _pickCardFromAlbum() async {
    final album = await _storage.getActiveAlbum();
    if (!mounted) return;
    if (album.cards.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Tu colección está vacía. Escanea cartas primero para añadirlas al mazo.'),
        ),
      );
      return;
    }

    final picked = await showModalBottomSheet<PokemonCard>(
      context: context,
      backgroundColor: const Color(0xFF0C1626),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.72,
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(14),
              child: Text(
                'Selecciona una carta de tu colección',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 20),
                itemCount: album.cards.length,
                itemBuilder: (ctx, i) {
                  final card = album.cards[i];
                  final count = _activeDeck?.cardCountsById[card.id] ?? 0;
                  return ListTile(
                    leading: _DeckThumb(imageUrl: card.thumbnailImageUrl),
                    title: Text(
                      card.name,
                      style: GoogleFonts.outfit(color: Colors.white),
                    ),
                    subtitle: Text(
                      card.setName.isNotEmpty
                          ? '${card.setName} • #${card.number}'
                          : '#${card.number}',
                      style: GoogleFonts.inter(color: Colors.white54),
                    ),
                    trailing: count > 0
                        ? Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: AppTheme.primary),
                            ),
                            child: Text(
                              'x$count',
                              style: GoogleFonts.outfit(
                                color: AppTheme.cyanAccent,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          )
                        : const Icon(Icons.add_circle_outline_rounded,
                            color: AppTheme.cyanAccent),
                    onTap: () => Navigator.pop(ctx, card),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );

    if (picked == null || !mounted) return;
    final ok = await _storage.addCardToDeck(_activeDeck!.id, picked);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Máximo 4 copias de "${picked.name}" permitidas en un mazo competitivo.'),
          backgroundColor: AppTheme.loss,
        ),
      );
    }
    await _load();
  }

  Future<void> _removeEntry(DeckCardEntry entry) async {
    await _storage.removeCardFromDeck(_activeDeck!.id, entry.cardId);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
    }

    if (_activeDeck != null) {
      return _buildDeckDetail(_activeDeck!);
    }

    return _buildDeckList();
  }

  // ── Lista de mazos ────────────────────────────────────────────────────────
  Widget _buildDeckList() {
    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
          children: [
            if (_decks.isEmpty) _buildEmptyState(),
            ..._decks.map(_buildDeckTile),
          ],
        ),
        Positioned(
          right: 16,
          bottom: 100,
          child: FloatingActionButton.extended(
            onPressed: _createDeck,
            backgroundColor: AppTheme.primary,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add_rounded),
            label: Text(
              'Nuevo Mazo',
              style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 24),
      child: Column(
        children: [
          Icon(Icons.layers_rounded,
              size: 56, color: AppTheme.cyanAccent.withValues(alpha: 0.7)),
          const SizedBox(height: 16),
          Text(
            'Aún no tienes mazos',
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Crea un mazo virtual de 60 cartas para jugar competitivo y organiza tus copias.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildDeckTile(TcgDeck deck) {
    final total = deck.totalCards;
    final legal = deck.isLegalSize;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: AppTheme.glassDecoration(radius: 18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => setState(() => _activeDeck = deck),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppTheme.neonButtonGradient,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.deepBlue.withValues(alpha: 0.4),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: const Icon(Icons.layers_rounded,
                    color: Colors.white, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      deck.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${deck.format ?? 'Estándar'} • $total/60 cartas',
                      style: GoogleFonts.inter(
                        color: AppTheme.textMuted,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: (legal ? AppTheme.success : AppTheme.loss)
                      .withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color:
                        legal ? AppTheme.success : AppTheme.loss,
                  ),
                ),
                child: Text(
                  legal ? 'VÁLIDO' : '$total/60',
                  style: GoogleFonts.outfit(
                    color: legal ? AppTheme.success : AppTheme.loss,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Detalle del mazo activo ───────────────────────────────────────────────
  Widget _buildDeckDetail(TcgDeck deck) {
    final total = deck.totalCards;
    final legal = deck.isLegalSize;

    return Column(
      children: [
        // Cabecera del mazo
        Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          padding: const EdgeInsets.all(14),
          decoration: AppTheme.glassDecoration(radius: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => setState(() => _activeDeck = null),
                    icon: const Icon(Icons.arrow_back_ios_new_rounded,
                        color: Colors.white70, size: 18),
                    tooltip: 'Volver a Mis Mazos',
                  ),
                  Expanded(
                    child: Text(
                      deck.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => _renameDeck(deck),
                    icon: const Icon(Icons.edit_outlined,
                        color: AppTheme.cyanAccent, size: 20),
                    tooltip: 'Renombrar',
                  ),
                  IconButton(
                    onPressed: () => _deleteDeck(deck),
                    icon: const Icon(Icons.delete_outline_rounded,
                        color: AppTheme.loss, size: 20),
                    tooltip: 'Eliminar mazo',
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: (total / 60).clamp(0.0, 1.0),
                        minHeight: 8,
                        backgroundColor: Colors.white10,
                        color: legal ? AppTheme.success : AppTheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '$total/60',
                    style: GoogleFonts.outfit(
                      color: legal ? AppTheme.success : AppTheme.cyanAccent,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                legal
                    ? 'Mazo competitivo válido (60 cartas, máximo 4 copias por nombre).'
                    : 'Añade ${60 - total} cartas más para completar el mazo de 60.',
                style: GoogleFonts.inter(
                  color: AppTheme.textMuted,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),

        // Acciones
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: NeonPillButton(
                  label: 'Añadir desde mi Colección',
                  icon: Icons.add_rounded,
                  style: NeonButtonStyle.primary,
                  compact: true,
                  onPressed: _pickCardFromAlbum,
                ),
              ),
            ],
          ),
        ),

        // Lista de cartas del mazo
        Expanded(
          child: deck.entries.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.style_outlined,
                            size: 48,
                            color: AppTheme.cyanAccent.withValues(alpha: 0.6)),
                        const SizedBox(height: 12),
                        Text(
                          'Mazo vacío',
                          style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Pulsa "Añadir desde mi Colección" para incluir cartas en este mazo.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                              color: AppTheme.textMuted, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
                  itemCount: deck.entries.length,
                  itemBuilder: (ctx, i) {
                    final entry = deck.entries[i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: AppTheme.glassDecoration(radius: 14),
                      child: ListTile(
                        leading: _DeckThumb(imageUrl: entry.imageUrl),
                        title: Text(
                          entry.cardName ?? entry.cardId,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.outfit(color: Colors.white),
                        ),
                        subtitle: Text(
                          [
                            if (entry.setName != null &&
                                entry.setName!.isNotEmpty)
                              entry.setName!,
                            '#${entry.number ?? '-'}',
                          ].join(' • '),
                          style:
                              GoogleFonts.inter(color: Colors.white54),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline_rounded,
                                  color: AppTheme.cyanAccent),
                              onPressed: () => _removeEntry(entry),
                            ),
                            Text(
                              'x${entry.quantity}',
                              style: GoogleFonts.outfit(
                                color: AppTheme.cyanAccent,
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline_rounded,
                                  color: AppTheme.cyanAccent),
                              onPressed: () async {
                                final ok = await _storage.addCardToDeck(
                                    deck.id,
                                    PokemonCard(
                                      id: entry.cardId,
                                      name: entry.cardName ?? entry.cardId,
                                      number: entry.number ?? '?',
                                      setName: entry.setName ?? '',
                                      imageUrl: entry.imageUrl ?? '',
                                    ));
                                if (!ok && mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                          'Máximo 4 copias por carta en un mazo competitivo.'),
                                      backgroundColor: AppTheme.loss,
                                    ),
                                  );
                                }
                                await _load();
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _DeckThumb extends StatelessWidget {
  final String? imageUrl;

  const _DeckThumb({this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    if (url != null && url.isNotEmpty && PokemonCard.isValidNetworkUrl(url)) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: CachedNetworkImage(
          imageUrl: url,
          width: 42,
          height: 58,
          memCacheWidth: 140,
          fit: BoxFit.cover,
          placeholder: (_, __) => Container(
            width: 42,
            height: 58,
            color: Colors.black26,
          ),
          errorWidget: (_, __, ___) => Container(
            width: 42,
            height: 58,
            color: Colors.black26,
            child: const Icon(Icons.broken_image,
                color: Colors.white38, size: 18),
          ),
        ),
      );
    }
    if (url != null && url.isNotEmpty && File(url).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.file(File(url),
            width: 42, height: 58, cacheWidth: 140, fit: BoxFit.cover),
      );
    }
    return Container(
      width: 42,
      height: 58,
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Icon(Icons.style_outlined,
          color: Colors.white38, size: 18),
    );
  }
}
