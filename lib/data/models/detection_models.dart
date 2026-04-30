import 'dart:convert';

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
  final String topLabel;
  final double topConfidence;

  HistoryEntry({
    this.id, required this.imagePath, required this.boxes,
    required this.detectedAt, required this.inferenceTimeMs,
    required this.topLabel, required this.topConfidence,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'image_path': imagePath,
      'boxes': jsonEncode(boxes.map((b) => b.toMap()).toList()), // List di-encode jadi JSON String
      'detected_at': detectedAt,
      'inference_time_ms': inferenceTimeMs,
      'top_label': topLabel,
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
      topLabel: map['top_label'] ?? '',
      topConfidence: map['top_confidence']?.toDouble() ?? 0.0,
    );
  }
}