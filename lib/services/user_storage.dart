// ============================================================
// services/user_storage.dart
// Almacenamiento transaccional de datos de usuario en SQLite.
//
// Esquema normalizado:
//   albums       → metadatos de cada álbum
//   album_cards  → cartas de cada álbum (una fila por carta)
//   decks        → metadatos de cada mazo
//   deck_entries → cartas de cada mazo (una fila por carta)
//   kv           → ajustes sueltos (álbum activo, marcadores, etc.)
//
// Mantiene una migración transparente desde el JSON histórico de
// SharedPreferences y un fallback para tests/plataformas sin plugin.
// ============================================================

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class UserStorage {
  static final UserStorage instance = UserStorage._internal();
  UserStorage._internal();

  static const String _dbName = 'tcg_user.db';
  static const int _schemaVersion = 2;

  Database? _db;
  Future<Database?>? _opening;

  Future<Database?> database() => _database();

  Future<Database?> _database() async {
    if (_db != null && _db!.isOpen) return _db;
    if (_opening != null) return _opening;

    _opening = _open();
    final opened = await _opening;
    _opening = null;
    return opened;
  }

  Future<Database?> _open() async {
    try {
      final databasesPath = await getDatabasesPath();
      final path = p.join(databasesPath, _dbName);
      _db = await openDatabase(
        path,
        version: _schemaVersion,
        onConfigure: (db) async {
          try {
            await db.execute('PRAGMA foreign_keys = ON');
          } catch (_) {}
        },
        onCreate: (db, version) async {
          await _createSchema(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          // v1 solo tenía la tabla kv con el JSON de álbumes/mazos.
          // Se conserva y se añaden las tablas normalizadas; los datos
          // se migran después desde AlbumStorageService.
          await _createSchema(db);
        },
      );
      return _db;
    } catch (_) {
      _db = null;
      return null;
    }
  }

  Future<void> _createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS kv (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS albums (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS album_cards (
        album_id TEXT NOT NULL,
        card_id TEXT NOT NULL,
        position INTEGER NOT NULL,
        name TEXT NOT NULL,
        number TEXT NOT NULL,
        set_name TEXT NOT NULL,
        image_url TEXT NOT NULL,
        game TEXT NOT NULL,
        avg_price REAL,
        trend_price REAL,
        psa10_price REAL,
        set_printed_total INTEGER,
        set_total INTEGER,
        language TEXT,
        purchase_price REAL,
        purchase_date TEXT,
        condition TEXT,
        grading_score TEXT,
        quantity INTEGER NOT NULL DEFAULT 1,
        PRIMARY KEY (album_id, card_id),
        FOREIGN KEY (album_id) REFERENCES albums(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS decks (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        format TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS deck_entries (
        deck_id TEXT NOT NULL,
        card_id TEXT NOT NULL,
        position INTEGER NOT NULL,
        quantity INTEGER NOT NULL DEFAULT 1,
        card_name TEXT,
        image_url TEXT,
        set_name TEXT,
        number TEXT,
        PRIMARY KEY (deck_id, card_id),
        FOREIGN KEY (deck_id) REFERENCES decks(id) ON DELETE CASCADE
      )
    ''');

    try {
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_album_cards_album '
        'ON album_cards(album_id, position)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_deck_entries_deck '
        'ON deck_entries(deck_id, position)',
      );
    } catch (_) {}
  }

  // ── Clave-valor ─────────────────────────────────────────────────────────
  Future<String?> read(String key) async {
    final db = await _database();
    if (db == null) return null;
    try {
      final rows = await db.query(
        'kv',
        columns: ['value'],
        where: 'key = ?',
        whereArgs: [key],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return rows.first['value'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Devuelve true si se guardó en SQLite. false permite al caller
  /// hacer fallback a SharedPreferences (tests o plugin no disponible).
  Future<bool> write(String key, String value) async {
    final db = await _database();
    if (db == null) return false;
    try {
      await db.insert(
        'kv',
        {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> delete(String key) async {
    final db = await _database();
    if (db == null) return;
    try {
      await db.delete('kv', where: 'key = ?', whereArgs: [key]);
    } catch (_) {}
  }
}
