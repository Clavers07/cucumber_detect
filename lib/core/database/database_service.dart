import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../../data/models/detection_models.dart';

class DatabaseService {
  // Singleton pattern
  static final DatabaseService instance = DatabaseService._init();
  static Database? _database;

  DatabaseService._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('sawit_detect.db'); // Sesuai dengan project doc
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    // Sesuai Project Doc: Tabel detection_history
    await db.execute('''
      CREATE TABLE detection_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        image_path TEXT NOT NULL,
        boxes TEXT NOT NULL,
        detected_at INTEGER NOT NULL,
        inference_time_ms INTEGER NOT NULL,
        top_label TEXT NOT NULL,
        top_confidence REAL NOT NULL
      )
    ''');

    // Indexing untuk mempercepat query saat filter/search
    await db.execute('CREATE INDEX idx_detected_at ON detection_history (detected_at DESC)');
    await db.execute('CREATE INDEX idx_top_label ON detection_history (top_label)');
  }

  // --- CRUD OPERATIONS (Asynchronous) ---
  
  Future<int> insertHistory(HistoryEntry entry) async {
    final db = await instance.database;
    // Berjalan secara asinkronus tanpa memblokir UI thread
    return await db.insert('detection_history', entry.toMap());
  }

  Future<List<HistoryEntry>> getAllHistory() async {
    final db = await instance.database;
    final result = await db.query('detection_history', orderBy: 'detected_at DESC');
    
    return result.map((json) => HistoryEntry.fromMap(json)).toList();
  }
  
  Future<int> deleteHistory(int id) async {
    final db = await instance.database;
    return await db.delete('detection_history', where: 'id = ?', whereArgs: [id]);
  }
}