// Firma visual de una carta. Sin dependencias de Flutter: el indexador de CI
// y la app usan exactamente el mismo código, así los hashes son comparables.

import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

typedef VisualSignature = ({List<bool> hash, List<int> colorProfile});

/// Recorte del arte, dHash de 256 bits y perfil cromático 4x4.
VisualSignature? computeVisualSignature(Uint8List imageBytes) {
  try {
    final image = img.decodeImage(imageBytes);
    if (image == null) return null;

    final artWidth = (image.width * 0.80).round().clamp(10, image.width);
    final artHeight = (image.height * 0.45).round().clamp(10, image.height);
    final startX =
        (image.width * 0.10).round().clamp(0, image.width - artWidth);
    final startY =
        (image.height * 0.15).round().clamp(0, image.height - artHeight);

    final artCrop = img.copyCrop(
      image,
      x: startX,
      y: startY,
      width: artWidth,
      height: artHeight,
    );

    final small = img.copyResize(artCrop, width: 17, height: 16);
    final gray = img.grayscale(small);

    final hash = <bool>[];
    for (var y = 0; y < 16; y++) {
      for (var x = 0; x < 16; x++) {
        final p1 = gray.getPixel(x, y).r;
        final p2 = gray.getPixel(x + 1, y).r;
        hash.add(p1 > p2);
      }
    }

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

/// Distancia Hamming entre dos hashes (0 = idénticos).
int visualHashDistance(List<bool> a, List<bool> b) {
  var diff = 0;
  final total = min(a.length, b.length);
  for (var i = 0; i < total; i++) {
    if (a[i] != b[i]) diff++;
  }
  return diff;
}

/// Similitud 0..1 = 75% estructura + 25% color.
double compareVisualSignatures(VisualSignature a, VisualSignature b) {
  final totalBits = min(a.hash.length, b.hash.length);
  if (totalBits == 0) return 0.0;
  final hashSimilarity = 1.0 - (visualHashDistance(a.hash, b.hash) / totalBits);

  double colorDistSum = 0;
  final totalChannels = min(a.colorProfile.length, b.colorProfile.length);
  for (var i = 0; i < totalChannels; i++) {
    final diff = a.colorProfile[i] - b.colorProfile[i];
    colorDistSum += diff * diff;
  }
  final avgColorDist = sqrt(colorDistSum / max(1, totalChannels));
  final colorSimilarity = (1.0 - (avgColorDist / 255.0)).clamp(0.0, 1.0);

  return (hashSimilarity * 0.75) + (colorSimilarity * 0.25);
}
