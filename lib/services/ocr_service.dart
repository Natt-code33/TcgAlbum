// ============================================================
// services/ocr_service.dart
// Servicio de reconocimiento óptico de caracteres (OCR) local
// usando Google ML Kit Text Recognition exclusivo para Pokémon TCG.
// Incorpora ordenación espacial (zonas superior e inferior de la carta),
// priorización geométrica por altura de fuente (boundingBox.height),
// normalización tolerante a fallos de OCR en números de colección,
// filtrado de subtítulos de evolución ("Evoluciona de..."), vida (HP/PS),
// y corrección difusa (Levenshtein) contra las 1.025 especies Pokémon.
// ============================================================

import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/card_number.dart';
import 'local_catalog_service.dart';

/// Idiomas soportados para el reconocimiento y búsqueda de cartas.
enum CardLanguage {
  auto('Auto', 'auto'),
  es('Español', 'es'),
  en('Inglés', 'en'),
  ja('Japonés', 'ja'),
  ko('Coreano', 'ko'),
  zh('Chino', 'zh-tw');

  final String label;
  final String apiCode;
  const CardLanguage(this.label, this.apiCode);
}

/// Resultado del análisis OCR sobre una imagen de carta TCG.
class OcrResult {
  /// Número de colección estructurado (set, número, total).
  final CardNumber? cardNumber;

  /// Texto de presentación del número (ej. "025/165", "TG14/30").
  String? get collectionNumber => cardNumber?.display;

  /// Nombre del personaje/carta detectado en el texto.
  final String? pokemonName;

  /// Idioma detectado en la carta.
  final CardLanguage detectedLanguage;

  /// Todo el texto bruto extraído por ML Kit.
  final String rawText;

  const OcrResult({
    this.cardNumber,
    this.pokemonName,
    this.detectedLanguage = CardLanguage.auto,
    required this.rawText,
  });

  /// Devuelve true si se encontró el número de colección o el nombre.
  bool get isSuccessful => cardNumber != null || pokemonName != null;
}

/// Servicio que encapsula la lógica de OCR exclusivo para Pokémon TCG con ordenación espacial.
class OcrService {
  final Map<TextRecognitionScript, TextRecognizer> _recognizers = {};
  bool _disposed = false;

  TextRecognizer _recognizer(TextRecognitionScript script) {
    if (_disposed) {
      throw StateError('OcrService disposed');
    }
    return _recognizers.putIfAbsent(
      script,
      () => TextRecognizer(script: script),
    );
  }

  Future<void> dispose() async {
    _disposed = true;
    for (final recognizer in _recognizers.values) {
      await recognizer.close();
    }
    _recognizers.clear();
  }

  // Palabras comunes de Pokémon TCG a ignorar para evitar falsos positivos
  static final Set<String> _ignoredWords = {
    'BASIC', 'BASICO', 'BÁSICO', 'GASICO', 'GÁSICO', 'CASICO', 'PASICO',
    'STAGE', 'STAGE 1', 'STAGE 2', 'FASE', 'FASE 1', 'FASE 2',
    'POKEMON', 'POKÉMON', 'POKEMON BASICO', 'POKÉMON BÁSICO',
    'TRAINER', 'ENTRENADOR', 'SUPPORTER', 'PARTIDARIO', 'ITEM', 'OBJETO',
    'STADIUM', 'ESTADIO', 'TOOL', 'HERRAMIENTA', 'HERRAMIENTA POKÉMON',
    'ENERGY', 'ENERGIA', 'ENERGÍA', 'VSTAR', 'VMAX', 'ABILITY', 'HABILIDAD',
    'WEAKNESS', 'DEBILIDAD', 'RESISTANCE', 'RESISTENCIA', 'RETREAT', 'RETIRADA',
    'RULE', 'REGLA', 'HP', 'PS', 'ILUS', 'ILLUS', 'ILLUST',
    'EVOLVES', 'EVOLVES FROM', 'EVOLUCIONA', 'EVOLUCIONA DE',
    'TERA', 'TERACRISTAL', 'ANCIENT', 'ANTIGUO', 'FUTURE', 'FUTURO',
    'SINGLE STRIKE', 'RAPID STRIKE', 'FUSION STRIKE',
    'GOLPE BRUSCO', 'GOLPE FLUIDO', 'GOLPE FUSIÓN',
    // Japonés Pokémon
    'たね', '1進化', '2進化', 'グッズ', 'サポート', 'スタジアム', 'トレーナーズ',
    'ポケモンのどうぐ', 'エネルギー', '特性', '弱点', '抵抗力', 'にげる', 'ルール',
    // Coreano Pokémon
    '기본', '1진화', '2진화', '아이템', '서포트', '스타디움', '트레이너스',
    '에너지', '특성', '약점', '저항력', '후퇴', '룰',
    // Chino Pokémon
    '基础', '1阶进化', '2阶进化', '物品', '支援者', '竞技场', '训练家',
    '能量', '撤退', '规则',
  };

  /// Reconoce texto de la imagen según el idioma seleccionado o auto-detección.
  Future<OcrResult> extractFromImage(
    File imageFile, {
    CardLanguage language = CardLanguage.auto,
  }) async {
    // La corrección difusa de nombres y la resolución del set necesitan el
    // catálogo cargado; en el primer escaneo tras abrir la app aún no lo está.
    await LocalCatalogService.instance.init();

    File? prepared;
    try {
      prepared = await _prepareOcrImage(imageFile);
      final workFile = prepared ?? imageFile;

      final result = await _extractFromImageFull(
        workFile,
        language: language,
      );

      CardNumber? number = result.cardNumber;
      var stripRaw = '';

      if (number == null || _needsStripPass(result)) {
        // Segunda pasada sobre el pie de la carta, ampliado. Los números y el
        // código de set son muy pequeños y el OCR los confunde en la pasada
        // completa, sobre todo en cartas japonesas (104 -> 100).
        final strip = await _extractNumberFromStrip(workFile);
        stripRaw = strip.$2;
        if (strip.$1 != null) {
          number = _chooseNumber(number, strip.$1, result);
        }
      }

      // Un código de set inventado ("GXEE") hace que el matcher descarte la
      // carta correcta. Si no existe en el catálogo, se quita.
      if (number != null && number.setCode != null) {
        final ids = await LocalCatalogService.instance.allSetIds();
        if (!ids.contains(number.setCode!.toLowerCase())) {
          number = number.clearSetCode();
        }
      }

      // El set impreso es diminuto y el OCR lo suele estropear ("sv11b" ->
      // "DSM1B"/"SV18"). Se resuelve contra el catálogo usando la especie y el
      // total; así el matcher puede corregir un dígito del número.
      if (number != null && _shouldResolveSet(number, result)) {
        final resolved = await LocalCatalogService.instance.resolveSetCode(
          '${result.rawText}\n$stripRaw',
          cardName: result.pokemonName,
          totalInSet: number.totalInt,
          numberText: number.number,
        );
        if (resolved != null && resolved != number.setCode) {
          number = number.withSetCode(resolved);
        }
      }

      if (identical(number, result.cardNumber)) return result;

      return OcrResult(
        cardNumber: number,
        pokemonName: result.pokemonName,
        detectedLanguage: result.detectedLanguage,
        rawText: result.rawText,
      );
    } finally {
      if (prepared != null && prepared.path != imageFile.path) {
        try {
          await prepared.delete();
        } catch (_) {}
      }
    }
  }

  /// Amplía la imagen antes del OCR. Las fotos de carta suelen llegar a
  /// ~600 px de ancho y el número del pie queda por debajo de la resolución
  /// útil de ML Kit; escalar a 1600 px recupera el texto fino.
  Future<File?> _prepareOcrImage(File imageFile) async {
    try {
      final bytes = await imageFile.readAsBytes();
      var decoded = img.decodeImage(bytes);
      if (decoded == null) return null;
      decoded = img.bakeOrientation(decoded);

      const targetWidth = 1600;
      if (decoded.width < targetWidth) {
        final scale = targetWidth / decoded.width;
        decoded = img.copyResize(
          decoded,
          width: targetWidth,
          height: (decoded.height * scale).round(),
          interpolation: img.Interpolation.cubic,
        );
      } else {
        return null;
      }

      final dir = await getTemporaryDirectory();
      final temp = File(p.join(
        dir.path,
        'ocr_full_${DateTime.now().microsecondsSinceEpoch}.png',
      ));
      await temp.writeAsBytes(img.encodePng(decoded), flush: true);
      return temp;
    } catch (_) {
      return null;
    }
  }

  /// En cartas asiáticas conviene revisar siempre el set; en latinas sólo
  /// cuando la pasada completa no lo encontró.
  bool _shouldResolveSet(CardNumber number, OcrResult result) {
    if (number.setCode == null || number.setCode!.isEmpty) return true;
    return result.detectedLanguage == CardLanguage.ja ||
        result.detectedLanguage == CardLanguage.ko ||
        result.detectedLanguage == CardLanguage.zh;
  }

  /// La pasada del pie compensa la baja resolución del número en cartas
  /// asiáticas o cuando el set detectado no es plausible.
  bool _needsStripPass(OcrResult result) {
    if (result.cardNumber == null) return true;
    if (result.detectedLanguage == CardLanguage.ja ||
        result.detectedLanguage == CardLanguage.ko ||
        result.detectedLanguage == CardLanguage.zh) {
      return true;
    }
    final set = result.cardNumber!.setCode;
    if (set == null || set.isEmpty) return true;
    return !RegExp(r'[0-9]').hasMatch(set) &&
        !RegExp(r'^[a-z]{1,4}-[a-z]{1,4}$').hasMatch(set.toLowerCase());
  }

  CardNumber? _chooseNumber(
    CardNumber? full,
    CardNumber? strip,
    OcrResult result,
  ) {
    if (full == null) return strip;
    if (strip == null) return full;

    // Una fracción real del pie siempre gana a un número/promo suelto de la
    // pasada completa, detecte o no el idioma asiático.
    if (_isFraction(strip) && !_isFraction(full)) return strip;
    if (_isFraction(full) && !_isFraction(strip)) return full;

    final asian = result.detectedLanguage == CardLanguage.ja ||
        result.detectedLanguage == CardLanguage.ko ||
        result.detectedLanguage == CardLanguage.zh;

    // En cartas asiáticas el pie ampliado puede leer mejor el número, pero
    // también confunde "SV11B" con "SV118". Solo se acepta si es una
    // fracción real; nunca un promo suelto.
    if (asian) {
      final stripIsFraction = _isFraction(strip);
      final fullIsFraction = _isFraction(full);

      if (fullIsFraction && !stripIsFraction) return full;
      // "SV11B 104/086" leído como "SV118": una fracción real del pie
      // siempre es mejor que un promo inventado por la pasada completa.
      if (!fullIsFraction && stripIsFraction) return strip;

      if (stripIsFraction && fullIsFraction) {
        if (strip.setCode != null && full.setCode == null) return strip;
        if (full.setCode != null) return full;
        // Ambos sin set: el pie se reconoció a mayor resolución.
        return strip;
      }
    }

    // Si la pasada completa no trajo un set plausible y el pie sí, usar el pie.
    final fullSet = full.setCode;
    final stripSet = strip.setCode;
    final fullSetValid = fullSet != null &&
        (RegExp(r'[0-9]').hasMatch(fullSet) ||
            RegExp(r'^[a-z]{1,4}-[a-z]{1,4}$').hasMatch(fullSet.toLowerCase()));
    if (!fullSetValid && stripSet != null && stripSet.isNotEmpty) {
      return strip;
    }

    return full;
  }

  bool _isFraction(CardNumber number) =>
      number.kind == CardNumberKind.fraction ||
      number.kind == CardNumberKind.prefixedFraction ||
      number.kind == CardNumberKind.setFraction;

  Future<OcrResult> _extractFromImageFull(
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

    // Validar si el título latino extraído es un nombre real (no un número de
    // HP, un código de set ni ruido del ilustrador). El reconocedor latino no
    // devuelve caracteres CJK, así que "S8a" o "DBB" no pueden tomarse por un
    // nombre y cortar la pasada japonesa.
    final latinName = latinResult.pokemonName?.trim();
    final looksLikeSetCode = latinName != null &&
        (RegExp(r'^[A-Za-z]{1,4}\d+[A-Za-z]?(?:[-.][A-Za-z0-9]+)*$')
                .hasMatch(latinName) ||
            !RegExp(r'[aeiouAEIOU]').hasMatch(latinName));
    final latinWords = latinName?.split(RegExp(r'\s+')) ?? const <String>[];
    final hasStopWord = latinWords.any(CardNumber.isStopWord);
    final bool hasValidLatinName = latinName != null &&
        latinName.length >= 2 &&
        !looksLikeSetCode &&
        !hasStopWord &&
        !RegExp(r'^\d+$').hasMatch(latinName) &&
        !RegExp(r'\b(HP|PS|ATK|DEF)\b', caseSensitive: false).hasMatch(latinName) &&
        RegExp(r'[\p{L}]', unicode: true).allMatches(latinName).length >= 2;

    // Si el usuario eligió un idioma latino explícito (es, en), respetar su elección
    if (language != CardLanguage.auto) {
      return latinResult;
    }

    // En modo Auto, sólo se evita la pasada asiática si NO hay ningún indicio
    // asiático (ni caracteres CJK ni códigos de set como s8a/sv/sm).
    final hasAsianChars = RegExp(r'[\u3040-\u30FF\uAC00-\uD7AF\u4E00-\u9FFF]').hasMatch(latinResult.rawText);
    final setCode = latinResult.cardNumber?.setCode;
    final hasJapaneseSetContext = setCode != null &&
        RegExp(r'^(s\d+|sv\d+|sm\d+)', caseSensitive: false)
            .hasMatch(setCode);
    final hasAsianContext = hasAsianChars ||
        hasJapaneseSetContext ||
        RegExp(r'\b(s\d+[a-z]?|sv\d+[a-z]?)\b', caseSensitive: false).hasMatch(latinResult.rawText) ||
        (latinResult.collectionNumber != null && RegExp(r'\b(s\d+[a-z]?|sv\d+[a-z]?)\b', caseSensitive: false).hasMatch(latinResult.collectionNumber!));

    // Un número en alfabeto latino no demuestra que la carta sea occidental:
    // las japonesas también imprimen "003/015". Sólo se evita la pasada
    // asiática cuando el título latino es un nombre real.
    if (!hasAsianContext && hasValidLatinName) {
      return latinResult;
    }

    // 3. En modo Auto, si la carta apunta a script asiático:
    // Usar únicamente el reconocedor más probable.
    final asianScripts = <(TextRecognitionScript, CardLanguage)>[];
    final hasHangul = RegExp(r'[\uAC00-\uD7AF]').hasMatch(latinResult.rawText);
    final hasKana =
        RegExp(r'[\u3040-\u30FF]').hasMatch(latinResult.rawText);
    final hasHan = RegExp(r'[\u4E00-\u9FFF]').hasMatch(latinResult.rawText);
    if (hasHangul) {
      asianScripts.add((TextRecognitionScript.korean, CardLanguage.ko));
    } else if (hasKana) {
      asianScripts.add((TextRecognitionScript.japanese, CardLanguage.ja));
    } else if (hasHan) {
      // Han sin kana: probablemente chino, pero el japonés también usa kanji.
      // Se prueban ambos y gana el que produzca una especie conocida.
      asianScripts.add((TextRecognitionScript.chinese, CardLanguage.zh));
      asianScripts.add((TextRecognitionScript.japanese, CardLanguage.ja));
    } else {
      // El reconocedor latino descarta los CJK, así que no saber el script no
      // significa que la carta sea occidental.
      asianScripts.add((TextRecognitionScript.japanese, CardLanguage.ja));
      asianScripts.add((TextRecognitionScript.chinese, CardLanguage.zh));
    }

    final asianRaw = StringBuffer();
    CardNumber? asianNumber;
    OcrResult? bestAsian;
    CardLanguage? bestAsianLang;
    var bestAsianScore = -1;

    for (final (script, lang) in asianScripts) {
      final OcrResult asianResult;
      try {
        asianResult = await _runRecognition(inputImage, script, lang);
      } catch (_) {
        // Si el modelo de ese script no está disponible en el dispositivo,
        // probar el siguiente en vez de romper todo el escaneo.
        continue;
      }
      asianRaw.writeln(asianResult.rawText);
      asianNumber ??= asianResult.cardNumber;

      final asianName = asianResult.pokemonName?.trim();
      final hasValidAsianName = asianName != null &&
          asianName.length >= 2 &&
          !RegExp(r'^\d+$').hasMatch(asianName) &&
          !RegExp(r'\b(HP|PS)\b', caseSensitive: false).hasMatch(asianName);
      final asianHasCjk = asianName != null &&
          RegExp(r'[\u3040-\u30FF\uAC00-\uD7AF\u4E00-\u9FFF]')
              .hasMatch(asianName);

      if (!hasValidAsianName) continue;
      // Si el nombre asiático es latino y ya teníamos un nombre latino válido,
      // no lo pisamos: evita etiquetar cartas occidentales como japonesas.
      if (!asianHasCjk && hasValidLatinName) continue;

      // Gana el script que reconoce una especie real del catálogo. Así una
      // carta china no se queda con el kanji que "adivina" el japonés.
      var score = asianHasCjk ? 1 : 0;
      if (asianHasCjk &&
          LocalCatalogService.instance.isKnownSpecies(asianName)) {
        score = 2;
      }
      if (score > bestAsianScore) {
        bestAsianScore = score;
        bestAsian = asianResult;
        bestAsianLang = lang;
      }
      if (score == 2) break;
    }

    if (bestAsian != null && bestAsianScore > 0) {
      return OcrResult(
        cardNumber: latinResult.cardNumber ?? bestAsian.cardNumber,
        pokemonName: bestAsian.pokemonName,
        detectedLanguage: bestAsian.detectedLanguage != CardLanguage.auto
            ? bestAsian.detectedLanguage
            : bestAsianLang!,
        rawText: '${latinResult.rawText}\n${bestAsian.rawText}',
      );
    }

    // Si ningún script asiático encontró nombre, conservar igualmente su texto
    // (sirve para resolver el set) y su número si el latino no lo encontró.
    return OcrResult(
      cardNumber: latinResult.cardNumber ?? asianNumber,
      pokemonName: hasValidLatinName ? latinResult.pokemonName : null,
      detectedLanguage: latinResult.detectedLanguage,
      rawText: '${latinResult.rawText}\n$asianRaw',
    );
  }

  /// Ejecuta un reconocedor específico para un script dado aplicando lógica espacial.
  Future<OcrResult> _runRecognition(
    InputImage inputImage,
    TextRecognitionScript script,
    CardLanguage targetLanguage,
  ) async {
    final recognizer = _recognizer(script);
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
      // En cartas TCG, el número suele estar en el pie de carta.
      CardNumber? cardNumber;
      List<TextLine> bottomLines = const [];

      if (hasValidCoordinates) {
        final bottomThreshold = minY + (totalHeight * 0.65);
        bottomLines =
            allLines.where((l) => l.boundingBox.top >= bottomThreshold).toList();
        // Preferir una fracción (58/102) sobre un número suelto del texto
        // de sabor ("#25") cuando ambos aparecen en el pie.
        cardNumber = _findBestCardNumber(bottomLines.reversed);
        // Si la fracción vino sola, buscar el código de set en el pie.
        if (cardNumber != null &&
            cardNumber.kind == CardNumberKind.fraction &&
            cardNumber.setCode == null) {
          final setCode = _findSetCode(bottomLines);
          if (setCode != null) {
            cardNumber = cardNumber.withSetCode(setCode);
          }
        }
      }

      // Si no se encontró en la zona inferior, buscar en todas las líneas.
      cardNumber ??= _findBestCardNumber(allLines.reversed);

      // Si aún no se encontró, probar en todo el texto concatenado.
      cardNumber ??= _extractCardNumber(rawText);

      final String? collectionNumber = cardNumber?.display;

      // ── 3. Extracción de Nombre de la Carta Pokémon ────────────────────
      // En cartas Pokémon, el nombre SIEMPRE está en el encabezado (primer 32% superior)
      // con la tipografía de mayor altura (boundingBox.height) y a la izquierda del HP/PS.
      String? cardTitle;

      List<TextLine> topLines;
      if (hasValidCoordinates) {
        final topThreshold = minY + (totalHeight * 0.32);
        topLines = allLines.where((l) => l.boundingBox.top <= topThreshold).toList();
        // Priorizar las líneas de mayor tamaño de fuente dentro del encabezado
        // para elegir el nombre del Pokémon por encima del subtítulo "Evoluciona de..." o "FASE 1"
        topLines.sort((a, b) => b.boundingBox.height.compareTo(a.boundingBox.height));
      } else {
        topLines = allLines.take(4).toList();
      }

      var skipEvolutionName = false;
      for (final line in topLines) {
        final text = line.text.trim();
        if (RegExp(
          r'(evoluciona\s+de|evolves\s+from|から進化|에서\s*진화|進化自|进化自)',
          caseSensitive: false,
        ).hasMatch(text)) {
          skipEvolutionName = true;
          continue;
        }
        if (skipEvolutionName) {
          skipEvolutionName = false;
          continue;
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

      // Fallback acotado al 38% superior (evitando la zona central donde están los ataques y habilidades)
      if (cardTitle == null) {
        skipEvolutionName = false;
        for (final line in allLines) {
          if (hasValidCoordinates) {
            if (line.boundingBox.top > (minY + totalHeight * 0.38)) {
              continue;
            }
          }
          final text = line.text.trim();
          if (RegExp(
            r'(evoluciona\s+de|evolves\s+from|から進化|에서\s*진화|進化自|进化自)',
            caseSensitive: false,
          ).hasMatch(text)) {
            skipEvolutionName = true;
            continue;
          }
          if (skipEvolutionName) {
            skipEvolutionName = false;
            continue;
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

      // Aplicar corrección difusa (Levenshtein) contra las 1.025 especies oficiales de Pokémon
      if (cardTitle != null) {
        cardTitle = LocalCatalogService.instance.repairOcrPokemonName(cardTitle);
      }

      // ── 4. Detección de idioma según caracteres del título o texto ────
      CardLanguage lang = targetLanguage;
      final setCodeJa = cardNumber?.setCode;
      final isJaContext =
          RegExp(r'(?:s\d+[a-z]?|sv\d+[a-z]?|[\u3040-\u30FF])',
                  caseSensitive: false)
              .hasMatch(rawText) ||
          (setCodeJa != null &&
              RegExp(r'^(s\d+|sv\d+|sm\d+)',
                      caseSensitive: false)
                  .hasMatch(setCodeJa)) ||
          (collectionNumber != null &&
              collectionNumber.toLowerCase().contains('s8a'));

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
          // Sin evidencia suficiente, no fijar un idioma erróneo.
          lang = CardLanguage.auto;
        }
      }

      return OcrResult(
        cardNumber: cardNumber,
        pokemonName: cardTitle,
        detectedLanguage: lang,
        rawText: rawText,
      );
    } finally {
      // El recognizer se reutiliza y se cierra en OcrService.dispose().
    }
  }

  /// Recupera una fracción cuyo OCR perdió la barra: "oos1so" -> "005/150".
  CardNumber? _parseCompressedFraction(String line) {
    final match = RegExp(r'[0-9OoSsIlBbZzGgDdQqAa]{5,7}').firstMatch(line);
    if (match == null) return null;
    final repaired = match.group(0)!
        .replaceAll(RegExp(r'[OoDdQq]'), '0')
        .replaceAll(RegExp(r'[Il]'), '1')
        .replaceAll(RegExp(r'[Ss]'), '5')
        .replaceAll(RegExp(r'[Bb]'), '8')
        .replaceAll(RegExp(r'[Zz]'), '2')
        .replaceAll(RegExp(r'[Gg]'), '6')
        .replaceAll(RegExp(r'[Aa]'), '4');
    if (!RegExp(r'^\d{5,7}$').hasMatch(repaired)) return null;
    return CardNumber(
      kind: CardNumberKind.fraction,
      number: repaired.substring(0, repaired.length - 3),
      total: repaired.substring(repaired.length - 3),
    );
  }

  /// Fallback: recorta la franja inferior de la foto y busca allí el número.
  /// Devuelve también el texto reconocido para poder resolver el set.
  Future<(CardNumber?, String)> _extractNumberFromStrip(File imageFile) async {
    File? temp;
    try {
      final bytes = await imageFile.readAsBytes();
      var decoded = img.decodeImage(bytes);
      if (decoded == null) return (null, '');

      decoded = img.bakeOrientation(decoded);
      final startY = (decoded.height * 0.78)
          .round()
          .clamp(0, decoded.height - 1)
          .toInt();

      var crop = img.copyCrop(
        decoded,
        x: 0,
        y: startY,
        width: decoded.width,
        height: decoded.height - startY,
      );
      if (crop.width < 2000) {
        crop = img.copyResize(
          crop,
          width: 2000,
          interpolation: img.Interpolation.linear,
        );
      }

      final dir = await getTemporaryDirectory();
      temp = File(p.join(
        dir.path,
        'ocr_strip_${DateTime.now().microsecondsSinceEpoch}.jpg',
      ));
      await temp.writeAsBytes(img.encodeJpg(crop, quality: 94), flush: true);

      final recognized = await _recognizer(TextRecognitionScript.latin)
          .processImage(InputImage.fromFile(temp));
      final rawStrip = recognized.text;

      CardNumber? best;
      var bestPriority = -1;
      for (final line in rawStrip.split('\n')) {
        final parsed = _extractCardNumber(line);
        if (parsed == null) continue;
        final priority = _cardNumberPriority(parsed);
        if (priority > bestPriority) {
          best = parsed;
          bestPriority = priority;
          if (priority >= 3 && parsed.setCode != null) break;
        }
      }

      if (best == null) {
        // En tipografía diminuta ML Kit pierde la barra: "005/150" -> "oos1so".
        for (final line in rawStrip.split('\n')) {
          best = _parseCompressedFraction(line);
          if (best != null) break;
        }
      }

      // Pasada adicional sobre la esquina inferior izquierda. En cartas foil
      // el texto del pie se pierde entre reflejos; recortando sólo esa zona y
      // subiendo el contraste el número vuelve a ser legible.
      File? cornerTemp;
      try {
        final cornerY = (decoded.height * 0.88)
            .round()
            .clamp(0, decoded.height - 1)
            .toInt();
        final cornerWidth = (decoded.width * 0.45)
            .round()
            .clamp(60, decoded.width)
            .toInt();
        var corner = img.copyCrop(
          decoded,
          x: 0,
          y: cornerY,
          width: cornerWidth,
          height: decoded.height - cornerY,
        );
        corner = img.contrast(img.grayscale(corner), contrast: 180);
        corner = img.copyResize(
          corner,
          width: 2000,
          interpolation: img.Interpolation.linear,
        );
        cornerTemp = File(p.join(
          dir.path,
          'ocr_corner_${DateTime.now().microsecondsSinceEpoch}.png',
        ));
        await cornerTemp.writeAsBytes(img.encodePng(corner), flush: true);

        final cornerText = await _recognizer(TextRecognitionScript.latin)
            .processImage(InputImage.fromFile(cornerTemp));
        CardNumber? cornerNumber;
        for (final line in cornerText.text.split('\n')) {
          final parsed = _extractCardNumber(line);
          if (parsed != null && _cardNumberPriority(parsed) >= 3) {
            cornerNumber = parsed;
            break;
          }
          cornerNumber ??= _parseCompressedFraction(line);
        }
        if (cornerNumber != null) best = cornerNumber;
      } catch (_) {
      } finally {
        if (cornerTemp != null) {
          try {
            await cornerTemp.delete();
          } catch (_) {}
        }
      }

      if (best != null &&
          best.kind == CardNumberKind.fraction &&
          best.setCode == null) {
        final setCode = _setCodeFromText(rawStrip);
        if (setCode != null) best = best.withSetCode(setCode);
      }
      return (best, rawStrip);
    } catch (_) {
      return (null, '');
    } finally {
      if (temp != null) {
        try {
          await temp.delete();
        } catch (_) {}
      }
    }
  }

  /// Parsea el número con el parser único. No repara ni reordena aquí.
  CardNumber? _extractCardNumber(String text) {
    if (text.trim().isEmpty) return null;
    return CardNumber.parse(text);
  }

  /// Elige el mejor número de una lista de líneas. Las fracciones
  /// (58/102) mandan sobre números sueltos del texto de sabor (#25).
  CardNumber? _findBestCardNumber(Iterable<TextLine> lines) {
    CardNumber? best;
    var bestPriority = -1;
    for (final line in lines) {
      final found = _extractCardNumber(line.text);
      if (found == null) continue;
      final priority = _cardNumberPriority(found);
      if (priority > bestPriority) {
        best = found;
        bestPriority = priority;
        if (bestPriority >= 3) break;
      }
    }
    return best;
  }

  int _cardNumberPriority(CardNumber number) {
    switch (number.kind) {
      case CardNumberKind.fraction:
      case CardNumberKind.prefixedFraction:
      case CardNumberKind.setFraction:
        return 3;
      case CardNumberKind.promo:
      case CardNumberKind.setDash:
        return 2;
      case CardNumberKind.prefixedNumber:
        return 1;
    }
  }

  /// Busca un código de set junto al número cuando la fracción vino sola.
  String? _findSetCode(List<TextLine> lines) {
    String? fallback;
    for (final line in lines) {
      final found = _setCodeFromText(line.text, fallback: fallback);
      if (found == null) continue;
      if (RegExp(r'[0-9]').hasMatch(found) ||
          RegExp(r'^[a-z]{1,4}-[a-z]{1,4}$').hasMatch(found.toLowerCase())) {
        return found;
      }
      fallback ??= found;
    }
    return null;
  }

  /// Extrae un código de set plausible de un texto. Prioriza los que llevan
  /// dígitos o guion (sv11b, s8a, sv-p) frente a palabras sueltas.
  String? _setCodeFromText(String text, {String? fallback}) {
    final pattern = RegExp(
      r'\b([a-z]{1,4}-[a-z]{1,4}|s\d+[a-z]?|sv\d+[a-z]?|sm\d+[a-z]?|xy\d+[a-z]?|bw\d+[a-z]?|dp\d+[a-z]?|hgss\d*|cp\d+|rc\d+|[A-Z]{2,5})\b',
      caseSensitive: false,
    );

    final clean = text.replaceAll(RegExp(r'[\[\]]'), ' ').trim();
    for (final match in pattern.allMatches(clean)) {
      final candidate = match.group(1)!;
      final upper = candidate.toUpperCase();
      if (CardNumber.isStopWord(upper)) continue;
      final isLowerHyphen =
          RegExp(r'^[a-z]{1,4}-[a-z]{1,4}$').hasMatch(candidate);
      if (!RegExp(r'[0-9]').hasMatch(candidate) && !isLowerHyphen) {
        continue;
      }
      return candidate;
    }
    return fallback;
  }

  /// Limpia y valida si una línea de texto corresponde al título de una carta Pokémon.
  String? _cleanAndValidateTitle(
    String line,
    String? collectionNumber, {
    double? lineLeftRatio,
  }) {
    // Si la línea está en el cuadrante derecho superior (> 58% del ancho),
    // es la zona reservada para HP/PS y tipo elemental. Nunca es el título.
    if (lineLeftRatio != null && lineLeftRatio > 0.58) {
      return null;
    }

    var trimmed = line.trim();
    if (trimmed.length < 2) return null;
    if (collectionNumber != null && collectionNumber.isNotEmpty) {
      // Si el OCR mezcló nombre y número en la misma línea, quitar el número
      // en vez de descartar el nombre.
      trimmed = trimmed.replaceAll(collectionNumber, '').trim();
      if (trimmed.length < 2) return null;
    }

    // Descartar subtítulos de evolución ("Evoluciona de Charmander", "Evolves from Pikachu", "…から進化")
    // y líneas de datos de Pokédex ("N.º 006", "Altura: 1,7 m", "Peso: 90,5 kg", "HT", "WT")
    if (RegExp(
      r'(evoluciona\s+de|evolves\s+from|put\s+on\s+the|coloca\s+sobre|から進化|에서\s*진화|進化自|进化自|\b(altura|peso|height|weight|length)\b)',
      caseSensitive: false,
    ).hasMatch(trimmed)) {
      return null;
    }

    // Número de Pokédex: "N.º 006", "No. 025".
    if (RegExp(r'^(?:n\.?\s*[ºo°]\.?|no\.?)\s*\d{1,4}$', caseSensitive: false)
        .hasMatch(trimmed)) {
      return null;
    }

    // Artista / ilustrador.
    if (RegExp(
      r'^(?:illus\.?|illust\.?|ilustración|illustration|イラスト|일러스트)\b',
      caseSensitive: false,
    ).hasMatch(trimmed)) {
      return null;
    }

    // Descartar si es estrictamente numérico o sólo contiene dígitos y símbolos de puntuación
    if (RegExp(r'^\d+$').hasMatch(trimmed)) return null;
    if (RegExp(r'^[\d\s\.\,\:\;\-\/]+$').hasMatch(trimmed)) return null;

    // Quitar indicadores de PS / HP y números pegados, sin descartar el nombre.
    // Ej: "Charizard ex 330 HP" -> "Charizard ex".
    trimmed = trimmed
        .replaceAll(
          RegExp(r'(?:HP|PS)\s*[:/]?\s*\d+|\d+\s*[:/]?\s*(?:HP|PS)',
              caseSensitive: false),
          '',
        )
        .replaceAll(RegExp(r'\b(HP|PS)\b', caseSensitive: false), '')
        .trim();
    if (trimmed.length < 2) return null;

    // Quitar sólo descriptores de etapa al inicio. No tocar "Pokémon Catcher",
    // "Energy Switch" ni "Item Finder".
    trimmed = trimmed
        .replaceAll(
          RegExp(
            r'^(?:pok[eé]mon\s+)?(?:b[aá]sico|g[aá]sico|c[aá]sico|p[aá]sico|fase\s*\d*|stage\s*\d*|basic)\b',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(
          RegExp(r'^(たね|1進化|2進化|기본|1진화|2진화|基础|1阶进化|2阶进化)'),
          '',
        )
        .trim();

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

    // Eliminar enteros sueltos de 2 o 3 dígitos al final del título (ej: HP "210" en "Blaziken V 210")
    // sin romper nombres con dígitos pegados como "Porygon2" ni cartas como "Rotom V"
    trimmed = trimmed.replaceAll(RegExp(r'\s+\d{2,3}$'), '').trim();

    if (trimmed.length < 2) return null;

    // Si después de limpiar sólo quedó un número (ej: "120"), descartar
    if (RegExp(r'^\d+$').hasMatch(trimmed)) return null;

    final upper = trimmed.toUpperCase();
    // Sólo palabras exactas: no rechazar "Pokémon Catcher", "Energy Switch", etc.
    if (_ignoredWords.contains(upper)) {
      return null;
    }
    if (RegExp(
      r'^(?:pok[eé]mon\s+)?(?:b[aá]sico|basic|stage\s*\d*|fase\s*\d*)$',
      caseSensitive: false,
    ).hasMatch(trimmed)) {
      return null;
    }

    // Filtrar líneas largas de descripción o textos de ataques (> 4 palabras).
    // En CJK no hay espacios: no aplicar este límite a kana/hangul/han.
    final hasCjk = RegExp(r'[\u3040-\u30FF\uAC00-\uD7AF\u4E00-\u9FFF]')
        .hasMatch(trimmed);
    if (!hasCjk && trimmed.split(RegExp(r'\s+')).length > 4) {
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
