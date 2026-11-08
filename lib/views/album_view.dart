// ============================================================
// views/album_view.dart
// Pantalla principal: Álbum de cartas TCG con soporte para MÚLTIPLES ÁLBUMES,
// gestión de colecciones, backup/exportación y diseño espaciado.
// ============================================================

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  List<TcgAlbum> _albums = [];
  TcgAlbum? _currentAlbum;
  List<PokemonCard> _cards = [];
  bool _isLoading = true;
  TcgGame _filterGame = TcgGame.all;

  @override
  void initState() {
    super.initState();
    _loadAlbumsAndActive();
  }

  Future<void> _loadAlbumsAndActive() async {
    final albums = await _storage.loadAllAlbums();
    final active = await _storage.getActiveAlbum();

    if (mounted) {
      setState(() {
        _albums = albums;
        _currentAlbum = active;
        _cards = active.cards;
        _isLoading = false;
      });
    }
  }

  Future<void> _switchAlbum(TcgAlbum album) async {
    await _storage.setActiveAlbumId(album.id);
    if (mounted) {
      setState(() {
        _currentAlbum = album;
        _cards = album.cards;
      });
    }
  }

  Future<void> _createNewAlbum() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16213E),
        title: const Text('Nuevo Álbum', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Ej: Colección 151, Mi Mazo Vintage...',
            hintStyle: TextStyle(color: Colors.white38),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black),
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) Navigator.pop(ctx, text);
            },
            child: const Text('Crear'),
          ),
        ],
      ),
    );

    if (name != null && name.isNotEmpty) {
      final newAlbum = await _storage.createAlbum(name);
      await _storage.setActiveAlbumId(newAlbum.id);
      await _loadAlbumsAndActive();
    }
  }

  Future<void> _renameCurrentAlbum() async {
    if (_currentAlbum == null) return;
    final controller = TextEditingController(text: _currentAlbum!.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16213E),
        title: const Text('Renombrar Álbum', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black),
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) Navigator.pop(ctx, text);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (name != null && name.isNotEmpty) {
      await _storage.renameAlbum(_currentAlbum!.id, name);
      await _loadAlbumsAndActive();
    }
  }

  Future<void> _deleteCurrentAlbum() async {
    if (_currentAlbum == null || _albums.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No puedes eliminar el único álbum existente.')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16213E),
        title: const Text('Eliminar Álbum', style: TextStyle(color: Colors.white)),
        content: Text(
          '¿Eliminar el álbum "${_currentAlbum!.name}" con todas sus cartas (${_currentAlbum!.cards.length})?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _storage.deleteAlbum(_currentAlbum!.id);
      await _loadAlbumsAndActive();
    }
  }

  Future<void> _showBackupDialog() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF16213E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Copia de Seguridad (Backup)',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Guarda tus datos para no perder tus álbumes al cambiar de móvil o reinstalar.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.file_upload, color: Colors.amber),
              title: const Text('Exportar copia de seguridad', style: TextStyle(color: Colors.white)),
              subtitle: const Text('Copia tus datos en formato texto/JSON', style: TextStyle(color: Colors.white54, fontSize: 12)),
              onTap: () async {
                Navigator.pop(ctx);
                final jsonStr = await _storage.exportAllAlbumsJson();
                await Clipboard.setData(ClipboardData(text: jsonStr));
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('✅ ¡Copia copiada al portapapeles! Guárdala en tus notas.'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.file_download, color: Color(0xFF00B4D8)),
              title: const Text('Restaurar copia de seguridad', style: TextStyle(color: Colors.white)),
              subtitle: const Text('Pega aquí un backup anterior para recuperar tus cartas', style: TextStyle(color: Colors.white54, fontSize: 12)),
              onTap: () {
                Navigator.pop(ctx);
                _showImportDialog();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showImportDialog() async {
    final controller = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16213E),
        title: const Text('Restaurar Copia', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          maxLines: 5,
          style: const TextStyle(color: Colors.white, fontSize: 12),
          decoration: const InputDecoration(
            hintText: 'Pega aquí el texto JSON de la copia de seguridad...',
            hintStyle: TextStyle(color: Colors.white38),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black),
            onPressed: () async {
              try {
                final count = await _storage.importAlbumsJson(controller.text.trim());
                if (ctx.mounted) Navigator.pop(ctx);
                await _loadAlbumsAndActive();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('✅ Restauradas $count cartas con éxito.'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text('Error al restaurar: $e'), backgroundColor: Colors.redAccent),
                  );
                }
              }
            },
            child: const Text('Restaurar'),
          ),
        ],
      ),
    );
  }

  Future<void> _openScanner() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ScannerView(
          initialGame: _filterGame != TcgGame.all ? _filterGame : TcgGame.pokemon,
        ),
      ),
    );
    await _loadAlbumsAndActive();
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
      await _loadAlbumsAndActive();
    }
  }

  Future<void> _deleteCard(PokemonCard card) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16213E),
        title: const Text('Eliminar carta', style: TextStyle(color: Colors.white)),
        content: Text('¿Quieres eliminar "${card.name}" del álbum?', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar', style: TextStyle(color: Colors.white54))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Eliminar', style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );

    if (confirm == true) {
      await _storage.removeCard(card.id);
      await _loadAlbumsAndActive();
    }
  }

  Future<void> _editCard(PokemonCard card) async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ManualCardView(cardToEdit: card)),
    );
    if (updated == true) {
      await _loadAlbumsAndActive();
    }
  }

  Future<void> _showCardDetails(PokemonCard card) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF16213E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: MediaQuery.of(ctx).padding.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 14),
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: card.imageUrl.startsWith('http')
                    ? CachedNetworkImage(
                        imageUrl: card.imageUrl,
                        height: 240,
                        fit: BoxFit.contain,
                        placeholder: (_, __) => const SizedBox(
                          height: 240,
                          child: Center(child: CircularProgressIndicator(color: Colors.amber)),
                        ),
                        errorWidget: (_, __, ___) => const SizedBox(
                          height: 240,
                          child: Icon(Icons.broken_image, color: Colors.white38, size: 60),
                        ),
                      )
                    : (card.imageUrl.isNotEmpty && File(card.imageUrl).existsSync()
                        ? Image.file(File(card.imageUrl), height: 240, fit: BoxFit.contain)
                        : const SizedBox(
                            height: 240,
                            child: Icon(Icons.image_not_supported, color: Colors.white38, size: 60),
                          )),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    card.name,
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Color(card.game.colorHex).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Color(card.game.colorHex), width: 1),
                  ),
                  child: Text(
                    '${card.game.icon} ${card.game.label}',
                    style: TextStyle(
                      color: Color(card.game.colorHex),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              card.setName.isNotEmpty ? '${card.setName} • #${card.number}' : 'Ref: #${card.number}',
              style: const TextStyle(color: Colors.white60, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFF0F3460), borderRadius: BorderRadius.circular(10)),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Column(
                        children: [
                          const Text('Cardmarket (Media)', style: TextStyle(color: Colors.white54, fontSize: 11)),
                          const SizedBox(height: 4),
                          Text(
                            card.cardmarketPrices?.averageSellPrice != null
                                ? '${card.cardmarketPrices!.averageSellPrice!.toStringAsFixed(2)} €'
                                : (card.cardmarketPrices?.trendPrice != null
                                    ? '${card.cardmarketPrices!.trendPrice!.toStringAsFixed(2)} €'
                                    : 'No disponible'),
                            style: const TextStyle(color: Color(0xFF00B4D8), fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      Container(width: 1, height: 35, color: Colors.white12),
                      Column(
                        children: [
                          const Text('PSA 10 (Estimado)', style: TextStyle(color: Colors.white54, fontSize: 11)),
                          const SizedBox(height: 4),
                          Text(
                            card.psa10Price != null ? '${card.psa10Price!.toStringAsFixed(2)} €' : 'No disponible',
                            style: const TextStyle(color: Color(0xFFFFD166), fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (card.purchasePrice != null || card.condition != null) ...[
                    const Divider(color: Colors.white12, height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        if (card.condition != null)
                          Row(
                            children: [
                              const Text('Estado: ', style: TextStyle(color: Colors.white54, fontSize: 11)),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Color(card.condition!.colorHex).withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Color(card.condition!.colorHex), width: 0.8),
                                ),
                                child: Text(
                                  card.condition == CardCondition.graded && card.gradingScore != null && card.gradingScore!.isNotEmpty
                                      ? 'Graded ${card.gradingScore}'
                                      : card.condition!.label,
                                  style: TextStyle(
                                    color: Color(card.condition!.colorHex),
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        if (card.purchasePrice != null)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                'Coste: ${card.purchasePrice!.toStringAsFixed(2)} €',
                                style: const TextStyle(color: Colors.white70, fontSize: 11),
                              ),
                              if (card.cardmarketPrices?.averageSellPrice != null || card.cardmarketPrices?.trendPrice != null) ...[
                                Builder(builder: (_) {
                                  final current = card.cardmarketPrices?.averageSellPrice ?? card.cardmarketPrices?.trendPrice ?? 0.0;
                                  final diff = current - card.purchasePrice!;
                                  final pct = card.purchasePrice! > 0 ? (diff / card.purchasePrice! * 100) : 0.0;
                                  final isGain = diff >= 0;
                                  return Text(
                                    '${isGain ? '+' : ''}${diff.toStringAsFixed(2)} € (${pct.toStringAsFixed(1)}%)',
                                    style: TextStyle(
                                      color: isGain ? const Color(0xFF4CAF50) : const Color(0xFFE57373),
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  );
                                }),
                              ],
                            ],
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _editCard(card);
                    },
                    icon: const Icon(Icons.edit, size: 18),
                    label: const Text('Editar Carta (Foto, Precios...)'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _deleteCard(card);
                    },
                    icon: const Icon(Icons.delete, color: Colors.redAccent, size: 18),
                    label: const Text('Eliminar', style: TextStyle(color: Colors.redAccent, fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.redAccent),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
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

  double get _totalCostBasis {
    double total = 0.0;
    for (final c in _filteredCards) {
      if (c.purchasePrice != null) {
        total += c.purchasePrice!;
      }
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
        title: _buildAlbumDropdown(),
        actions: [
          IconButton(
            icon: const Icon(Icons.backup, color: Colors.white70),
            tooltip: 'Copia de seguridad',
            onPressed: _showBackupDialog,
          ),
          IconButton(
            icon: const Icon(Icons.edit_note, color: Colors.amber),
            tooltip: 'Añadir datos manualmente',
            onPressed: _openManualEntry,
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
                  child: filtered.isEmpty ? _buildEmptyState() : _buildGrid(filtered),
                ),
              ],
            ),

      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
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
              label: const Text('Escanear / Buscar', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  // ── Selector de Álbum en la AppBar (Soporte Múltiples Álbumes) ─────────────
  Widget _buildAlbumDropdown() {
    return PopupMenuButton<String>(
      tooltip: 'Cambiar de álbum',
      color: const Color(0xFF16213E),
      onSelected: (action) {
        if (action == '__new__') {
          _createNewAlbum();
        } else if (action == '__rename__') {
          _renameCurrentAlbum();
        } else if (action == '__delete__') {
          _deleteCurrentAlbum();
        } else {
          final target = _albums.firstWhere((a) => a.id == action);
          _switchAlbum(target);
        }
      },
      itemBuilder: (ctx) => [
        ..._albums.map((a) {
          final isSelected = a.id == _currentAlbum?.id;
          return PopupMenuItem<String>(
            value: a.id,
            child: Row(
              children: [
                Icon(
                  isSelected ? Icons.folder : Icons.folder_outlined,
                  color: isSelected ? Colors.amber : Colors.white70,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${a.name} (${a.cards.length})',
                    style: TextStyle(
                      color: isSelected ? Colors.amber : Colors.white,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: '__new__',
          child: Row(
            children: [
              Icon(Icons.add_circle_outline, color: Colors.greenAccent, size: 20),
              SizedBox(width: 10),
              Text('Crear nuevo álbum', style: TextStyle(color: Colors.greenAccent)),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: '__rename__',
          child: Row(
            children: [
              Icon(Icons.edit, color: Colors.white70, size: 20),
              SizedBox(width: 10),
              Text('Renombrar este álbum', style: TextStyle(color: Colors.white70)),
            ],
          ),
        ),
        if (_albums.length > 1)
          const PopupMenuItem<String>(
            value: '__delete__',
            child: Row(
              children: [
                Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                SizedBox(width: 10),
                Text('Eliminar este álbum', style: TextStyle(color: Colors.redAccent)),
              ],
            ),
          ),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🃏 ', style: TextStyle(fontSize: 20)),
          Flexible(
            child: Text(
              _currentAlbum?.name ?? 'Mi Álbum',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          const Icon(Icons.arrow_drop_down, color: Colors.amber),
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
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                selected: isSelected,
                selectedColor: Color(game.colorHex),
                backgroundColor: const Color(0xFF0F3460),
                side: BorderSide(color: isSelected ? Color(game.colorHex) : Colors.white12),
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

  Widget _buildSummaryBar(int count) {
    final value = _totalEstimatedValue;
    final cost = _totalCostBasis;
    final hasCost = cost > 0;
    final diff = value - cost;
    final pct = cost > 0 ? (diff / cost * 100) : 0.0;
    final isGain = diff >= 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      color: const Color(0xFF0F3460).withValues(alpha: 0.6),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _filterGame == TcgGame.all
                    ? '$count cartas'
                    : '${_filterGame.icon} ${_filterGame.label}: $count cartas',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              if (value > 0)
                Text(
                  'Valor: ${value.toStringAsFixed(2)} €',
                  style: const TextStyle(color: Color(0xFF00B4D8), fontSize: 13, fontWeight: FontWeight.bold),
                ),
            ],
          ),
          if (hasCost) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Coste: ${cost.toStringAsFixed(2)} €',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
                Text(
                  '${isGain ? '+' : ''}${diff.toStringAsFixed(2)} € (${pct.toStringAsFixed(1)}%)',
                  style: TextStyle(
                    color: isGain ? const Color(0xFF4CAF50) : const Color(0xFFE57373),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final isFiltered = _filterGame != TcgGame.all;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(isFiltered ? Icons.filter_list_off : Icons.collections, size: 70, color: Colors.white24),
            const SizedBox(height: 16),
            Text(
              isFiltered ? 'No hay cartas de ${_filterGame.label}' : 'Este álbum está vacío',
              style: const TextStyle(color: Colors.white70, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              isFiltered
                  ? 'Escanea cartas de ${_filterGame.label} o añádelas con el botón manual.'
                  : 'Escanea cualquier carta TCG (Pokémon, Magic, YGO, Digimon...) o introduce sus datos a mano.',
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
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Grid de cartas con margen inferior amplio para que nada se corte ─────
  Widget _buildGrid(List<PokemonCard> cards) {
    return GridView.builder(
      padding: const EdgeInsets.only(left: 12, right: 12, top: 12, bottom: 90),
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
          onTap: () => _showCardDetails(cards[index]),
          onEdit: () => _editCard(cards[index]),
          onDelete: () => _deleteCard(cards[index]),
        );
      },
    );
  }
}

// ── Tarjeta individual en el Álbum ───────────────────────────────────────────
class _CardTile extends StatelessWidget {
  final PokemonCard card;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _CardTile({
    required this.card,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onDelete,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amber),
                            ),
                          ),
                          errorWidget: (context, url, error) => Container(
                            color: const Color(0xFF0F3460),
                            child: const Icon(Icons.broken_image, color: Colors.white38, size: 40),
                          ),
                        )
                      : (card.imageUrl.isNotEmpty && File(card.imageUrl).existsSync()
                          ? Image.file(File(card.imageUrl), fit: BoxFit.cover)
                          : Container(
                              color: const Color(0xFF0F3460),
                              child: const Icon(Icons.image_not_supported, color: Colors.white38, size: 40),
                            )),
                ),

                Positioned(
                  top: 6,
                  left: 6,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: onEdit,
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.75),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.amber.withValues(alpha: 0.8), width: 1),
                        ),
                        child: const Icon(Icons.edit, color: Colors.amber, size: 13),
                      ),
                    ),
                  ),
                ),

                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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

                if (card.condition != null)
                  Positioned(
                    bottom: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: Color(card.condition!.colorHex).withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        card.condition == CardCondition.graded && card.gradingScore != null && card.gradingScore!.isNotEmpty
                            ? card.gradingScore!
                            : card.condition!.shortCode,
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 8.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            card.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            decoration: BoxDecoration(color: const Color(0xFF0F3460), borderRadius: BorderRadius.circular(6)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(color: const Color(0xFF1A1A2E), borderRadius: BorderRadius.circular(4)),
                    child: Text(
                      card.cardmarketPrices?.averageSellPrice != null
                          ? 'CM: ${card.cardmarketPrices!.averageSellPrice!.toStringAsFixed(1)}€'
                          : (card.cardmarketPrices?.trendPrice != null
                              ? 'CM: ${card.cardmarketPrices!.trendPrice!.toStringAsFixed(1)}€'
                              : 'CM: N/A'),
                      style: const TextStyle(color: Color(0xFF00B4D8), fontSize: 9.5, fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(color: const Color(0xFF1A1A2E), borderRadius: BorderRadius.circular(4)),
                    child: Text(
                      card.psa10Price != null ? 'PSA10: ${card.psa10Price!.toStringAsFixed(0)}€' : 'PSA10: N/A',
                      style: const TextStyle(color: Color(0xFFFFD166), fontSize: 9.5, fontWeight: FontWeight.bold),
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
