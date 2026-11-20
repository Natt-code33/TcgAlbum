// ============================================================
// services/perspective_crop.dart
// Corrección de perspectiva de cuatro puntos.
//
// Mapea el cuadrilátero marcado por el usuario (TL, TR, BR, BL) a
// un rectángulo mediante una homografía real (transformada
// proyectiva), no un simple recorte rectangular. Se ejecuta en un
// isolate mediante [compute].
// ============================================================

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Petición enviable a un isolate. Los puntos van planos para evitar
/// objetos no enviables: [x0,y0, x1,y1, x2,y2, x3,y3] normalizados 0..1.
class PerspectiveCropRequest {
  final String path;
  final List<double> points;
  final int quarterTurns;

  const PerspectiveCropRequest({
    required this.path,
    required this.points,
    required this.quarterTurns,
  });
}

/// Aplica rotación de 90° y homografía, y devuelve JPEG.
Uint8List cropPerspectiveJpeg(PerspectiveCropRequest request) {
  final raw = File(request.path).readAsBytesSync();
  var image = img.decodeImage(raw);
  if (image == null) {
    throw const FormatException('Formato de imagen no soportado');
  }
  image = img.bakeOrientation(image);

  if (request.quarterTurns != 0) {
    image = img.copyRotate(image, angle: request.quarterTurns * 90);
  }

  if (request.points.length != 8) {
    throw const FormatException('Se esperaban cuatro esquinas');
  }

  final w = image.width.toDouble();
  final h = image.height.toDouble();
  final p = <_P>[
    for (var i = 0; i < 4; i++)
      _P(
        request.points[i * 2].clamp(0.0, 1.0) * w,
        request.points[i * 2 + 1].clamp(0.0, 1.0) * h,
      ),
  ];

  final top = _distance(p[0], p[1]);
  final bottom = _distance(p[3], p[2]);
  final left = _distance(p[0], p[3]);
  final right = _distance(p[1], p[2]);
  final avgWidth = (top + bottom) / 2;
  final avgHeight = (left + right) / 2;

  if (avgWidth < 24 || avgHeight < 24) {
    throw const FormatException('El recorte es demasiado pequeño');
  }

  var outWidth = avgWidth.round().clamp(320, 1600);
  final scale = outWidth / avgWidth;
  var outHeight = (avgHeight * scale).round().clamp(320, 2600);

  // Nunca ampliar más de lo razonable: si el original es pequeño,
  // mantener su resolución en vez de inventar píxeles.
  final maxOutWidth = math.min(1600, image.width * 2);
  if (outWidth > maxOutWidth) {
    final ratio = maxOutWidth / outWidth;
    outWidth = maxOutWidth;
    outHeight = math.max(320, (outHeight * ratio).round());
  }

  // Homografía unidad -> cuadrilátero de origen.
  final h0 = _homography(p);

  final output = img.Image(width: outWidth, height: outHeight);
  final maxX = (image.width - 1).toDouble();
  final maxY = (image.height - 1).toDouble();

  for (var y = 0; y < outHeight; y++) {
    final v = outHeight <= 1 ? 0.0 : y / (outHeight - 1);
    for (var x = 0; x < outWidth; x++) {
      final u = outWidth <= 1 ? 0.0 : x / (outWidth - 1);
      final denom = h0.g * u + h0.h * v + 1.0;
      if (denom.abs() < 1e-8) continue;

      final sx = ((h0.a * u + h0.b * v + h0.c) / denom)
          .clamp(0.0, maxX)
          .toDouble();
      final sy = ((h0.d * u + h0.e * v + h0.f) / denom)
          .clamp(0.0, maxY)
          .toDouble();

      output.setPixel(
        x,
        y,
        image.getPixelInterpolate(
          sx,
          sy,
          interpolation: img.Interpolation.linear,
        ),
      );
    }
  }

  return Uint8List.fromList(img.encodeJpg(output, quality: 93));
}

double _distance(_P a, _P b) {
  final dx = a.dx - b.dx;
  final dy = a.dy - b.dy;
  return math.sqrt(dx * dx + dy * dy);
}

class _Homography {
  final double a, b, c, d, e, f, g, h;

  const _Homography(this.a, this.b, this.c, this.d, this.e, this.f, this.g,
      this.h);
}

/// Homografía que mapea el cuadrado unitario a los cuatro puntos
/// [TL, TR, BR, BL] (en ese orden).
_Homography _homography(List<_P> p) {
  final x0 = p[0].dx, y0 = p[0].dy;
  final x1 = p[1].dx, y1 = p[1].dy;
  final x2 = p[2].dx, y2 = p[2].dy;
  final x3 = p[3].dx, y3 = p[3].dy;

  final dx1 = x1 - x2;
  final dx2 = x3 - x2;
  final dx3 = x0 - x1 + x2 - x3;
  final dy1 = y1 - y2;
  final dy2 = y3 - y2;
  final dy3 = y0 - y1 + y2 - y3;

  if (dx3.abs() < 1e-8 && dy3.abs() < 1e-8) {
    return _Homography(
      x1 - x0,
      x3 - x0,
      x0,
      y1 - y0,
      y3 - y0,
      y0,
      0,
      0,
    );
  }

  final det = dx1 * dy2 - dx2 * dy1;
  if (det.abs() < 1e-8) {
    return _Homography(
      x1 - x0,
      x3 - x0,
      x0,
      y1 - y0,
      y3 - y0,
      y0,
      0,
      0,
    );
  }

  final g = (dx3 * dy2 - dx2 * dy3) / det;
  final h = (dx1 * dy3 - dx3 * dy1) / det;

  return _Homography(
    x1 - x0 + g * x1,
    x3 - x0 + h * x3,
    x0,
    y1 - y0 + g * y1,
    y3 - y0 + h * y3,
    y0,
    g,
    h,
  );
}

/// Punto 2D mínimo para no depender de Flutter en los tests puros.
class _P {
  final double dx;
  final double dy;

  const _P(this.dx, this.dy);
}
