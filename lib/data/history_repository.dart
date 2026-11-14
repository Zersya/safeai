import 'dart:async';
import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../checking/link_checker.dart';
import '../checking/models.dart';

class HistoryRepository implements ResultStore {
  HistoryRepository(this._db);

  final Database _db;
  final _changes = StreamController<void>.broadcast();

  static const _maxRows = 500;

  static Future<HistoryRepository> open() async {
    final path = p.join(await getDatabasesPath(), 'blockai.db');
    final db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, _) => db.execute(
        'CREATE TABLE checks(id INTEGER PRIMARY KEY AUTOINCREMENT, url TEXT NOT NULL, '
        'final_url TEXT, verdict TEXT NOT NULL, reasons TEXT NOT NULL, '
        'source TEXT NOT NULL, checked_at INTEGER NOT NULL)',
      ),
    );
    return HistoryRepository(db);
  }

  Stream<void> get changes => _changes.stream;

  @override
  Future<CheckResult> insert(CheckResult result) async {
    final id = await _db.insert('checks', {
      'url': result.url,
      'final_url': result.finalUrl,
      'verdict': result.verdict.name,
      'reasons': jsonEncode([for (final r in result.reasons) r.name]),
      'source': result.source.name,
      'checked_at': result.checkedAt.millisecondsSinceEpoch,
    });
    await _db.rawDelete(
      'DELETE FROM checks WHERE id NOT IN '
      '(SELECT id FROM checks ORDER BY checked_at DESC, id DESC LIMIT $_maxRows)',
    );
    _changes.add(null);
    return result.withId(id);
  }

  Future<List<CheckResult>> all() async {
    final rows = await _db.query('checks', orderBy: 'checked_at DESC, id DESC');
    return rows.map(_decode).toList();
  }

  Future<void> clear() async {
    await _db.delete('checks');
    _changes.add(null);
  }

  static CheckResult _decode(Map<String, Object?> row) {
    final reasons = <ReasonCode>[];
    try {
      for (final name in jsonDecode(row['reasons'] as String) as List) {
        final match = ReasonCode.values.where((r) => r.name == name);
        if (match.isNotEmpty) reasons.add(match.first);
      }
    } on FormatException {
      // Corrupt reasons column: show the row without reasons.
    }
    return CheckResult(
      id: row['id'] as int,
      url: row['url'] as String,
      finalUrl: row['final_url'] as String?,
      verdict: Verdict.values.firstWhere(
        (v) => v.name == row['verdict'],
        orElse: () => Verdict.unchecked,
      ),
      reasons: reasons,
      source: LinkSource.values.firstWhere(
        (s) => s.name == row['source'],
        orElse: () => LinkSource.manual,
      ),
      checkedAt: DateTime.fromMillisecondsSinceEpoch(row['checked_at'] as int),
    );
  }
}
