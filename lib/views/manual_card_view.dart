// ============================================================
// views/manual_card_view.dart
// Pantalla para introducir manualmente todos los datos de una carta:
// Juego TCG, Nombre, Set, Número, Precios (Cardmarket y PSA 10), Idioma y Foto.
// ============================================================

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../models/pokemon_card.dart';
import '../services/album_storage_service.dart';
import '../services/ocr_service.dart';

class ManualCardView extends StatefulWidget {
  final PokemonCard? cardToEdit;
  final String? initialName;
  final String? initialNumber;
  final String? initialSet;
  final File? initialImage;
  final CardLanguage? initialLanguage;
  final TcgGame? initialGame;

  const ManualCardView({
    super.key,
    this.cardToEdit,
    this.initialName,
    this.initialNumber,
    this.initialSet,
    this.initialImage,
    this.initialLanguage,
    this.initialGame,
  });

  @override
  State<ManualCardView> createState() => _ManualCardViewState();
}

class _ManualCardViewState extends State<ManualCardView> {
  final _formKey = GlobalKey<FormState>();
  final AlbumStorageService _storage = AlbumStorageService();
  final ImagePicker _picker = ImagePicker();

  late final TextEditingController _nameController;
  late final TextEditingController _numberController;
  late final TextEditingController _setController;
  late final TextEditingController _cmPriceController;
  late final TextEditingController _psa10PriceController;
  late final TextEditingController _imageUrlController;
  late final TextEditingController _purchasePriceController;
  late final TextEditingController _gradingScoreController;

  File? _imageFile;
  TcgGame _selectedGame = TcgGame.pokemon;
  CardLanguage _selectedLanguage = CardLanguage.es;
  CardCondition? _selectedCondition;
  DateTime? _purchaseDate;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final edit = widget.cardToEdit;

    _nameController = TextEditingController(
      text: edit?.name ?? widget.initialName ?? '',
    );
    _numberController = TextEditingController(
      text: edit?.number ?? widget.initialNumber ?? '',
    );
    _setController = TextEditingController(
      text: edit?.setName ?? widget.initialSet ?? '',
    );
    _cmPriceController = TextEditingController(
      text: edit?.cardmarketPrices?.averageSellPrice != null
          ? edit!.cardmarketPrices!.averageSellPrice!.toStringAsFixed(2)
          : (edit?.cardmarketPrices?.trendPrice != null
              ? edit!.cardmarketPrices!.trendPrice!.toStringAsFixed(2)
              : ''),
    );
    _psa10PriceController = TextEditingController(
      text: edit?.psa10Price != null
          ? edit!.psa10Price!.toStringAsFixed(2)
          : '',
    );
    _imageUrlController = TextEditingController(
      text: (edit != null && edit.imageUrl.startsWith('http'))
          ? edit.imageUrl
          : '',
    );
    _purchasePriceController = TextEditingController(
      text: edit?.purchasePrice != null ? edit!.purchasePrice!.toStringAsFixed(2) : '',
    );
    _gradingScoreController = TextEditingController(
      text: edit?.gradingScore ?? '',
    );
    _selectedCondition = edit?.condition;
    _purchaseDate = edit?.purchaseDate;

    if (edit != null &&
        !edit.imageUrl.startsWith('http') &&
        edit.imageUrl.isNotEmpty) {
      final f = File(edit.imageUrl);
      if (f.existsSync()) {
        _imageFile = f;
      }
    } else {
      _imageFile = widget.initialImage;
    }

    if (edit != null) {
      _selectedGame = edit.game;
      if (edit.language != null) {
        _selectedLanguage = CardLanguage.values.firstWhere(
          (l) => l.apiCode == edit.language,
          orElse: () => CardLanguage.es,
        );
      }
    } else {
      if (widget.initialGame != null && widget.initialGame != TcgGame.all) {
        _selectedGame = widget.initialGame!;
      }
      if (widget.initialLanguage != null &&
          widget.initialLanguage != CardLanguage.auto) {
        _selectedLanguage = widget.initialLanguage!;
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _numberController.dispose();
    _setController.dispose();
    _cmPriceController.dispose();
    _psa10PriceController.dispose();
    _imageUrlController.dispose();
    _purchasePriceController.dispose();
    _gradingScoreController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final photo = await _picker.pickImage(
        source: source,
        imageQuality: 90,
      );
      if (photo != null) {
        setState(() {
          _imageFile = File(photo.path);
          _imageUrlController.clear();
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al seleccionar imagen: $e')),
      );
    }
  }

  Future<void> _saveCard() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    final rawName = _nameController.text.trim();
    final rawNumber = _numberController.text.trim();
    final rawSet = _setController.text.trim();
    final cmPrice = double.tryParse(
      _cmPriceController.text.trim().replaceAll(',', '.'),
    );
    final psaPrice = double.tryParse(
      _psa10PriceController.text.trim().replaceAll(',', '.'),
    );
    final purchasePrice = double.tryParse(
      _purchasePriceController.text.trim().replaceAll(',', '.'),
    );
    final gradingScore = _gradingScoreController.text.trim();

    String finalImageUrl = '';
    if (_imageFile != null) {
      finalImageUrl = _imageFile!.path;
    } else if (_imageUrlController.text.trim().isNotEmpty) {
      final inputUrl = _imageUrlController.text.trim();
      if (!inputUrl.startsWith('https://') && !inputUrl.startsWith('http://')) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('La URL de la imagen debe comenzar por https://'),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }
      finalImageUrl = inputUrl;
    } else if (widget.cardToEdit != null) {
      finalImageUrl = widget.cardToEdit!.imageUrl;
    }

    int? setTotal;
    if (rawNumber.contains('/')) {
      final parts = rawNumber.split('/');
      setTotal = int.tryParse(parts[1].trim());
    }

    // Modo edición: actualiza la carta existente manteniendo su ID
    if (widget.cardToEdit != null) {
      final updated = widget.cardToEdit!.copyWith(
        name: rawName,
        number: rawNumber,
        setName: rawSet.isNotEmpty ? rawSet : widget.cardToEdit!.setName,
        imageUrl: finalImageUrl,
        game: _selectedGame,
        cardmarketPrices: cmPrice != null
            ? CardmarketPrices(
                averageSellPrice: cmPrice,
                trendPrice: cmPrice,
                psa10Price: psaPrice ?? widget.cardToEdit!.psa10Price,
              )
            : (psaPrice != null
                ? CardmarketPrices(psa10Price: psaPrice)
                : widget.cardToEdit!.cardmarketPrices),
        psa10Price: psaPrice ?? widget.cardToEdit!.psa10Price,
        setPrintedTotal: setTotal ?? widget.cardToEdit!.setPrintedTotal,
        setTotal: setTotal ?? widget.cardToEdit!.setTotal,
        language: _selectedLanguage.apiCode,
        purchasePrice: purchasePrice,
        purchaseDate: _purchaseDate,
        condition: _selectedCondition,
        gradingScore: gradingScore.isNotEmpty ? gradingScore : null,
        clearPurchasePrice: purchasePrice == null,
        clearCondition: _selectedCondition == null,
        clearGradingScore: gradingScore.isEmpty,
      );

      await _storage.updateCard(updated);

      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('¡"${updated.name}" actualizada en tu álbum!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
        Navigator.of(context).pop(true);
      }
      return;
    }

    // Modo creación: añade una nueva carta con ID único
    final card = PokemonCard(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      name: rawName,
      number: rawNumber,
      setName: rawSet.isNotEmpty ? rawSet : 'Colección ${_selectedGame.label}',
      imageUrl: finalImageUrl,
      game: _selectedGame,
      cardmarketPrices: cmPrice != null
          ? CardmarketPrices(
              averageSellPrice: cmPrice,
              trendPrice: cmPrice,
            )
          : null,
      psa10Price: psaPrice,
      setPrintedTotal: setTotal,
      setTotal: setTotal,
      language: _selectedLanguage.apiCode,
      purchasePrice: purchasePrice,
      purchaseDate: _purchaseDate,
      condition: _selectedCondition,
      gradingScore: gradingScore.isNotEmpty ? gradingScore : null,
    );

    final isNew = await _storage.saveCard(card);

    if (mounted) {
      setState(() => _isSaving = false);
      if (isNew) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('¡"${card.name}" guardada en tu álbum!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('"${card.name}" ya estaba guardada en tu álbum.'),
            backgroundColor: Colors.amber.shade800,
            duration: const Duration(seconds: 2),
          ),
        );
      }
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16213E),
        title: Text(
          widget.cardToEdit != null ? 'Editar Carta' : 'Añadir Carta Manualmente',
          style: const TextStyle(color: Colors.white, fontSize: 18),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Selector de Franquicia TCG ──────────────────────────────
              _buildGameSelector(),

              const SizedBox(height: 16),

              // ── Selector de Foto / Imagen ────────────────────────────────
              _buildImageSection(),

              const SizedBox(height: 18),

              // ── Campos de texto ──────────────────────────────────────────
              _buildTextField(
                controller: _nameController,
                label: 'Nombre de la carta *',
                hint: 'Ej: Black Lotus, Charizard ex, Dark Magician...',
                validator: (val) =>
                    (val == null || val.trim().isEmpty) ? 'Requerido' : null,
              ),

              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      controller: _setController,
                      label: 'Set / Colección',
                      hint: 'Ej: Vintage Masters, 151, LOB...',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildTextField(
                      controller: _numberController,
                      label: 'Número de carta *',
                      hint: 'Ej: 140/195, 070/280, ST1-03...',
                      validator: (val) =>
                          (val == null || val.trim().isEmpty) ? 'Requerido' : null,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              _buildLanguageSelector(),

              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      controller: _cmPriceController,
                      label: 'Precio Cardmarket (€)',
                      hint: 'Ej: 14.50',
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      prefixText: '€ ',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildTextField(
                      controller: _psa10PriceController,
                      label: 'Precio PSA 10 (opcional)',
                      hint: 'Ej: 75.00',
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      prefixText: r'€/$ ',
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              // ── Sección de Portfolio (Coste de compra y Estado) ──────────
              _buildPortfolioSection(),

              const SizedBox(height: 12),

              if (_imageFile == null)
                _buildTextField(
                  controller: _imageUrlController,
                  label: 'O pegar URL de imagen de la carta',
                  hint: 'https://...',
                ),

              const SizedBox(height: 24),

              ElevatedButton.icon(
                onPressed: _isSaving ? null : _saveCard,
                icon: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check),
                label: Text(
                  _isSaving
                      ? 'Guardando...'
                      : (widget.cardToEdit != null
                          ? 'Guardar Cambios'
                          : 'Guardar en mi Álbum'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),

              // Espacio amplio al final para evitar que quede pegado al borde
              const SizedBox(height: 50),
            ],
          ),
        ),
      ),
    );
  }

  // ── Selector de Franquicia TCG ─────────────────────────────────────────────
  Widget _buildGameSelector() {
    final availableGames =
        TcgGame.values.where((g) => g != TcgGame.all).toList();

    return Container(
      padding: const EdgeInsets.all(12),
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
                'Selecciona el juego TCG:',
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
              children: availableGames.map((game) {
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
                      if (selected) setState(() => _selectedGame = game);
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

  Widget _buildImageSection() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF16213E),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          if (_imageFile != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.file(_imageFile!, height: 180, fit: BoxFit.contain),
            ),
            const SizedBox(height: 10),
          ] else if (_imageUrlController.text.trim().isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: CachedNetworkImage(
                imageUrl: _imageUrlController.text.trim(),
                height: 180,
                fit: BoxFit.contain,
                errorWidget: (_, __, ___) => const Icon(
                  Icons.broken_image,
                  color: Colors.white38,
                  size: 50,
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              OutlinedButton.icon(
                onPressed: () => _pickImage(ImageSource.camera),
                icon: const Icon(Icons.camera_alt, color: Colors.amber, size: 18),
                label: const Text('Hacer Foto',
                    style: TextStyle(color: Colors.white, fontSize: 13)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.amber),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _pickImage(ImageSource.gallery),
                icon: const Icon(Icons.photo_library,
                    color: Colors.amber, size: 18),
                label: const Text('De Galería',
                    style: TextStyle(color: Colors.white, fontSize: 13)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.amber),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                ),
              ),
              if (_imageFile != null)
                IconButton(
                  tooltip: 'Quitar foto',
                  icon: const Icon(Icons.close, color: Colors.redAccent),
                  onPressed: () => setState(() => _imageFile = null),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    String? prefixText,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70, fontSize: 13),
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
        prefixText: prefixText,
        prefixStyle:
            const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold),
        filled: true,
        fillColor: const Color(0xFF0F3460),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildLanguageSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0F3460),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.language, color: Colors.white60, size: 16),
          const SizedBox(width: 8),
          const Text('Idioma:',
              style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(width: 10),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: CardLanguage.values
                    .where((l) => l != CardLanguage.auto)
                    .map((lang) {
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
                      backgroundColor: const Color(0xFF16213E),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      onSelected: (selected) {
                        if (selected) setState(() => _selectedLanguage = lang);
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

  Widget _buildPortfolioSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF16213E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.account_balance_wallet, color: Colors.greenAccent, size: 18),
              SizedBox(width: 8),
              Text(
                'Datos de Portfolio / Colección (Opcional)',
                style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildTextField(
                  controller: _purchasePriceController,
                  label: 'Coste de compra (€)',
                  hint: 'Ej: 12.00',
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  prefixText: '€ ',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _purchaseDate ?? DateTime.now(),
                      firstDate: DateTime(1996),
                      lastDate: DateTime.now(),
                      builder: (context, child) {
                        return Theme(
                          data: ThemeData.dark().copyWith(
                            colorScheme: const ColorScheme.dark(
                              primary: Colors.amber,
                              surface: Color(0xFF16213E),
                            ),
                          ),
                          child: child!,
                        );
                      },
                    );
                    if (picked != null) {
                      setState(() => _purchaseDate = picked);
                    }
                  },
                  child: Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F3460),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _purchaseDate != null
                              ? '${_purchaseDate!.day}/${_purchaseDate!.month}/${_purchaseDate!.year}'
                              : 'Fecha compra',
                          style: TextStyle(
                            color: _purchaseDate != null ? Colors.white : Colors.white38,
                            fontSize: 12,
                          ),
                        ),
                        const Icon(Icons.calendar_today, size: 16, color: Colors.white54),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Estado de la carta:',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ...CardCondition.values.map((cond) {
                  final isSelected = _selectedCondition == cond;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(
                        '${cond.shortCode} (${cond.label})',
                        style: TextStyle(
                          color: isSelected ? Colors.black : Colors.white70,
                          fontSize: 11,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      selected: isSelected,
                      selectedColor: Color(cond.colorHex),
                      backgroundColor: const Color(0xFF0F3460),
                      side: BorderSide(
                        color: isSelected ? Color(cond.colorHex) : Colors.white24,
                      ),
                      onSelected: (selected) {
                        setState(() {
                          _selectedCondition = selected ? cond : null;
                        });
                      },
                    ),
                  );
                }),
                if (_selectedCondition != null)
                  TextButton(
                    onPressed: () => setState(() => _selectedCondition = null),
                    child: const Text('Limpiar', style: TextStyle(color: Colors.white38, fontSize: 11)),
                  ),
              ],
            ),
          ),
          if (_selectedCondition == CardCondition.graded) ...[
            const SizedBox(height: 10),
            _buildTextField(
              controller: _gradingScoreController,
              label: 'Puntuación y Empresa de Graduación',
              hint: 'Ej: PSA 9, BGS 9.5, CGC 10...',
            ),
          ],
        ],
      ),
    );
  }
}
