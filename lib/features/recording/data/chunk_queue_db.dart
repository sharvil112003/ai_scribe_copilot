import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../../recording/domain/models.dart';

class ChunkQueueDb {
  static Database? _db;

  static Future<Database> _open() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = join(dir.path, 'chunk_queue.db');
    return openDatabase(path, version: 1, onCreate: (db, _) async {
      await db.execute('''
      CREATE TABLE chunks(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sessionId TEXT,
        chunkNumber INTEGER,
        filePath TEXT,
        mimeType TEXT,
        status TEXT,
        retries INTEGER DEFAULT 0,
        createdAt INTEGER
      );
      ''');
      await db.execute('CREATE INDEX idx_chunks_status ON chunks(status)');
    });
  }

  static Future<Database> get _database async => _db ??= await _open();

  static Future<int> insert(ChunkItem c) async {
    final db = await _database;
    return db.insert('chunks', c.toMap());
  }

  static Future<List<ChunkItem>> nextBatch({int limit = 5}) async {
    final db = await _database;
    final rows = await db.query('chunks',
        where: 'status IN (?, ?)', whereArgs: ['pending','failed'],
        orderBy: 'createdAt ASC', limit: limit);
    return rows.map(ChunkItem.fromMap).toList();
  }

  static Future<void> updateStatus(int id, String status) async {
    final db = await _database;
    await db.update('chunks', {'status': status}, where: 'id=?', whereArgs: [id]);
  }

  static Future<void> incRetry(int id) async {
    final db = await _database;
    await db.rawUpdate('UPDATE chunks SET retries = retries + 1 WHERE id=?',[id]);
  }

  static Future<int> pendingCount() async {
    final db = await _database;
    final r = await db.rawQuery("SELECT COUNT(*) c FROM chunks WHERE status IN ('pending','failed')");
    return (r.first['c'] as int?) ?? 0;
  }

  static Future<void> clearUploadedOlderThan(Duration d) async {
    final db = await _database;
    final cutoff = DateTime.now().subtract(d).millisecondsSinceEpoch;
    await db.delete('chunks',
        where: "status='uploaded' AND createdAt<?", whereArgs: [cutoff]);
  }
}
