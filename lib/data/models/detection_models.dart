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
  final int detectedAt; // epoch ms
  final int inferenceTimeMs;
  final String diseaseId; // Refaktor dari topLabel menjadi diseaseId
  final double topConfidence;
  final List<String> diseaseList;
  final List<double> confidenceList;
  final List<int> countList;
  final List<DetectionBox> boxList;

  HistoryEntry({
    this.id,
    required this.imagePath,
    required this.detectedAt,
    required this.inferenceTimeMs,
    required this.diseaseId,
    required this.topConfidence,
    required this.diseaseList,
    required this.confidenceList,
    required this.countList,
    required this.boxList,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'image_path': imagePath,
      'detected_at': detectedAt,
      'inference_time_ms': inferenceTimeMs,
      'disease_id': diseaseId,
      'top_confidence': topConfidence,
      'disease_list': jsonEncode(diseaseList),
      'confidence_list': jsonEncode(confidenceList),
      'count_list': jsonEncode(countList),
      'box_list': jsonEncode(boxList.map((x) => x.toMap()).toList()),
    };
  }

  factory HistoryEntry.fromMap(Map<String, dynamic> map) {
    return HistoryEntry(
      id: map['id']?.toInt(),
      imagePath: map['image_path'] ?? '',
      detectedAt: map['detected_at']?.toInt() ?? 0,
      inferenceTimeMs: map['inference_time_ms']?.toInt() ?? 0,
      diseaseId: map['disease_id'] ?? '',
      topConfidence: map['top_confidence']?.toDouble() ?? 0.0,
      diseaseList: List<String>.from(jsonDecode(map['disease_list'] as String? ?? '[]')),
      confidenceList: List<double>.from(jsonDecode(map['confidence_list'] as String? ?? '[]').map((x) => x.toDouble())),
      countList: List<int>.from(jsonDecode(map['count_list'] as String? ?? '[]').map((x) => x.toInt())),
      boxList: List<DetectionBox>.from(
        (jsonDecode(map['box_list'] as String? ?? '[]') as List)
            .map((x) => DetectionBox.fromMap(x as Map<String, dynamic>))
      ),
    );
  }
}

// Model gabungan untuk UI yang butuh detail penyakit sekaligus data histori (hasil JOIN)
class HistoryWithDetail {
  final int id;
  final String imagePath;
  final int detectedAt;
  final int inferenceTimeMs;
  final double topConfidence;
  final DiseaseModel disease;
  final List<String> diseaseList;
  final List<double> confidenceList;
  final List<int> countList;
  final List<DetectionBox> boxList;

  HistoryWithDetail({
    required this.id,
    required this.imagePath,
    required this.detectedAt,
    required this.inferenceTimeMs,
    required this.topConfidence,
    required this.disease,
    required this.diseaseList,
    required this.confidenceList,
    required this.countList,
    required this.boxList,
  });

  // Mengembalikan list ringkasan untuk di-render di UI, misal: "2x Jamur Ganoderma (85.5%)"
  List<String> get labelSummaries {
    final List<String> summaries = [];
    for (int i = 0; i < diseaseList.length; i++) {
      if (i >= confidenceList.length || i >= countList.length) break;
      final String id = diseaseList[i];
      final String name = _snakeToTitleCase(id);
      final int count = countList[i];
      final double confidence = confidenceList[i];
      final percentage = (confidence * 100).toStringAsFixed(1);
      summaries.add("${count}x $name ($percentage%)");
    }
    return summaries;
  }

  factory HistoryWithDetail.fromMap(Map<String, dynamic> map) {
    final String diseaseId = map['disease_id'] ?? '';
    return HistoryWithDetail(
      id: map['history_id']?.toInt() ?? 0,
      imagePath: map['image_path'] ?? '',
      detectedAt: map['detected_at']?.toInt() ?? 0,
      inferenceTimeMs: map['inference_time_ms']?.toInt() ?? 0,
      topConfidence: map['top_confidence']?.toDouble() ?? 0.0,
      disease: DiseaseModel(
        id: diseaseId,
        nama: map['disease_nama'] ?? _snakeToTitleCase(diseaseId),
        namaLatin: map['disease_nama_latin'] ?? 'Elaeis guineensis',
        kategori: map['disease_kategori'] ?? 'Lainnya',
        deskripsi: map['disease_deskripsi'] ?? 'Detail informasi penyakit belum tersedia.',
        ciriCiri: map['disease_ciri_ciri'] != null 
            ? List<String>.from(jsonDecode(map['disease_ciri_ciri'])) 
            : const [],
        penyebab: map['disease_penyebab'] ?? 'Tidak diketahui',
        penanganan: map['disease_penanganan'] != null 
            ? List<String>.from(jsonDecode(map['disease_penanganan'])) 
            : const [],
        pencegahan: map['disease_pencegahan'] != null 
            ? List<String>.from(jsonDecode(map['disease_pencegahan'])) 
            : const [],
      ),
      diseaseList: List<String>.from(jsonDecode(map['disease_list'] as String? ?? '[]')),
      confidenceList: List<double>.from(jsonDecode(map['confidence_list'] as String? ?? '[]').map((x) => x.toDouble())),
      countList: List<int>.from(jsonDecode(map['count_list'] as String? ?? '[]').map((x) => x.toInt())),
      boxList: List<DetectionBox>.from(
        (jsonDecode(map['box_list'] as String? ?? '[]') as List)
            .map((x) => DetectionBox.fromMap(x as Map<String, dynamic>))
      ),
    );
  }
}

// Fungsi helper global untuk mengonversi snake_case database ke Title Case visual
String _snakeToTitleCase(String text) {
  if (text.isEmpty) return '';
  if (text == 'unknown') return 'Unknown';
  return text.split('_').map((word) {
    if (word.isEmpty) return '';
    return word[0].toUpperCase() + word.substring(1);
  }).join(' ');
}