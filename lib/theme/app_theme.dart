import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Sistema de diseño centralizado: "Dark Glass Premium"
class AppTheme {
  // ── Paleta de Colores ───────────────────────────────────────────────────────
  static const Color bgDark = Color(0xFF0B1020);
  static const Color bgSurface = Color(0xFF16213E);
  static const Color bgSurfaceLight = Color(0xFF1F2D52);
  static const Color bgCard = Color(0xFF141D38);

  static const Color primary = Color(0xFFFFB800);      // Ámbar intenso
  static const Color cyanAccent = Color(0xFF00E5FF);  // Cian vivo
  static const Color success = Color(0xFF4CD97B);     // Verde esmeralda vivo
  static const Color loss = Color(0xFFFF6B6B);        // Rojo salmón vivo
  static const Color textMuted = Color(0xFF8E9CB8);

  // ── Gradientes ─────────────────────────────────────────────────────────────
  static const LinearGradient bgGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFF0B1020),
      Color(0xFF12182B),
      Color(0xFF16213E),
    ],
  );

  static const LinearGradient glassCardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0x33283B6B),
      Color(0x1A141D38),
    ],
  );

  static const LinearGradient heroCardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF1A264D),
      Color(0xFF111933),
    ],
  );

  // ── Decoraciones Glass ─────────────────────────────────────────────────────
  static BoxDecoration glassDecoration({
    double radius = 16,
    Color borderColor = const Color(0x334B68B8),
    Color fillColor = const Color(0x4016213E),
  }) {
    return BoxDecoration(
      color: fillColor,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: borderColor, width: 1),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.35),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }

  // ── ThemeData ──────────────────────────────────────────────────────────────
  static ThemeData get darkTheme {
    final textTheme = GoogleFonts.interTextTheme(ThemeData.dark().textTheme);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bgDark,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        secondary: cyanAccent,
        surface: bgSurface,
        error: loss,
      ),
      textTheme: textTheme.copyWith(
        displayLarge: GoogleFonts.outfit(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
        displayMedium: GoogleFonts.outfit(
          fontSize: 26,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
        titleLarge: GoogleFonts.outfit(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
        titleMedium: GoogleFonts.outfit(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.outfit(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xFF1C2744),
        contentTextStyle: GoogleFonts.inter(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0x444B68B8)),
        ),
      ),
    );
  }
}
