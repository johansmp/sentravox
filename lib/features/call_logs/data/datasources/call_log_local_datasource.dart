import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../../domain/entities/call_log.dart';

class CallLogLocalDatasource {
  static Database? _db;

  /// v2 añadió la columna `outcome`.
  /// v3 añadió `sentiment` y `lead_score` (CRM/lead detection).
  static const int _schemaVersion = 3;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDB();
    return _db!;
  }

  Future<Database> _initDB() async {
    final path = join(await getDatabasesPath(), 'sentravox_logs.db');

    return await openDatabase(
      path,
      version: _schemaVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE call_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            number TEXT,
            transcript TEXT,
            intent TEXT,
            risk REAL,
            summary TEXT,
            timestamp TEXT,
            outcome TEXT NOT NULL DEFAULT '${CallOutcome.agent}',
            sentiment TEXT NOT NULL DEFAULT 'neutro',
            lead_score REAL NOT NULL DEFAULT 0
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // Las llamadas ya guardadas venían todas del agente.
          await db.execute(
            "ALTER TABLE call_logs ADD COLUMN outcome TEXT NOT NULL "
            "DEFAULT '${CallOutcome.agent}'",
          );
        }
        if (oldVersion < 3) {
          await db.execute(
            "ALTER TABLE call_logs ADD COLUMN sentiment TEXT NOT NULL "
            "DEFAULT 'neutro'",
          );
          await db.execute(
            "ALTER TABLE call_logs ADD COLUMN lead_score REAL NOT NULL DEFAULT 0",
          );
        }
      },
    );
  }

  Future<void> insertLog(CallLogEntry entry) async {
    final db = await database;

    await db.insert('call_logs', {
      'number': entry.number,
      'transcript': entry.transcript,
      'intent': entry.intent,
      'risk': entry.risk,
      'summary': entry.summary,
      'timestamp': entry.timestamp.toIso8601String(),
      'outcome': entry.outcome,
      'sentiment': entry.sentiment,
      'lead_score': entry.leadScore,
    });
  }

  Future<List<CallLogEntry>> getLogs() async {
    final db = await database;
    final result = await db.query('call_logs', orderBy: 'timestamp DESC');

    return result.map(_fromRow).toList();
  }

  CallLogEntry _fromRow(Map<String, Object?> row) {
    return CallLogEntry(
      id: row['id'] as int?,
      number: (row['number'] as String?) ?? 'desconocido',
      transcript: (row['transcript'] as String?) ?? '',
      intent: (row['intent'] as String?) ?? 'sin_intencion',
      risk: (row['risk'] as num?)?.toDouble() ?? 0,
      summary: (row['summary'] as String?) ?? '',
      timestamp:
          DateTime.tryParse((row['timestamp'] as String?) ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0),
      outcome: (row['outcome'] as String?) ?? CallOutcome.agent,
      sentiment: (row['sentiment'] as String?) ?? 'neutro',
      leadScore: (row['lead_score'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
