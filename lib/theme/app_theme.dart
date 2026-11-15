import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Sistema de diseño centralizado inspirado en "Pokémon TCG Scanner Neon HUD"
class AppTheme {
  // ── Paleta de Colores ───────────────────────────────────────────────────────
  static const Color bgDark = Color(0xFF070C1A);
  static const Color bgSurface = Color(0xFF101B33);
  static const Color bgSurfaceLight = Color(0xFF19284A);
  static const Color bgCard = Color(0xFF121E38);

  static const Color primary = Color(0xFFFFCB05);      // Amarillo Pokémon oficial
  static const Color pokemonBlue = Color(0xFF2A75BB);  // Azul borde Pokémon
  static const Color cyanAccent = Color(0xFF00E5FF);   // Cian neón HUD
  static const Color neonGreen = Color(0xFF1EF59B);
  static const Color success = Color(0xFF1EF59B);      // Verde menta neón ("Añadir a mi Colección")
  static const Color electricBlue = Color(0xFF0099FF); // Azul neón ("Ver en el Mercado")
  static const Color loss = Color(0xFFFF6B6B);         // Rojo coral
  static const Color textMuted = Color(0xFF8E9CB8);

  // ── Gradientes ─────────────────────────────────────────────────────────────
  static const LinearGradient bgGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFF060B18),
      Color(0xFF0B162C),
      Color(0xFF0E1D38),
      Color(0xFF080F20),
    ],
  );

  static const LinearGradient neonGreenButtonGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [
      Color(0xFF2AF598),
      Color(0xFF00E676),
    ],
  );

  static const LinearGradient neonBlueButtonGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [
      Color(0xFF00C6FF),
      Color(0xFF0072FF),
    ],
  );

  static const LinearGradient darkStatsButtonGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFF232F4B),
      Color(0xFF151E32),
    ],
  );

  static const LinearGradient glassCardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xCC162442),
      Color(0xB30D162B),
    ],
  );

  static const LinearGradient heroCardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF152447),
      Color(0xFF0C152B),
    ],
  );

  // ── Decoraciones Glass / HUD ───────────────────────────────────────────────
  static BoxDecoration glassDecoration({
    double radius = 20,
    Color borderColor = const Color(0x4D00E5FF),
    Color fillColor = const Color(0xCC101B33),
  }) {
    return BoxDecoration(
      color: fillColor,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: borderColor, width: 1.2),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.45),
          blurRadius: 22,
          offset: const Offset(0, 10),
        ),
        BoxShadow(
          color: cyanAccent.withValues(alpha: 0.08),
          blurRadius: 16,
          spreadRadius: 1,
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
        centerTitle: true,
        titleTextStyle: GoogleFonts.outfit(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xFF142240),
        contentTextStyle: GoogleFonts.inter(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: cyanAccent.withValues(alpha: 0.4)),
        ),
      ),
    );
  }
}
