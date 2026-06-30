import 'dart:convert';
import '../../features/dictionary/models/disease_model.dart';

// Model untuk menampung hasil satu bounding box (Murni tanpa UI)
class DetectionBox {
  final double x, y, w, h, confidence;
  final int classIndex;
  
  const DetectionBox({
    required this.x, required this.y, required this.w, required this.h,
    required this.confidence, required this.classIndex,
  });

  // Konversi ke Map untuk disimpan di SQLite (sebagai JSON)
  Map<String, dynamic> toMap() {
    return {
      'x': x, 'y': y, 'w': w, 'h': h,
      'confidence': confidence, 'classIndex': classIndex,
    };
  }

  factory DetectionBox.fromMap(Map<String, dynamic> map) {
    return DetectionBox(
      x: map['x']?.toDouble() ?? 0.0,
      y: map['y']?.toDouble() ?? 0.0,
      w: map['w']?.toDouble() ?? 0.0,
      h: map['h']?.toDouble() ?? 0.0,
      confidence: map['confidence']?.toDouble() ?? 0.0,
      classIndex: map['classIndex']?.toInt() ?? 0,
    );
  }
}

// Model untuk struktur tabel detection_history di SQLite
class HistoryEntry {
  final int? id;
  final String imagePath;
  final List<DetectionBox> boxes;
  final int detectedAt; // epoch ms
  final int inferenceTimeMs;
  final String diseaseId; // Refaktor dari topLabel menjadi diseaseId
  final double topConfidence;

  HistoryEntry({
    this.id, required this.imagePath, required this.boxes,
    required this.detectedAt, required this.inferenceTimeMs,
    required this.diseaseId, required this.topConfidence,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'image_path': imagePath,
      'boxes': jsonEncode(boxes.map((b) => b.toMap()).toList()), // List di-encode jadi JSON String
      'detected_at': detectedAt,
      'inference_time_ms': inferenceTimeMs,
      'disease_id': diseaseId,
      'top_confidence': topConfidence,
    };
  }

  factory HistoryEntry.fromMap(Map<String, dynamic> map) {
    final List<dynamic> boxesJson = jsonDecode(map['boxes'] as String);
    return HistoryEntry(
      id: map['id']?.toInt(),
      imagePath: map['image_path'] ?? '',
      boxes: boxesJson.map((b) => DetectionBox.fromMap(b)).toList(),
      detectedAt: map['detected_at']?.toInt() ?? 0,
      inferenceTimeMs: map['inference_time_ms']?.toInt() ?? 0,
      diseaseId: map['disease_id'] ?? '',
      topConfidence: map['top_confidence']?.toDouble() ?? 0.0,
    );
  }
}

// Model gabungan untuk UI yang butuh detail penyakit sekaligus data histori (hasil JOIN)
class HistoryWithDetail {
  final int id;
  final String imagePath;
  final List<DetectionBox> boxes;
  final int detectedAt;
  final int inferenceTimeMs;
  final double topConfidence;
  final DiseaseModel disease;

  HistoryWithDetail({
    required this.id,
    required this.imagePath,
    required this.boxes,
    required this.detectedAt,
    required this.inferenceTimeMs,
    required this.topConfidence,
    required this.disease,
  });

  factory HistoryWithDetail.fromMap(Map<String, dynamic> map) {
    final List<dynamic> boxesJson = jsonDecode(map['boxes'] as String);
    return HistoryWithDetail(
      id: map['history_id']?.toInt() ?? 0,
      imagePath: map['image_path'] ?? '',
      boxes: boxesJson.map((b) => DetectionBox.fromMap(b)).toList(),
      detectedAt: map['detected_at']?.toInt() ?? 0,
      inferenceTimeMs: map['inference_time_ms']?.toInt() ?? 0,
      topConfidence: map['top_confidence']?.toDouble() ?? 0.0,
      disease: DiseaseModel(
        id: map['disease_id'] ?? '',
        nama: map['disease_nama'] ?? '',
        namaLatin: map['disease_nama_latin'] ?? '',
        kategori: map['disease_kategori'] ?? '',
        deskripsi: map['disease_deskripsi'] ?? '',
        ciriCiri: List<String>.from(jsonDecode(map['disease_ciri_ciri'] ?? '[]')),
        penyebab: map['disease_penyebab'] ?? '',
        penanganan: List<String>.from(jsonDecode(map['disease_penanganan'] ?? '[]')),
        pencegahan: List<String>.from(jsonDecode(map['disease_pencegahan'] ?? '[]')),
      ),
    );
  }
}