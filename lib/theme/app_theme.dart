import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Sistema de diseño centralizado: "Neon Navy HUD" (azul y negro, sin amarillos).
class AppTheme {
  // ── Paleta de Colores ───────────────────────────────────────────────────────
  static const Color bgDark = Color(0xFF050A14);
  static const Color bgSurface = Color(0xFF0C1626);
  static const Color bgSurfaceLight = Color(0xFF14243C);
  static const Color bgCard = Color(0xFF0E1B2E);

  static const Color primary = Color(0xFF38BDF8);      // Azul cielo neón
  static const Color cyanAccent = Color(0xFF22D3EE);   // Cian neón
  static const Color deepBlue = Color(0xFF0EA5E9);     // Azul intenso
  static const Color success = Color(0xFF34D399);      // Verde esmeralda (ganancias)
  static const Color loss = Color(0xFFF87171);         // Rojo coral (pérdidas)
  static const Color textMuted = Color(0xFF8FA3C0);

  // ── Gradientes ─────────────────────────────────────────────────────────────
  static const LinearGradient bgGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFF04080F),
      Color(0xFF081120),
      Color(0xFF0B1A2E),
      Color(0xFF060C16),
    ],
  );

  static const LinearGradient neonButtonGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [
      Color(0xFF38BDF8),
      Color(0xFF0EA5E9),
    ],
  );

  static const LinearGradient darkButtonGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFF1B2C46),
      Color(0xFF0E1B2E),
    ],
  );

  static const LinearGradient glassCardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xCC12233D),
      Color(0xB30A1424),
    ],
  );

  static const LinearGradient heroCardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF10253F),
      Color(0xFF091424),
    ],
  );

  // ── Decoraciones Glass / HUD ───────────────────────────────────────────────
  static BoxDecoration glassDecoration({
    double radius = 18,
    Color borderColor = const Color(0x4D22D3EE),
    Color fillColor = const Color(0xCC0C1626),
  }) {
    return BoxDecoration(
      color: fillColor,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: borderColor, width: 1.1),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.5),
          blurRadius: 22,
          offset: const Offset(0, 10),
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
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xFF0E1B2E),
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
      // Botones uniformes en toda la app: píldora azul neón
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 2,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
          textStyle: GoogleFonts.outfit(
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: BorderSide(color: primary.withValues(alpha: 0.6)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
          textStyle: GoogleFonts.outfit(
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: GoogleFonts.outfit(fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF0C1626),
        hintStyle: GoogleFonts.inter(color: Colors.white38, fontSize: 13),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(999),
          borderSide: BorderSide(color: primary.withValues(alpha: 0.3)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(999),
          borderSide: BorderSide(color: primary.withValues(alpha: 0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(999),
          borderSide: const BorderSide(color: cyanAccent, width: 1.5),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFF0E1B2E),
        selectedColor: primary.withValues(alpha: 0.22),
        side: BorderSide(color: primary.withValues(alpha: 0.35)),
        labelStyle: GoogleFonts.outfit(color: Colors.white70, fontSize: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: const Color(0xFF0C1626),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: primary.withValues(alpha: 0.4)),
        ),
        titleTextStyle: GoogleFonts.outfit(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
        contentTextStyle: GoogleFonts.inter(color: Colors.white70, fontSize: 14),
      ),
    );
  }
}
