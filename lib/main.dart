// ============================================================
// main.dart
// Punto de entrada de la aplicación PokéÁlbum.
// ============================================================

import 'dart:ui';

import 'package:flutter/material.dart';
import 'views/album_view.dart';
import 'theme/app_theme.dart';

void main() {
  // Necesario para inicializar bindings de Flutter antes de
  // usar plugins nativos (ML Kit, SQLite, SharedPreferences, etc.).
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Unhandled error: $error\n$stack');
    return true;
  };

  // El catálogo SQLite se inicializa de forma lazy en la primera búsqueda.
  // Así no se bloquea el primer frame con la copia de 12,5 MB.
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
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        minScaleFactor: 0.8,
        maxScaleFactor: 1.3,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const AlbumView(),
    );
  }
}
