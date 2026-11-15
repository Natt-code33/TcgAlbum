import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 1. LOGO CABECERA "Pokémon TCG SCANNER" (Paleta Azul / Negro Neón)
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
          Stack(
            alignment: Alignment.center,
            children: [
              // Resplandor exterior
              Text(
                'Pokémon',
                style: GoogleFonts.outfit(
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                  height: 1.0,
                  shadows: [
                    Shadow(
                      color: Colors.black.withValues(alpha: 0.8),
                      offset: const Offset(0, 5),
                      blurRadius: 12,
                    ),
                    Shadow(
                      color: AppTheme.cyanAccent.withValues(alpha: 0.7),
                      offset: const Offset(0, 0),
                      blurRadius: 18,
                    ),
                  ],
                  foreground: Paint()
                    ..style = PaintingStyle.stroke
                    ..strokeWidth = 7.5
                    ..strokeJoin = StrokeJoin.round
                    ..color = const Color(0xFF0B3B66),
                ),
              ),
              // Trazo azul neón
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
                    ..color = const Color(0xFF0EA5E9),
                ),
              ),
              // Relleno azul cielo → cian
              ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFFBAE6FD),
                    Color(0xFF38BDF8),
                    Color(0xFF0369A1),
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF0A2440),
                  Color(0xFF123E66),
                  Color(0xFF0A2440),
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
// 2. MARCO DE ESCANEO NEÓN HUD (Esquinas Cian/Azul + Retícula + Callout)
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
            Container(
              width: widget.width,
              height: widget.height,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                color: const Color(0xFF081120),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.cyanAccent.withValues(alpha: 0.18),
                    blurRadius: 24,
                    offset: const Offset(-8, 0),
                  ),
                  BoxShadow(
                    color: AppTheme.deepBlue.withValues(alpha: 0.18),
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
                        Positioned(
                          top: laserY,
                          left: 0,
                          right: 0,
                          child: Container(
                            height: 2.5,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  Color(0x0022D3EE),
                                  Color(0xFF22D3EE),
                                  Color(0xFF38BDF8),
                                  Color(0xFF22D3EE),
                                  Color(0x0022D3EE),
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF22D3EE)
                                      .withValues(alpha: 0.75),
                                  blurRadius: 10,
                                  spreadRadius: 1.5,
                                ),
                              ],
                            ),
                          ),
                        ),
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

            IgnorePointer(
              child: CustomPaint(
                size: Size(widget.width + 18, widget.height + 18),
                painter: _NeonBracketsPainter(),
              ),
            ),

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
            color: const Color(0xE6081120),
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
                    color: AppTheme.cyanAccent,
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
                      colors: [Color(0xFF0EA5E9), Color(0xFF0369A1)],
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
      ..moveTo(0, cornerLen)
      ..lineTo(0, radius)
      ..quadraticBezierTo(0, 0, radius, 0)
      ..lineTo(cornerLen, 0)
      ..moveTo(0, size.height - cornerLen)
      ..lineTo(0, size.height - radius)
      ..quadraticBezierTo(0, size.height, radius, size.height)
      ..lineTo(cornerLen, size.height);

    canvas.drawPath(leftPath, cyanGlowPaint);
    canvas.drawPath(leftPath, cyanPaint);

    // ── Esquinas Derechas (Azul Neón) ──
    final blueGlowPaint = Paint()
      ..color = AppTheme.deepBlue.withValues(alpha: 0.65)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth + 5
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    final bluePaint = Paint()
      ..color = AppTheme.deepBlue
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final rightPath = Path()
      ..moveTo(size.width - cornerLen, 0)
      ..lineTo(size.width - radius, 0)
      ..quadraticBezierTo(size.width, 0, size.width, radius)
      ..lineTo(size.width, cornerLen)
      ..moveTo(size.width - cornerLen, size.height)
      ..lineTo(size.width - radius, size.height)
      ..quadraticBezierTo(
          size.width, size.height, size.width, size.height - radius)
      ..lineTo(size.width, size.height - cornerLen);

    canvas.drawPath(rightPath, blueGlowPaint);
    canvas.drawPath(rightPath, bluePaint);
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
      ..color = AppTheme.primary
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
// 3. BOTONES PÍLDORA NEÓN UNIFICADOS (mismo diseño y fuente en toda la app)
// ─────────────────────────────────────────────────────────────────────────────
enum NeonButtonStyle { primary, dark, green, darkStats }

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
    this.style = NeonButtonStyle.primary,
    this.onPressed,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDark = style == NeonButtonStyle.dark || style == NeonButtonStyle.darkStats;
    final bool isGreen = style == NeonButtonStyle.green;
    final bool isDarkStats = style == NeonButtonStyle.darkStats;

    final Gradient gradient = isGreen
        ? const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [Color(0xFF1A3A5C), Color(0xFF0D2440)],
          )
        : isDarkStats
            ? const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF1B2C46), Color(0xFF0E1B2E)],
              )
            : (isDark ? AppTheme.darkButtonGradient : AppTheme.neonButtonGradient);
    final Color borderColor = isGreen
        ? const Color(0xFF38BDF8).withValues(alpha: 0.6)
        : isDarkStats
            ? const Color(0xFF2E4A6E)
            : (isDark ? const Color(0xFF2E4A6E) : const Color(0xFF7DD3FC));
    final Color glowColor = isGreen
        ? AppTheme.deepBlue.withValues(alpha: 0.35)
        : (isDark
            ? Colors.black.withValues(alpha: 0.35)
            : AppTheme.deepBlue.withValues(alpha: 0.45));
    final Color textColor = Colors.white;
    final Color iconColor = isGreen
        ? AppTheme.cyanAccent
        : (isDark ? AppTheme.cyanAccent : Colors.white);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 14 : 18,
            vertical: compact ? 9 : 12,
          ),
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: borderColor, width: 1.3),
            boxShadow: [
              BoxShadow(
                color: glowColor,
                blurRadius: 12,
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
                  color: iconColor,
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
                    fontWeight: FontWeight.w700,
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
//    Pestañas: Colección | Mazos | (Pokéball Escanear) | Historial | Mercado
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
                      Color(0xEB0C1626),
                      Color(0xF5050A14),
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
                      icon: Icons.style_rounded,
                      label: 'Colección',
                      isSelected: selectedIndex == 0,
                      onTap: () => onTabSelected(0),
                    ),
                    _NavTabItem(
                      icon: Icons.layers_rounded,
                      label: 'Mazos',
                      isSelected: selectedIndex == 1,
                      onTap: () => onTabSelected(1),
                    ),
                    const SizedBox(width: 74),
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

          // Botón Pokéball Central Elevado (único disparador de escaneo)
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
                          color: AppTheme.deepBlue.withValues(alpha: 0.45),
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
    final color = isSelected ? AppTheme.cyanAccent : const Color(0xFF7C93B5);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: color,
              size: 22,
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
                fontSize: 10.5,
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

    final topPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF7DD3FC),
          Color(0xFF0EA5E9),
          Color(0xFF075985),
        ],
      ).createShader(rect);

    canvas.drawArc(rect, math.pi, math.pi, true, topPaint);

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

    final bandPaint = Paint()
      ..color = const Color(0xFF081120)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5;
    canvas.drawLine(
      Offset(3, center.dy),
      Offset(size.width - 3, center.dy),
      bandPaint,
    );

    final outerRingPaint = Paint()
      ..color = AppTheme.cyanAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6;
    canvas.drawCircle(center, radius - 1.5, outerRingPaint);

    final centerOuterPaint = Paint()
      ..color = const Color(0xFF081120)
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
          Color(0xFF67E8F9),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius * 0.22));
    canvas.drawCircle(center, radius * 0.20, centerCorePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
