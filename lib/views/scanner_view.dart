// ============================================================
// views/scanner_view.dart
// Pantalla de escaneo con cámara y búsqueda manual universal:
// Pokémon, Magic (MTG), Yu-Gi-Oh!, Digimon, One Piece, Lorcana, etc.
// Multiidioma: Español, Inglés, Japonés, Coreano y Chino.
// ============================================================

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../models/pokemon_card.dart';
import '../services/album_storage_service.dart';
import '../services/ocr_service.dart';
import '../services/tcg_api_service.dart';
import '../services/image_matching_service.dart';
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
  Map<String, int> _visualScores = {};
  String? _errorMessage;
  late TcgGame _selectedGame;
  CardLanguage _selectedLanguage = CardLanguage.auto;
  int _searchRequestId = 0;

  // ── Controladores ─────────────────────────────────────────────────────────
  final TextEditingController _manualSearchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedGame = widget.initialGame;
  }

  @override
  void dispose() {
    _manualSearchController.dispose();
    super.dispose();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // PASO 1: Capturar imagen con la cámara o galería.
  // ──────────────────────────────────────────────────────────────────────────
  Future<void> _captureImage([ImageSource source = ImageSource.camera]) async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: source,
        imageQuality: 95,
        preferredCameraDevice: CameraDevice.rear,
      );

      if (photo == null) return;
      if (!mounted) return;

      final imageFile = File(photo.path);
      setState(() {
        _capturedImage = imageFile;
        _isProcessing = true;
        _isMatchingImages = false;
        _visualScores = {};
        _errorMessage = null;
        _searchResults = [];
        _selectedCard = null;
      });

      await _runOcr(imageFile);
    } catch (e) {
      _showError('Error al capturar la imagen: $e');
    }
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
        // Si el usuario tenía seleccionado Auto y el OCR detectó un idioma específico (ej: japonés),
        // actualizar _selectedLanguage para que la UI y las búsquedas reflejen el idioma detectado
        if (_selectedLanguage == CardLanguage.auto &&
            result.detectedLanguage != CardLanguage.auto) {
          _selectedLanguage = result.detectedLanguage;
        }
      });

      if (result.pokemonName != null || result.collectionNumber != null) {
        // Auto-rellenar el campo de búsqueda para que el usuario siempre vea lo que detectó el OCR
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
        );
      } else {
        setState(() {
          _isProcessing = false;
          _errorMessage =
              'No se detectó el texto de la carta claramente. Asegúrate de encuadrar de cerca con buena luz, o introduce el número abajo.';
        });
      }
    } catch (e) {
      _showError('Error durante el OCR: $e');
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // PASO 3: Consulta a las APIs TCG con protección contra carreras y mounted.
  // ──────────────────────────────────────────────────────────────────────────
  Future<void> _searchApi({
    String? pokemonName,
    String? collectionNumber,
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

      if (manualQuery != null && manualQuery.isNotEmpty) {
        final parts = _parseManualQuery(manualQuery);
        queryName = parts.$1;
        targetNumber = parts.$2;
      } else {
        queryName = pokemonName ?? '';
        targetNumber = collectionNumber;
      }

      final effectiveLang = (_selectedLanguage == CardLanguage.auto &&
              _ocrResult?.detectedLanguage != null &&
              _ocrResult!.detectedLanguage != CardLanguage.auto)
          ? _ocrResult!.detectedLanguage
          : _selectedLanguage;

      final results = await _apiService.searchUniversal(
        query: queryName,
        number: targetNumber,
        game: _selectedGame,
        language: effectiveLang,
      );

      if (!mounted || currentRequestId != _searchRequestId) return;

      if (results.isEmpty) {
        setState(() {
          _isProcessing = false;
          _errorMessage =
              'No se encontraron cartas para esta búsqueda. '
              'Puedes introducir todos sus datos manualmente si lo deseas.';
        });
        return;
      }

      PokemonCard? autoSelected;
      if (results.length == 1) {
        autoSelected = results.first;
        if (autoSelected.game == TcgGame.pokemon &&
            autoSelected.cardmarketPrices == null) {
          final detail = await _apiService.fetchCardDetail(
            autoSelected.id,
            lang: autoSelected.language ?? _selectedLanguage.apiCode,
          );
          if (!mounted || currentRequestId != _searchRequestId) return;
          if (detail != null) autoSelected = detail;
        }
      }

      if (!mounted || currentRequestId != _searchRequestId) return;

      setState(() {
        _searchResults = results;
        _selectedCard = autoSelected;
        _isProcessing = false;
      });

      // Si tenemos una foto capturada y hay múltiples candidatas,
      // comparar el arte visual para clasificar y destacar la carta idéntica.
      if (_capturedImage != null && results.length > 1) {
        _runVisualMatching(results);
      }
    } on TcgApiException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError('Error de conexión: $e');
    }
  }

  /// Emparejamiento visual en segundo plano:
  /// Compara el dibujo central de la foto con cada una de las candidatas encontradas.
  Future<void> _runVisualMatching(List<PokemonCard> candidates) async {
    if (_capturedImage == null || !mounted) return;

    setState(() => _isMatchingImages = true);

    try {
      final rankedResults = await _imageMatcher.rankCardsByVisualSimilarity(
        userPhotoFile: _capturedImage!,
        candidateCards: candidates,
        maxCandidatesToCompare: 16,
      );

      if (!mounted) return;

      final scores = <String, int>{};
      for (final r in rankedResults) {
        if (r.matchPercentage > 0) {
          scores[r.card.id] = r.matchPercentage;
        }
      }

      final sortedCards = rankedResults.map((r) => r.card).toList();
      final bestMatch = rankedResults.first;

      setState(() {
        _isMatchingImages = false;
        _visualScores = scores;
        _searchResults = sortedCards;

        // Si la mejor coincidencia visual es notable (>= 50%), seleccionarla
        if (bestMatch.similarity >= 0.50) {
          _selectedCard = bestMatch.card;
        }
      });

      // Si es Pokémon y no tiene precio detallado, cargarlo
      if (_selectedCard != null &&
          _selectedCard!.game == TcgGame.pokemon &&
          _selectedCard!.cardmarketPrices == null) {
        final detail = await _apiService.fetchCardDetail(
          _selectedCard!.id,
          lang: _selectedCard!.language ?? _selectedLanguage.apiCode,
        );
        if (mounted && detail != null && _selectedCard?.id == detail.id) {
          setState(() => _selectedCard = detail);
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isMatchingImages = false);
      }
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // PASO 4: Búsqueda manual.
  // ──────────────────────────────────────────────────────────────────────────
  Future<void> _onManualSearch([String? overrideQuery]) async {
    final query = overrideQuery ?? _manualSearchController.text.trim();
    if (query.isEmpty) return;
    if (overrideQuery != null) {
      _manualSearchController.text = overrideQuery;
    }
    await _searchApi(manualQuery: query);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // PASO 5: Selección de carta en la lista.
  // ──────────────────────────────────────────────────────────────────────────
  Future<void> _selectCard(PokemonCard card) async {
    setState(() => _isProcessing = true);

    if (card.game == TcgGame.pokemon &&
        (card.cardmarketPrices == null || card.setName.isEmpty)) {
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
  }

  // ──────────────────────────────────────────────────────────────────────────
  // PASO 6: Guardar carta en el álbum local con feedback de duplicados.
  // ──────────────────────────────────────────────────────────────────────────
  Future<void> _saveCard() async {
    if (_selectedCard == null) return;

    setState(() => _isProcessing = true);
    final isNew = await _storage.saveCard(_selectedCard!);

    if (mounted) {
      if (isNew) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('¡"${_selectedCard!.name}" guardada en tu álbum!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('"${_selectedCard!.name}" ya estaba guardada en tu álbum.'),
            backgroundColor: Colors.amber.shade800,
            duration: const Duration(seconds: 2),
          ),
        );
      }
      Navigator.of(context).pop();
    }
  }

  Future<void> _openManualEntry() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ManualCardView(
          initialName: _ocrResult?.pokemonName ?? _manualSearchController.text,
          initialNumber: _ocrResult?.collectionNumber,
          initialImage: _capturedImage,
          initialLanguage: _selectedLanguage,
          initialGame: _selectedGame != TcgGame.all ? _selectedGame : null,
        ),
      ),
    );
    if (saved == true && mounted) {
      Navigator.of(context).pop();
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Parser de búsqueda manual tolerante a comillas, prefijos y referencias.
  // ──────────────────────────────────────────────────────────────────────────
  (String, String?) _parseManualQuery(String input) {
    var clean = input.replaceAll(RegExp(r'["״“”«»' "'" r']'), ' ').trim();

    clean = clean.replaceAll(
      RegExp(
        r'\b(pok[eé]mon\s+)?(b[aá]sico|g[aá]sico|c[aá]sico|p[aá]sico|fase\s*\d*|stage\s*\d*|basic|creature|instant|sorcery|trap|spell)\b',
        caseSensitive: false,
      ),
      ' ',
    ).replaceAll(
      RegExp(r'(たね|1進化|2進化|기본|1진화|2진화|基础|1阶进化|2阶进化)'),
      ' ',
    ).trim();

    // 1. Buscar número de colección XXX/YYY (ej: "140/195", "070/280")
    final matchFraction = RegExp(r'\b(\d{1,4}/\d{1,4})\b').firstMatch(clean);
    if (matchFraction != null) {
      final number = matchFraction.group(1)!;
      final name = clean.replaceFirst(matchFraction.group(0)!, '').trim();
      return (name, number);
    }

    // 2. Buscar código con guion tipo set TCG (ej: "SV5K-005", "ST1-03", "OP01-025", "LOB-005")
    final matchSetCode = RegExp(
            r'\b([A-Za-z0-9]{2,6}[A-Za-z0-9\.\-]*\s*[-–]\s*\d{1,4})\b')
        .firstMatch(clean);
    if (matchSetCode != null) {
      final code = matchSetCode.group(1)!;
      final name = clean.replaceFirst(matchSetCode.group(0)!, '').trim();
      return (name, code);
    }

    // 3. Buscar número individual al final (ej: "Ho-Oh 140", "Agumon 03")
    final matchSingle =
        RegExp(r'^(.*?)(?:#|\s+)(\d{1,4})\s*$').firstMatch(clean);
    if (matchSingle != null && matchSingle.group(1)!.trim().isNotEmpty) {
      final name = matchSingle.group(1)!.trim();
      final number = matchSingle.group(2)!.trim();
      return (name, number);
    }

    // 4. Si es solo un número o código de referencia (ej: "140", "#140", "46986414")
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
  // BUILD
  // ──────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16213E),
        title: const Text('Escanear o Buscar Carta TCG',
            style: TextStyle(color: Colors.white, fontSize: 18)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_note, color: Colors.amber),
            tooltip: 'Añadir datos manualmente',
            onPressed: _openManualEntry,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Selector de Franquicia TCG ────────────────────────────────
            _buildGameSelector(),

            const SizedBox(height: 10),

            // ── Selector de Idioma (para todas las colecciones) ───────────
            _buildLanguageSelector(),
            const SizedBox(height: 12),

            // ── Cámara / Foto de la carta ─────────────────────────────────
            _buildImagePreview(),

            const SizedBox(height: 14),

            // ── Buscador manual con sugerencias rápidas ───────────────────
            _buildManualInput(),

            const SizedBox(height: 14),

            // ── Indicador de carga ────────────────────────────────────────
            if (_isProcessing) ...[
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      CircularProgressIndicator(color: Colors.amber),
                      SizedBox(height: 10),
                      Text('Consultando bases de datos TCG...',
                          style: TextStyle(color: Colors.white70)),
                    ],
                  ),
                ),
              ),
            ],

            // ── Mensaje de error / Opción de crear a mano ─────────────────
            if (_errorMessage != null && !_isProcessing)
              _buildErrorBanner(_errorMessage!),

            // ── Info de lo que detectó el OCR ─────────────────────────────
            if (_ocrResult != null && !_isProcessing)
              _buildOcrInfo(),

            // ── Confirmación de carta seleccionada ────────────────────────
            if (_selectedCard != null && !_isProcessing) ...[
              _buildConfirmation(),
              const SizedBox(height: 20),
            ],

            // ── Lista de resultados para elegir con imagen ────────────────
            if (_searchResults.isNotEmpty && !_isProcessing)
              _buildResultsList(),

            // Espacio final generoso para que nada quede cortado al hacer scroll
            const SizedBox(height: 60),
          ],
        ),
      ),
    );
  }

  // ── Selector de Franquicia TCG ─────────────────────────────────────────────
  Widget _buildGameSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF16213E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.style, color: Colors.amber, size: 18),
              SizedBox(width: 8),
              Text(
                'Juego / Franquicia TCG:',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: TcgGame.values.map((game) {
                final isSelected = _selectedGame == game;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(
                      '${game.icon} ${game.label}',
                      style: TextStyle(
                        color: isSelected ? Colors.black : Colors.white70,
                        fontSize: 12,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    selected: isSelected,
                    selectedColor: Color(game.colorHex),
                    backgroundColor: const Color(0xFF0F3460),
                    side: BorderSide(
                      color: isSelected
                          ? Color(game.colorHex)
                          : Colors.white24,
                    ),
                    onSelected: (selected) {
                      if (selected) {
                        setState(() => _selectedGame = game);
                        if (_manualSearchController.text.trim().isNotEmpty) {
                          _onManualSearch();
                        }
                      }
                    },
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // ── Selector de Idioma ────────────────────────────────────────────────────
  Widget _buildLanguageSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF16213E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          const Icon(Icons.language, color: Colors.white60, size: 16),
          const SizedBox(width: 8),
          const Text('Idioma:',
              style: TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: CardLanguage.values.map((lang) {
                  final isSelected = _selectedLanguage == lang;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(
                        lang.label,
                        style: TextStyle(
                          color: isSelected ? Colors.black : Colors.white70,
                          fontSize: 11,
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      selected: isSelected,
                      selectedColor: Colors.amber,
                      backgroundColor: const Color(0xFF0F3460),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      onSelected: (selected) {
                        if (selected) {
                          setState(() => _selectedLanguage = lang);
                          if (_manualSearchController.text.trim().isNotEmpty) {
                            _onManualSearch();
                          }
                        }
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImagePreview() {
    return Column(
      children: [
        GestureDetector(
          onTap: () => _captureImage(ImageSource.camera),
          child: Container(
            height: 160,
            decoration: BoxDecoration(
              color: const Color(0xFF0F3460),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.amber.withValues(alpha: 0.4),
                width: 1.5,
              ),
            ),
            child: _capturedImage != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(15),
                    child: Image.file(_capturedImage!, fit: BoxFit.cover),
                  )
                : const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.camera_alt, color: Colors.amber, size: 40),
                      SizedBox(height: 8),
                      Text('Toma una foto a cualquier carta TCG',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center),
                      SizedBox(height: 4),
                      Text(
                          'Toca aquí para abrir la cámara o elige de tu galería abajo',
                          style: TextStyle(color: Colors.white54, fontSize: 11),
                          textAlign: TextAlign.center),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _captureImage(ImageSource.camera),
                icon: const Icon(Icons.camera_alt, size: 16),
                label: const Text('Hacer Foto',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _captureImage(ImageSource.gallery),
                icon: const Icon(Icons.photo_library,
                    size: 16, color: Colors.white70),
                label: const Text('Desde Galería',
                    style: TextStyle(fontSize: 12, color: Colors.white70)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white24),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildManualInput() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF16213E),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.search, color: Colors.amber, size: 20),
              SizedBox(width: 8),
              Text(
                'Búsqueda por nombre o referencia',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Nombre ("Black Lotus", "Ho-Oh"), número ("140") o código ("ST1-03", "OP01-025"):',
            style: TextStyle(color: Colors.white60, fontSize: 12),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _manualSearchController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Ej: Black Lotus, Dark Magician, 140/195, OP01-025...',
              hintStyle: const TextStyle(color: Colors.white38),
              filled: true,
              fillColor: const Color(0xFF0F3460),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              suffixIcon: IconButton(
                icon: const Icon(Icons.arrow_forward, color: Colors.amber),
                onPressed: () => _onManualSearch(),
              ),
            ),
            onSubmitted: (_) => _onManualSearch(),
          ),
          const SizedBox(height: 10),

          // Chips de búsqueda rápida de diversos TCG
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              _buildQuickChip('Ho-Oh 140/195', TcgGame.pokemon),
              _buildQuickChip('Black Lotus', TcgGame.magic),
              _buildQuickChip('Dark Magician', TcgGame.yugioh),
              _buildQuickChip('Agumon ST1-03', TcgGame.digimon),
              _buildQuickChip('Zoro OP01-025', TcgGame.onepiece),
              _buildQuickChip('140', TcgGame.all),
            ],
          ),

          const SizedBox(height: 12),

          OutlinedButton.icon(
            onPressed: _openManualEntry,
            icon: const Icon(Icons.edit_note, color: Colors.amber, size: 18),
            label: const Text(
              '¿Prefieres meter todos los datos a mano? Pulsa aquí ✍️',
              style: TextStyle(color: Colors.amber, fontSize: 12),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: Colors.amber.withValues(alpha: 0.4)),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickChip(String label, TcgGame game) {
    return ActionChip(
      avatar: Text(game.icon, style: const TextStyle(fontSize: 12)),
      label: Text(label,
          style: const TextStyle(color: Colors.white70, fontSize: 11)),
      backgroundColor: const Color(0xFF0F3460),
      side: BorderSide(color: Color(game.colorHex).withValues(alpha: 0.4)),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      onPressed: () {
        setState(() => _selectedGame = game);
        _onManualSearch(label);
      },
    );
  }

  Widget _buildOcrInfo() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('✅ OCR leído de la carta:',
              style: TextStyle(
                  color: Colors.greenAccent, fontWeight: FontWeight.bold)),
          if (_ocrResult!.pokemonName != null)
            Text('Nombre: ${_ocrResult!.pokemonName}',
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
          if (_ocrResult!.collectionNumber != null)
            Text('Referencia: ${_ocrResult!.collectionNumber}',
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
          if (_ocrResult!.detectedLanguage != CardLanguage.auto)
            Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Text(
                'Idioma: ${_ocrResult!.detectedLanguage.label}',
                style: const TextStyle(
                    color: Colors.amber,
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(message,
              style: const TextStyle(color: Colors.orangeAccent, fontSize: 13)),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: _openManualEntry,
            icon: const Icon(Icons.edit_note, size: 18),
            label: const Text('Crear esta carta manualmente'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F3460),
              foregroundColor: Colors.amber,
              side: const BorderSide(color: Colors.amber),
            ),
          ),
        ],
      ),
    );
  }

  // ── Lista de cartas con imagen para que el usuario escoja ────────────────
  Widget _buildResultsList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${_searchResults.length} cartas encontradas:',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Text(
              'Toca una para elegirla',
              style: TextStyle(color: Colors.amber, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 10),

        if (_isMatchingImages) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.35)),
            ),
            child: const Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.amber,
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '🎨 Comparando arte de ilustración con tu foto...',
                    style: TextStyle(color: Colors.amber, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],

        ..._searchResults.map((card) => _ResultCard(
              card: card,
              isSelected: _selectedCard?.id == card.id,
              visualScore: _visualScores[card.id],
              onSelect: () => _selectCard(card),
            )),
      ],
    );
  }

  // ── Vista de confirmación de la carta seleccionada ─────────────────────────
  Widget _buildConfirmation() {
    final card = _selectedCard!;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF16213E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.green, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Carta seleccionada:',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Color(card.game.colorHex).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                  border:
                      Border.all(color: Color(card.game.colorHex), width: 1),
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
          const SizedBox(height: 12),

          // Imagen grande de la carta
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: card.imageUrl.startsWith('http')
                  ? CachedNetworkImage(
                      imageUrl: card.imageUrl,
                      height: 220,
                      fit: BoxFit.contain,
                      placeholder: (_, __) => const SizedBox(
                        height: 220,
                        child: Center(
                            child:
                                CircularProgressIndicator(color: Colors.amber)),
                      ),
                      errorWidget: (_, __, ___) => const Icon(
                          Icons.broken_image,
                          color: Colors.white38,
                          size: 60),
                    )
                  : (card.imageUrl.isNotEmpty && File(card.imageUrl).existsSync()
                      ? Image.file(File(card.imageUrl),
                          height: 220, fit: BoxFit.contain)
                      : const SizedBox(
                          height: 220,
                          child: Icon(Icons.image_not_supported,
                              color: Colors.white38, size: 60),
                        )),
            ),
          ),

          const SizedBox(height: 12),

          // Tabla de datos
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF0F3460),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                _InfoRow(label: 'Nombre', value: card.name),
                _InfoRow(label: 'Juego / TCG', value: '${card.game.icon} ${card.game.label}'),
                if (_visualScores.containsKey(card.id))
                  _InfoRow(
                    label: 'Coincidencia de arte',
                    value: '🎨 ${_visualScores[card.id]}% de parecido visual',
                  ),
                if (card.setName.isNotEmpty)
                  _InfoRow(label: 'Set / Colección', value: card.setName),
                _InfoRow(
                  label: 'Número de carta',
                  value: card.setPrintedTotal != null
                      ? '#${card.number} / ${card.setPrintedTotal}'
                      : '#${card.number}',
                ),
                _InfoRow(
                  label: 'Cardmarket (Precio medio)',
                  value: card.cardmarketPrices?.averageSellPrice != null
                      ? '${card.cardmarketPrices!.averageSellPrice!.toStringAsFixed(2)} €'
                      : (card.cardmarketPrices?.trendPrice != null
                          ? '${card.cardmarketPrices!.trendPrice!.toStringAsFixed(2)} €'
                          : 'No disponible'),
                ),
                if (card.psa10Price != null)
                  _InfoRow(
                    label: 'PSA 10 (Estimado)',
                    value: '${card.psa10Price!.toStringAsFixed(2)} €/\$',
                  ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          ElevatedButton.icon(
            onPressed: _isProcessing ? null : _saveCard,
            icon: const Icon(Icons.bookmark_add),
            label: const Text('Guardar en mi Álbum',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
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
    return Card(
      color: isSelected ? const Color(0xFF1E3A5F) : const Color(0xFF0F3460),
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: isSelected ? Colors.green : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onSelect,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: card.imageUrl.startsWith('http')
                    ? CachedNetworkImage(
                        imageUrl: card.imageUrl,
                        width: 48,
                        height: 68,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(
                          width: 48,
                          height: 68,
                          color: Colors.black26,
                        ),
                        errorWidget: (_, __, ___) => Container(
                          width: 48,
                          height: 68,
                          color: Colors.black26,
                          child: const Icon(Icons.broken_image,
                              color: Colors.white38, size: 20),
                        ),
                      )
                    : (card.imageUrl.isNotEmpty &&
                            File(card.imageUrl).existsSync()
                        ? Image.file(
                            File(card.imageUrl),
                            width: 48,
                            height: 68,
                            fit: BoxFit.cover,
                          )
                        : Container(
                            width: 48,
                            height: 68,
                            color: Colors.black26,
                            child: const Icon(Icons.image,
                                color: Colors.white38, size: 20),
                          )),
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
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (visualScore != null && visualScore! > 0) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            margin: const EdgeInsets.only(right: 6),
                            decoration: BoxDecoration(
                              color: (visualScore! >= 65
                                      ? Colors.green
                                      : (visualScore! >= 45
                                          ? Colors.orange
                                          : Colors.blueGrey))
                                  .withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: visualScore! >= 65
                                    ? Colors.greenAccent
                                    : (visualScore! >= 45
                                        ? Colors.orangeAccent
                                        : Colors.white38),
                                width: 0.8,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('🎨 ', style: TextStyle(fontSize: 9)),
                                Text(
                                  '$visualScore%',
                                  style: TextStyle(
                                    color: visualScore! >= 65
                                        ? Colors.greenAccent
                                        : (visualScore! >= 45
                                            ? Colors.orangeAccent
                                            : Colors.white70),
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Color(card.game.colorHex)
                                .withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${card.game.icon} ${card.game.label}',
                            style: TextStyle(
                              color: Color(card.game.colorHex),
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      card.setName.isNotEmpty
                          ? '${card.setName} • #${card.number}'
                          : 'Ref: #${card.number}',
                      style: const TextStyle(
                          color: Colors.white60, fontSize: 12),
                    ),
                    if (card.cardmarketPrices?.averageSellPrice != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Cardmarket: ${card.cardmarketPrices!.averageSellPrice!.toStringAsFixed(2)} €',
                        style: const TextStyle(
                          color: Color(0xFF00B4D8),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(width: 8),

              Icon(
                isSelected ? Icons.check_circle : Icons.chevron_right,
                color: isSelected ? Colors.green : Colors.white38,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white60, fontSize: 12)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
