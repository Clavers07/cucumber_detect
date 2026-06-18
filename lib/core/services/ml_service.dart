import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import '../../data/models/detection_models.dart';

class MLService {
  Interpreter? _interpreter;
  List<String> labels = [];

  // Konfigurasi asli yang tidak diubah
  final int inputSize = 640;
  final int numClasses = 6;
  final int numAnchors = 8400;
  final double confThreshold = 0.25;
  final double iouThreshold = 0.45;

  Future<void> init() async {
    await _loadModel();
    await _loadLabels();
  }

  Future<void> _loadLabels() async {
    try {
      final labelsData = await rootBundle.loadString('assets/labels.txt');
      labels = labelsData.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      debugPrint('✅ MLService: Labels loaded (${labels.length} classes)');
    } catch (e) {
      debugPrint('❌ MLService Error: Gagal memuat labels.txt - $e');
    }
  }

  Future<void> _loadModel() async {
    try {
      _interpreter = await Interpreter.fromAsset('assets/best_int8.tflite');
      debugPrint('✅ MLService: Model loaded');
    } catch (e) {
      debugPrint('❌ MLService Error: $e');
    }
  }

  void setLabels(List<String> loadedLabels) {
    labels = loadedLabels;
  }

  // Preprocess murni dari kode sebelumnya
  Float32List preprocess(File imageFile) {
    img.Image image = img.decodeImage(imageFile.readAsBytesSync())!;
    img.Image resized = img.copyResize(image, width: inputSize, height: inputSize);

    final input = Float32List(1 * inputSize * inputSize * 3);
    int idx = 0;
    for (int y = 0; y < inputSize; y++) {
      for (int x = 0; x < inputSize; x++) {
        final pixel = resized.getPixel(x, y);
        input[idx++] = pixel.r / 255.0;
        input[idx++] = pixel.g / 255.0;
        input[idx++] = pixel.b / 255.0;
      }
    }
    return input;
  }

  // Output direturn sebagai List<DetectionBox>, bukan memanggil setState
  Future<List<DetectionBox>> runInference(File imageFile) async {
    if (_interpreter == null) throw Exception('Interpreter is null');

    final input = preprocess(imageFile).reshape([1, inputSize, inputSize, 3]);
    final outputShape = _interpreter!.getOutputTensor(0).shape;
    final int rows = outputShape[1];
    final int numAnchorsDynamic = outputShape[2];
    final int numClassesDynamic = rows - 4;

    final output = List.generate(
      1, (_) => List.generate(rows, (_) => List<double>.filled(numAnchorsDynamic, 0.0))
    );

    _interpreter!.run(input, output);

    final List<DetectionBox> raw = [];
    for (int i = 0; i < numAnchorsDynamic; i++) {
      double maxScore = 0.0;
      int classIdx = 0;
      for (int c = 0; c < numClassesDynamic; c++) {
        final s = output[0][4 + c][i];
        if (s > maxScore) {
          maxScore = s;
          classIdx = c;
        }
      }
      if (maxScore < confThreshold) continue;

      final cx = output[0][0][i];
      final cy = output[0][1][i];
      final bw = output[0][2][i];
      final bh = output[0][3][i];

      raw.add(DetectionBox(
        x: cx - bw / 2,
        y: cy - bh / 2,
        w: bw,
        h: bh,
        confidence: maxScore,
        classIndex: classIdx,
      ));
    }

    return _nms(raw);
  }

  // NMS dan IOU asli dari _DetectionPageState
  List<DetectionBox> _nms(List<DetectionBox> dets) {
    dets.sort((a, b) => b.confidence.compareTo(a.confidence));
    final out = <DetectionBox>[];
    while (dets.isNotEmpty) {
      final best = dets.removeAt(0);
      out.add(best);
      dets.removeWhere((d) => d.classIndex == best.classIndex && _iou(best, d) > iouThreshold);
    }
    return out;
  }

  double _iou(DetectionBox a, DetectionBox b) {
    final ix1 = a.x > b.x ? a.x : b.x;
    final iy1 = a.y > b.y ? a.y : b.y;
    final ix2 = (a.x + a.w) < (b.x + b.w) ? (a.x + a.w) : (b.x + b.w);
    final iy2 = (a.y + a.h) < (b.y + b.h) ? (a.y + a.h) : (b.y + b.h);
    if (ix2 <= ix1 || iy2 <= iy1) return 0.0;
    final inter = (ix2 - ix1) * (iy2 - iy1);
    return inter / (a.w * a.h + b.w * b.h - inter);
  }
}