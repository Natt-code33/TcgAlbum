// ============================================================
// main.dart
// Punto de entrada de la aplicación PokéÁlbum.
// ============================================================

import 'package:flutter/material.dart';
import 'views/album_view.dart';

void main() {
  // Necesario para inicializar bindings de Flutter antes de
  // usar plugins nativos (ML Kit, SharedPreferences, etc.).
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PokemonAlbumApp());
}

class PokemonAlbumApp extends StatelessWidget {
  const PokemonAlbumApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PokéÁlbum',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00B4D8),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: const AlbumView(),
    );
  }
}
