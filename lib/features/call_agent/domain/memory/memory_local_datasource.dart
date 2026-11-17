import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'memory_entry.dart';

class MemoryLocalDatasource {
  static Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDB();
    return _db!;
  }

  Future<Database> _initDB() async {
    final path = join(await getDatabasesPath(), 'sentravox_memory.db');

    return await openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE memory (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            number TEXT,
            key TEXT,
            value TEXT,
            UNIQUE(number, key)
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // v1 -> v2: eliminar duplicados acumulados y añadir unicidad.
        if (oldVersion < 2) {
          await db.execute('''
            DELETE FROM memory
            WHERE id NOT IN (
              SELECT MAX(id) FROM memory GROUP BY number, key
            )
          ''');
          await db.execute(
            'CREATE UNIQUE INDEX IF NOT EXISTS idx_memory_number_key ON memory(number, key)',
          );
        }
      },
    );
  }

  Future<void> save(MemoryEntry entry) async {
    final db = await database;
    await db.insert(
      'memory',
      {
        'number': entry.number,
        'key': entry.key,
        'value': entry.value,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<MemoryEntry>> getByNumber(String number) async {
    final db = await database;
    final result = await db.query(
      'memory',
      where: 'number = ?',
      whereArgs: [number],
    );

    return result.map((row) {
      return MemoryEntry(
        id: row['id'] as int,
        number: row['number'] as String,
        key: row['key'] as String,
        value: row['value'] as String,
      );
    }).toList();
  }
}
