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
import '../services/tcg_api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/game_badge.dart';
import '../widgets/pokemon_scanner_hud.dart';
import 'scanner_view.dart';
import 'manual_card_view.dart';
import 'deck_builder_view.dart';

enum AlbumSortOption {
  recent('Recientes', Icons.schedule_rounded),
  priceDesc('Mayor valor (€)', Icons.trending_up_rounded),
  priceAsc('Menor valor (€)', Icons.trending_down_rounded),
  nameAsc('Nombre (A-Z)', Icons.sort_by_alpha_rounded),
  numberAsc('Número (#)', Icons.tag_rounded);

  final String label;
  final IconData icon;
  const AlbumSortOption(this.label, this.icon);
}

enum PokemonAlbumFilter {
  all('Todas', Icons.style_rounded, 0xFF38BDF8),
  es('Español', Icons.language_rounded, 0xFF38BDF8),
  en('Inglés', Icons.language_rounded, 0xFF0EA5E9),
  ja('Japonés', Icons.translate_rounded, 0xFF22D3EE),
  ko('Coreano', Icons.translate_rounded, 0xFF818CF8),
  zh('Chino', Icons.translate_rounded, 0xFF2DD4BF),
  graded('Graduadas', Icons.workspace_premium_rounded, 0xFF34D399);

  final String label;
  final IconData iconData;
  final int colorHex;
  const PokemonAlbumFilter(this.label, this.iconData, this.colorHex);

  bool matches(PokemonCard card) {
    switch (this) {
      case PokemonAlbumFilter.all:
        return true;
      case PokemonAlbumFilter.es:
        return (card.language ?? 'es').toLowerCase() == 'es';
      case PokemonAlbumFilter.en:
        return (card.language ?? '').toLowerCase() == 'en';
      case PokemonAlbumFilter.ja:
        return (card.language ?? '').toLowerCase() == 'ja';
      case PokemonAlbumFilter.ko:
        return (card.language ?? '').toLowerCase() == 'ko';
      case PokemonAlbumFilter.zh:
        final l = (card.language ?? '').toLowerCase();
        return l == 'zh' || l == 'zh-tw' || l == 'zh-cn';
      case PokemonAlbumFilter.graded:
        return card.condition == CardCondition.graded;
    }
  }
}

class AlbumView extends StatefulWidget {
  const AlbumView({super.key});

  @override
  State<AlbumView> createState() => _AlbumViewState();
}

class _AlbumViewState extends State<AlbumView> {
  final AlbumStorageService _storage = AlbumStorageService();
  final TcgApiService _apiService = TcgApiService();
  final TextEditingController _searchController = TextEditingController();

  List<TcgAlbum> _albums = [];
  TcgAlbum? _currentAlbum;
  List<PokemonCard> _cards = [];
  bool _isLoading = true;
  bool _isRefreshingPrices = false;
  bool _showSearchBar = false;
  String _searchQuery = '';
  AlbumSortOption _sortOption = AlbumSortOption.recent;
  PokemonAlbumFilter _activeFilter = PokemonAlbumFilter.all;
  int _bottomNavIndex = 0; // 0 Colección, 1 Mazos, 2 Historial, 3 Mercado

  @override
  void initState() {
    super.initState();
    _loadAlbumsAndActive();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
        backgroundColor: const Color(0xFF0C1626),
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
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
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
        backgroundColor: const Color(0xFF0C1626),
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
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
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
        backgroundColor: const Color(0xFF0C1626),
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
      backgroundColor: const Color(0xFF0C1626),
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
              leading: const Icon(Icons.file_upload, color: AppTheme.primary),
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
              leading: const Icon(Icons.file_download, color: AppTheme.cyanAccent),
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
        backgroundColor: const Color(0xFF0C1626),
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
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
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
    final returnedTab = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => const ScannerView(),
      ),
    );
    await _loadAlbumsAndActive();
    if (returnedTab != null && mounted) {
      _onBottomTabSelected(returnedTab);
    }
  }

  void _onBottomTabSelected(int index) {
    // El escaneo SOLO se dispara con la Pokéball central.
    // Las pestañas cambian entre Colección, Mazos, Historial y Mercado.
    setState(() {
      _bottomNavIndex = index;
    });
  }

  Future<void> _openManualEntry() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const ManualCardView(),
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
        backgroundColor: const Color(0xFF0C1626),
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

  Future<void> _updateCardQuantity(PokemonCard card, int newQuantity) async {
    if (newQuantity <= 0) {
      await _deleteCard(card);
      return;
    }
    final updated = card.copyWith(quantity: newQuantity);
    await _storage.updateCard(updated);
    await _loadAlbumsAndActive();
  }

  Future<void> _refreshAlbumPrices() async {
    if (_isRefreshingPrices || _cards.isEmpty) return;

    setState(() => _isRefreshingPrices = true);
    int updatedCount = 0;

    try {
      final currentCards = List<PokemonCard>.from(_cards);
      const int batchSize = 6;

      for (int start = 0; start < currentCards.length; start += batchSize) {
        final end = (start + batchSize < currentCards.length)
            ? start + batchSize
            : currentCards.length;
        final batchIndices = List<int>.generate(end - start, (i) => start + i);

        final results = await Future.wait(
          batchIndices.map((idx) async {
            final c = currentCards[idx];
            if (c.id.startsWith('custom_')) return null;
            return _apiService.fetchCardDetail(
              c.id,
              lang: c.language ?? 'es',
            );
          }),
        );

        for (int j = 0; j < batchIndices.length; j++) {
          final detail = results[j];
          final idx = batchIndices[j];
          if (detail?.cardmarketPrices != null) {
            currentCards[idx] = currentCards[idx].copyWith(
              cardmarketPrices: detail!.cardmarketPrices,
            );
            updatedCount++;
          }
        }
      }

      if (updatedCount > 0) {
        await _storage.saveAlbum(currentCards);
        await _loadAlbumsAndActive();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              updatedCount > 0
                  ? 'Precios actualizados en $updatedCount cartas.'
                  : 'Los precios de tus cartas ya están al día.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al actualizar precios: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isRefreshingPrices = false);
      }
    }
  }

  Future<void> _showCardDetails(PokemonCard initialCard) async {
    PokemonCard card = initialCard;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0C1626),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
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
                child: PokemonCard.isValidNetworkUrl(card.imageUrl)
                    ? CachedNetworkImage(
                        imageUrl: card.imageUrl,
                        height: 240,
                        memCacheWidth: 750,
                        fit: BoxFit.contain,
                        placeholder: (_, __) => const SizedBox(
                          height: 240,
                          child: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
                        ),
                        errorWidget: (_, __, ___) => const SizedBox(
                          height: 240,
                          child: Icon(Icons.broken_image, color: Colors.white38, size: 60),
                        ),
                      )
                    : (card.imageUrl.isNotEmpty && File(card.imageUrl).existsSync()
                        ? Image.file(File(card.imageUrl), height: 240, cacheWidth: 750, fit: BoxFit.contain)
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
                GameBadge(game: card.game, language: card.language),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    card.setName.isNotEmpty ? '${card.setName} • #${card.number}' : 'Ref: #${card.number}',
                    style: const TextStyle(color: Colors.white60, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Selector de cantidad de copias (x1, x2, x3...)
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF10203A),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppTheme.primary.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 28),
                        padding: EdgeInsets.zero,
                        icon: const Icon(Icons.remove, size: 15, color: Colors.white70),
                        onPressed: card.quantity > 1
                            ? () async {
                                final updated = card.copyWith(quantity: card.quantity - 1);
                                setModalState(() => card = updated);
                                await _updateCardQuantity(card, updated.quantity);
                              }
                            : null,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text(
                          'x${card.quantity}',
                          style: GoogleFonts.outfit(
                            color: AppTheme.primary,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 28),
                        padding: EdgeInsets.zero,
                        icon: const Icon(Icons.add, size: 15, color: AppTheme.primary),
                        onPressed: () async {
                          final updated = card.copyWith(quantity: card.quantity + 1);
                          setModalState(() => card = updated);
                          await _updateCardQuantity(card, updated.quantity);
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFF10203A), borderRadius: BorderRadius.circular(10)),
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
                            style: TextStyle(color: AppTheme.cyanAccent, fontSize: 16, fontWeight: FontWeight.bold),
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
                            style: const TextStyle(color: AppTheme.primary, fontSize: 16, fontWeight: FontWeight.bold),
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
                                      color: isGain ? AppTheme.success : AppTheme.loss,
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
            NeonPillButton(
              label: 'Editar Carta y Estadísticas',
              icon: Icons.bar_chart_rounded,
              style: NeonButtonStyle.green,
              onPressed: () {
                Navigator.pop(ctx);
                _editCard(card);
              },
            ),
            const SizedBox(height: 10),
            NeonPillButton(
              label: 'Eliminar de mi Colección',
              icon: Icons.delete_outline_rounded,
              style: NeonButtonStyle.darkStats,
              onPressed: () {
                Navigator.pop(ctx);
                _deleteCard(card);
              },
            ),
          ],
        ),
      ),
      ),
    );
  }

  List<PokemonCard> get _filteredCards {
    var list = _activeFilter == PokemonAlbumFilter.all
        ? List<PokemonCard>.from(_cards)
        : _cards.where(_activeFilter.matches).toList();

    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.trim().toLowerCase();
      list = list.where((c) {
        return c.name.toLowerCase().contains(q) ||
            c.setName.toLowerCase().contains(q) ||
            c.number.toLowerCase().contains(q);
      }).toList();
    }

    double unitPrice(PokemonCard c) =>
        c.cardmarketPrices?.averageSellPrice ??
        c.cardmarketPrices?.trendPrice ??
        0.0;

    switch (_sortOption) {
      case AlbumSortOption.recent:
        break;
      case AlbumSortOption.priceDesc:
        list.sort((a, b) => unitPrice(b).compareTo(unitPrice(a)));
        break;
      case AlbumSortOption.priceAsc:
        list.sort((a, b) => unitPrice(a).compareTo(unitPrice(b)));
        break;
      case AlbumSortOption.nameAsc:
        list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
      case AlbumSortOption.numberAsc:
        list.sort((a, b) {
          final na = int.tryParse(a.number.replaceAll(RegExp(r'[^\d]'), '')) ?? 99999;
          final nb = int.tryParse(b.number.replaceAll(RegExp(r'[^\d]'), '')) ?? 99999;
          return na.compareTo(nb);
        });
        break;
    }

    return list;
  }

  int get _totalFilteredCopies {
    int count = 0;
    for (final c in _filteredCards) {
      count += c.quantity;
    }
    return count;
  }

  double get _totalEstimatedValue {
    double total = 0.0;
    for (final c in _filteredCards) {
      final price = c.cardmarketPrices?.averageSellPrice ??
          c.cardmarketPrices?.trendPrice ??
          0.0;
      total += price * c.quantity;
    }
    return total;
  }

  double get _totalCostBasis {
    double total = 0.0;
    for (final c in _filteredCards) {
      if (c.purchasePrice != null) {
        total += c.purchasePrice! * c.quantity;
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
        title: _buildAppBarTitle(),
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              color: AppTheme.bgDark.withValues(alpha: 0.7),
            ),
          ),
        ),
        actions: _buildAppBarActions(),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppTheme.bgGradient,
        ),
        child: SafeArea(
          bottom: false,
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: AppTheme.primary))
              : IndexedStack(
                  index: _bottomNavIndex,
                  children: [
                    _buildCollectionPage(filtered),
                    const DeckBuilderView(),
                    _buildHistoryPage(),
                    _buildMarketPage(),
                  ],
                ),
        ),
      ),
      bottomNavigationBar: PokeballBottomBar(
        selectedIndex: _bottomNavIndex,
        onCenterScanTap: _openScanner,
        onTabSelected: _onBottomTabSelected,
      ),
    );
  }

  Widget _buildAppBarTitle() {
    switch (_bottomNavIndex) {
      case 1:
        return Text('Mis Mazos',
            style: GoogleFonts.outfit(
                color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold));
      case 2:
        return Text('Historial',
            style: GoogleFonts.outfit(
                color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold));
      case 3:
        return Text('Mercado',
            style: GoogleFonts.outfit(
                color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold));
      case 0:
      default:
        return _buildAlbumDropdown();
    }
  }

  List<Widget> _buildAppBarActions() {
    if (_bottomNavIndex != 0) {
      return const [];
    }
    return [
      IconButton(
        icon: Icon(
          _showSearchBar ? Icons.search_off_rounded : Icons.search_rounded,
          color: _showSearchBar ? AppTheme.primary : Colors.white70,
        ),
        tooltip: 'Buscar en el álbum',
        onPressed: () {
          setState(() {
            _showSearchBar = !_showSearchBar;
            if (!_showSearchBar) {
              _searchController.clear();
              _searchQuery = '';
            }
          });
        },
      ),
      if (_cards.isNotEmpty)
        IconButton(
          icon: _isRefreshingPrices
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppTheme.cyanAccent),
                )
              : const Icon(Icons.sync_rounded, color: Colors.white70),
          tooltip: 'Actualizar precios de mercado',
          onPressed: _isRefreshingPrices ? null : _refreshAlbumPrices,
        ),
      IconButton(
        icon: const Icon(Icons.backup_outlined, color: Colors.white70),
        tooltip: 'Copia de seguridad',
        onPressed: _showBackupDialog,
      ),
      IconButton(
        icon: const Icon(Icons.edit_note_rounded, color: AppTheme.primary),
        tooltip: 'Añadir carta manualmente',
        onPressed: _openManualEntry,
      ),
    ];
  }

  // ── Página 0: Colección ───────────────────────────────────────────────────
  Widget _buildCollectionPage(List<PokemonCard> filtered) {
    return Column(
      children: [
        _buildFilterChips(),
        if (_showSearchBar || _sortOption != AlbumSortOption.recent)
          _buildSearchAndSortBar(),
        if (_cards.isNotEmpty) _buildSummaryBar(_totalFilteredCopies),
        Expanded(
          child: filtered.isEmpty ? _buildEmptyState() : _buildGrid(filtered),
        ),
      ],
    );
  }

  // ── Página 2: Historial (últimas cartas añadidas) ─────────────────────────
  Widget _buildHistoryPage() {
    final recent = _cards.reversed.take(40).toList();
    if (recent.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'Aún no has escaneado ninguna carta.',
            style: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 14),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
      itemCount: recent.length,
      itemBuilder: (ctx, i) {
        final card = recent[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: AppTheme.glassDecoration(radius: 14),
          child: ListTile(
            leading: _HistoryThumb(card: card),
            title: Text(
              card.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(color: Colors.white),
            ),
            subtitle: Text(
              card.setName.isNotEmpty
                  ? '${card.setName} • #${card.number}'
                  : '#${card.number}',
              style: GoogleFonts.inter(color: Colors.white54),
            ),
            trailing: Text(
              '${card.quantity} copia${card.quantity > 1 ? 's' : ''}',
              style: GoogleFonts.outfit(color: AppTheme.cyanAccent),
            ),
            onTap: () => _showCardDetails(card),
          ),
        );
      },
    );
  }

  // ── Página 3: Mercado (cartas ordenadas por valor) ────────────────────────
  Widget _buildMarketPage() {
    final priced = _cards.where((c) {
      final p = c.cardmarketPrices?.averageSellPrice ??
          c.cardmarketPrices?.trendPrice;
      return p != null && p > 0;
    }).toList()
      ..sort((a, b) {
        final pa = a.cardmarketPrices?.averageSellPrice ??
            a.cardmarketPrices?.trendPrice ??
            0.0;
        final pb = b.cardmarketPrices?.averageSellPrice ??
            b.cardmarketPrices?.trendPrice ??
            0.0;
        return pb.compareTo(pa);
      });

    if (priced.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.show_chart_rounded,
                  size: 54,
                  color: AppTheme.cyanAccent.withValues(alpha: 0.7)),
              const SizedBox(height: 14),
              Text(
                'Sin precios de mercado',
                style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                'Pulsa el icono de sincronización en la Colección para actualizar los precios de Cardmarket.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
      itemCount: priced.length,
      itemBuilder: (ctx, i) {
        final card = priced[i];
        final price = card.cardmarketPrices?.averageSellPrice ??
            card.cardmarketPrices?.trendPrice;
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: AppTheme.glassDecoration(radius: 14),
          child: ListTile(
            leading: _HistoryThumb(card: card),
            title: Text(
              card.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(color: Colors.white),
            ),
            subtitle: Text(
              card.setName.isNotEmpty
                  ? '${card.setName} • #${card.number}'
                  : '#${card.number}',
              style: GoogleFonts.inter(color: Colors.white54),
            ),
            trailing: price != null
                ? Text(
                    '${price.toStringAsFixed(2)} €',
                    style: GoogleFonts.outfit(
                      color: AppTheme.primary,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  )
                : null,
            onTap: () => _showCardDetails(card),
          ),
        );
      },
    );
  }

  Widget _buildSearchAndSortBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 40,
              child: TextField(
                controller: _searchController,
                onChanged: (val) => setState(() => _searchQuery = val),
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Buscar por nombre, set o # en tu álbum...',
                  hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                  prefixIcon: const Icon(Icons.search, color: Colors.white54, size: 18),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, color: Colors.white54, size: 16),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: AppTheme.bgSurface.withValues(alpha: 0.85),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0x334B68B8)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0x334B68B8)),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<AlbumSortOption>(
            tooltip: 'Ordenar cartas',
            color: AppTheme.bgSurface,
            onSelected: (opt) => setState(() => _sortOption = opt),
            itemBuilder: (_) => AlbumSortOption.values.map((opt) {
              final selected = _sortOption == opt;
              return PopupMenuItem<AlbumSortOption>(
                value: opt,
                child: Row(
                  children: [
                    Icon(
                      opt.icon,
                      size: 18,
                      color: selected ? AppTheme.primary : Colors.white70,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      opt.label,
                      style: GoogleFonts.outfit(
                        color: selected ? AppTheme.primary : Colors.white,
                        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: AppTheme.bgSurface.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0x3322D3EE)),
              ),
              child: Row(
                children: [
                  Icon(_sortOption.icon, size: 16, color: AppTheme.primary),
                  const SizedBox(width: 4),
                  Text(
                    _sortOption.label,
                    style: GoogleFonts.outfit(color: Colors.white, fontSize: 11.5),
                  ),
                ],
              ),
            ),
          ),
        ],
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
          final target = _albums.firstWhere(
            (a) => a.id == action,
            orElse: () => _albums.first,
          );
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

  // ── Chips de filtro para Pokémon TCG (Por Idioma y Graduadas) ─────────────
  Widget _buildFilterChips() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: PokemonAlbumFilter.values.map((filter) {
            final isSelected = _activeFilter == filter;
            final count = _cards.where(filter.matches).fold<int>(
                  0,
                  (sum, c) => sum + c.quantity,
                );
            final color = Color(filter.colorHex);

            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                avatar: Icon(
                  filter.iconData,
                  size: 14,
                  color: isSelected ? Colors.white : color,
                ),
                label: Text(
                  '${filter.label} ($count)',
                  style: GoogleFonts.outfit(
                    color: isSelected ? Colors.white : Colors.white70,
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  ),
                ),
                selected: isSelected,
                selectedColor: color.withValues(alpha: 0.85),
                backgroundColor: AppTheme.bgSurface.withValues(alpha: 0.7),
                side: BorderSide(
                  color: isSelected ? color : const Color(0x3322D3EE),
                  width: 1,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
                onSelected: (selected) {
                  if (selected) setState(() => _activeFilter = filter);
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
          border: Border.all(color: const Color(0x3322D3EE), width: 1),
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
    final isFiltered = _activeFilter != PokemonAlbumFilter.all || _searchQuery.isNotEmpty;
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
                border: Border.all(color: AppTheme.cyanAccent.withValues(alpha: 0.4), width: 1.5),
              ),
              child: Icon(
                isFiltered ? Icons.filter_list_off : Icons.collections_bookmark_rounded,
                size: 54,
                color: AppTheme.cyanAccent.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              isFiltered ? 'No hay cartas para este filtro' : 'Tu álbum Pokémon está vacío',
              style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              isFiltered
                  ? 'Prueba a cambiar el filtro de idioma o búsqueda.'
                  : 'Empieza a coleccionar escaneando tus cartas Pokémon con la cámara.',
              style: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            NeonPillButton(
              label: 'Escanear mi primera carta',
              icon: Icons.camera_alt_rounded,
              style: NeonButtonStyle.primary,
              onPressed: _openScanner,
            ),
          ],
        ),
      ),
    );
  }

  // ── Grid adaptable a móviles, phablets y tablets ─────────────────────────
  Widget _buildGrid(List<PokemonCard> cards) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final crossAxisCount = screenWidth >= 900 ? 4 : (screenWidth >= 600 ? 3 : 2);

    return GridView.builder(
      padding: EdgeInsets.only(
        left: 14,
        right: 14,
        top: 12,
        bottom: 130 + MediaQuery.paddingOf(context).bottom,
      ),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 12,
        mainAxisSpacing: 14,
        childAspectRatio: 0.63,
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
          borderColor: const Color(0x3322D3EE),
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
                    child: PokemonCard.isValidNetworkUrl(card.imageUrl)
                        ? CachedNetworkImage(
                            imageUrl: card.thumbnailImageUrl,
                            memCacheWidth: 320,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(
                              color: const Color(0xFF0C1626),
                              child: const Center(
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
                              ),
                            ),
                            errorWidget: (context, url, error) => Container(
                              color: const Color(0xFF0C1626),
                              child: const Icon(Icons.broken_image_rounded, color: Colors.white24, size: 40),
                            ),
                          )
                        : (card.imageUrl.isNotEmpty && File(card.imageUrl).existsSync()
                            ? Image.file(File(card.imageUrl), cacheWidth: 320, fit: BoxFit.cover)
                            : Container(
                                color: const Color(0xFF0C1626),
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

                  // Badge de idioma de la carta Pokémon
                  Positioned(
                    top: 8,
                    right: 8,
                    child: GameBadge(game: card.game, language: card.language, showLabel: true, fontSize: 9, iconSize: 12),
                  ),

                  // Badge de cantidad si hay copias repetidas (x2, x3...)
                  if (card.quantity > 1)
                    Positioned(
                      bottom: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.white70, width: 0.8),
                        ),
                        child: Text(
                          'x${card.quantity}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
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

// ── Miniatura de carta reutilizable en Historial / Mercado ────────────────────
class _HistoryThumb extends StatelessWidget {
  final PokemonCard card;

  const _HistoryThumb({required this.card});

  @override
  Widget build(BuildContext context) {
    if (PokemonCard.isValidNetworkUrl(card.imageUrl)) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CachedNetworkImage(
          imageUrl: card.thumbnailImageUrl,
          width: 46,
          height: 64,
          memCacheWidth: 160,
          fit: BoxFit.cover,
          placeholder: (_, __) => Container(
            width: 46,
            height: 64,
            color: Colors.black26,
          ),
          errorWidget: (_, __, ___) => Container(
            width: 46,
            height: 64,
            color: Colors.black26,
            child: const Icon(Icons.broken_image,
                color: Colors.white38, size: 20),
          ),
        ),
      );
    }
    if (card.imageUrl.isNotEmpty && File(card.imageUrl).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(File(card.imageUrl),
            width: 46, height: 64, cacheWidth: 160, fit: BoxFit.cover),
      );
    }
    return Container(
      width: 46,
      height: 64,
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.catching_pokemon,
          color: Colors.white38, size: 20),
    );
  }
}
