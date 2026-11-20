// ============================================================
// views/scanner_view.dart
// Pantalla de escaneo Pokémon TCG con estética Neon HUD:
// - Logo Pokémon TCG SCANNER
// - Visor HUD con esquinas neón Cian/Amarillo, láser y etiqueta flotante
// - Tarjeta de resultado con precio estimado y los 3 botones píldora neón
// - Barra inferior con Pokéball central luminosa
// ============================================================

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/card_number.dart';
import '../models/pokemon_card.dart';
import '../services/album_storage_service.dart';
import '../services/ocr_service.dart';
import '../services/tcg_api_service.dart';
import '../services/image_matching_service.dart';
import '../theme/app_theme.dart';
import '../widgets/game_badge.dart';
import '../widgets/pokemon_scanner_hud.dart';
import 'card_crop_view.dart';
import 'live_camera_view.dart';
import 'manual_card_view.dart';

class ScannerView extends StatefulWidget {
  final TcgGame initialGame;

  const ScannerView({
    super.key,
    this.initialGame = TcgGame.pokemon,
  });

  @override
  State<ScannerView> createState() => _ScannerViewState();
}

class _ScannerViewState extends State<ScannerView> {
  // ── Servicios ─────────────────────────────────────────────────────────────
  final OcrService _ocrService = OcrService();
  final TcgApiService _apiService = TcgApiService();
  final AlbumStorageService _storage = AlbumStorageService();
  final ImagePicker _picker = ImagePicker();
  final ImageMatchingService _imageMatcher = ImageMatchingService();

  // ── Estado ────────────────────────────────────────────────────────────────
  File? _capturedImage;
  OcrResult? _ocrResult;
  List<PokemonCard> _searchResults = [];
  PokemonCard? _selectedCard;
  bool _isProcessing = false;
  bool _isMatchingImages = false;
  bool _expandedHeroCard = false;
  Map<String, int> _visualScores = {};
  String? _errorMessage;
  late TcgGame _selectedGame;
  CardLanguage _selectedLanguage = CardLanguage.auto;
  CardLanguage? _detectedLanguage;
  int _searchRequestId = 0;
  int _visualRequestId = 0;
  bool _keepCapturedImage = false;

  // ── Controladores ─────────────────────────────────────────────────────────
  final TextEditingController _manualSearchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedGame = widget.initialGame;
  }

  void _deleteTempFileIfNeeded(File? file) {
    if (file == null) return;
    try {
      if (file.existsSync() && !file.path.contains('card_images')) {
        file.deleteSync();
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    unawaited(_ocrService.dispose());
    _imageMatcher.dispose();
    if (!_keepCapturedImage) {
      _deleteTempFileIfNeeded(_capturedImage);
    }
    _manualSearchController.dispose();
    super.dispose();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // PASO 1: Capturar imagen con la galería o la cámara en vivo.
  // ──────────────────────────────────────────────────────────────────────────
  Future<void> _captureImage([ImageSource source = ImageSource.gallery]) async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: source,
        imageQuality: 92,
        maxWidth: 1800,
        maxHeight: 2400,
        preferredCameraDevice: CameraDevice.rear,
      );

      if (photo == null) return;
      if (!mounted) return;

      await _processImageFile(File(photo.path));
    } catch (e) {
      _showError('Error al capturar la imagen: $e');
    }
  }

  Future<void> _openLiveCamera() async {
    try {
      final File? captured = await Navigator.of(context).push<File>(
        MaterialPageRoute(builder: (_) => const LiveCameraView()),
      );

      if (captured == null || !mounted) return;
      await _processImageFile(captured);
    } catch (e) {
      _showError('Error al abrir la cámara: $e');
    }
  }

  /// Recorte manual opcional + OCR sobre la imagen elegida/capturada.
  Future<void> _processImageFile(File originalFile) async {
    if (!mounted) return;

    final croppedFile = await Navigator.of(context).push<File>(
      MaterialPageRoute(
        builder: (_) => CardCropView(imageFile: originalFile),
      ),
    );

    if (!mounted) return;
    if (croppedFile == null) {
      _deleteTempFileIfNeeded(originalFile);
      return;
    }

    if (croppedFile.path != originalFile.path) {
      _deleteTempFileIfNeeded(originalFile);
    }

    final previousImage = _capturedImage;
    final imageFile = croppedFile;
    setState(() {
      _capturedImage = imageFile;
      _isProcessing = true;
      _isMatchingImages = false;
      _visualScores = {};
      _errorMessage = null;
      _searchResults = [];
      _selectedCard = null;
    });
    if (previousImage != null && previousImage.path != imageFile.path) {
      _deleteTempFileIfNeeded(previousImage);
    }

    await _runOcr(imageFile);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // PASO 2: Reconocimiento OCR local multiidioma con ordenación espacial.
  // ──────────────────────────────────────────────────────────────────────────
  Future<void> _runOcr(File imageFile) async {
    try {
      final result = await _ocrService.extractFromImage(
        imageFile,
        language: _selectedLanguage,
      );

      if (!mounted) return;

      setState(() {
        _ocrResult = result;
        _detectedLanguage = result.detectedLanguage == CardLanguage.auto
            ? null
            : result.detectedLanguage;
      });

      if (result.pokemonName != null || result.collectionNumber != null) {
        if (result.collectionNumber != null) {
          _manualSearchController.text = result.pokemonName != null
              ? '${result.pokemonName} ${result.collectionNumber}'
              : result.collectionNumber!;
        } else if (result.pokemonName != null) {
          _manualSearchController.text = result.pokemonName!;
        }

        await _searchApi(
          pokemonName: result.pokemonName,
          collectionNumber: result.collectionNumber,
          cardNumber: result.cardNumber,
        );
      } else {
        setState(() {
          _isProcessing = false;
          _errorMessage =
              'No se detectó el texto con claridad. Encuadra bien la carta con buena luz o usa el buscador superior.';
        });
      }
    } catch (e) {
      _showError('Error durante el OCR: $e');
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // PASO 3: Consulta al catálogo SQLite local + APIs TCG.
  // ──────────────────────────────────────────────────────────────────────────
  Future<void> _searchApi({
    String? pokemonName,
    String? collectionNumber,
    CardNumber? cardNumber,
    String? manualQuery,
  }) async {
    final int currentRequestId = ++_searchRequestId;

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
      _selectedCard = null;
    });

    try {
      String queryName = '';
      String? targetNumber;
      CardNumber? targetCardNumber = cardNumber;

      if (manualQuery != null && manualQuery.isNotEmpty) {
        final parts = _parseManualQuery(manualQuery);
        queryName = parts.$1;
        targetNumber = parts.$2;
        targetCardNumber = targetNumber == null
            ? null
            : CardNumber.parse(targetNumber);
      } else {
        queryName = pokemonName ?? '';
        targetNumber = collectionNumber;
      }

      final effectiveLang = _selectedLanguage == CardLanguage.auto
          ? (_detectedLanguage ?? CardLanguage.auto)
          : _selectedLanguage;

      final outcome = await _apiService
          .searchUniversalOutcome(
            query: queryName,
            number: targetNumber,
            cardNumber: targetCardNumber,
            game: _selectedGame,
            language: effectiveLang,
          )
          .timeout(const Duration(seconds: 12));

      if (!mounted || currentRequestId != _searchRequestId) return;

      if (outcome.cards.isEmpty) {
        setState(() {
          _isProcessing = false;
          _errorMessage =
              'No se encontraron cartas para esta búsqueda. '
              'Puedes introducir sus datos manualmente pulsando Ajustes o el icono de edición.';
        });
        return;
      }

      final first = outcome.cards.first;
      setState(() {
        _searchResults = outcome.cards;
        _selectedCard = outcome.autoSelect ? first : null;
        _isProcessing = false;
      });

      // El precio se carga después: la carta ya está visible.
      if (_selectedCard != null) {
        unawaited(_enrichPrice(first, currentRequestId));
      }

      if (_capturedImage != null && outcome.cards.length > 1) {
        _runVisualMatching(outcome.cards, currentRequestId);
      }
    } on TimeoutException {
      _showError(
        'La búsqueda tardó demasiado. Revisa tu conexión o usa el catálogo local.',
      );
    } on TcgApiException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError('Error de conexión: $e');
    }
  }

  Future<void> _enrichPrice(PokemonCard card, int requestId) async {
    if (card.cardmarketPrices != null) return;

    try {
      final detail = await _apiService.fetchCardDetail(
        card.id,
        lang: card.language ?? _selectedLanguage.apiCode,
      );
      if (!mounted || requestId != _searchRequestId) return;
      if (_selectedCard?.id != card.id || detail == null) return;
      setState(() => _selectedCard = detail);
    } catch (_) {
      // La carta ya se mostró; el precio es opcional.
    }
  }

  /// Emparejamiento visual en segundo plano (Isolate):
  Future<void> _runVisualMatching(
    List<PokemonCard> candidates,
    int requestId,
  ) async {
    if (_capturedImage == null || !mounted) return;

    final int visualId = ++_visualRequestId;
    setState(() => _isMatchingImages = true);

    try {
      final rankedResults = await _imageMatcher.rankCardsByVisualSimilarity(
        userPhotoFile: _capturedImage!,
        candidateCards: candidates,
        maxCandidatesToCompare: 6,
      );

      if (!mounted ||
          visualId != _visualRequestId ||
          requestId != _searchRequestId) {
        return;
      }

      final scores = <String, int>{};
      for (final result in rankedResults) {
        if (result.matchPercentage > 0) {
          scores[result.card.id] = result.matchPercentage;
        }
      }

      final sortedCards = rankedResults.map((result) => result.card).toList();
      final best = rankedResults.first;
      final second = rankedResults.length > 1 ? rankedResults[1] : null;

      final canSelect = _selectedCard == null &&
          best.similarity >= 0.82 &&
          (second == null || best.similarity - second.similarity >= 0.08);

      setState(() {
        _isMatchingImages = false;
        _visualScores = scores;
        _searchResults = sortedCards;
        if (canSelect) {
          _selectedCard = best.card;
        }
      });

      if (canSelect) {
        unawaited(_enrichPrice(best.card, requestId));
      }
    } catch (_) {
      if (mounted && visualId == _visualRequestId) {
        setState(() => _isMatchingImages = false);
      }
    }
  }

  Future<void> _onManualSearch([String? overrideQuery]) async {
    final query = overrideQuery ?? _manualSearchController.text.trim();
    if (query.isEmpty) return;
    if (overrideQuery != null) {
      _manualSearchController.text = overrideQuery;
    }
    await _searchApi(manualQuery: query);
  }

  Future<void> _selectCard(PokemonCard card) async {
    setState(() => _isProcessing = true);

    try {
      if (card.cardmarketPrices == null || card.setName.isEmpty) {
        final detailed = await _apiService.fetchCardDetail(
          card.id,
          lang: card.language ?? _selectedLanguage.apiCode,
        );
        if (mounted) {
          setState(() {
            _selectedCard = detailed ?? card;
            _isProcessing = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _selectedCard = card;
            _isProcessing = false;
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _selectedCard = card;
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _saveCard() async {
    final card = _selectedCard;
    if (card == null) return;

    setState(() => _isProcessing = true);

    try {
      final isNew = await _storage.saveCard(card);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isNew
                ? '¡"${card.name}" añadida a tu Colección!'
                : '¡Añadida otra copia de "${card.name}" a tu Colección!',
          ),
          backgroundColor: isNew ? const Color(0xFF00C853) : AppTheme.success,
          duration: const Duration(seconds: 2),
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo guardar la carta: $e'),
          backgroundColor: AppTheme.loss,
        ),
      );
    }
  }

  Future<void> _openManualEntry({PokemonCard? cardToEdit}) async {
    _keepCapturedImage = true;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ManualCardView(
          cardToEdit: cardToEdit,
          initialName: _ocrResult?.pokemonName ?? _manualSearchController.text,
          initialNumber: _ocrResult?.collectionNumber,
          initialImage: _capturedImage,
          initialLanguage: _selectedLanguage,
          initialGame: TcgGame.pokemon,
        ),
      ),
    );
    if (saved == true && mounted) {
      Navigator.of(context).pop();
    } else {
      _keepCapturedImage = false;
    }
  }

  (String, String?) _parseManualQuery(String input) {
    var clean = input.replaceAll(RegExp(r'["״“”«»' "'" r']'), ' ').trim();

    // Si el usuario pega solo un número (incluidos promos como SWSH001),
    // usar el parser único en vez de las heurísticas de texto.
    final onlyNumber = CardNumber.parse(clean);
    if (onlyNumber != null &&
        RegExp(
          r'^\s*(?:[A-Za-z]{2,5}\d{2,4}|[A-Za-z0-9]{1,6}\s*\d{1,4}\s*/\s*\d{1,4})\s*$',
          caseSensitive: false,
        ).hasMatch(clean)) {
      return ('', onlyNumber.display);
    }

    clean = clean
        .replaceAll(
          RegExp(
            r'\b(pok[eé]mon\s+)?(b[aá]sico|g[aá]sico|c[aá]sico|p[aá]sico|fase\s*\d*|stage\s*\d*|basic)\b',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(
          RegExp(r'(たね|1進化|2進化|기본|1진화|2진화|基础|1阶进化|2阶进化)'),
          ' ',
        )
        .trim();

    final matchAlphaFraction =
        RegExp(r'\b([A-Za-z]{1,6})?(\d{1,4})/(?:[A-Za-z]{1,6})?(\d{1,4})\b')
            .firstMatch(clean);
    if (matchAlphaFraction != null) {
      final prefix = matchAlphaFraction.group(1) ?? '';
      final numPart = matchAlphaFraction.group(2)!;
      final totalPart = matchAlphaFraction.group(3)!;
      final fullNumber =
          prefix.isNotEmpty ? '$prefix$numPart/$totalPart' : '$numPart/$totalPart';
      final name = clean.replaceFirst(matchAlphaFraction.group(0)!, '').trim();
      return (name, fullNumber);
    }

    final matchFractionWithPrefixSpace =
        RegExp(r'\b([A-Za-z]{2,6})\s+(\d{1,4}/\d{1,4})\b').firstMatch(clean);
    if (matchFractionWithPrefixSpace != null) {
      final number =
          '${matchFractionWithPrefixSpace.group(1)} ${matchFractionWithPrefixSpace.group(2)}';
      final name =
          clean.replaceFirst(matchFractionWithPrefixSpace.group(0)!, '').trim();
      return (name, number);
    }

    final matchSetCode = RegExp(
            r'\b([A-Za-z0-9]{2,6}[A-Za-z0-9\.\-]*\s*[-–]\s*\d{1,4})\b')
        .firstMatch(clean);
    if (matchSetCode != null) {
      final code = matchSetCode.group(1)!;
      final name = clean.replaceFirst(matchSetCode.group(0)!, '').trim();
      return (name, code);
    }

    final matchSingle =
        RegExp(r'^(.*?)(?:#|\s+)(\d{1,4})\s*$').firstMatch(clean);
    if (matchSingle != null && matchSingle.group(1)!.trim().isNotEmpty) {
      final name = matchSingle.group(1)!.trim();
      final number = matchSingle.group(2)!.trim();
      return (name, number);
    }

    final numberOnlyMatch = RegExp(
      r'^(?:#|n[oº°]\.?\s*)?(\d{1,8}(?:/\d{1,4})?)$',
      caseSensitive: false,
    ).firstMatch(clean);
    if (numberOnlyMatch != null) {
      return ('', numberOnlyMatch.group(1)!);
    }

    return (clean, null);
  }

  void _showError(String msg) {
    setState(() {
      _isProcessing = false;
      _errorMessage = msg;
    });
  }

  // ──────────────────────────────────────────────────────────────────────────
  // MODALES DE "VER EN EL MERCADO", "ANALIZAR ESTADÍSTICAS" Y "AJUSTES"
  // ──────────────────────────────────────────────────────────────────────────
  void _showMarketSheet(PokemonCard card) {
    final avg = card.cardmarketPrices?.averageSellPrice;
    final trend = card.cardmarketPrices?.trendPrice;
    final psa10 = card.psa10Price ?? (avg != null ? avg * 4.5 : null);
    final queryText = '${card.name} ${card.number} ${card.setName}'.trim();

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0C1626),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.shopping_cart_checkout_rounded,
                    color: AppTheme.cyanAccent, size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Mercado • ${card.name}',
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                GameBadge(game: card.game, language: card.language),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              card.setName.isNotEmpty
                  ? '${card.setName} • #${card.number}'
                  : 'Referencia #${card.number}',
              style: GoogleFonts.inter(color: Colors.white60, fontSize: 13),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: AppTheme.glassDecoration(radius: 16),
              child: Column(
                children: [
                  _MarketMetricRow(
                    label: 'Cardmarket (Precio Medio)',
                    value: avg != null
                        ? '${avg.toStringAsFixed(2)} €'
                        : 'Sin cotización reciente',
                    valueColor: AppTheme.primary,
                  ),
                  const Divider(color: Colors.white12, height: 18),
                  _MarketMetricRow(
                    label: 'Tendencia de Mercado (Trend)',
                    value: trend != null
                        ? '${trend.toStringAsFixed(2)} €'
                        : 'Sin datos',
                    valueColor: AppTheme.cyanAccent,
                  ),
                  const Divider(color: Colors.white12, height: 18),
                  _MarketMetricRow(
                    label: 'Estimación PSA 10 / Graduada',
                    value: psa10 != null
                        ? '~${psa10.toStringAsFixed(2)} €'
                        : 'No disponible',
                    valueColor: AppTheme.cyanAccent,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            NeonPillButton(
              label: 'Copiar referencia para Cardmarket / eBay',
              icon: Icons.copy_rounded,
              style: NeonButtonStyle.primary,
              onPressed: () {
                Clipboard.setData(ClipboardData(text: queryText));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Referencia copiada: "$queryText"'),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showStatsSheet(PokemonCard card) {
    final avg = card.cardmarketPrices?.averageSellPrice ??
        card.cardmarketPrices?.trendPrice;
    final visualScore = _visualScores[card.id];
    final setTotal = card.setPrintedTotal ?? card.setTotal;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0C1626),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.bar_chart_rounded,
                    color: AppTheme.cyanAccent, size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Estadísticas y Ficha Técnica',
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: AppTheme.glassDecoration(radius: 16),
              child: Column(
                children: [
                  _MarketMetricRow(
                    label: 'ID Oficial Catálogo',
                    value: card.id,
                    valueColor: Colors.white,
                  ),
                  const Divider(color: Colors.white12, height: 16),
                  _MarketMetricRow(
                    label: 'Colección / Set',
                    value:
                        card.setName.isNotEmpty ? card.setName : 'Pokémon TCG',
                    valueColor: AppTheme.cyanAccent,
                  ),
                  const Divider(color: Colors.white12, height: 16),
                  _MarketMetricRow(
                    label: 'Numeración en el Set',
                    value: setTotal != null
                        ? '#${card.number} de $setTotal cartas'
                        : '#${card.number}',
                    valueColor: AppTheme.primary,
                  ),
                  if (visualScore != null) ...[
                    const Divider(color: Colors.white12, height: 16),
                    _MarketMetricRow(
                      label: 'Precisión Visual IA (dHash + Color)',
                      value: '$visualScore% de coincidencia',
                      valueColor: AppTheme.cyanAccent,
                    ),
                  ],
                  if (avg != null) ...[
                    const Divider(color: Colors.white12, height: 16),
                    _MarketMetricRow(
                      label: 'Rango Estimado (NM - Mint)',
                      value:
                          '${(avg * 0.85).toStringAsFixed(2)} € – ${(avg * 1.25).toStringAsFixed(2)} €',
                      valueColor: Colors.white,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            NeonPillButton(
              label: 'Personalizar Estado / Graduación (PSA/BGS)',
              icon: Icons.workspace_premium_rounded,
              style: NeonButtonStyle.dark,
              onPressed: () {
                Navigator.pop(ctx);
                _openManualEntry(cardToEdit: card);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showSettingsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0C1626),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Ajustes del Escáner Pokémon',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Selecciona el idioma prioritario para el reconocimiento OCR y el catálogo:',
                style: GoogleFonts.inter(color: Colors.white60, fontSize: 12.5),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: CardLanguage.values.map((lang) {
                  final isSelected = _selectedLanguage == lang;
                  return ChoiceChip(
                    label: Text(
                      lang.label,
                      style: GoogleFonts.outfit(
                        color: isSelected ? Colors.white : Colors.white70,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.w500,
                      ),
                    ),
                    selected: isSelected,
                    selectedColor: AppTheme.cyanAccent,
                    backgroundColor: const Color(0xFF162647),
                    onSelected: (sel) {
                      if (sel) {
                        setState(() => _selectedLanguage = lang);
                        setModalState(() {});
                        if (_manualSearchController.text.trim().isNotEmpty) {
                          _onManualSearch();
                        }
                      }
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 18),
              NeonPillButton(
                label: 'Añadir Carta Manualmente',
                icon: Icons.edit_note_rounded,
                style: NeonButtonStyle.dark,
                onPressed: () {
                  Navigator.pop(ctx);
                  _openManualEntry();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // BUILD PRINCIPAL (DISEÑO POKÉMON TCG SCANNER HUD)
  // ──────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      extendBody: true,
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppTheme.bgGradient,
        ),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // ── 1. Barra de búsqueda redondeada superior + Cabecera ─────────
              _buildTopSearchAndHeader(),

              // ── 2. Cuerpo desplazable con el Visor Neón y Resultados ───────
              Expanded(
                child: SingleChildScrollView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Logo "Pokémon TCG SCANNER" con botones laterales Ajustes / Colección
                      _buildLogoHeaderRow(),

                      const SizedBox(height: 8),

                      // Indicador de estado ("Escaneando...", selector de idioma rápido)
                      _buildScannerStatusText(),

                      const SizedBox(height: 10),

                      // ── VISOR CENTRAL NEÓN HUD ──────────────────────────────
                      _buildHudViewfinder(),

                      const SizedBox(height: 12),

                      // Botones rápidos de Cámara / Galería y Chips de prueba
                      _buildQuickCameraAndChipsBar(),

                      const SizedBox(height: 14),

                      // ── Mensaje de error si ocurrió alguno ──────────────────
                      if (_errorMessage != null && !_isProcessing)
                        _buildErrorBanner(_errorMessage!),

                      // ── TARJETA PRINCIPAL DE CARTA DETECTADA (3 Botones Neón)
                      if (_selectedCard != null && !_isProcessing) ...[
                        _buildScannerResultCard(_selectedCard!),
                        const SizedBox(height: 16),
                      ],

                      // ── Otras versiones / candidatas encontradas ────────────
                      if (_searchResults.isNotEmpty &&
                          _selectedCard == null &&
                          !_isProcessing)
                        _buildCandidatesList(),

                      const SizedBox(height: 190),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: PokeballBottomBar(
        selectedIndex: -1,
        onCenterScanTap: _openLiveCamera,
        onTabSelected: (index) {
          Navigator.of(context).pop(index);
        },
      ),
    );
  }

  // ── Barra de búsqueda píldora superior (como en la pantalla izquierda) ─────
  Widget _buildTopSearchAndHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Colors.white70, size: 20),
            tooltip: 'Volver al álbum',
          ),
          Expanded(
            child: Container(
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFF13203B).withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.28),
                  width: 1.1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.cyanAccent.withValues(alpha: 0.1),
                    blurRadius: 12,
                  ),
                ],
              ),
              child: TextField(
                controller: _manualSearchController,
                style: GoogleFonts.inter(color: Colors.white, fontSize: 13.5),
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _onManualSearch(),
                decoration: InputDecoration(
                  hintText: 'Buscar Charizard, 140/195, s8a 001/028...',
                  hintStyle:
                      GoogleFonts.inter(color: Colors.white38, fontSize: 12.5),
                  prefixIcon: const Icon(Icons.search_rounded,
                      color: Colors.white70, size: 20),
                  suffixIcon: _manualSearchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded,
                              color: Colors.white54, size: 17),
                          onPressed: () {
                            setState(() => _manualSearchController.clear());
                          },
                        )
                      : IconButton(
                          icon: const Icon(Icons.arrow_forward_rounded,
                              color: AppTheme.cyanAccent, size: 18),
                          onPressed: () => _onManualSearch(),
                        ),
                  border: InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Fila con Ajustes + Logo Pokémon TCG SCANNER + Colección ────────────────
  Widget _buildLogoHeaderRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _HeaderIconAction(
          icon: Icons.settings_outlined,
          label: 'Ajustes',
          onTap: _showSettingsSheet,
        ),
        const Expanded(
          child: Center(
            child: PokemonScannerLogo(scale: 0.95),
          ),
        ),
        _HeaderIconAction(
          icon: Icons.style_outlined,
          label: 'Colección',
          onTap: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _buildScannerStatusText() {
    if (_isProcessing) {
      return Text(
        'Escaneando carta...',
        style: GoogleFonts.outfit(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          shadows: [
            Shadow(
              color: AppTheme.cyanAccent.withValues(alpha: 0.7),
              blurRadius: 10,
            ),
          ],
        ),
      );
    }

    if (_isMatchingImages) {
      return Text(
        'Comparando holografía y arte de la carta...',
        style: GoogleFonts.outfit(
          color: AppTheme.cyanAccent,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      );
    }

    return GestureDetector(
      onTap: _showSettingsSheet,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF122240),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.language_rounded,
                size: 13, color: AppTheme.cyanAccent),
            const SizedBox(width: 5),
            Text(
              'Idioma OCR: ${_selectedLanguage.label}',
              style: GoogleFonts.outfit(
                color: Colors.white70,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Visor Central NeonScannerFrame con imagen y etiqueta lateral HUD ───────
  Widget _buildHudViewfinder() {
    final card = _selectedCard;
    final price = card?.cardmarketPrices?.averageSellPrice ??
        card?.cardmarketPrices?.trendPrice;

    final String? calloutTitle = card?.name ?? _ocrResult?.pokemonName;
    final String? calloutSubtitle = price != null
        ? 'Est. ${price.toStringAsFixed(2)} €'
        : (card != null
            ? '#${card.number}'
            : _ocrResult?.collectionNumber);
    final String? calloutBadge = card?.language?.toUpperCase() ??
        (_ocrResult?.detectedLanguage != null &&
                _ocrResult!.detectedLanguage != CardLanguage.auto
            ? _ocrResult!.detectedLanguage.apiCode.toUpperCase()
            : null);

    Widget previewContent;
    if (_capturedImage != null) {
      previewContent = Image.file(
        _capturedImage!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        cacheWidth: 560,
      );
    } else if (card != null && PokemonCard.isValidNetworkUrl(card.imageUrl)) {
      previewContent = CachedNetworkImage(
        imageUrl: card.imageUrl,
        fit: BoxFit.contain,
        memCacheWidth: 560,
        placeholder: (_, __) => const Center(
          child: CircularProgressIndicator(color: AppTheme.cyanAccent),
        ),
        errorWidget: (_, __, ___) => _buildEmptyViewfinderContent(),
      );
    } else {
      previewContent = _buildEmptyViewfinderContent();
    }

    return NeonScannerFrame(
      width: 215,
      height: 298,
      isScanning: _isProcessing || _isMatchingImages,
      showLaser: _capturedImage != null || card != null || _isProcessing,
      calloutTitle: calloutTitle,
      calloutSubtitle: calloutSubtitle,
      calloutBadge: calloutBadge,
      onTap: _openLiveCamera,
      child: previewContent,
    );
  }

  Widget _buildEmptyViewfinderContent() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0F2142),
            Color(0xFF091326),
          ],
        ),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.cyanAccent.withValues(alpha: 0.12),
              border: Border.all(
                color: AppTheme.cyanAccent.withValues(alpha: 0.45),
                width: 1.5,
              ),
            ),
            child: const Icon(
              Icons.camera_alt_rounded,
              color: AppTheme.cyanAccent,
              size: 38,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Toca para Escanear Carta',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Reconocimiento local en varios idiomas con catálogo Pokémon TCG offline',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: Colors.white60,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickCameraAndChipsBar() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _MiniHudButton(
              icon: Icons.photo_library_rounded,
              label: 'Galería',
              color: AppTheme.primary,
              onTap: () => _captureImage(ImageSource.gallery),
            ),
            const SizedBox(width: 10),
            _MiniHudButton(
              icon: Icons.edit_note_rounded,
              label: 'Manual',
              color: AppTheme.cyanAccent,
              onTap: () => _openManualEntry(),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildQuickChip('Charizard ex'),
              _buildQuickChip('Ho-Oh 140/195'),
              _buildQuickChip('Pikachu TG05/TG30'),
              _buildQuickChip('s8a 001/028'),
              _buildQuickChip('113/094'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildQuickChip(String label) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ActionChip(
        avatar: const Icon(Icons.catching_pokemon,
            size: 13, color: AppTheme.primary),
        label: Text(
          label,
          style: GoogleFonts.outfit(color: Colors.white70, fontSize: 11),
        ),
        backgroundColor: const Color(0xFF11203D),
        side: BorderSide(color: AppTheme.cyanAccent.withValues(alpha: 0.3)),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 0),
        onPressed: () => _onManualSearch(label),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // TARJETA DE RESULTADO ESTILO IMAGEN DE REFERENCIA
  // Soporta vista con miniatura lateral (izquierda/centro de la imagen) y
  // vista expandida con "Est. €120.00" gigante (derecha de la imagen).
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildScannerResultCard(PokemonCard card) {
    final price = card.cardmarketPrices?.averageSellPrice ??
        card.cardmarketPrices?.trendPrice;
    final priceLabel = price != null
        ? 'Est. ${price.toStringAsFixed(2)} €'
        : 'Est. Consultar';
    final setSubtitle = card.setName.isNotEmpty
        ? '${card.setName} • #${card.number}'
        : 'Rareza / Ref #${card.number}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xF215233E),
            Color(0xF50C1528),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: AppTheme.cyanAccent.withValues(alpha: 0.45),
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.65),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: AppTheme.cyanAccent.withValues(alpha: 0.12),
            blurRadius: 18,
          ),
        ],
      ),
      child: _expandedHeroCard
          ? _buildExpandedHeroCardContent(card, setSubtitle, priceLabel)
          : _buildSplitCardContent(card, setSubtitle, priceLabel),
    );
  }

  /// Diseño Pantallas 1 y 2: Miniatura de carta a la izquierda + 3 botones neón a la derecha
  Widget _buildSplitCardContent(
    PokemonCard card,
    String setSubtitle,
    String priceLabel,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Imagen de la carta a la izquierda
        GestureDetector(
          onTap: () => setState(() => _expandedHeroCard = true),
          child: Container(
            width: 108,
            height: 152,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppTheme.primary.withValues(alpha: 0.7),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primary.withValues(alpha: 0.2),
                  blurRadius: 12,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: _buildCardImageWidget(card, useFullRes: true),
            ),
          ),
        ),
        const SizedBox(width: 14),
        // Columna derecha con Título, Rareza/Set, Precio Dorado y los 3 Botones Píldora
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      card.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(
                      Icons.open_in_full_rounded,
                      color: Colors.white54,
                      size: 16,
                    ),
                    tooltip: 'Ampliar tarjeta de precio',
                    onPressed: () =>
                        setState(() => _expandedHeroCard = !_expandedHeroCard),
                  ),
                ],
              ),
              Text(
                setSubtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  color: Colors.white70,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                priceLabel,
                style: GoogleFonts.outfit(
                  color: AppTheme.primary,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  shadows: [
                    Shadow(
                      color: AppTheme.primary.withValues(alpha: 0.45),
                      blurRadius: 10,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              NeonPillButton(
                label: 'Añadir a mi Colección',
                style: NeonButtonStyle.primary,
                compact: true,
                onPressed: _isProcessing ? null : _saveCard,
              ),
              const SizedBox(height: 8),
              NeonPillButton(
                label: 'Ver en el Mercado',
                style: NeonButtonStyle.primary,
                compact: true,
                onPressed: () => _showMarketSheet(card),
              ),
              const SizedBox(height: 8),
              NeonPillButton(
                label: 'Analizar Estadísticas',
                icon: Icons.bar_chart_rounded,
                style: NeonButtonStyle.dark,
                compact: true,
                onPressed: () => _showStatsSheet(card),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Diseño Pantalla 3: Vista Hero Centrada con "Est. €120.00" gigante y 3 botones grandes
  Widget _buildExpandedHeroCardContent(
    PokemonCard card,
    String setSubtitle,
    String priceLabel,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            GameBadge(game: card.game, language: card.language),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close_fullscreen_rounded,
                  color: Colors.white54, size: 18),
              tooltip: 'Vista compacta con miniatura',
              onPressed: () => setState(() => _expandedHeroCard = false),
            ),
          ],
        ),
        Text(
          card.name,
          textAlign: TextAlign.center,
          style: GoogleFonts.outfit(
            color: Colors.white,
            fontSize: 25,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          setSubtitle,
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            color: Colors.white70,
            fontSize: 13.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          priceLabel,
          textAlign: TextAlign.center,
          style: GoogleFonts.outfit(
            color: AppTheme.primary,
            fontSize: 29,
            fontWeight: FontWeight.w900,
            shadows: [
              Shadow(
                color: AppTheme.primary.withValues(alpha: 0.55),
                blurRadius: 14,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        NeonPillButton(
          label: 'Añadir a mi Colección',
          style: NeonButtonStyle.primary,
          onPressed: _isProcessing ? null : _saveCard,
        ),
        const SizedBox(height: 10),
        NeonPillButton(
          label: 'Ver en el Mercado',
          style: NeonButtonStyle.primary,
          onPressed: () => _showMarketSheet(card),
        ),
        const SizedBox(height: 10),
        NeonPillButton(
          label: 'Analizar Estadísticas',
          icon: Icons.bar_chart_rounded,
          style: NeonButtonStyle.dark,
          onPressed: () => _showStatsSheet(card),
        ),
      ],
    );
  }

  Widget _buildCardImageWidget(PokemonCard card, {bool useFullRes = false}) {
    if (PokemonCard.isValidNetworkUrl(card.imageUrl)) {
      return CachedNetworkImage(
        imageUrl: useFullRes ? card.imageUrl : card.thumbnailImageUrl,
        fit: BoxFit.cover,
        memCacheWidth: useFullRes ? 450 : 180,
        placeholder: (_, __) => Container(
          color: Colors.black26,
          child: const Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppTheme.cyanAccent,
            ),
          ),
        ),
        errorWidget: (_, __, ___) => Container(
          color: Colors.black26,
          child: const Icon(Icons.catching_pokemon,
              color: Colors.white38, size: 32),
        ),
      );
    }
    if (card.imageUrl.isNotEmpty && File(card.imageUrl).existsSync()) {
      return Image.file(
        File(card.imageUrl),
        fit: BoxFit.cover,
        cacheWidth: useFullRes ? 450 : 180,
      );
    }
    if (_capturedImage != null) {
      return Image.file(
        _capturedImage!,
        fit: BoxFit.cover,
        cacheWidth: 360,
      );
    }
    return Container(
      color: Colors.black26,
      child:
          const Icon(Icons.catching_pokemon, color: Colors.white38, size: 32),
    );
  }

  // ── Lista de candidatas adicionales si hay más de 1 coincidencia ───────────
  Widget _buildCandidatesList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            _searchResults.length == 1
                ? 'Posible coincidencia (1):'
                : 'Otras ediciones encontradas (${_searchResults.length}):',
            style: GoogleFonts.outfit(
              color: Colors.white70,
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 8),
        ..._searchResults.map(
          (card) => _ResultCard(
            card: card,
            isSelected: _selectedCard?.id == card.id,
            visualScore: _visualScores[card.id],
            onSelect: () => _selectCard(card),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.loss.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.loss.withValues(alpha: 0.45)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.error_outline_rounded, color: AppTheme.loss),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 12.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          NeonPillButton(
            label: 'Introducir datos de la carta a mano',
            icon: Icons.edit_note_rounded,
            style: NeonButtonStyle.dark,
            compact: true,
            onPressed: _openManualEntry,
          ),
        ],
      ),
    );
  }
}

class _HeaderIconAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _HeaderIconAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(height: 2),
            Text(
              label,
              style: GoogleFonts.outfit(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniHudButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _MiniHudButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.55), width: 1.1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MarketMetricRow extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;

  const _MarketMetricRow({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.inter(color: Colors.white70, fontSize: 13),
          ),
        ),
        Text(
          value,
          style: GoogleFonts.outfit(
            color: valueColor,
            fontSize: 14.5,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

// ── Tarjeta individual en la lista de resultados con imagen ──────────────────
class _ResultCard extends StatelessWidget {
  final PokemonCard card;
  final bool isSelected;
  final int? visualScore;
  final VoidCallback onSelect;

  const _ResultCard({
    required this.card,
    required this.isSelected,
    this.visualScore,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFF1A3158) : const Color(0xFF101E38),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSelected
              ? AppTheme.cyanAccent
              : AppTheme.cyanAccent.withValues(alpha: 0.2),
          width: isSelected ? 1.5 : 1.0,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onSelect,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: PokemonCard.isValidNetworkUrl(card.imageUrl)
                    ? CachedNetworkImage(
                        imageUrl: card.thumbnailImageUrl,
                        width: 46,
                        height: 64,
                        memCacheWidth: 150,
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
                      )
                    : Container(
                        width: 46,
                        height: 64,
                        color: Colors.black26,
                        child: const Icon(Icons.catching_pokemon,
                            color: Colors.white38, size: 20),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            card.name,
                            style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontSize: 14.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (visualScore != null && visualScore! > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            margin: const EdgeInsets.only(right: 6),
                            decoration: BoxDecoration(
                              color: AppTheme.cyanAccent.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: AppTheme.cyanAccent,
                                width: 0.8,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.palette_outlined,
                                    size: 11, color: AppTheme.cyanAccent),
                                const SizedBox(width: 3),
                                Text(
                                  '$visualScore%',
                                  style: GoogleFonts.outfit(
                                    color: AppTheme.cyanAccent,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        GameBadge(
                          game: card.game,
                          language: card.language,
                          fontSize: 9,
                          iconSize: 11,
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      card.setName.isNotEmpty
                          ? '${card.setName} • #${card.number}'
                          : 'Ref: #${card.number}',
                      style: GoogleFonts.inter(
                          color: Colors.white60, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                isSelected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: isSelected ? AppTheme.cyanAccent : Colors.white24,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
