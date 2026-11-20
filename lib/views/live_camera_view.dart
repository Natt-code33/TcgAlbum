// ============================================================
// views/live_camera_view.dart
// Vista previa de cámara en vivo para encuadrar la carta.
//
// Devuelve la foto capturada (File) al escáner, que después ofrece
// el recorte manual antes del OCR.
// ============================================================

import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';

class LiveCameraView extends StatefulWidget {
  const LiveCameraView({super.key});

  @override
  State<LiveCameraView> createState() => _LiveCameraViewState();
}

class _LiveCameraViewState extends State<LiveCameraView>
    with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = const [];
  int _cameraIndex = 0;
  bool _initializing = true;
  bool _capturing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    _controller = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      final controller = _controller;
      _controller = null;
      controller?.dispose();
    } else if (state == AppLifecycleState.resumed && _controller == null) {
      _initialize();
    }
  }

  Future<void> _initialize() async {
    if (!mounted) return;
    setState(() {
      _initializing = true;
      _error = null;
    });

    try {
      if (_cameras.isEmpty) {
        _cameras = await availableCameras();
      }
      if (_cameras.isEmpty) {
        if (!mounted) return;
        setState(() {
          _initializing = false;
          _error = 'No se encontró ninguna cámara en este dispositivo.';
        });
        return;
      }

      // Preferir la cámara trasera.
      if (_cameraIndex >= _cameras.length) _cameraIndex = 0;
      final backIndex = _cameras.indexWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
      );
      if (backIndex != -1 && _cameras[_cameraIndex].lensDirection != CameraLensDirection.back) {
        _cameraIndex = backIndex;
      }

      final controller = CameraController(
        _cameras[_cameraIndex],
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }

      // Enfoque automático continuo cuando el dispositivo lo soporta.
      try {
        await controller.setFocusMode(FocusMode.auto);
      } catch (_) {}

      setState(() {
        _controller = controller;
        _initializing = false;
      });
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = e.code == 'CameraAccessDenied'
            ? 'Permiso de cámara denegado. Actívalo en Ajustes del sistema.'
            : 'No se pudo iniciar la cámara: ${e.description ?? e.code}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = 'No se pudo iniciar la cámara: $e';
      });
    }
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _capturing) {
      return;
    }

    setState(() => _capturing = true);
    try {
      final picture = await controller.takePicture();
      if (!mounted) return;
      Navigator.of(context).pop(File(picture.path));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _capturing = false;
        _error = 'No se pudo capturar la foto: $e';
      });
    }
  }

  Future<void> _toggleFlash() async {
    final controller = _controller;
    if (controller == null) return;

    try {
      final next = controller.value.flashMode == FlashMode.off
          ? FlashMode.auto
          : FlashMode.off;
      await controller.setFlashMode(next);
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2) return;

    final previous = _controller;
    _controller = null;
    await previous?.dispose();

    setState(() {
      _cameraIndex = (_cameraIndex + 1) % _cameras.length;
      _initializing = true;
    });
    await _initialize();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final flashMode = controller?.value.flashMode ?? FlashMode.off;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(child: _buildPreview(controller)),
            Positioned(
              top: 8,
              left: 8,
              right: 8,
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    tooltip: 'Cerrar',
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: _toggleFlash,
                    icon: Icon(
                      flashMode == FlashMode.off
                          ? Icons.flash_off_rounded
                          : Icons.flash_auto_rounded,
                      color: Colors.white,
                    ),
                    tooltip: 'Flash',
                  ),
                  if (_cameras.length > 1)
                    IconButton(
                      onPressed: _switchCamera,
                      icon: const Icon(
                        Icons.cameraswitch_rounded,
                        color: Colors.white,
                      ),
                      tooltip: 'Cambiar cámara',
                    ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildBottomControls(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview(CameraController? controller) {
    if (_initializing) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.cyanAccent),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography_rounded,
                  color: Colors.white38, size: 44),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _initialize,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.cyanAccent,
                  foregroundColor: const Color(0xFF04121E),
                ),
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    if (controller == null || !controller.value.isInitialized) {
      return const Center(
        child: Text(
          'Cámara no disponible',
          style: TextStyle(color: Colors.white54),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: AspectRatio(
            aspectRatio: controller.value.aspectRatio,
            child: CameraPreview(controller),
          ),
        ),
        IgnorePointer(
          child: CustomPaint(painter: _CameraFramePainter()),
        ),
      ],
    );
  }

  Widget _buildBottomControls() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Color(0xCC000000)],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Encuadra la carta dentro del marco y pulsa el botón',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              const SizedBox(width: 56),
              GestureDetector(
                onTap: _capturing ? null : _capture,
                child: Container(
                  width: 74,
                  height: 74,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppTheme.cyanAccent,
                      width: 3,
                    ),
                  ),
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      width: _capturing ? 26 : 58,
                      height: _capturing ? 26 : 58,
                      decoration: BoxDecoration(
                        shape: _capturing ? BoxShape.rectangle : BoxShape.circle,
                        borderRadius:
                            _capturing ? BorderRadius.circular(6) : null,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 56),
            ],
          ),
        ],
      ),
    );
  }
}

/// Marco guía con proporción de carta Pokémon (63 × 88 mm).
class _CameraFramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const cardAspect = 63 / 88;
    final maxHeight = size.height * 0.66;
    final maxWidth = size.width * 0.82;

    var height = maxHeight;
    var width = height * cardAspect;
    if (width > maxWidth) {
      width = maxWidth;
      height = width / cardAspect;
    }

    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.44),
      width: width,
      height: height,
    );

    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..color = Colors.white.withValues(alpha: 0.85);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(14)),
      border,
    );

    final cornerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..color = AppTheme.cyanAccent;

    const len = 26.0;
    final r = rect;
    final paths = <Path>[
      Path()
        ..moveTo(r.left, r.top + len)
        ..lineTo(r.left, r.top)
        ..lineTo(r.left + len, r.top),
      Path()
        ..moveTo(r.right - len, r.top)
        ..lineTo(r.right, r.top)
        ..lineTo(r.right, r.top + len),
      Path()
        ..moveTo(r.right, r.bottom - len)
        ..lineTo(r.right, r.bottom)
        ..lineTo(r.right - len, r.bottom),
      Path()
        ..moveTo(r.left + len, r.bottom)
        ..lineTo(r.left, r.bottom)
        ..lineTo(r.left, r.bottom - len),
    ];
    for (final path in paths) {
      canvas.drawPath(path, cornerPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
