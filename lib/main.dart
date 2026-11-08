// ============================================================
// main.dart
// Punto de entrada de la aplicación PokéÁlbum.
// ============================================================

import 'package:flutter/material.dart';
import 'views/album_view.dart';
import 'services/local_catalog_service.dart';
import 'theme/app_theme.dart';

void main() async {
  // Necesario para inicializar bindings de Flutter antes de
  // usar plugins nativos (ML Kit, SQLite, SharedPreferences, etc.).
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializar base de datos local SQLite para catálogo y búsqueda instantánea
  LocalCatalogService.instance.init();

  runApp(const PokemonAlbumApp());
}

class PokemonAlbumApp extends StatelessWidget {
  const PokemonAlbumApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TcgAlbum',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const AlbumView(),
    );
  }
}
