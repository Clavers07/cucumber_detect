import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../../data/models/detection_models.dart';
import '../../features/dictionary/models/disease_model.dart';

class DatabaseService {
  // Singleton pattern
  static final DatabaseService instance = DatabaseService._init();
  static Database? _database;

  DatabaseService._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('sawit_detect.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 4, // Versi 4 untuk menambahkan kolom box_list koordinat bounding box
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    // 1. Buat Tabel Penyakit (Read-Only)
    await db.execute('''
      CREATE TABLE penyakit (
        id TEXT PRIMARY KEY,
        nama TEXT NOT NULL,
        nama_latin TEXT NOT NULL,
        kategori TEXT NOT NULL,
        deskripsi TEXT NOT NULL,
        ciri_ciri TEXT NOT NULL, -- JSON string list
        penyebab TEXT NOT NULL,
        penanganan TEXT NOT NULL, -- JSON string list
        pencegahan TEXT NOT NULL -- JSON string list
      )
    ''');

    // 2. Buat Tabel Riwayat Deteksi dengan Relasi Foreign Key
    await db.execute('''
      CREATE TABLE detection_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        image_path TEXT NOT NULL,
        disease_list TEXT NOT NULL,
        confidence_list TEXT NOT NULL,
        count_list TEXT NOT NULL,
        box_list TEXT NOT NULL,
        detected_at INTEGER NOT NULL,
        inference_time_ms INTEGER NOT NULL,
        disease_id TEXT NOT NULL, -- Relasi Foreign Key
        top_confidence REAL NOT NULL,
        FOREIGN KEY (disease_id) REFERENCES penyakit (id) ON DELETE RESTRICT
      )
    ''');

    // Buat index untuk mempercepat pencarian/sorting
    await db.execute('CREATE INDEX idx_detected_at ON detection_history (detected_at DESC)');
    await db.execute('CREATE INDEX idx_disease_id ON detection_history (disease_id)');

    // 3. Inject data awal secara otomatis dari assets/data/diseases.json
    await _injectInitialDiseases(db);
  }

  // Handle migrasi jika versi database sebelumnya adalah versi < 4
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 4) {
      await db.execute('DROP TABLE IF EXISTS detection_history');
      await db.execute('DROP TABLE IF EXISTS penyakit');
      await _createDB(db, newVersion);
    }
  }

  // Menginjeksi data penyakit dari JSON ke DB SQLite saat pertama kali dibuat
  Future<void> _injectInitialDiseases(Database db) async {
    try {
      final jsonString = await rootBundle.loadString('assets/data/diseases.json');
      final List<dynamic> jsonList = jsonDecode(jsonString);
      
      final batch = db.batch();
      for (final item in jsonList) {
        batch.insert('penyakit', {
          'id': item['id'],
          'nama': item['nama'],
          'nama_latin': item['nama_latin'],
          'kategori': item['kategori'],
          'deskripsi': item['deskripsi'],
          'ciri_ciri': jsonEncode(item['ciri_ciri']),
          'penyebab': item['penyebab'],
          'penanganan': jsonEncode(item['penanganan']),
          'pencegahan': jsonEncode(item['pencegahan']),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
      debugPrint('✅ DatabaseService: Initial diseases successfully injected to SQLite');
    } catch (e) {
      debugPrint('❌ DatabaseService Error: Failed to inject initial diseases - $e');
    }
  }

  // --- METHODS QUERY PENYAKIT (READ-ONLY) ---

  Future<List<DiseaseModel>> getAllDiseases() async {
    final db = await instance.database;
    final result = await db.query('penyakit', orderBy: 'nama ASC');
    
    return result.map((json) {
      return DiseaseModel(
        id: json['id'] as String,
        nama: json['nama'] as String,
        namaLatin: json['nama_latin'] as String,
        kategori: json['kategori'] as String,
        deskripsi: json['deskripsi'] as String,
        ciriCiri: List<String>.from(jsonDecode(json['ciri_ciri'] as String)),
        penyebab: json['penyebab'] as String,
        penanganan: List<String>.from(jsonDecode(json['penanganan'] as String)),
        pencegahan: List<String>.from(jsonDecode(json['pencegahan'] as String)),
      );
    }).toList();
  }

  Future<DiseaseModel?> getDiseaseById(String id) async {
    final db = await instance.database;
    final result = await db.query('penyakit', where: 'id = ?', whereArgs: [id], limit: 1);
    
    if (result.isEmpty) return null;
    final json = result.first;
    return DiseaseModel(
      id: json['id'] as String,
      nama: json['nama'] as String,
      namaLatin: json['nama_latin'] as String,
      kategori: json['kategori'] as String,
      deskripsi: json['deskripsi'] as String,
      ciriCiri: List<String>.from(jsonDecode(json['ciri_ciri'] as String)),
      penyebab: json['penyebab'] as String,
      penanganan: List<String>.from(jsonDecode(json['penanganan'] as String)),
      pencegahan: List<String>.from(jsonDecode(json['pencegahan'] as String)),
    );
  }

  // --- CRUD HISTORY OPERATIONS ---
  
  Future<int> insertHistory(HistoryEntry entry) async {
    final db = await instance.database;
    return await db.insert('detection_history', entry.toMap());
  }

  Future<List<HistoryEntry>> getAllHistory() async {
    final db = await instance.database;
    final result = await db.query('detection_history', orderBy: 'detected_at DESC');
    
    return result.map((json) => HistoryEntry.fromMap(json)).toList();
  }

  // Mengambil seluruh riwayat beserta relasi data penyakit secara JOIN
  Future<List<HistoryWithDetail>> getAllHistoryWithDetail() async {
    final db = await instance.database;
    
    final result = await db.rawQuery('''
      SELECT 
        h.id AS history_id,
        h.image_path,
        h.disease_list,
        h.confidence_list,
        h.count_list,
        h.box_list,
        h.detected_at,
        h.inference_time_ms,
        h.top_confidence,
        p.id AS disease_id,
        p.nama AS disease_nama,
        p.nama_latin AS disease_nama_latin,
        p.kategori AS disease_kategori,
        p.deskripsi AS disease_deskripsi,
        p.ciri_ciri AS disease_ciri_ciri,
        p.penyebab AS disease_penyebab,
        p.penanganan AS disease_penanganan,
        p.pencegahan AS disease_pencegahan
      FROM detection_history h
      LEFT JOIN penyakit p ON h.disease_id = p.id
      ORDER BY h.detected_at DESC
    ''');
    
    return result.map((row) => HistoryWithDetail.fromMap(row)).toList();
  }
  
  Future<int> deleteHistory(int id) async {
    final db = await instance.database;
    return await db.delete('detection_history', where: 'id = ?', whereArgs: [id]);
  }
}