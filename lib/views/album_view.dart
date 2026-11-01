// ============================================================
// views/album_view.dart
// Pantalla principal: muestra el álbum de cartas TCG en un GridView
// de 2 columnas con imagen, precio CM y precio PSA 10.
// Soporta filtrado por franquicia: Pokémon, Magic, YGO, Digimon, etc.
// ============================================================

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/pokemon_card.dart';
import '../services/album_storage_service.dart';
import 'scanner_view.dart';
import 'manual_card_view.dart';

class AlbumView extends StatefulWidget {
  const AlbumView({super.key});

  @override
  State<AlbumView> createState() => _AlbumViewState();
}

class _AlbumViewState extends State<AlbumView> {
  final AlbumStorageService _storage = AlbumStorageService();
  List<PokemonCard> _cards = [];
  bool _isLoading = true;
  TcgGame _filterGame = TcgGame.all;

  @override
  void initState() {
    super.initState();
    _loadAlbum();
  }

  Future<void> _loadAlbum() async {
    final cards = await _storage.loadAlbum();
    if (mounted) {
      setState(() {
        _cards = cards;
        _isLoading = false;
      });
    }
  }

  Future<void> _openScanner() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ScannerView()),
    );
    await _loadAlbum();
  }

  Future<void> _openManualEntry() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ManualCardView(
          initialGame: _filterGame != TcgGame.all ? _filterGame : null,
        ),
      ),
    );
    if (saved == true) {
      await _loadAlbum();
    }
  }

  Future<void> _deleteCard(PokemonCard card) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16213E),
        title: const Text('Eliminar carta',
            style: TextStyle(color: Colors.white)),
        content: Text('¿Quieres eliminar "${card.name}" de tu álbum?',
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar',
                style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _storage.removeCard(card.id);
      await _loadAlbum();
    }
  }

  List<PokemonCard> get _filteredCards {
    if (_filterGame == TcgGame.all) return _cards;
    return _cards.where((c) => c.game == _filterGame).toList();
  }

  double get _totalEstimatedValue {
    double total = 0.0;
    for (final c in _filteredCards) {
      final price = c.cardmarketPrices?.averageSellPrice ??
          c.cardmarketPrices?.trendPrice ??
          0.0;
      total += price;
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredCards;

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16213E),
        title: const Row(
          children: [
            Text('🃏', style: TextStyle(fontSize: 22)),
            SizedBox(width: 10),
            Text(
              'Mi Álbum TCG',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_note, color: Colors.amber),
            tooltip: 'Añadir datos manualmente',
            onPressed: _openManualEntry,
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 14.0),
              child: Text(
                '${filtered.length} cartas',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.amber))
          : Column(
              children: [
                // ── Filtro horizontal por Franquicia TCG ───────────────────
                _buildFilterChips(),

                // ── Banner con total de cartas y valor de colección ────────
                if (_cards.isNotEmpty) _buildSummaryBar(filtered.length),

                // ── Contenido: Grid o Estado Vacío ────────────────────────
                Expanded(
                  child: filtered.isEmpty
                      ? _buildEmptyState()
                      : _buildGrid(filtered),
                ),
              ],
            ),

      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.small(
            heroTag: 'fab_manual',
            onPressed: _openManualEntry,
            backgroundColor: const Color(0xFF0F3460),
            foregroundColor: Colors.amber,
            tooltip: 'Añadir carta a mano',
            child: const Icon(Icons.edit_note),
          ),
          const SizedBox(height: 10),
          FloatingActionButton.extended(
            heroTag: 'fab_scanner',
            onPressed: _openScanner,
            backgroundColor: Colors.amber,
            foregroundColor: Colors.black,
            icon: const Icon(Icons.camera_alt),
            label: const Text('Escanear / Buscar',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ── Chips de filtro por Franquicia ─────────────────────────────────────────
  Widget _buildFilterChips() {
    return Container(
      color: const Color(0xFF16213E),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: TcgGame.values.map((game) {
            final isSelected = _filterGame == game;
            final count = game == TcgGame.all
                ? _cards.length
                : _cards.where((c) => c.game == game).length;

            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(
                  '${game.icon} ${game.label} ($count)',
                  style: TextStyle(
                    color: isSelected ? Colors.black : Colors.white70,
                    fontSize: 11,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                selected: isSelected,
                selectedColor: Color(game.colorHex),
                backgroundColor: const Color(0xFF0F3460),
                side: BorderSide(
                  color: isSelected ? Color(game.colorHex) : Colors.white12,
                ),
                onSelected: (selected) {
                  if (selected) setState(() => _filterGame = game);
                },
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // ── Barra de resumen con valor total ───────────────────────────────────────
  Widget _buildSummaryBar(int count) {
    final value = _totalEstimatedValue;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: const Color(0xFF0F3460).withValues(alpha: 0.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            _filterGame == TcgGame.all
                ? 'Colección completa: $count cartas'
                : '${_filterGame.icon} ${_filterGame.label}: $count cartas',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          if (value > 0)
            Text(
              'Valor aprox: ${value.toStringAsFixed(2)} €',
              style: const TextStyle(
                color: Color(0xFF00B4D8),
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
        ],
      ),
    );
  }

  // ── Estado vacío ──────────────────────────────────────────────────────────
  Widget _buildEmptyState() {
    final isFiltered = _filterGame != TcgGame.all;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isFiltered ? Icons.filter_list_off : Icons.collections,
              size: 70,
              color: Colors.white24,
            ),
            const SizedBox(height: 16),
            Text(
              isFiltered
                  ? 'No hay cartas de ${_filterGame.label}'
                  : 'Tu álbum está vacío',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isFiltered
                  ? 'Escanea cartas de ${_filterGame.label} o añádelas con el botón manual.'
                  : 'Escanea cualquier carta TCG (Pokémon, Magic, YGO, Digimon, One Piece...) o introduce sus datos a mano.',
              style: const TextStyle(color: Colors.white38, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _openManualEntry,
              icon: const Icon(Icons.edit_note),
              label: const Text('Introducir datos a mano'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F3460),
                foregroundColor: Colors.amber,
                side: const BorderSide(color: Colors.amber, width: 1),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Grid de cartas (2 columnas, proporción 0.62) ───────────────────────────
  Widget _buildGrid(List<PokemonCard> cards) {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.62,
      ),
      itemCount: cards.length,
      itemBuilder: (context, index) {
        return _CardTile(
          card: cards[index],
          onDelete: () => _deleteCard(cards[index]),
        );
      },
    );
  }
}

// ── Tarjeta individual en el Álbum ───────────────────────────────────────────
class _CardTile extends StatelessWidget {
  final PokemonCard card;
  final VoidCallback onDelete;

  const _CardTile({required this.card, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: onDelete,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Imagen con badge de franquicia superpuesto
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: card.imageUrl.startsWith('http')
                      ? CachedNetworkImage(
                          imageUrl: card.imageUrl,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(
                            color: const Color(0xFF0F3460),
                            child: const Center(
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.amber),
                            ),
                          ),
                          errorWidget: (context, url, error) => Container(
                            color: const Color(0xFF0F3460),
                            child: const Icon(Icons.broken_image,
                                color: Colors.white38, size: 40),
                          ),
                        )
                      : (card.imageUrl.isNotEmpty &&
                              File(card.imageUrl).existsSync()
                          ? Image.file(File(card.imageUrl), fit: BoxFit.cover)
                          : Container(
                              color: const Color(0xFF0F3460),
                              child: const Icon(Icons.image_not_supported,
                                  color: Colors.white38, size: 40),
                            )),
                ),

                // Badge pequeño de franquicia TCG en la esquina superior
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: Color(card.game.colorHex).withValues(alpha: 0.6),
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      '${card.game.icon} ${card.game.label}',
                      style: TextStyle(
                        color: Color(card.game.colorHex),
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 6),

          // Nombre de la carta
          Text(
            card.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),

          const SizedBox(height: 4),

          // Fila de precios: Cardmarket | PSA 10
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF0F3460),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A2E),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      card.cardmarketPrices?.averageSellPrice != null
                          ? 'CM: ${card.cardmarketPrices!.averageSellPrice!.toStringAsFixed(1)}€'
                          : (card.cardmarketPrices?.trendPrice != null
                              ? 'CM: ${card.cardmarketPrices!.trendPrice!.toStringAsFixed(1)}€'
                              : 'CM: N/A'),
                      style: const TextStyle(
                        color: Color(0xFF00B4D8),
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),

                const SizedBox(width: 4),

                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A2E),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      card.psa10Price != null
                          ? 'PSA10: ${card.psa10Price!.toStringAsFixed(0)}€'
                          : 'PSA10: N/A',
                      style: const TextStyle(
                        color: Color(0xFFFFD166),
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
