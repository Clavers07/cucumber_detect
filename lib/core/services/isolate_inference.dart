import 'dart:isolate';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import '../../data/models/detection_models.dart';
import '../utils/image_utils.dart';

class IsolateInference {
  static const String _modelPath = 'assets/best_float32.tflite';

  static Future<List<DetectionBox>> runInference(CameraImage cameraImage, Interpreter interpreter, int inputSize, double confThreshold) async {
    // Kumpulkan data yang bisa di-serialize untuk dikirim ke Isolate
    final List<Uint8List> planes = cameraImage.planes.map((p) => p.bytes).toList();
    final List<int> bytesPerRow = cameraImage.planes.map((p) => p.bytesPerRow).toList();
    final List<int> bytesPerPixel = cameraImage.planes.map((p) => p.bytesPerPixel ?? 1).toList();

    final inputData = _InferenceModel(
      planes: planes,
      width: cameraImage.width,
      height: cameraImage.height,
      bytesPerRow: bytesPerRow,
      bytesPerPixel: bytesPerPixel,
      formatGroup: cameraImage.format.group,
      inputSize: inputSize,
      interpreterAddress: interpreter.address,
      confThreshold: confThreshold,
    );

    return await Isolate.run(() => _inferenceTask(inputData));
  }

  static List<DetectionBox> _inferenceTask(_InferenceModel data) {
    // 1. Rekonstruksi gambar dari bytes (YUV -> RGB)
    final imgData = _convertCameraImage(data);
    if (imgData == null) return [];

    // 2. Resize & Normalize
    img.Image resized = img.copyResize(imgData, width: data.inputSize, height: data.inputSize);
    final input = Float32List(1 * data.inputSize * data.inputSize * 3);
    int idx = 0;
    for (int y = 0; y < data.inputSize; y++) {
      for (int x = 0; x < data.inputSize; x++) {
        final pixel = resized.getPixel(x, y);
        input[idx++] = pixel.r / 255.0;
        input[idx++] = pixel.g / 255.0;
        input[idx++] = pixel.b / 255.0;
      }
    }

    // 3. Re-attach ke Interpreter dari address
    final interpreter = Interpreter.fromAddress(data.interpreterAddress);

    // 4. Run Model
    final outputShape = interpreter.getOutputTensor(0).shape;
    final int rows = outputShape[1];
    final int numAnchors = outputShape[2];
    final int numClasses = rows - 4;

    final output = List.generate(
        1, (_) => List.generate(rows, (_) => List<double>.filled(numAnchors, 0.0))
    );

    interpreter.run(input.reshape([1, data.inputSize, data.inputSize, 3]), output);

    // 5. Post-process
    final List<DetectionBox> raw = [];
    double absoluteMaxScore = 0.0;
    
    for (int i = 0; i < numAnchors; i++) {
      double maxScore = 0.0;
      int classIdx = 0;
      for (int c = 0; c < numClasses; c++) {
        final s = output[0][4 + c][i];
        if (s > maxScore) {
          maxScore = s;
          classIdx = c;
        }
      }
      
      if (maxScore > absoluteMaxScore) {
        absoluteMaxScore = maxScore;
      }

      if (maxScore < data.confThreshold) continue;

      final cx = output[0][0][i];
      final cy = output[0][1][i];
      final bw = output[0][2][i];
      final bh = output[0][3][i];

      // Normalize coordinates
      final normalizedX = (cx - bw / 2) / data.inputSize;
      final normalizedY = (cy - bh / 2) / data.inputSize;
      final normalizedW = bw / data.inputSize;
      final normalizedH = bh / data.inputSize;

      raw.add(DetectionBox(
        x: normalizedX.clamp(0.0, 1.0),
        y: normalizedY.clamp(0.0, 1.0),
        w: normalizedW.clamp(0.0, 1.0),
        h: normalizedH.clamp(0.0, 1.0),
        confidence: maxScore,
        classIndex: classIdx,
      ));
    }

    print('📊 IsolateInference: Max score = $absoluteMaxScore, raw detections above threshold = ${raw.length}');
    return _nms(raw, 0.45);
  }

  static img.Image? _convertCameraImage(_InferenceModel image) {
    if (image.formatGroup == ImageFormatGroup.bgra8888) {
      final imgData = img.Image.fromBytes(
        width: image.width,
        height: image.height,
        bytes: image.planes[0].buffer,
        order: img.ChannelOrder.bgra,
      );
      // ROTASI: Sensor kamera fisik adalah landscape (berputar 90 derajat).
      // Kita harus memutar frame BGRA8888 sebesar 90 derajat searah jarum jam
      // agar AI melihat gambar dalam orientasi portrait yang tegak.
      return img.copyRotate(imgData, angle: 90);
    } else if (image.formatGroup == ImageFormatGroup.yuv420) {
      // YUV420 Fallback for Android devices that don't support BGRA8888
      final int width = image.width;
      final int height = image.height;
      final img.Image imgData = img.Image(width: width, height: height);

      final yBuffer = image.planes[0];
      final uBuffer = image.planes[1];
      final vBuffer = image.planes[2];

      final int yRowStride = image.bytesPerRow[0];
      final int uvRowStride = image.bytesPerRow[1];
      final int uvPixelStride = image.bytesPerPixel[1];

      for (int y = 0; y < height; y++) {
        int uvRow = y >> 1;
        for (int x = 0; x < width; x++) {
          int uvCol = x >> 1;
          int yIndex = (y * yRowStride) + x;
          int uvIndex = (uvRow * uvRowStride) + (uvCol * uvPixelStride);

          int yp = yBuffer[yIndex];
          int up = uBuffer[uvIndex];
          int vp = vBuffer[uvIndex];

          // Konversi standar YUV ke RGB dengan offset yang benar (+135 untuk green)
          int r = (yp + vp * 1436 / 1024 - 179).round().clamp(0, 255);
          int g = (yp - up * 46549 / 131072 - vp * 93604 / 131072 + 135).round().clamp(0, 255);
          int b = (yp + up * 1814 / 1024 - 227).round().clamp(0, 255);

          imgData.setPixelRgb(x, y, r, g, b);
        }
      }
      
      // ROTASI: Sensor kamera Android biasanya landscape (rotasi 90 derajat)
      return img.copyRotate(imgData, angle: 90);
    }
    
    print("Error: Isolate menerima format selain BGRA8888/YUV420: ${image.formatGroup}");
    return null;
  }

  static List<DetectionBox> _nms(List<DetectionBox> dets, double iouThreshold) {
    dets.sort((a, b) => b.confidence.compareTo(a.confidence));
    final out = <DetectionBox>[];
    while (dets.isNotEmpty) {
      final best = dets.removeAt(0);
      out.add(best);
      dets.removeWhere((d) => d.classIndex == best.classIndex && _iou(best, d) > iouThreshold);
    }
    return out;
  }

  static double _iou(DetectionBox a, DetectionBox b) {
    final ix1 = a.x > b.x ? a.x : b.x;
    final iy1 = a.y > b.y ? a.y : b.y;
    final ix2 = (a.x + a.w) < (b.x + b.w) ? (a.x + a.w) : (b.x + b.w);
    final iy2 = (a.y + a.h) < (b.y + b.h) ? (a.y + a.h) : (b.y + b.h);
    if (ix2 <= ix1 || iy2 <= iy1) return 0.0;
    final inter = (ix2 - ix1) * (iy2 - iy1);
    return inter / (a.w * a.h + b.w * b.h - inter);
  }
}

class _InferenceModel {
  final List<Uint8List> planes;
  final int width;
  final int height;
  final List<int> bytesPerRow;
  final List<int> bytesPerPixel;
  final ImageFormatGroup formatGroup;
  final int inputSize;
  final int interpreterAddress;
  final double confThreshold;

  _InferenceModel({
    required this.planes,
    required this.width,
    required this.height,
    required this.bytesPerRow,
    required this.bytesPerPixel,
    required this.formatGroup,
    required this.inputSize,
    required this.interpreterAddress,
    required this.confThreshold,
  });
}
