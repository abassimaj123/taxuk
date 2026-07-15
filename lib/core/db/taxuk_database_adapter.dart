import 'dart:convert';
import 'package:calcwise_core/calcwise_core.dart' show DatabaseAdapter;
import 'database_service.dart';

/// DatabaseAdapter for TaxUK — bridges SmartHistoryService to the local
/// sqflite [DatabaseService] history table.
///
/// All 8 calculators (income_tax, vat, cgt, dividend, rental_income,
/// savings_interest, salary_comparison, student_loan_uk) route their
/// auto-save/save-scenario calls through SmartHistoryService into this same
/// `history` table, each tagged with its own `screen_id`. Rows are scoped by
/// `screen_id` everywhere a lookup could otherwise collide across screens
/// (hash dedup in [getRowByHash], per-screen listing in [getRows]).
///
/// The `history` table stores legacy `inputs`/`results` JSON blobs so the
/// HistoryScreen tile renderer keeps working. New SmartHistory columns
/// (`is_pinned`, `input_hash`, `pin_label`, `pin_order`, `l1_json`) were
/// added in schema v2, `screen_id` in schema v3.
class TaxUKDatabaseAdapter implements DatabaseAdapter {
  const TaxUKDatabaseAdapter();

  static const _appKey = 'taxuk';
  // Fallback screen_id for legacy rows (pre-v3) and legacy VAT/CGT inserts
  // that bypass insertRow via DatabaseService.insert.
  static const _screenId = 'income_tax';

  // ── Insert ─────────────────────────────────────────────────────────────────

  @override
  Future<int> insertRow(Map<String, dynamic> row) async {
    final l2 = jsonDecode(row['l2_json'] as String) as Map<String, dynamic>;
    final savedAt = DateTime.fromMillisecondsSinceEpoch(row['saved_at'] as int);

    final inputs = (l2['inputs'] as Map?)?.cast<String, dynamic>() ?? l2;
    final results = (l2['results'] as Map?)?.cast<String, dynamic>() ?? {};

    return DatabaseService.instance.insertHistory({
      'timestamp': savedAt.toIso8601String(),
      'inputs': jsonEncode(inputs),
      'results': jsonEncode(results),
      'is_pinned': row['is_pinned'] ?? 0,
      'input_hash': row['result_hash'],
      'pin_label': row['pin_label'],
      'pin_order': row['pin_order'] ?? 0,
      'l1_json': row['l1_json'],
      'screen_id': row['screen_id'] ?? _screenId,
    });
  }

  // ── Query ──────────────────────────────────────────────────────────────────

  @override
  Future<List<Map<String, dynamic>>> getRows({
    required String appKey,
    String? screenId,
    bool? isPinned,
    int? limit,
  }) async {
    final all = await DatabaseService.instance.getAll(
      limit: limit ?? 999999,
    );
    return all
        .where((r) {
          if (screenId != null && r['screen_id'] != screenId) return false;
          if (isPinned != null) {
            return (r['is_pinned'] as int? ?? 0) == (isPinned ? 1 : 0);
          }
          return true;
        })
        .map(_toAdapterRow)
        .take(limit ?? 999999)
        .toList();
  }

  @override
  Future<Map<String, dynamic>?> getRowByHash({
    required String appKey,
    required String screenId,
    required String resultHash,
  }) async {
    final row =
        await DatabaseService.instance.getHistoryByHash(resultHash, screenId);
    return row == null ? null : _toAdapterRow(row);
  }

  // ── Update / Delete ────────────────────────────────────────────────────────

  @override
  Future<int> updateRow(int id, Map<String, dynamic> values) async {
    return DatabaseService.instance.updateHistoryEntry(id, values);
  }

  @override
  Future<int> deleteRow(int id) async {
    await DatabaseService.instance.deleteHistory(id);
    return 1;
  }

  // ── Count / Eviction ───────────────────────────────────────────────────────

  @override
  Future<int> countRows({required String appKey, bool? isPinned}) async {
    // Count all screens' rows — the ring buffer / pinned cap are app-wide,
    // not per-screen (matches DatabaseAdapter's countRows contract).
    final db = await DatabaseService.instance.db;
    String query = 'SELECT COUNT(*) as cnt FROM history';
    final args = <Object?>[];
    if (isPinned != null) {
      query += ' WHERE is_pinned = ?';
      args.add(isPinned ? 1 : 0);
    }
    final result = await db.rawQuery(query, args);
    return (result.first['cnt'] as int?) ?? 0;
  }

  @override
  Future<List<Map<String, dynamic>>> getOldestAutoSaves({
    required String appKey,
    required int limit,
  }) async {
    final db = await DatabaseService.instance.db;
    final rows = await db.rawQuery(
      'SELECT * FROM history WHERE is_pinned = 0 '
      'ORDER BY id ASC LIMIT ?',
      [limit],
    );
    return rows
        .map(_rawDecodeRow)
        .map(_toAdapterRow)
        .toList();
  }

  @override
  Future<List<Map<String, dynamic>>> getOldestPinned({
    required String appKey,
    required int limit,
  }) async {
    final db = await DatabaseService.instance.db;
    final rows = await db.rawQuery(
      'SELECT * FROM history WHERE is_pinned = 1 '
      'ORDER BY pin_order ASC LIMIT ?',
      [limit],
    );
    return rows
        .map(_rawDecodeRow)
        .map(_toAdapterRow)
        .toList();
  }

  // ── Mapping ────────────────────────────────────────────────────────────────

  Map<String, dynamic> _rawDecodeRow(Map<String, dynamic> r) {
    return {
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
      'screen_id': r['screen_id'] ?? _screenId,
    };
  }

  Map<String, dynamic> _toAdapterRow(Map<String, dynamic> r) {
    final timestamp = r['timestamp'] as String? ?? '';
    final savedAt = timestamp.isNotEmpty
        ? (DateTime.tryParse(timestamp)?.millisecondsSinceEpoch ?? 0)
        : 0;

    final inputs = r['inputs'] as Map<String, dynamic>;
    final results = r['results'] as Map<String, dynamic>;

    final l1Json = (r['l1_json'] as String?) ?? _buildDefaultL1Json(inputs, results);
    final l2Json = jsonEncode({'inputs': inputs, 'results': results});

    return {
      'id': r['id'],
      'app_key': _appKey,
      'screen_id': (r['screen_id'] as String?) ?? _screenId,
      'result_hash': (r['input_hash'] as String?) ?? '',
      'l1_json': l1Json,
      'l2_json': l2Json,
      'saved_at': savedAt,
      'is_pinned': (r['is_pinned'] as int?) ?? 0,
      'pin_label': r['pin_label'],
      'pin_order': (r['pin_order'] as int?) ?? 0,
    };
  }

  String _buildDefaultL1Json(
      Map<String, dynamic> inputs, Map<String, dynamic> results) {
    final gross = (inputs['gross'] as num?)?.toDouble() ?? 0;
    final net = (results['net'] as num?)?.toDouble() ?? 0;
    return jsonEncode({
      'title': 'Income Tax — £${gross.toStringAsFixed(0)} gross',
      'subtitle': 'Take-home: £${net.toStringAsFixed(0)}',
    });
  }
}
