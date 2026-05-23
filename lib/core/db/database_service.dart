import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseService {
  DatabaseService._();
  static final DatabaseService instance = DatabaseService._();

  Database? _db;

  Future<Database> get db async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final path = join(await getDatabasesPath(), 'taxuk_history.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, v) => db.execute('''
        CREATE TABLE history (
          id        INTEGER PRIMARY KEY AUTOINCREMENT,
          timestamp TEXT    NOT NULL,
          inputs    TEXT    NOT NULL,
          results   TEXT    NOT NULL
        )
      '''),
      onUpgrade: (db, oldVersion, newVersion) async {
        // Future schema migrations go here
      },
    );
  }

  /// Insert a calculation entry. Returns the new row id.
  Future<int> insert({
    required Map<String, dynamic> inputs,
    required Map<String, dynamic> results,
  }) async {
    final database = await db;
    return database.insert('history', {
      'timestamp': DateTime.now().toIso8601String(),
      'inputs': jsonEncode(inputs),
      'results': jsonEncode(results),
    });
  }

  /// Returns all history entries, newest first, up to [limit].
  Future<List<Map<String, dynamic>>> getAll({int limit = 999999}) async {
    final database = await db;
    final rows = await database.query(
      'history',
      orderBy: 'id DESC',
      limit: limit,
    );
    return rows.map((r) {
      return {
        'id': r['id'],
        'timestamp': r['timestamp'],
        'inputs': jsonDecode(r['inputs'] as String) as Map<String, dynamic>,
        'results': jsonDecode(r['results'] as String) as Map<String, dynamic>,
      };
    }).toList();
  }

  Future<int> count() async {
    final database = await db;
    final result =
        await database.rawQuery('SELECT COUNT(*) as cnt FROM history');
    return (result.first['cnt'] as int?) ?? 0;
  }

  Future<void> delete(int id) async {
    final database = await db;
    await database.delete('history', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearAll() async {
    final database = await db;
    await database.delete('history');
  }
}
