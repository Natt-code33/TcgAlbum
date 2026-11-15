// ============================================================
// services/image_matching_service.dart
// Servicio de reconocimiento visual y comparación de imágenes
// para cartas TCG (Pokémon, Magic, YGO, Digimon, One Piece, etc.).
//
// Compara la fotografía capturada por la cámara con las imágenes
// de las cartas candidatas mediante:
// 1. Recorte centrado en la zona de ilustración / arte de la carta.
// 2. Cálculo de Perceptual Difference Hash (dHash).
// 3. Comparación de cuadrantes cromáticos y distribución de color.
// 4. Puntuación de similitud porcentual (0% - 100%).
// ============================================================

import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import '../models/pokemon_card.dart';

/// Resultado del emparejamiento visual de una carta candidata.
class VisualMatchResult {
  final PokemonCard card;

  /// Puntuación de similitud de 0.0 (totalmente diferente) a 1.0 (idéntica).
  final double similarity;

  const VisualMatchResult({
    required this.card,
    required this.similarity,
  });

  /// Porcentaje de coincidencia formateado (ej: 94).
  int get matchPercentage => (similarity * 100).clamp(0, 100).round();
}

typedef _VisualSignature = ({List<bool> hash, List<int> colorProfile});

class ImageMatchingService {
  static const Map<String, String> _headers = {
    'Accept': 'image/*, application/json',
    'User-Agent': 'TcgAlbum/1.0 (Android; Flutter)',
  };

  final http.Client _client;

  ImageMatchingService({http.Client? client}) : _client = client ?? http.Client();

  /// Decodifica bytes de imagen y calcula su firma visual (dHash + perfil cromático)
  /// de forma estática para poder ejecutarse dentro de un Isolate secundario.
  static _VisualSignature? _decodeAndComputeSignature(Uint8List imageBytes) {
    try {
      final image = img.decodeImage(imageBytes);
      if (image == null) return null;

      // 1. Recortar la región del arte / ilustración de la carta:
      // Verticalmente: entre el 15% y el 60% de la altura (donde está el dibujo)
      // Horizontalmente: entre el 10% y el 90% del ancho
      final artWidth = (image.width * 0.80).round().clamp(10, image.width);
      final artHeight = (image.height * 0.45).round().clamp(10, image.height);
      final startX = (image.width * 0.10).round().clamp(0, image.width - artWidth);
      final startY = (image.height * 0.15).round().clamp(0, image.height - artHeight);

      final artCrop = img.copyCrop(
        image,
        x: startX,
        y: startY,
        width: artWidth,
        height: artHeight,
      );

      // 2. Normalizar a 17x16 píxeles para dHash
      final small = img.copyResize(artCrop, width: 17, height: 16);
      final gray = img.grayscale(small);

      // 3. dHash: comparar cada pixel horizontal con su vecino adyacente
      final hash = <bool>[];
      for (int y = 0; y < 16; y++) {
        for (int x = 0; x < 16; x++) {
          final p1 = gray.getPixel(x, y).r;
          final p2 = gray.getPixel(x + 1, y).r;
          hash.add(p1 > p2);
        }
      }

      // 4. Perfil cromático en 4 cuadrantes (Top-Left, Top-Right, Bottom-Left, Bottom-Right)
      // Normalizamos el recorte de arte a 4x4 y extraemos R, G, B medios
      final colorSample = img.copyResize(artCrop, width: 4, height: 4);
      final colorProfile = <int>[];
      for (final pixel in colorSample) {
        colorProfile.add(pixel.r.toInt());
        colorProfile.add(pixel.g.toInt());
        colorProfile.add(pixel.b.toInt());
      }

      return (hash: hash, colorProfile: colorProfile);
    } catch (_) {
      return null;
    }
  }

  /// Compara dos firmas visuales y devuelve una puntuación entre 0.0 y 1.0.
  static double _compareSignatures(
    _VisualSignature sig1,
    _VisualSignature sig2,
  ) {
    // 1. Similitud de estructura por gradientes (Hamming distance sobre 256 bits)
    int diffBits = 0;
    final totalBits = min(sig1.hash.length, sig2.hash.length);
    if (totalBits == 0) return 0.0;

    for (int i = 0; i < totalBits; i++) {
      if (sig1.hash[i] != sig2.hash[i]) diffBits++;
    }
    final hashSimilarity = 1.0 - (diffBits / totalBits);

    // 2. Similitud de color por distancia euclidiana en los cuadrantes de color
    double colorDistSum = 0;
    final totalColorChannels = min(sig1.colorProfile.length, sig2.colorProfile.length);
    for (int i = 0; i < totalColorChannels; i++) {
      final diff = sig1.colorProfile[i] - sig2.colorProfile[i];
      colorDistSum += diff * diff;
    }
    final avgColorDist = sqrt(colorDistSum / max(1, totalColorChannels));
    final colorSimilarity = (1.0 - (avgColorDist / 255.0)).clamp(0.0, 1.0);

    // 3. Ponderación final: 55% estructura del dibujo + 45% tonalidad/color
    return (hashSimilarity * 0.55) + (colorSimilarity * 0.45);
  }

  /// Ordena una lista de cartas candidatas comparando visualmente su arte
  /// con la foto capturada por el usuario en un Isolate en segundo plano.
  Future<List<VisualMatchResult>> rankCardsByVisualSimilarity({
    required File userPhotoFile,
    required List<PokemonCard> candidateCards,
    int maxCandidatesToCompare = 20,
  }) async {
    if (!userPhotoFile.existsSync() || candidateCards.isEmpty) {
      return candidateCards.map((c) => VisualMatchResult(card: c, similarity: 0.0)).toList();
    }

    try {
      // 1. Leer bytes de la foto del usuario y calcular su firma en Isolate secundario
      final photoBytes = await userPhotoFile.readAsBytes();
      final userSig = await Isolate.run(() => _decodeAndComputeSignature(photoBytes));
      if (userSig == null) {
        return candidateCards.map((c) => VisualMatchResult(card: c, similarity: 0.0)).toList();
      }

      // 2. Descargar bytes de las cartas candidatas en paralelo
      final candidates = candidateCards.take(maxCandidatesToCompare).toList();
      final remaining = candidateCards.skip(maxCandidatesToCompare).toList();

      final candidateBytesList = await Future.wait(
        candidates.map((card) async {
          try {
            if (PokemonCard.isValidNetworkUrl(card.imageUrl)) {
              final res = await _client
                  .get(Uri.parse(card.imageUrl), headers: _headers)
                  .timeout(const Duration(seconds: 4));
              if (res.statusCode == 200) {
                return res.bodyBytes;
              }
            } else if (card.imageUrl.isNotEmpty && File(card.imageUrl).existsSync()) {
              return await File(card.imageUrl).readAsBytes();
            }
          } catch (_) {}
          return null;
        }),
      );

      // 3. Procesar todas las imágenes candidatas y calcular puntuaciones en un único Isolate
      final scores = await Isolate.run(() {
        final results = <double>[];
        for (final bytes in candidateBytesList) {
          if (bytes == null) {
            results.add(0.0);
            continue;
          }
          final refSig = _decodeAndComputeSignature(bytes);
          if (refSig != null) {
            results.add(_compareSignatures(userSig, refSig));
          } else {
            results.add(0.0);
          }
        }
        return results;
      });

      final ranked = <VisualMatchResult>[];
      for (int i = 0; i < candidates.length; i++) {
        ranked.add(VisualMatchResult(card: candidates[i], similarity: scores[i]));
      }

      // 4. Ordenar de mayor a menor coincidencia visual
      ranked.sort((a, b) => b.similarity.compareTo(a.similarity));

      // Agregar las cartas restantes que no se alcanzaron a comparar al final
      final remainingResults = remaining
          .map((c) => VisualMatchResult(card: c, similarity: 0.0))
          .toList();

      return [...ranked, ...remainingResults];
    } catch (e) {
      developer.log('Error en ranking visual: $e', name: 'ImageMatchingService');
      return candidateCards.map((c) => VisualMatchResult(card: c, similarity: 0.0)).toList();
    }
  }
}
