// ============================================================
// services/ocr_service.dart
// Servicio de reconocimiento óptico de caracteres (OCR) local
// usando Google ML Kit Text Recognition para cartas TCG:
// Pokémon, Magic (MTG), Yu-Gi-Oh!, Digimon, One Piece, Lorcana, etc.
// Incorpora ordenación espacial (zonas superior e inferior de la carta),
// normalización tolerante a fallos de OCR en números de colección,
// filtrado estricto de indicadores de vida (HP/PS) y atributos,
// y reconocimiento robusto multi-script para cartas asiáticas (JA, KO, ZH).
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

/// Servicio que encapsula la lógica de OCR multi-juego y multiidioma con ordenación espacial.
class OcrService {
  // Palabras comunes a ignorar de todos los TCG para evitar falsos positivos
  static final Set<String> _ignoredWords = {
    // ── Pokémon ──
    'BASIC', 'BASICO', 'BÁSICO', 'GASICO', 'GÁSICO', 'CASICO', 'PASICO',
    'STAGE', 'STAGE 1', 'STAGE 2', 'FASE', 'FASE 1', 'FASE 2',
    'POKEMON', 'POKÉMON', 'POKEMON BASICO', 'POKÉMON BÁSICO',
    'TRAINER', 'ENTRENADOR', 'SUPPORTER', 'PARTIDARIO', 'ITEM', 'OBJETO',
    'ENERGY', 'ENERGIA', 'ENERGÍA', 'VSTAR', 'VMAX', 'ABILITY', 'HABILIDAD',
    'WEAKNESS', 'DEBILIDAD', 'RESISTANCE', 'RESISTENCIA', 'RETREAT', 'RETIRADA',
    'RULE', 'REGLA', 'HP', 'PS', 'ILUS', 'ILLUS', 'ILLUST',
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

    // 1. Si el usuario seleccionó un idioma asiático específico, usar ese script directamente
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
      language,
    );

    // Validar si el título latino extraído es un nombre real (no un número de HP ni ruido)
    final latinName = latinResult.pokemonName?.trim();
    final bool hasValidLatinName = latinName != null &&
        latinName.length >= 2 &&
        !RegExp(r'^\d+$').hasMatch(latinName) &&
        !RegExp(r'\b(HP|PS|ATK|DEF)\b', caseSensitive: false).hasMatch(latinName) &&
        RegExp(r'[\p{L}]', unicode: true).allMatches(latinName).length >= 2;

    // Si el usuario eligió un idioma latino explícito (es, en), respetar su elección
    if (language != CardLanguage.auto) {
      return latinResult;
    }

    // En modo Auto:
    // Si tenemos nombre latino válido Y número, y NO hay caracteres asiáticos obvios en el texto general:
    final hasAsianChars = RegExp(r'[\u3040-\u30FF\uAC00-\uD7AF\u4E00-\u9FFF]').hasMatch(latinResult.rawText);
    if (hasValidLatinName && latinResult.collectionNumber != null && !hasAsianChars) {
      return latinResult;
    }

    // 3. En modo Auto, si no hay nombre latino válido o la carta contiene texto asiático:
    // Probar scripts asiáticos (japonés, coreano, chino)
    final asianScripts = [
      (TextRecognitionScript.japanese, CardLanguage.ja),
      (TextRecognitionScript.korean, CardLanguage.ko),
      (TextRecognitionScript.chinese, CardLanguage.zh),
    ];

    for (final (script, lang) in asianScripts) {
      final asianResult = await _runRecognition(inputImage, script, lang);
      final asianName = asianResult.pokemonName?.trim();
      final hasValidAsianName = asianName != null &&
          asianName.length >= 2 &&
          !RegExp(r'^\d+$').hasMatch(asianName) &&
          !RegExp(r'\b(HP|PS)\b', caseSensitive: false).hasMatch(asianName);

      if (hasValidAsianName) {
        return OcrResult(
          collectionNumber: latinResult.collectionNumber ?? asianResult.collectionNumber,
          pokemonName: asianResult.pokemonName,
          detectedLanguage: asianResult.detectedLanguage != CardLanguage.auto
              ? asianResult.detectedLanguage
              : lang,
          rawText: '${latinResult.rawText}\n${asianResult.rawText}',
        );
      }
    }

    // Si ningún script asiático encontró nombre, devolver el mejor resultado posible
    return OcrResult(
      collectionNumber: latinResult.collectionNumber,
      pokemonName: hasValidLatinName ? latinResult.pokemonName : null,
      detectedLanguage: latinResult.detectedLanguage,
      rawText: latinResult.rawText,
    );
  }

  /// Ejecuta un reconocedor específico para un script dado aplicando lógica espacial.
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

      // ── 1. Recopilar todas las líneas con sus coordenadas espaciales ──
      final allLines = <TextLine>[];
      double minX = double.infinity;
      double maxX = 0;
      double minY = double.infinity;
      double maxY = 0;

      for (final block in recognizedText.blocks) {
        for (final line in block.lines) {
          allLines.add(line);
          final box = line.boundingBox;
          if (box.left < minX) minX = box.left;
          if (box.right > maxX) maxX = box.right;
          if (box.top < minY) minY = box.top;
          if (box.bottom > maxY) maxY = box.bottom;
        }
      }

      // Ordenar líneas verticalmente de arriba hacia abajo
      allLines.sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));

      final totalHeight = (maxY - minY).abs();
      final totalWidth = (maxX - minX).abs();
      final hasValidCoordinates = totalHeight > 80 && allLines.length >= 2;

      // ── 2. Extracción de Número de Colección / Código de Set ──────────
      // En cartas TCG, el número siempre está en el pie de carta (último 35% inferior)
      String? collectionNumber;

      if (hasValidCoordinates) {
        final bottomThreshold = minY + (totalHeight * 0.65);
        final bottomLines = allLines.where((l) => l.boundingBox.top >= bottomThreshold).toList();
        for (final line in bottomLines.reversed) {
          final found = _extractCollectionNumber(line.text);
          if (found != null) {
            collectionNumber = found;
            break;
          }
        }

        // Si se detectó sólo la fracción (ej: "012/028") sin código de set,
        // buscar en las líneas inferiores si alguna contiene el código de colección (ej: "s8a", "SV4a", "MEW", "S12a")
        if (collectionNumber != null && !collectionNumber.contains(' ') && !collectionNumber.contains('-')) {
          for (final line in bottomLines) {
            final clean = line.text.replaceAll(RegExp(r'[\[\]]'), ' ').trim();
            final match = RegExp(
              r'\b(s\d+[a-z]?|sv\d+[a-z]?|sm\d+[a-z]?|xy\d+|bw\d+|dp\d+|cp\d+|[A-Za-z]{2,4}\d{0,2})\b',
              caseSensitive: false,
            ).firstMatch(clean);
            if (match != null) {
              final candSet = match.group(1)!;
              final upper = candSet.toUpperCase();
              if (!['NO', 'NUM', 'REF', 'CARD', 'ITEM', 'PAGE', 'HP', 'PS', 'PROMO', 'BASIC'].contains(upper)) {
                collectionNumber = '$candSet $collectionNumber';
                break;
              }
            }
          }
        }
      }

      // Si no se encontró en la zona inferior, buscar en todas las líneas individuales
      if (collectionNumber == null) {
        for (final line in allLines.reversed) {
          final found = _extractCollectionNumber(line.text);
          if (found != null) {
            collectionNumber = found;
            break;
          }
        }
      }

      // Si aún no se encontró, probar en todo el texto concatenado
      collectionNumber ??= _extractCollectionNumber(rawText);

      // ── 3. Extracción de Nombre de la Carta ────────────────────────────
      // En cartas TCG, el nombre SIEMPRE está en el encabezado (primer 30% superior)
      // y en el lateral izquierdo/central (NUNCA en la esquina superior derecha donde se ubica el HP/Coste)
      String? cardTitle;

      List<TextLine> topLines;
      if (hasValidCoordinates) {
        final topThreshold = minY + (totalHeight * 0.32);
        topLines = allLines.where((l) => l.boundingBox.top <= topThreshold).toList();
      } else {
        topLines = allLines.take(4).toList();
      }

      for (final line in topLines) {
        final leftRatio = (hasValidCoordinates && totalWidth > 50)
            ? (line.boundingBox.left - minX) / totalWidth
            : null;
        final candidate = _cleanAndValidateTitle(line.text, collectionNumber, lineLeftRatio: leftRatio);
        if (candidate != null) {
          cardTitle = candidate;
          break;
        }
      }

      // Si no se encontró en el encabezado estricto, buscar en las líneas superiores (hasta 55%)
      if (cardTitle == null) {
        for (final line in allLines) {
          if (hasValidCoordinates) {
            if (line.boundingBox.top > (minY + totalHeight * 0.55)) {
              continue; // Evitar el pie de carta (ilustradores, números, legal)
            }
          }
          final leftRatio = (hasValidCoordinates && totalWidth > 50)
              ? (line.boundingBox.left - minX) / totalWidth
              : null;
          final candidate = _cleanAndValidateTitle(line.text, collectionNumber, lineLeftRatio: leftRatio);
          if (candidate != null) {
            cardTitle = candidate;
            break;
          }
        }
      }

      // ── 4. Detección de idioma según caracteres del título o texto ────
      CardLanguage lang = targetLanguage;
      final isJaContext = RegExp(r'(?:s\d+[a-z]?|sv\d+[a-z]?|[\u3040-\u30FF])', caseSensitive: false).hasMatch(rawText) ||
          (collectionNumber != null && collectionNumber.toLowerCase().contains('s8a'));

      final titleOrRaw = cardTitle ?? rawText;
      if (RegExp(r'[\u3040-\u30FF]').hasMatch(titleOrRaw)) {
        lang = CardLanguage.ja;
      } else if (RegExp(r'[\uAC00-\uD7AF]').hasMatch(titleOrRaw)) {
        lang = CardLanguage.ko;
      } else if (RegExp(r'[\u4E00-\u9FFF]').hasMatch(titleOrRaw)) {
        // Caracteres CJK (Kanji): Si el contexto contiene Kana o código de set japonés (s8a, sv...), es 100% Japonés
        lang = isJaContext ? CardLanguage.ja : CardLanguage.zh;
      } else if (targetLanguage == CardLanguage.auto) {
        // ── Detección entre Español e Inglés para texto latino en modo Auto ──
        final hasSpanishPs = RegExp(r'\bPS\s*\d+\b').hasMatch(rawText); // En español siempre es "PS", en inglés "HP"
        final hasSpanishWords = RegExp(
          r'\b(básico|fase\s*[12]|daño|energía|descarta|descarte|baraja|roba|rival|combate|banca|puedes|ataque|debilidad|resistencia|retirada|partidario|objeto|estadio|habilidad)\b',
          caseSensitive: false,
        ).hasMatch(rawText);
        final hasSpanishAccents = RegExp(r'[áéíóúñ¿¡]').hasMatch(rawText);

        final hasEnglishHp = RegExp(r'\bHP\s*\d+\b').hasMatch(rawText);
        final hasEnglishWords = RegExp(
          r'\b(basic|stage\s*[12]|damage|discard|deck|opponent|bench|weakness|resistance|retreat|supporter|stadium|ability)\b',
          caseSensitive: false,
        ).hasMatch(rawText);

        if (hasSpanishPs || hasSpanishWords || hasSpanishAccents) {
          lang = CardLanguage.es;
        } else if (hasEnglishHp || hasEnglishWords) {
          lang = CardLanguage.en;
        } else {
          // Por defecto en la app en español, clasificar como español
          lang = CardLanguage.es;
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

  /// Extractor resiliente de números de colección, códigos de set y passcodes.
  /// Tolera espacios accidentales ("140 / 195"), caracteres confundidos por OCR
  /// ("O25/165" -> "025/165", "025/l65" -> "025/165"), y separadores como pipes ("|").
  String? _extractCollectionNumber(String text) {
    if (text.trim().isEmpty) return null;

    // Normalizar separadores y barras
    var normalized = text.replaceAll(RegExp(r'[|\\／]'), '/');
    normalized = normalized.replaceAll(RegExp(r'\s*/\s*'), '/');

    // Reparar posibles barras accidentales introducidas por el OCR dentro de números (ej: "0/12/028" -> "012/028")
    normalized = normalized.replaceAllMapped(
      RegExp(r'\b(\d)/(\d{2,3}/\d{2,4})\b'),
      (m) => '${m.group(1)}${m.group(2)}',
    );

    // 1. Formato Set + Fracción (ej: "s8a 012/028", "[s8a] 012/028", "s8a-012/028", "SV4a 025/190", "MEW 025/165")
    final matchSetAndFrac = RegExp(
      r'(?:\[|\b)([A-Za-z0-9]{2,6})(?:\]|\b)?\s*[-–_]?\s*(\d{1,4}/\d{1,4})\b',
    ).firstMatch(normalized);
    if (matchSetAndFrac != null) {
      final setCode = matchSetAndFrac.group(1)!;
      final frac = matchSetAndFrac.group(2)!;
      final upperSet = setCode.toUpperCase();
      if (!['NO', 'NUM', 'REF', 'CARD', 'ITEM', 'PAGE', 'BASIC', 'STAGE', 'POKEMON', 'HP', 'PS'].contains(upperSet)) {
        return '$setCode $frac';
      }
    }

    // 2. Fracción estándar de colección (ej: "025/165", "140/195", "070/280", "012/028")
    final matchStandard = RegExp(r'\b(\d{1,4}/\d{1,4})\b').firstMatch(normalized);
    if (matchStandard != null) {
      return matchStandard.group(1);
    }

    // 3. Fracción con caracteres alfanuméricos confundidos por OCR:
    // 'O'/'o' por 0, 'I'/'l' por 1, 'S'/'s' por 5 (ej: "O25/165", "025/l65", "140/19S")
    final matchConfused = RegExp(r'\b([0-9OIlS]{1,4}/[0-9OIlS]{1,4})\b').firstMatch(normalized);
    if (matchConfused != null) {
      final rawMatch = matchConfused.group(1)!;
      final repaired = rawMatch
          .replaceAll(RegExp(r'[Oo]'), '0')
          .replaceAll(RegExp(r'[Il]'), '1')
          .replaceAll(RegExp(r'[Ss]'), '5');
      if (RegExp(r'^\d{1,4}/\d{1,4}$').hasMatch(repaired)) {
        return repaired;
      }
    }

    // 4. Código de Set con prefijo y número (ej: "s8a-012", "SV5K-005", "LOB-005", "ST1-03", "OP01-025", "BT1-025")
    final matchSetCode = RegExp(r'\b([A-Za-z0-9]{2,6}[A-Za-z0-9\.\-]*\s*[-–_]\s*\d{1,4})\b')
        .firstMatch(normalized);
    if (matchSetCode != null) {
      return matchSetCode.group(1)!.replaceAll(' ', '');
    }

    // 5. Código Passcode Yu-Gi-Oh! (8 dígitos exactos)
    final matchPasscode = RegExp(r'\b(\d{8})\b').firstMatch(normalized);
    if (matchPasscode != null) {
      return matchPasscode.group(1);
    }

    // 6. Número individual precedido de No. o # (ej: "No. 025", "#025", "Ref: 051")
    final matchPrefixedNumber = RegExp(r'(?:no\.?|#|ref:?)\s*(\d{2,4})\b', caseSensitive: false)
        .firstMatch(normalized);
    if (matchPrefixedNumber != null) {
      return matchPrefixedNumber.group(1);
    }

    return null;
  }

  /// Limpia y valida si una línea de texto corresponde al título de una carta.
  String? _cleanAndValidateTitle(
    String line,
    String? collectionNumber, {
    double? lineLeftRatio,
  }) {
    // Si la línea está en el cuadrante derecho superior (> 58% del ancho),
    // es la zona reservada para HP, tipo elemental, mana o atributo. Nunca es el título.
    if (lineLeftRatio != null && lineLeftRatio > 0.58) {
      return null;
    }

    var trimmed = line.trim();
    if (trimmed.length < 2) return null;
    if (collectionNumber != null && trimmed.contains(collectionNumber)) return null;

    // Descartar si es estrictamente numérico o sólo contiene dígitos y símbolos de puntuación
    if (RegExp(r'^\d+$').hasMatch(trimmed)) return null;
    if (RegExp(r'^[\d\s\.\,\:\;\-\/]+$').hasMatch(trimmed)) return null;

    // Descartar si contiene indicadores de vida (HP / PS) solos o combinados con números
    // Ejemplos: "HP 120", "120 HP", "HP120", "120HP", "PS 120", "HP: 70", "120 PS", "HP"
    if (RegExp(r'\b(HP|PS)\b', caseSensitive: false).hasMatch(trimmed) &&
        RegExp(r'\d+').hasMatch(trimmed)) {
      return null;
    }
    if (RegExp(r'(?:HP|PS)\s*[:/]?\s*\d+|\d+\s*[:/]?\s*(?:HP|PS)', caseSensitive: false).hasMatch(trimmed)) {
      return null;
    }

    // Quitar indicadores de PS / HP / ATK / DEF / DP y números pegados
    trimmed = trimmed
        .replaceAll(RegExp(r'(?:HP|PS|ATK|DEF|DP)\s*[:/]?\s*\d+', caseSensitive: false), '')
        .replaceAll(RegExp(r'\d+\s*(?:HP|PS|ATK|DEF|DP)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\b(HP|PS|ATK|DEF|DP)\b', caseSensitive: false), '')
        .replaceAll(RegExp(r'\[(Monster|Spell|Trap|Creature|Monstruo|Magia|Trampa)\]', caseSensitive: false), '')
        .trim();

    // Quitar palabras de descriptor de fase y tipos
    trimmed = trimmed.replaceAll(
      RegExp(
        r'\b(pok[eé]mon\s+)?(b[aá]sico|g[aá]sico|c[aá]sico|p[aá]sico|fase\s*\d*|stage\s*\d*|basic|creature|instant|sorcery|trap|spell|monster|trainer|supporter|item)\b',
        caseSensitive: false,
      ),
      '',
    ).replaceAll(
      RegExp(r'(たね|1進化|2進化|기본|1진화|2진화|基础|1阶进化|2阶进化)'),
      '',
    ).trim();

    // Quitar caracteres no alfanuméricos de los extremos
    trimmed = trimmed.replaceAll(
      RegExp(r'^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$', unicode: true),
      '',
    ).trim();

    // Separar sufijos pegados al nombre (ej: "Pikachuex" -> "Pikachu EX")
    trimmed = trimmed.replaceAllMapped(
      RegExp(r'([\p{L}\-]{2,})(vmax|vstar|ex|gx|break|v)$', caseSensitive: false, unicode: true),
      (m) => '${m.group(1)} ${m.group(2)!.toUpperCase()}',
    );

    if (trimmed.length < 2) return null;

    // Si después de limpiar sólo quedó un número (ej: "120"), descartar
    if (RegExp(r'^\d+$').hasMatch(trimmed)) return null;

    final upper = trimmed.toUpperCase();
    if (_ignoredWords.any((w) => upper == w || upper.startsWith('$w '))) {
      return null;
    }

    // Filtrar líneas largas de descripción o textos de ataques (> 4 palabras)
    if (trimmed.split(RegExp(r'\s+')).length > 4) {
      return null;
    }

    // Debe contener al menos 2 caracteres alfabéticos válidos (latinos o asiáticos)
    final letterCount = RegExp(r'[\p{L}]', unicode: true).allMatches(trimmed).length;
    if (letterCount >= 2) {
      return _cleanName(trimmed);
    }

    return null;
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
