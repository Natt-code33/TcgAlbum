// ============================================================
// services/image_matching_service.dart
// Servicio de reconocimiento visual y comparación de imágenes
// para cartas Pokémon TCG.
//
// Compara la fotografía capturada por la cámara con las imágenes
// de las cartas candidatas mediante:
// 1. Recorte centrado en la zona de ilustración / arte de la carta.
// 2. Cálculo de Perceptual Difference Hash (dHash).
// 3. Comparación de cuadrantes cromáticos y distribución de color.
// 4. Puntuación de similitud porcentual (0% - 100%).
// ============================================================

import 'dart:io';
import 'dart:typed_data';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import '../models/pokemon_card.dart';
import 'visual_signature.dart';

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

class ImageMatchingService {
  static const Map<String, String> _headers = {
    'Accept': 'image/*, application/json',
    'User-Agent': 'TcgAlbum/1.0 (Android; Flutter)',
  };

  final http.Client _client;
  final bool _ownsClient;

  ImageMatchingService({http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }

  /// Misma firma que usa el indexador de CI.
  static VisualSignature? computeSignature(Uint8List imageBytes) =>
      computeVisualSignature(imageBytes);

  static int hashDistance(List<bool> a, List<bool> b) =>
      visualHashDistance(a, b);

  static double _compareSignatures(VisualSignature a, VisualSignature b) =>
      compareVisualSignatures(a, b);

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
      final userSig = computeVisualSignature(photoBytes);
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
                  .get(Uri.parse(card.thumbnailImageUrl), headers: _headers)
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
      final scores = <double>[];
      for (final bytes in candidateBytesList) {
        if (bytes == null) {
          scores.add(0.0);
          continue;
        }
        final refSig = computeVisualSignature(bytes);
        if (refSig != null) {
          scores.add(_compareSignatures(userSig, refSig));
        } else {
          scores.add(0.0);
        }
      }

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
