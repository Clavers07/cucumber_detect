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
      _interpreter = await Interpreter.fromAsset('assets/best_float32.tflite');
      debugPrint('✅ MLService: Model loaded');
      
      // Print input tensor details to check layout (NCHW vs NHWC)
      final inputTensor = _interpreter!.getInputTensor(0);
      debugPrint('📊 MLService Model Input: shape=${inputTensor.shape}, type=${inputTensor.type}, name=${inputTensor.name}');
      
      final outputTensor = _interpreter!.getOutputTensor(0);
      debugPrint('📊 MLService Model Output: shape=${outputTensor.shape}, type=${outputTensor.type}, name=${outputTensor.name}');
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

    // Logging output shape and sample values for debugging
    debugPrint('📊 MLService: Inference completed. Output shape: $outputShape');
    
    // Print raw values for first and middle anchors to inspect data range
    if (numAnchorsDynamic > 0) {
      debugPrint('📊 MLService Raw Anchor 0: coords=[${output[0][0][0]}, ${output[0][1][0]}, ${output[0][2][0]}, ${output[0][3][0]}], classes=[${List.generate(numClassesDynamic, (c) => output[0][4 + c][0].toStringAsFixed(4)).join(', ')}]');
    }
    if (numAnchorsDynamic > 4000) {
      debugPrint('📊 MLService Raw Anchor 4000: coords=[${output[0][0][4000]}, ${output[0][1][4000]}, ${output[0][2][4000]}, ${output[0][3][4000]}], classes=[${List.generate(numClassesDynamic, (c) => output[0][4 + c][4000].toStringAsFixed(4)).join(', ')}]');
    }
    
    double absoluteMaxScore = -double.infinity;
    double absoluteMinScore = double.infinity;
    bool hasNegativeScores = false;
    
    final List<DetectionBox> raw = [];
    for (int i = 0; i < numAnchorsDynamic; i++) {
      double maxScore = -double.infinity;
      int classIdx = 0;
      for (int c = 0; c < numClassesDynamic; c++) {
        final s = output[0][4 + c][i];
        if (s < absoluteMinScore) absoluteMinScore = s;
        if (s > absoluteMaxScore) absoluteMaxScore = s;
        if (s < 0) hasNegativeScores = true;
        
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

      // YOLOv8/v12 outputs absolute pixel values (0-640).
      // We divide by inputSize (640) to normalize them to [0, 1] range
      // so that they render correctly in the BoundingBoxOverlay widget.
      final normalizedX = (cx - bw / 2) / inputSize;
      final normalizedY = (cy - bh / 2) / inputSize;
      final normalizedW = bw / inputSize;
      final normalizedH = bh / inputSize;

      raw.add(DetectionBox(
        x: normalizedX.clamp(0.0, 1.0),
        y: normalizedY.clamp(0.0, 1.0),
        w: normalizedW.clamp(0.0, 1.0),
        h: normalizedH.clamp(0.0, 1.0),
        confidence: maxScore,
        classIndex: classIdx,
      ));
    }

    debugPrint('📊 MLService: Score Range = [$absoluteMinScore, $absoluteMaxScore]');
    debugPrint('📊 MLService: Has negative scores (Logits)? = $hasNegativeScores');
    debugPrint('📊 MLService: Total raw detections above threshold ($confThreshold) = ${raw.length}');
    if (raw.isNotEmpty) {
      debugPrint('📊 MLService: Sample detection: x=${raw[0].x.toStringAsFixed(2)}, y=${raw[0].y.toStringAsFixed(2)}, w=${raw[0].w.toStringAsFixed(2)}, h=${raw[0].h.toStringAsFixed(2)}, conf=${raw[0].confidence.toStringAsFixed(2)}, class=${raw[0].classIndex}');
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