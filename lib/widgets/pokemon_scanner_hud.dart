import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 1. LOGO CABECERA "Pokémon TCG SCANNER"
// ─────────────────────────────────────────────────────────────────────────────
class PokemonScannerLogo extends StatelessWidget {
  final double scale;

  const PokemonScannerLogo({
    super.key,
    this.scale = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: scale,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Texto "Pokémon" con borde azul 3D y relleno amarillo brillante
          Stack(
            alignment: Alignment.center,
            children: [
              // Sombra exterior profunda
              Text(
                'Pokémon',
                style: GoogleFonts.outfit(
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                  height: 1.0,
                  shadows: [
                    Shadow(
                      color: Colors.black.withValues(alpha: 0.75),
                      offset: const Offset(0, 5),
                      blurRadius: 10,
                    ),
                    Shadow(
                      color: AppTheme.pokemonBlue.withValues(alpha: 0.8),
                      offset: const Offset(0, 0),
                      blurRadius: 16,
                    ),
                  ],
                  foreground: Paint()
                    ..style = PaintingStyle.stroke
                    ..strokeWidth = 7.5
                    ..strokeJoin = StrokeJoin.round
                    ..color = const Color(0xFF1B539B),
                ),
              ),
              // Segundo trazo azul eléctrico
              Text(
                'Pokémon',
                style: GoogleFonts.outfit(
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                  height: 1.0,
                  foreground: Paint()
                    ..style = PaintingStyle.stroke
                    ..strokeWidth = 4.5
                    ..strokeJoin = StrokeJoin.round
                    ..color = const Color(0xFF2A75BB),
                ),
              ),
              // Relleno amarillo dorado con degradado superior
              ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFFFFF176),
                    Color(0xFFFFCB05),
                    Color(0xFFFFA000),
                  ],
                ).createShader(bounds),
                child: Text(
                  'Pokémon',
                  style: GoogleFonts.outfit(
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                    height: 1.0,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          // Sub-badge "TCG SCANNER" con borde neón cian
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF0E2954),
                  Color(0xFF18458B),
                  Color(0xFF0E2954),
                ],
              ),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: AppTheme.cyanAccent.withValues(alpha: 0.85),
                width: 1.3,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.cyanAccent.withValues(alpha: 0.35),
                  blurRadius: 10,
                  spreadRadius: 0.5,
                ),
              ],
            ),
            child: Text(
              'TCG SCANNER',
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 2.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. MARCO DE ESCANEO NEÓN HUD (Esquinas Cian/Amarillo + Retícula + Callout)
// ─────────────────────────────────────────────────────────────────────────────
class NeonScannerFrame extends StatefulWidget {
  final Widget child;
  final bool isScanning;
  final bool showLaser;
  final String? calloutTitle;
  final String? calloutSubtitle;
  final String? calloutBadge;
  final VoidCallback? onTap;
  final double width;
  final double height;

  const NeonScannerFrame({
    super.key,
    required this.child,
    this.isScanning = false,
    this.showLaser = true,
    this.calloutTitle,
    this.calloutSubtitle,
    this.calloutBadge,
    this.onTap,
    this.width = 225,
    this.height = 310,
  });

  @override
  State<NeonScannerFrame> createState() => _NeonScannerFrameState();
}

class _NeonScannerFrameState extends State<NeonScannerFrame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: SizedBox(
        width: widget.width + (widget.calloutTitle != null ? 96 : 24),
        height: widget.height + 24,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            // Contenedor interior de la carta
            Container(
              width: widget.width,
              height: widget.height,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                color: const Color(0xFF0A1428),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.cyanAccent.withValues(alpha: 0.16),
                    blurRadius: 24,
                    offset: const Offset(-8, 0),
                  ),
                  BoxShadow(
                    color: AppTheme.primary.withValues(alpha: 0.16),
                    blurRadius: 24,
                    offset: const Offset(8, 0),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: widget.child,
              ),
            ),

            // Láser horizontal y retícula circular HUD
            if (widget.showLaser || widget.isScanning)
              SizedBox(
                width: widget.width + 16,
                height: widget.height,
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) {
                    final progress = widget.isScanning ? _controller.value : 0.48;
                    final laserY = 28 + (widget.height - 56) * progress;

                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        // Línea láser neón verde/cian
                        Positioned(
                          top: laserY,
                          left: 0,
                          right: 0,
                          child: Container(
                            height: 2.5,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  Color(0x0000E5FF),
                                  Color(0xFF00E5FF),
                                  Color(0xFF2AF598),
                                  Color(0xFF00E5FF),
                                  Color(0x0000E5FF),
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF2AF598)
                                      .withValues(alpha: 0.75),
                                  blurRadius: 10,
                                  spreadRadius: 1.5,
                                ),
                              ],
                            ),
                          ),
                        ),
                        // Retícula circular central estilo HUD
                        CustomPaint(
                          size: const Size(68, 68),
                          painter: _HudReticlePainter(
                            rotation: widget.isScanning
                                ? _controller.value * math.pi * 2
                                : 0.4,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),

            // Esquinas neón (Cian a la izquierda, Amarillo a la derecha)
            IgnorePointer(
              child: CustomPaint(
                size: Size(widget.width + 18, widget.height + 18),
                painter: _NeonBracketsPainter(),
              ),
            ),

            // Etiqueta flotante lateral derecha (HUD Callout Tag)
            if (widget.calloutTitle != null && widget.calloutTitle!.isNotEmpty)
              Positioned(
                right: 0,
                top: widget.height * 0.22,
                child: _HudCalloutTag(
                  title: widget.calloutTitle!,
                  subtitle: widget.calloutSubtitle,
                  badge: widget.calloutBadge,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _HudCalloutTag extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? badge;

  const _HudCalloutTag({
    required this.title,
    this.subtitle,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Línea conectora cian
        Container(
          width: 14,
          height: 1.8,
          decoration: BoxDecoration(
            color: AppTheme.cyanAccent,
            boxShadow: [
              BoxShadow(
                color: AppTheme.cyanAccent.withValues(alpha: 0.8),
                blurRadius: 6,
              ),
            ],
          ),
        ),
        Container(
          constraints: const BoxConstraints(maxWidth: 112),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xE60B1528),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: AppTheme.cyanAccent.withValues(alpha: 0.75),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.6),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: AppTheme.cyanAccent.withValues(alpha: 0.2),
                blurRadius: 10,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    color: AppTheme.neonGreen,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              if (badge != null && badge!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF6B35), Color(0xFFE63946)],
                    ),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    badge!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _NeonBracketsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const double cornerLen = 42.0;
    const double radius = 18.0;
    const double strokeWidth = 4.2;

    // ── Esquinas Izquierdas (Cian Neón) ──
    final cyanGlowPaint = Paint()
      ..color = AppTheme.cyanAccent.withValues(alpha: 0.65)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth + 5
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    final cyanPaint = Paint()
      ..color = AppTheme.cyanAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final leftPath = Path()
      // Superior izquierda
      ..moveTo(0, cornerLen)
      ..lineTo(0, radius)
      ..quadraticBezierTo(0, 0, radius, 0)
      ..lineTo(cornerLen, 0)
      // Inferior izquierda
      ..moveTo(0, size.height - cornerLen)
      ..lineTo(0, size.height - radius)
      ..quadraticBezierTo(0, size.height, radius, size.height)
      ..lineTo(cornerLen, size.height);

    canvas.drawPath(leftPath, cyanGlowPaint);
    canvas.drawPath(leftPath, cyanPaint);

    // ── Esquinas Derechas (Amarillo/Dorado Neón) ──
    final yellowGlowPaint = Paint()
      ..color = AppTheme.primary.withValues(alpha: 0.65)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth + 5
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    final yellowPaint = Paint()
      ..color = AppTheme.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final rightPath = Path()
      // Superior derecha
      ..moveTo(size.width - cornerLen, 0)
      ..lineTo(size.width - radius, 0)
      ..quadraticBezierTo(size.width, 0, size.width, radius)
      ..lineTo(size.width, cornerLen)
      // Inferior derecha
      ..moveTo(size.width - cornerLen, size.height)
      ..lineTo(size.width - radius, size.height)
      ..quadraticBezierTo(
          size.width, size.height, size.width, size.height - radius)
      ..lineTo(size.width, size.height - cornerLen);

    canvas.drawPath(rightPath, yellowGlowPaint);
    canvas.drawPath(rightPath, yellowPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _HudReticlePainter extends CustomPainter {
  final double rotation;

  const _HudReticlePainter({required this.rotation});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    final glowPaint = Paint()
      ..color = AppTheme.cyanAccent.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    final ringPaint = Paint()
      ..color = AppTheme.cyanAccent.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;

    canvas.drawCircle(center, radius * 0.72, glowPaint);
    canvas.drawCircle(center, radius * 0.72, ringPaint);

    final arcPaint = Paint()
      ..color = AppTheme.neonGreen
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round;

    final rect = Rect.fromCircle(center: center, radius: radius * 0.92);
    canvas.drawArc(rect, rotation, math.pi * 0.65, false, arcPaint);
    canvas.drawArc(
        rect, rotation + math.pi, math.pi * 0.65, false, arcPaint);
  }

  @override
  bool shouldRepaint(covariant _HudReticlePainter oldDelegate) =>
      oldDelegate.rotation != rotation;
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. BOTONES PÍLDORA NEÓN ("Añadir a mi Colección", "Ver en el Mercado", etc.)
// ─────────────────────────────────────────────────────────────────────────────
enum NeonButtonStyle { green, blue, darkStats }

class NeonPillButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final NeonButtonStyle style;
  final VoidCallback? onPressed;
  final bool compact;

  const NeonPillButton({
    super.key,
    required this.label,
    this.icon,
    this.style = NeonButtonStyle.green,
    this.onPressed,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final Gradient gradient;
    final Color borderColor;
    final Color glowColor;
    final Color textColor;

    switch (style) {
      case NeonButtonStyle.green:
        gradient = AppTheme.neonGreenButtonGradient;
        borderColor = const Color(0xFF9EFFD0);
        glowColor = const Color(0xFF00E676).withValues(alpha: 0.45);
        textColor = const Color(0xFF042315);
        break;
      case NeonButtonStyle.blue:
        gradient = AppTheme.neonBlueButtonGradient;
        borderColor = const Color(0xFF80E5FF);
        glowColor = const Color(0xFF0099FF).withValues(alpha: 0.45);
        textColor = Colors.white;
        break;
      case NeonButtonStyle.darkStats:
        gradient = AppTheme.darkStatsButtonGradient;
        borderColor = const Color(0xFF4A608A);
        glowColor = Colors.black.withValues(alpha: 0.35);
        textColor = Colors.white;
        break;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 14 : 18,
            vertical: compact ? 8 : 11,
          ),
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: borderColor, width: 1.3),
            boxShadow: [
              BoxShadow(
                color: glowColor,
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.max,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: compact ? 15 : 18,
                  color: style == NeonButtonStyle.darkStats
                      ? AppTheme.cyanAccent
                      : textColor,
                ),
                const SizedBox(width: 7),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    color: textColor,
                    fontSize: compact ? 12.5 : 14.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 4. BARRA DE NAVEGACIÓN INFERIOR CON POKÉBALL CENTRAL NEÓN
// ─────────────────────────────────────────────────────────────────────────────
class PokeballBottomBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTabSelected;
  final VoidCallback onCenterScanTap;

  const PokeballBottomBar({
    super.key,
    required this.selectedIndex,
    required this.onTabSelected,
    required this.onCenterScanTap,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return SizedBox(
      height: 84 + bottomPadding,
      child: Stack(
        alignment: Alignment.bottomCenter,
        clipBehavior: Clip.none,
        children: [
          // Fondo cristal oscuro de la barra inferior
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                height: 68 + bottomPadding,
                padding: EdgeInsets.only(
                  left: 8,
                  right: 8,
                  bottom: bottomPadding,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xEB0E1A32),
                      Color(0xF5070D1B),
                    ],
                  ),
                  border: Border(
                    top: BorderSide(
                      color: AppTheme.cyanAccent.withValues(alpha: 0.35),
                      width: 1.2,
                    ),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.6),
                      blurRadius: 20,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _NavTabItem(
                      icon: Icons.center_focus_strong_rounded,
                      label: 'Escanear',
                      isSelected: selectedIndex == 0,
                      onTap: () => onTabSelected(0),
                    ),
                    _NavTabItem(
                      icon: Icons.style_rounded,
                      label: 'Mi Mazo',
                      isSelected: selectedIndex == 1,
                      onTap: () => onTabSelected(1),
                    ),
                    const SizedBox(width: 74), // Espacio para la Pokéball central
                    _NavTabItem(
                      icon: Icons.history_rounded,
                      label: 'Historial',
                      isSelected: selectedIndex == 2,
                      onTap: () => onTabSelected(2),
                    ),
                    _NavTabItem(
                      icon: Icons.shopping_cart_outlined,
                      label: 'Mercado',
                      isSelected: selectedIndex == 3,
                      onTap: () => onTabSelected(3),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Botón Pokéball Central Elevado con Brillo Neón Cian
          Positioned(
            bottom: bottomPadding + 6,
            child: GestureDetector(
              onTap: onCenterScanTap,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.cyanAccent.withValues(alpha: 0.65),
                          blurRadius: 18,
                          spreadRadius: 2,
                        ),
                        BoxShadow(
                          color: AppTheme.electricBlue.withValues(alpha: 0.45),
                          blurRadius: 28,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: CustomPaint(
                      painter: _NeonPokeballPainter(),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Escanear',
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavTabItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavTabItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isSelected ? AppTheme.cyanAccent : const Color(0xFF8FA3C7);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: color,
              size: 23,
              shadows: isSelected
                  ? [
                      Shadow(
                        color: AppTheme.cyanAccent.withValues(alpha: 0.7),
                        blurRadius: 10,
                      ),
                    ]
                  : null,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: GoogleFonts.outfit(
                color: color,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NeonPokeballPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final rect = Rect.fromCircle(center: center, radius: radius - 2);

    // Mitad superior azul cian brillante
    final topPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF40E0FF),
          Color(0xFF0077FF),
          Color(0xFF0A3D91),
        ],
      ).createShader(rect);

    canvas.drawArc(rect, math.pi, math.pi, true, topPaint);

    // Mitad inferior blanca/plateada con reflejo azulado
    final bottomPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFFFFFFFF),
          Color(0xFFD6E6FF),
          Color(0xFF9BB8E8),
        ],
      ).createShader(rect);

    canvas.drawArc(rect, 0, math.pi, true, bottomPaint);

    // Franja ecuatorial oscura
    final bandPaint = Paint()
      ..color = const Color(0xFF091326)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5;
    canvas.drawLine(
      Offset(3, center.dy),
      Offset(size.width - 3, center.dy),
      bandPaint,
    );

    // Anillo exterior neón cian
    final outerRingPaint = Paint()
      ..color = AppTheme.cyanAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6;
    canvas.drawCircle(center, radius - 1.5, outerRingPaint);

    // Botón central de la Pokéball
    final centerOuterPaint = Paint()
      ..color = const Color(0xFF091326)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius * 0.34, centerOuterPaint);

    final centerRingPaint = Paint()
      ..color = AppTheme.cyanAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(center, radius * 0.32, centerRingPaint);

    final centerCorePaint = Paint()
      ..shader = const RadialGradient(
        colors: [
          Colors.white,
          Color(0xFF80EAFF),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius * 0.22));
    canvas.drawCircle(center, radius * 0.20, centerCorePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
