// ============================================================
// views/card_crop_view.dart
// Recorte manual de la carta antes del OCR.
//
// Permite arrastrar las cuatro esquinas para corregir la
// perspectiva (homografía real), mover la selección y rotarla en
// pasos de 90°. El resultado se escribe como JPEG temporal y se
// devuelve al escáner para el reconocimiento.
// ============================================================

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../services/perspective_crop.dart';
import '../theme/app_theme.dart';

/// Decodifica, aplica orientación EXIF y genera una vista previa JPEG.
/// Debe ser de nivel superior para poder usarse con [compute].
(Uint8List, int, int) _decodePreviewWorker(Uint8List bytes) {
  var image = img.decodeImage(bytes);
  if (image == null) {
    throw const FormatException('Formato de imagen no soportado');
  }
  image = img.bakeOrientation(image);

  var preview = image;
  if (preview.width > 1400) {
    preview = img.copyResize(
      preview,
      width: 1400,
      interpolation: img.Interpolation.linear,
    );
  }

  final encoded = Uint8List.fromList(img.encodeJpg(preview, quality: 88));
  return (encoded, image.width, image.height);
}

class CardCropView extends StatefulWidget {
  final File imageFile;

  const CardCropView({super.key, required this.imageFile});

  @override
  State<CardCropView> createState() => _CardCropViewState();
}

class _CardCropViewState extends State<CardCropView> {
  Uint8List? _previewBytes;
  int _sourceWidth = 0;
  int _sourceHeight = 0;
  bool _loading = true;
  bool _applying = false;
  String? _error;

  int _quarterTurns = 0;

  /// Esquinas normalizadas (0..1) sobre la imagen ya rotada:
  /// [superior izquierda, superior derecha, inferior derecha, inferior izquierda].
  List<Offset> _quad = _defaultQuad();

  int? _activeCorner; // 0..3 esquina, 4 interior
  Offset _dragStart = Offset.zero;
  List<Offset> _startQuad = const [];

  Rect _displayRect = Rect.zero;

  static const double _minEdge = 0.06;

  static List<Offset> _defaultQuad() {
    const r = Rect.fromLTRB(0.02, 0.02, 0.98, 0.98);
    return [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft];
  }

  static List<Offset> _quadFromRect(Rect rect) =>
      [rect.topLeft, rect.topRight, rect.bottomRight, rect.bottomLeft];

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    try {
      final bytes = await widget.imageFile.readAsBytes();
      final decoded = await compute(_decodePreviewWorker, bytes);
      if (!mounted) return;

      setState(() {
        _previewBytes = decoded.$1;
        _sourceWidth = decoded.$2;
        _sourceHeight = decoded.$3;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'No se pudo abrir la imagen: $e';
      });
    }
  }

  int get _rotatedWidth =>
      _quarterTurns.isEven ? _sourceWidth : _sourceHeight;

  int get _rotatedHeight =>
      _quarterTurns.isEven ? _sourceHeight : _sourceWidth;

  void _rotate(int delta) {
    if (_loading || _applying) return;
    setState(() {
      _quarterTurns = (_quarterTurns + delta) % 4;
      if (_quarterTurns < 0) _quarterTurns += 4;
      _quad = _defaultQuad();
    });
  }

  void _resetSelection() {
    setState(() {
      _quad = _defaultQuad();
    });
  }

  void _useCardAspect() {
    // Proporción física estándar de una carta Pokémon (63 × 88 mm).
    const cardAspect = 63 / 88;
    final imageAspect = _rotatedWidth / _rotatedHeight;

    double width;
    double height;
    if (imageAspect > cardAspect) {
      height = 0.98;
      width = (height * cardAspect) / imageAspect;
    } else {
      width = 0.98;
      height = (width * imageAspect) / cardAspect;
    }
    width = width.clamp(_minEdge, 1.0);
    height = height.clamp(_minEdge, 1.0);

    setState(() {
      _quad = _quadFromRect(
        Rect.fromCenter(
          center: const Offset(0.5, 0.5),
          width: width,
          height: height,
        ),
      );
    });
  }

  List<Offset> _quadPixels() {
    final w = _displayRect.width;
    final h = _displayRect.height;
    return [
      for (final point in _quad)
        Offset(
          _displayRect.left + point.dx * w,
          _displayRect.top + point.dy * h,
        ),
    ];
  }

  static bool _isInsideQuad(List<Offset> quad, Offset point) {
    var inside = false;
    for (var i = 0, j = quad.length - 1; i < quad.length; j = i++) {
      final a = quad[i];
      final b = quad[j];
      final intersects = ((a.dy > point.dy) != (b.dy > point.dy)) &&
          (point.dx <
              (b.dx - a.dx) * (point.dy - a.dy) / (b.dy - a.dy) + a.dx);
      if (intersects) inside = !inside;
    }
    return inside;
  }

  void _onPanStart(DragStartDetails details) {
    if (_loading || _applying || _displayRect.isEmpty) return;
    final pos = details.localPosition;
    final corners = _quadPixels();

    var nearest = -1;
    var bestDistance = 64.0;
    for (var i = 0; i < corners.length; i++) {
      final distance = (corners[i] - pos).distance;
      if (distance < bestDistance) {
        bestDistance = distance;
        nearest = i;
      }
    }

    _dragStart = pos;
    _startQuad = List<Offset>.of(_quad);

    if (nearest != -1) {
      _activeCorner = nearest;
    } else if (_isInsideQuad(corners, pos)) {
      _activeCorner = 4;
    } else {
      _activeCorner = null;
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    final corner = _activeCorner;
    if (corner == null || _displayRect.isEmpty || _startQuad.length != 4) {
      return;
    }

    final pos = details.localPosition;
    final w = _displayRect.width;
    final h = _displayRect.height;

    if (corner == 4) {
      final dx = (pos.dx - _dragStart.dx) / w;
      final dy = (pos.dy - _dragStart.dy) / h;

      final minX = _startQuad.map((p) => p.dx).reduce(math.min);
      final maxX = _startQuad.map((p) => p.dx).reduce(math.max);
      final minY = _startQuad.map((p) => p.dy).reduce(math.min);
      final maxY = _startQuad.map((p) => p.dy).reduce(math.max);

      final clampedDx = dx.clamp(-minX, 1.0 - maxX).toDouble();
      final clampedDy = dy.clamp(-minY, 1.0 - maxY).toDouble();

      setState(() {
        _quad = [
          for (final point in _startQuad)
            Offset(point.dx + clampedDx, point.dy + clampedDy),
        ];
      });
      return;
    }

    final nx = ((pos.dx - _displayRect.left) / w).clamp(0.0, 1.0).toDouble();
    final ny = ((pos.dy - _displayRect.top) / h).clamp(0.0, 1.0).toDouble();

    final q = List<Offset>.of(_quad);
    switch (corner) {
      case 0: // superior izquierda
        q[0] = Offset(
          nx.clamp(0.0, q[1].dx - _minEdge).toDouble(),
          ny.clamp(0.0, q[3].dy - _minEdge).toDouble(),
        );
        break;
      case 1: // superior derecha
        q[1] = Offset(
          nx.clamp(q[0].dx + _minEdge, 1.0).toDouble(),
          ny.clamp(0.0, q[2].dy - _minEdge).toDouble(),
        );
        break;
      case 2: // inferior derecha
        q[2] = Offset(
          nx.clamp(q[3].dx + _minEdge, 1.0).toDouble(),
          ny.clamp(q[1].dy + _minEdge, 1.0).toDouble(),
        );
        break;
      case 3: // inferior izquierda
        q[3] = Offset(
          nx.clamp(0.0, q[2].dx - _minEdge).toDouble(),
          ny.clamp(q[0].dy + _minEdge, 1.0).toDouble(),
        );
        break;
    }

    if (_quadArea(q) < 0.01) return;

    setState(() {
      _quad = q;
    });
  }

  static double _quadArea(List<Offset> q) {
    var area = 0.0;
    for (var i = 0; i < q.length; i++) {
      final a = q[i];
      final b = q[(i + 1) % q.length];
      area += a.dx * b.dy - b.dx * a.dy;
    }
    return (area / 2).abs();
  }

  void _onPanEnd() {
    _activeCorner = null;
    _startQuad = const [];
  }

  Future<void> _applyCrop() async {
    if (_loading || _applying) return;

    setState(() => _applying = true);
    try {
      final request = PerspectiveCropRequest(
        path: widget.imageFile.path,
        points: [
          for (final point in _quad) ...[point.dx, point.dy],
        ],
        quarterTurns: _quarterTurns,
      );

      final croppedBytes =
          await compute(cropPerspectiveJpeg, request);

      final dir = await getTemporaryDirectory();
      final outFile = File(p.join(
        dir.path,
        'card_crop_${DateTime.now().microsecondsSinceEpoch}.jpg',
      ));
      await outFile.writeAsBytes(croppedBytes, flush: true);

      if (!mounted) return;
      Navigator.of(context).pop(outFile);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _applying = false;
        _error = 'No se pudo recortar la imagen: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050B16),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Recortar carta',
          style: GoogleFonts.outfit(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(
                'Ajusta las 4 esquinas a la carta. Si está inclinada, mueve '
                'cada esquina: se corrige la perspectiva antes del OCR.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: Colors.white60,
                  fontSize: 12.5,
                  height: 1.35,
                ),
              ),
            ),
            Expanded(child: _buildEditor()),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    color: AppTheme.loss,
                    fontSize: 12.5,
                  ),
                ),
              ),
            _buildToolbar(),
            _buildActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildEditor() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.cyanAccent),
      );
    }

    final preview = _previewBytes;
    if (preview == null) {
      return Center(
        child: Text(
          'Vista previa no disponible',
          style: GoogleFonts.inter(color: Colors.white54),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final available = Size(
          constraints.maxWidth - 24,
          constraints.maxHeight - 24,
        );
        final imageAspect = _rotatedWidth / _rotatedHeight;
        final containerAspect = available.width / available.height;

        double width;
        double height;
        if (imageAspect > containerAspect) {
          width = available.width;
          height = width / imageAspect;
        } else {
          height = available.height;
          width = height * imageAspect;
        }

        _displayRect = Rect.fromCenter(
          center: Offset(constraints.maxWidth / 2, constraints.maxHeight / 2),
          width: width,
          height: height,
        );

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: _onPanStart,
          onPanUpdate: _onPanUpdate,
          onPanEnd: (_) => _onPanEnd(),
          child: Stack(
            children: [
              Positioned.fromRect(
                rect: _displayRect,
                child: RotatedBox(
                  quarterTurns: _quarterTurns,
                  child: Image.memory(
                    preview,
                    fit: BoxFit.fill,
                    gaplessPlayback: true,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
              ),
              Positioned.fill(
                child: CustomPaint(
                  painter: _CropOverlayPainter(
                    quad: _quadPixels(),
                  ),
                ),
              ),
              if (_applying)
                const Positioned.fill(
                  child: ColoredBox(
                    color: Colors.black54,
                    child: Center(
                      child: CircularProgressIndicator(
                        color: AppTheme.cyanAccent,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildToolbar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _CropTool(
            icon: Icons.rotate_left_rounded,
            label: 'Girar',
            onTap: () => _rotate(-1),
          ),
          _CropTool(
            icon: Icons.rotate_right_rounded,
            label: 'Girar',
            onTap: () => _rotate(1),
          ),
          _CropTool(
            icon: Icons.crop_free_rounded,
            label: 'Carta',
            onTap: _useCardAspect,
          ),
          _CropTool(
            icon: Icons.restart_alt_rounded,
            label: 'Reset',
            onTap: _resetSelection,
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _applying
                  ? null
                  : () => Navigator.of(context).pop(widget.imageFile),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: const BorderSide(color: Colors.white24),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                'Usar original',
                style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: FilledButton.icon(
              onPressed: _applying ? null : _applyCrop,
              icon: const Icon(Icons.crop_rounded, size: 18),
              label: Text(
                'Aplicar recorte',
                style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.cyanAccent,
                foregroundColor: const Color(0xFF04121E),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CropTool extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _CropTool({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppTheme.cyanAccent, size: 20),
            const SizedBox(height: 2),
            Text(
              label,
              style: GoogleFonts.inter(
                color: Colors.white70,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CropOverlayPainter extends CustomPainter {
  final List<Offset> quad;

  _CropOverlayPainter({required this.quad});

  @override
  void paint(Canvas canvas, Size size) {
    if (quad.length != 4) return;

    final shape = Path()
      ..moveTo(quad[0].dx, quad[0].dy)
      ..lineTo(quad[1].dx, quad[1].dy)
      ..lineTo(quad[2].dx, quad[2].dy)
      ..lineTo(quad[3].dx, quad[3].dy)
      ..close();

    final dim = Path()
      ..addRect(Offset.zero & size)
      ..addPath(shape, Offset.zero)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(
      dim,
      Paint()..color = Colors.black.withValues(alpha: 0.62),
    );

    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = AppTheme.cyanAccent;
    canvas.drawPath(shape, borderPaint);

    final gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7
      ..color = Colors.white.withValues(alpha: 0.35);

    Offset lerp(Offset a, Offset b, double t) => Offset(
          a.dx + (b.dx - a.dx) * t,
          a.dy + (b.dy - a.dy) * t,
        );

    for (var i = 1; i < 3; i++) {
      final t = i / 3;
      canvas.drawLine(
        lerp(quad[0], quad[1], t),
        lerp(quad[3], quad[2], t),
        gridPaint,
      );
      canvas.drawLine(
        lerp(quad[0], quad[3], t),
        lerp(quad[1], quad[2], t),
        gridPaint,
      );
    }

    final handleFill = Paint()..color = Colors.white;
    final handleBorder = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = AppTheme.cyanAccent;

    for (final corner in quad) {
      canvas.drawCircle(corner, 9, handleFill);
      canvas.drawCircle(corner, 9, handleBorder);
    }
  }

  @override
  bool shouldRepaint(covariant _CropOverlayPainter oldDelegate) {
    return !listEquals(oldDelegate.quad, quad);
  }
}
