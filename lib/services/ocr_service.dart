// ============================================================
// services/ocr_service.dart
// Servicio de reconocimiento óptico de caracteres (OCR) local
// usando Google ML Kit Text Recognition para cartas TCG:
// Pokémon, Magic (MTG), Yu-Gi-Oh!, Digimon, One Piece, Lorcana, etc.
// Soporta caracteres Latinos (Español, Inglés), Coreanos (Hangul),
// Japoneses (Kanji/Kana) y Chinos.
// ============================================================

import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Idiomas soportados para el reconocimiento y búsqueda de cartas.
enum CardLanguage {
  auto('🌐 Auto', 'auto'),
  es('🇪🇸 Español', 'es'),
  en('🇬🇧 Inglés', 'en'),
  ja('🇯🇵 Japonés', 'ja'),
  ko('🇰🇷 Coreano', 'ko'),
  zh('🇨🇳 Chino', 'zh-tw');

  final String label;
  final String apiCode;
  const CardLanguage(this.label, this.apiCode);
}

/// Resultado del análisis OCR sobre una imagen de carta TCG.
class OcrResult {
  /// Número de colección o referencia detectado (ej. "140/195", "070/280", "LOB-005", "ST1-03", "OP01-025").
  final String? collectionNumber;

  /// Nombre del personaje/carta detectado en el texto.
  final String? pokemonName;

  /// Idioma detectado en la carta.
  final CardLanguage detectedLanguage;

  /// Todo el texto bruto extraído por ML Kit.
  final String rawText;

  const OcrResult({
    this.collectionNumber,
    this.pokemonName,
    this.detectedLanguage = CardLanguage.auto,
    required this.rawText,
  });

  /// Devuelve true si se encontró el número de colección o el nombre.
  bool get isSuccessful => collectionNumber != null || pokemonName != null;
}

/// Servicio que encapsula la lógica de OCR multi-juego y multiidioma.
class OcrService {
  // ── RegEx 1: Número de colección estándar con fracción (ej: "140/195", "070/280") ─────
  static final RegExp _collectionNumberRegex =
      RegExp(r'\b(\d{1,4}/\d{1,4})\b');

  // ── RegEx 2: Código con prefijo de set (ej: "SV5K-005", "LOB-005", "ST1-03", "OP01-025") ───────
  static final RegExp _setCodeRegex =
      RegExp(r'\b([A-Za-z0-9]{2,6}[A-Za-z0-9\.\-]*\s*[-–]\s*\d{1,4})\b');

  // ── RegEx 3: Código de 8 dígitos tipo Yu-Gi-Oh! Passcode (ej: 46986414) ───────────
  static final RegExp _passcodeRegex = RegExp(r'\b(\d{8})\b');

  // Palabras comunes a ignorar de todos los TCG
  static final Set<String> _ignoredWords = {
    // ── Pokémon ──
    'BASIC', 'BASICO', 'BÁSICO', 'GASICO', 'GÁSICO', 'CASICO', 'PASICO',
    'STAGE', 'STAGE 1', 'STAGE 2', 'FASE', 'FASE 1', 'FASE 2',
    'POKEMON', 'POKÉMON', 'POKEMON BASICO', 'POKÉMON BÁSICO',
    'TRAINER', 'ENTRENADOR', 'SUPPORTER', 'PARTIDARIO', 'ITEM', 'OBJETO',
    'ENERGY', 'ENERGIA', 'ENERGÍA', 'VSTAR', 'VMAX', 'ABILITY', 'HABILIDAD',
    'WEAKNESS', 'DEBILIDAD', 'RESISTANCE', 'RESISTENCIA', 'RETREAT', 'RETIRADA',
    'RULE', 'REGLA', 'HP', 'PS', 'ILUS', 'ILLUS',
    // Japonés Pokémon
    'たね', '1進化', '2進化', 'グッズ', 'サポート', 'スタジアム', 'トレーナーズ',
    'エネルギー', '特性', '弱点', '抵抗力', 'にげる', 'ルール',
    // Coreano Pokémon
    '기본', '1진화', '2진화', '아이템', '서포트', '스타디움', '트레이너스',
    '에너지', '특성', '약점', '저항力', '후퇴', '룰',
    // Chino Pokémon
    '基础', '1阶进化', '2阶进化', '物品', '支援者', '竞技场', '训练家',
    '能量', '撤退', '规则',

    // ── Magic: The Gathering (MTG) ──
    'CREATURE', 'CRIATURA', 'SORCERY', 'CONJURO', 'INSTANT', 'INSTANTANEO',
    'INSTANTÁNEO', 'ARTIFACT', 'ARTEFACTO', 'ENCHANTMENT', 'ENCANTAMIENTO',
    'PLANESWALKER', 'LAND', 'TIERRA', 'LEGENDARY', 'LEYENDA', 'TRAMPLE',
    'FLYING', 'VIGILANCE', 'DEATHTOUCH',

    // ── Yu-Gi-Oh! ──
    'MONSTER', 'MONSTRUO', 'SPELL', 'MAGIA', 'TRAP', 'TRAMPA', 'FUSION',
    'FUSIÓN', 'SYNCHRO', 'SINCRONÍA', 'XYZ', 'PENDULUM', 'PÉNDULO', 'LINK',
    'ENLACE', 'EFFECT', 'EFECTO', 'ATK', 'DEF', '1ST EDITION', 'EDICIÓN LIMITADA',

    // ── Digimon ──
    'DIGIMON', 'OPTION', 'OPCIÓN', 'TAMER', 'DOMADOR', 'DIGI-EGG', 'DIGIHUEVO',
    'ROOKIE', 'CHAMPION', 'ULTIMATE', 'MEGA', 'VACCINE', 'VIRUS', 'DATA',

    // ── One Piece ──
    'LEADER', 'LÍDER', 'CHARACTER', 'PERSONAJE', 'EVENT', 'EVENTO',
    'ESCENARIO', 'SLASH', 'STRIKE', 'DON!!', 'COUNTER', 'POWER', 'COST',
  };

  /// Reconoce texto de la imagen según el idioma seleccionado o auto-detección.
  Future<OcrResult> extractFromImage(
    File imageFile, {
    CardLanguage language = CardLanguage.auto,
  }) async {
    final inputImage = InputImage.fromFile(imageFile);

    // 1. Si el usuario seleccionó un idioma asiático específico, usar ese script
    if (language == CardLanguage.ja) {
      return _runRecognition(inputImage, TextRecognitionScript.japanese, CardLanguage.ja);
    } else if (language == CardLanguage.ko) {
      return _runRecognition(inputImage, TextRecognitionScript.korean, CardLanguage.ko);
    } else if (language == CardLanguage.zh) {
      return _runRecognition(inputImage, TextRecognitionScript.chinese, CardLanguage.zh);
    }

    // 2. Modo Auto o Latino: primero reconocer en Latin (lee números 140/195 y texto occidental)
    final latinResult = await _runRecognition(
      inputImage,
      TextRecognitionScript.latin,
      CardLanguage.en,
    );

    // Si encontró el nombre en caracteres latinos, devolverlo
    if (latinResult.pokemonName != null && latinResult.pokemonName!.isNotEmpty) {
      return latinResult;
    }

    // 3. Si en Auto no encontró nombre latino (ej: carta japonesa, coreana o china),
    // probar con reconocedor Japonés, Coreano o Chino
    final asianScripts = [
      (TextRecognitionScript.korean, CardLanguage.ko),
      (TextRecognitionScript.japanese, CardLanguage.ja),
      (TextRecognitionScript.chinese, CardLanguage.zh),
    ];

    for (final (script, lang) in asianScripts) {
      final asianResult = await _runRecognition(inputImage, script, lang);
      if (asianResult.pokemonName != null && asianResult.pokemonName!.isNotEmpty) {
        return OcrResult(
          collectionNumber: latinResult.collectionNumber ?? asianResult.collectionNumber,
          pokemonName: asianResult.pokemonName,
          detectedLanguage: lang,
          rawText: '${latinResult.rawText}\n${asianResult.rawText}',
        );
      }
    }

    return latinResult;
  }

  /// Ejecuta un reconocedor específico para un script dado.
  Future<OcrResult> _runRecognition(
    InputImage inputImage,
    TextRecognitionScript script,
    CardLanguage targetLanguage,
  ) async {
    final recognizer = TextRecognizer(script: script);
    try {
      final RecognizedText recognizedText =
          await recognizer.processImage(inputImage);

      final rawText = recognizedText.text;

      // ── Paso 1: Buscar número de colección o código de set ─────────────
      String? collectionNumber;
      final matchStandard = _collectionNumberRegex.firstMatch(rawText);
      if (matchStandard != null) {
        collectionNumber = matchStandard.group(1);
      } else {
        final matchSetCode = _setCodeRegex.firstMatch(rawText);
        if (matchSetCode != null) {
          collectionNumber = matchSetCode.group(1);
        } else {
          final matchPasscode = _passcodeRegex.firstMatch(rawText);
          collectionNumber = matchPasscode?.group(1);
        }
      }

      // ── Paso 2: Buscar nombre del personaje/carta ──────────────────────
      String? cardTitle;

      for (final line in rawText.split('\n')) {
        var trimmed = line.trim();

        if (trimmed.length < 2) continue;
        if (trimmed == collectionNumber) continue;
        if (RegExp(r'^\d+$').hasMatch(trimmed)) continue;

        // Quitar indicadores de PS / HP / ATK / DEF / DP
        trimmed = trimmed
            .replaceAll(RegExp(r'\b(HP|PS|ATK|DEF|DP)\s*[:/]?\s*\d+\b', caseSensitive: false), '')
            .replaceAll(RegExp(r'\b\d+\s*(HP|PS|ATK|DEF|DP)\b', caseSensitive: false), '')
            .replaceAll(RegExp(r'\[(Monster|Spell|Trap|Creature|Monstruo|Magia|Trampa)\]', caseSensitive: false), '')
            .trim();

        // Quitar palabras de estado en cualquier idioma
        trimmed = trimmed.replaceAll(
          RegExp(
            r'\b(pok[eé]mon\s+)?(b[aá]sico|g[aá]sico|c[aá]sico|p[aá]sico|fase\s*\d*|stage\s*\d*|basic|creature|instant|sorcery|trap|spell)\b',
            caseSensitive: false,
          ),
          '',
        ).replaceAll(
          RegExp(r'(たね|1進化|2進化|기본|1진화|2진화|基础|1阶进化|2阶进化)'),
          '',
        ).trim();

        // Quitar caracteres no alfabéticos de los extremos
        trimmed = trimmed.replaceAll(
          RegExp(r'^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$', unicode: true),
          '',
        ).trim();

        // Separar sufijos pegados al nombre
        trimmed = trimmed.replaceAllMapped(
          RegExp(r'([\p{L}\-]{2,})(vmax|vstar|ex|gx|break|v)$',
              caseSensitive: false, unicode: true),
          (m) => '${m.group(1)} ${m.group(2)!.toUpperCase()}',
        );

        if (trimmed.length < 2) continue;

        final upper = trimmed.toUpperCase();
        if (_ignoredWords.any((w) => upper == w || upper.startsWith('$w '))) {
          continue;
        }

        // Si contiene letras latinas, coreanas, japonesas o chinas válidas
        if (RegExp(r'[\p{L}]', unicode: true).hasMatch(trimmed)) {
          cardTitle = _cleanName(trimmed);
          break;
        }
      }

      // Detectar idioma si se encontraron caracteres asiáticos
      CardLanguage lang = targetLanguage;
      if (cardTitle != null) {
        if (RegExp(r'[\uAC00-\uD7AF]').hasMatch(cardTitle)) {
          lang = CardLanguage.ko;
        } else if (RegExp(r'[\u3040-\u30FF]').hasMatch(cardTitle)) {
          lang = CardLanguage.ja;
        } else if (RegExp(r'[\u4E00-\u9FFF]').hasMatch(cardTitle)) {
          lang = CardLanguage.zh;
        }
      }

      return OcrResult(
        collectionNumber: collectionNumber,
        pokemonName: cardTitle,
        detectedLanguage: lang,
        rawText: rawText,
      );
    } finally {
      await recognizer.close();
    }
  }

  String _cleanName(String text) {
    var clean = text.trim();
    // Si es latino, capitalizar estilo título
    if (RegExp(r'^[A-Za-z\s\-\.]+$').hasMatch(clean)) {
      clean = clean.split(' ').map((word) {
        if (word.isEmpty) return word;
        if (['V', 'EX', 'GX', 'VSTAR', 'VMAX', 'SP', 'SR', 'SEC'].contains(word.toUpperCase())) {
          return word.toUpperCase();
        }
        return word.split('-').map((part) {
          if (part.isEmpty) return part;
          return part[0].toUpperCase() + part.substring(1).toLowerCase();
        }).join('-');
      }).join(' ');
    }
    return clean;
  }
}
