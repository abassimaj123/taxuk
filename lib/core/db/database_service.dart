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
      version: 3,
      onCreate: (db, v) => db.execute('''
        CREATE TABLE history (
          id         INTEGER PRIMARY KEY AUTOINCREMENT,
          timestamp  TEXT    NOT NULL,
          inputs     TEXT    NOT NULL,
          results    TEXT    NOT NULL,
          is_pinned  INTEGER NOT NULL DEFAULT 0,
          input_hash TEXT,
          pin_label  TEXT,
          pin_order  INTEGER NOT NULL DEFAULT 0,
          l1_json    TEXT,
          screen_id  TEXT    NOT NULL DEFAULT 'income_tax'
        )
      '''),
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
              'ALTER TABLE history ADD COLUMN is_pinned INTEGER NOT NULL DEFAULT 0');
          await db.execute('ALTER TABLE history ADD COLUMN input_hash TEXT');
          await db.execute('ALTER TABLE history ADD COLUMN pin_label TEXT');
          await db.execute(
              'ALTER TABLE history ADD COLUMN pin_order INTEGER NOT NULL DEFAULT 0');
          await db.execute('ALTER TABLE history ADD COLUMN l1_json TEXT');
        }
        if (oldVersion < 3) {
          // Scope history rows by screen so hash-based dedup/lookup never
          // merges saves from two different calculators that happen to hash
          // to the same rounded inputs. Existing rows predate multi-screen
          // SmartHistory usage and default to 'income_tax' (the only screen
          // originally wired through this table).
          await db.execute(
              "ALTER TABLE history ADD COLUMN screen_id TEXT NOT NULL DEFAULT 'income_tax'");
        }
      },
    );
  }

  // ── Legacy insert (used by secondary calculators: VAT, CGT, etc.) ──────────

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

  // ── SmartHistory-aware insert (used by TaxUKDatabaseAdapter) ───────────────

  /// Insert a full row map (called by TaxUKDatabaseAdapter). Returns the row id.
  Future<int> insertHistory(Map<String, dynamic> row) async {
    final database = await db;
    return database.insert('history', row,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ── Queries ────────────────────────────────────────────────────────────────

  /// Returns all history entries ordered: pinned first, then newest first.
  Future<List<Map<String, dynamic>>> getAll({int limit = 999999}) async {
    final database = await db;
    final rows = await database.query(
      'history',
      orderBy: 'is_pinned DESC, pin_order DESC, id DESC',
      limit: limit,
    );
    return rows.map(_decodeRow).toList();
  }

  Future<Map<String, dynamic>?> getHistoryByHash(
      String hash, String screenId) async {
    final database = await db;
    final rows = await database.query('history',
        where: 'input_hash = ? AND screen_id = ?',
        whereArgs: [hash, screenId],
        limit: 1);
    if (rows.isEmpty) return null;
    return _decodeRow(rows.first);
  }

  Future<int> countHistory({bool? isPinned}) async {
    final database = await db;
    final where = isPinned != null ? ' WHERE is_pinned = ?' : '';
    final args = isPinned != null ? [isPinned ? 1 : 0] : <Object?>[];
    final result = await database
        .rawQuery('SELECT COUNT(*) as cnt FROM history$where', args);
    return (result.first['cnt'] as int?) ?? 0;
  }

  /// Oldest non-pinned rows for FIFO eviction — ordered by id ASC.
  Future<List<Map<String, dynamic>>> getOldestAutoSaves(int limit) async {
    final database = await db;
    final rows = await database.query(
      'history',
      where: 'is_pinned = 0',
      orderBy: 'id ASC',
      limit: limit,
    );
    return rows.map(_decodeRow).toList();
  }

  /// Oldest pinned rows for free-tier cap eviction — ordered by pin_order ASC.
  Future<List<Map<String, dynamic>>> getOldestPinnedEntries(int limit) async {
    final database = await db;
    final rows = await database.query(
      'history',
      where: 'is_pinned = 1',
      orderBy: 'pin_order ASC',
      limit: limit,
    );
    return rows.map(_decodeRow).toList();
  }

  // ── Legacy compatibility aliases (used by secondary calculators) ──────────

  /// Alias for [countHistory] — used by VAT, CGT, Dividend, etc. screens.
  Future<int> count() => countHistory();

  /// Alias for [deleteHistory] — used by legacy screens.
  Future<void> delete(int id) => deleteHistory(id);

  /// Alias for [updateHistoryEntry] — used by legacy screens.
  Future<int> update(int id, Map<String, dynamic> fields) =>
      updateHistoryEntry(id, fields);

  // ── Mutations ──────────────────────────────────────────────────────────────

  Future<int> updateHistoryEntry(int id, Map<String, dynamic> fields) async {
    final database = await db;
    return database.update('history', fields, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteHistory(int id) async {
    final database = await db;
    await database.delete('history', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearAll() async {
    final database = await db;
    await database.delete('history');
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Map<String, dynamic> _decodeRow(Map<String, dynamic> r) => {
        'id': r['id'],
        'timestamp': r['timestamp'],
        'inputs': r['inputs'] is String
            ? jsonDecode(r['inputs'] as String) as Map<String, dynamic>
            : (r['inputs'] as Map?)?.cast<String, dynamic>() ?? {},
        'results': r['results'] is String
            ? jsonDecode(r['results'] as String) as Map<String, dynamic>
            : (r['results'] as Map?)?.cast<String, dynamic>() ?? {},
        'is_pinned': r['is_pinned'] ?? 0,
        'input_hash': r['input_hash'],
        'pin_label': r['pin_label'],
        'pin_order': r['pin_order'] ?? 0,
        'l1_json': r['l1_json'],
        'screen_id': r['screen_id'] ?? 'income_tax',
      };
}
