// ============================================================
// views/album_view.dart
// Pantalla principal: Álbum de cartas TCG con soporte para MÚLTIPLES ÁLBUMES,
// gestión de colecciones, backup/exportación y diseño espaciado.
// ============================================================

import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/pokemon_card.dart';
import '../services/album_storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/game_badge.dart';
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
                      content: Text('Copia de seguridad guardada en el portapapeles.'),
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
                      content: Text('Restauradas $count cartas con éxito.'),
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
                    style: GoogleFonts.outfit(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                GameBadge(game: card.game),
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
      backgroundColor: Colors.transparent,
      extendBody: true,
      appBar: AppBar(
        title: _buildAlbumDropdown(),
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              color: AppTheme.bgDark.withValues(alpha: 0.7),
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.backup_outlined, color: Colors.white70),
            tooltip: 'Copia de seguridad',
            onPressed: _showBackupDialog,
          ),
          IconButton(
            icon: const Icon(Icons.edit_note_rounded, color: AppTheme.primary),
            tooltip: 'Añadir datos manualmente',
            onPressed: _openManualEntry,
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppTheme.bgGradient,
        ),
        child: SafeArea(
          bottom: false,
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
              : Column(
                  children: [
                    // ── Filtro horizontal por Franquicia TCG ───────────────────
                    _buildFilterChips(),

                    // ── Hero Card con total de cartas y valor de colección ─────
                    if (_cards.isNotEmpty) _buildSummaryBar(filtered.length),

                    // ── Contenido: Grid o Estado Vacío ────────────────────────
                    Expanded(
                      child: filtered.isEmpty ? _buildEmptyState() : _buildGrid(filtered),
                    ),
                  ],
                ),
        ),
      ),

      bottomNavigationBar: _buildBottomBar(),
    );
  }

  // ── Barra inferior fija con efecto Glass ─────────────────────────────────
  Widget _buildBottomBar() {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 12,
            bottom: MediaQuery.of(context).padding.bottom + 12,
          ),
          decoration: BoxDecoration(
            color: AppTheme.bgDark.withValues(alpha: 0.8),
            border: const Border(
              top: BorderSide(color: Color(0x334B68B8), width: 1),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: ElevatedButton.icon(
                  onPressed: _openScanner,
                  icon: const Icon(Icons.camera_alt_rounded, size: 20),
                  label: Text(
                    'Escanear Carta',
                    style: GoogleFonts.outfit(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 4,
                    shadowColor: AppTheme.primary.withValues(alpha: 0.4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: OutlinedButton.icon(
                  onPressed: _openManualEntry,
                  icon: const Icon(Icons.edit_note_rounded, size: 18, color: Colors.white70),
                  label: Text(
                    'A mano',
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0x554B68B8)),
                    backgroundColor: const Color(0x3316213E),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Selector de Álbum en la AppBar ───────────────────────────────────────
  Widget _buildAlbumDropdown() {
    return PopupMenuButton<String>(
      tooltip: 'Cambiar de álbum',
      color: AppTheme.bgSurface,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0x334B68B8)),
      ),
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
                  color: isSelected ? AppTheme.primary : Colors.white70,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${a.name} (${a.cards.length})',
                    style: GoogleFonts.outfit(
                      color: isSelected ? AppTheme.primary : Colors.white,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: '__new__',
          child: Row(
            children: [
              const Icon(Icons.add_circle_outline, color: AppTheme.success, size: 20),
              const SizedBox(width: 10),
              Text(
                'Crear nuevo álbum',
                style: GoogleFonts.outfit(color: AppTheme.success, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: '__rename__',
          child: Row(
            children: [
              const Icon(Icons.edit_outlined, color: Colors.white70, size: 20),
              const SizedBox(width: 10),
              Text('Renombrar este álbum', style: GoogleFonts.outfit(color: Colors.white70)),
            ],
          ),
        ),
        if (_albums.length > 1)
          PopupMenuItem<String>(
            value: '__delete__',
            child: Row(
              children: [
                const Icon(Icons.delete_outline, color: AppTheme.loss, size: 20),
                const SizedBox(width: 10),
                Text('Eliminar este álbum', style: GoogleFonts.outfit(color: AppTheme.loss)),
              ],
            ),
          ),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.folder_special_rounded, color: AppTheme.primary, size: 20),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              _currentAlbum?.name ?? 'Mi Álbum',
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const Icon(Icons.keyboard_arrow_down_rounded, color: AppTheme.primary),
        ],
      ),
    );
  }

  // ── Chips de filtro por Franquicia ─────────────────────────────────────────
  Widget _buildFilterChips() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: TcgGame.values.map((game) {
            final isSelected = _filterGame == game;
            final count = game == TcgGame.all
                ? _cards.length
                : _cards.where((c) => c.game == game).length;
            final color = Color(game.colorHex);

            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                avatar: Icon(
                  game.iconData,
                  size: 14,
                  color: isSelected ? Colors.black : color,
                ),
                label: Text(
                  '${game.label} ($count)',
                  style: GoogleFonts.outfit(
                    color: isSelected ? Colors.black : Colors.white70,
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  ),
                ),
                selected: isSelected,
                selectedColor: color,
                backgroundColor: AppTheme.bgSurface.withValues(alpha: 0.7),
                side: BorderSide(
                  color: isSelected ? color : const Color(0x334B68B8),
                  width: 1,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
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

  // ── Hero Card de Portfolio ───────────────────────────────────────────────
  Widget _buildSummaryBar(int count) {
    final value = _totalEstimatedValue;
    final cost = _totalCostBasis;
    final hasCost = cost > 0;
    final diff = value - cost;
    final pct = cost > 0 ? (diff / cost * 100) : 0.0;
    final isGain = diff >= 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: AppTheme.heroCardGradient,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0x334B68B8), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'VALOR ESTIMADO',
                      style: GoogleFonts.outfit(
                        color: AppTheme.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${value.toStringAsFixed(2)} €',
                      style: GoogleFonts.outfit(
                        color: AppTheme.cyanAccent,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0x22FFFFFF),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: const Color(0x33FFFFFF)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.style_outlined, size: 14, color: Colors.white70),
                      const SizedBox(width: 5),
                      Text(
                        '$count cartas',
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (hasCost) ...[
              const SizedBox(height: 12),
              const Divider(color: Color(0x224B68B8), height: 1),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Coste invertido: ${cost.toStringAsFixed(2)} €',
                    style: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 12),
                  ),
                  Row(
                    children: [
                      Icon(
                        isGain ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                        color: isGain ? AppTheme.success : AppTheme.loss,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${isGain ? '+' : ''}${diff.toStringAsFixed(2)} € (${pct.toStringAsFixed(1)}%)',
                        style: GoogleFonts.outfit(
                          color: isGain ? AppTheme.success : AppTheme.loss,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final isFiltered = _filterGame != TcgGame.all;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: AppTheme.glassCardGradient,
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0x334B68B8), width: 1.5),
              ),
              child: Icon(
                isFiltered ? Icons.filter_list_off : Icons.collections_bookmark_rounded,
                size: 54,
                color: AppTheme.primary.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              isFiltered ? 'No hay cartas de ${_filterGame.label}' : 'Tu álbum está vacío',
              style: GoogleFonts.outfit(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              isFiltered
                  ? 'Escanea cartas de ${_filterGame.label} con la cámara o añádelas manualmente.'
                  : 'Empieza a coleccionar escaneando cartas de cualquier TCG con la cámara.',
              style: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _openScanner,
              icon: const Icon(Icons.camera_alt_rounded, size: 18),
              label: Text('Escanear mi primera carta', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
      padding: const EdgeInsets.only(left: 14, right: 14, top: 12, bottom: 100),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 14,
        childAspectRatio: 0.61,
      ),
      itemCount: cards.length,
      itemBuilder: (context, index) {
        return _CardTile(
          card: cards[index],
          onTap: () => _showCardDetails(cards[index]),
          onEdit: () => _editCard(cards[index]),
          onDelete: () => _deleteCard(cards[index]),
        )
            .animate()
            .fadeIn(duration: 250.ms, delay: (index.clamp(0, 10) * 30).ms)
            .slideY(begin: 0.08, end: 0, duration: 250.ms, curve: Curves.easeOutQuad);
      },
    );
  }
}

// ── Tarjeta individual en el Álbum (Dark Glass Premium) ───────────────────────
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
      child: Container(
        decoration: AppTheme.glassDecoration(
          radius: 16,
          fillColor: AppTheme.bgCard.withValues(alpha: 0.6),
          borderColor: const Color(0x334B68B8),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                    child: card.imageUrl.startsWith('http')
                        ? CachedNetworkImage(
                            imageUrl: card.imageUrl,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(
                              color: const Color(0xFF16213E),
                              child: const Center(
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
                              ),
                            ),
                            errorWidget: (context, url, error) => Container(
                              color: const Color(0xFF16213E),
                              child: const Icon(Icons.broken_image_rounded, color: Colors.white24, size: 40),
                            ),
                          )
                        : (card.imageUrl.isNotEmpty && File(card.imageUrl).existsSync()
                            ? Image.file(File(card.imageUrl), fit: BoxFit.cover)
                            : Container(
                                color: const Color(0xFF16213E),
                                child: const Icon(Icons.image_not_supported_rounded, color: Colors.white24, size: 40),
                              )),
                  ),

                  // Gradiente inferior sobre la foto para máxima legibilidad
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 50,
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Color(0xCC0B1020)],
                        ),
                      ),
                    ),
                  ),

                  // Botón flotante editar
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: onEdit,
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.65),
                            shape: BoxShape.circle,
                            border: Border.all(color: AppTheme.primary.withValues(alpha: 0.7), width: 1),
                          ),
                          child: const Icon(Icons.edit_rounded, color: AppTheme.primary, size: 13),
                        ),
                      ),
                    ),
                  ),

                  // Badge de franquicia con icono Material
                  Positioned(
                    top: 8,
                    right: 8,
                    child: GameBadge(game: card.game, showLabel: false, iconSize: 12),
                  ),

                  // Badge de condición
                  if (card.condition != null)
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Color(card.condition!.colorHex).withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          card.condition == CardCondition.graded && card.gradingScore != null && card.gradingScore!.isNotEmpty
                              ? card.gradingScore!
                              : card.condition!.shortCode,
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    card.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppTheme.bgSurface.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0x224B68B8)),
                          ),
                          child: Text(
                            card.cardmarketPrices?.averageSellPrice != null
                                ? '${card.cardmarketPrices!.averageSellPrice!.toStringAsFixed(1)}€'
                                : (card.cardmarketPrices?.trendPrice != null
                                    ? '${card.cardmarketPrices!.trendPrice!.toStringAsFixed(1)}€'
                                    : 'N/A'),
                            style: GoogleFonts.outfit(
                              color: AppTheme.cyanAccent,
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppTheme.bgSurface.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0x224B68B8)),
                          ),
                          child: Text(
                            card.psa10Price != null ? 'PSA ${card.psa10Price!.toStringAsFixed(0)}€' : 'PSA -',
                            style: GoogleFonts.outfit(
                              color: AppTheme.primary,
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
