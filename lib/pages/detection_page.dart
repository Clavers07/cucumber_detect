import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class DetectionPage extends StatefulWidget {
  const DetectionPage({super.key});
  @override
  State<DetectionPage> createState() => _DetectionPageState();
}

class _DetectionPageState extends State<DetectionPage> {
  Interpreter? _interpreter;
  File? _image;
  List<Detection> detections = [];
  List<String> labels = [];

  // ──────────────────────────────────────────────
  // KONFIGURASI MODEL
  // Output Netron: [1, 10, 8400]
  // numClasses = 10 - 4 = 6  ← sesuaikan jika beda!
  // ──────────────────────────────────────────────
  final int inputSize  = 640;
  final int numClasses = 6;      // ganti sesuai jumlah class model kamu
  final int numAnchors = 8400;
  final double confThreshold = 0.25;
  final double iouThreshold  = 0.45;

  int originalWidth  = 0;
  int originalHeight = 0;

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await loadLabels();
    await loadModel();
  }

  Future<void> loadModel() async {
    _interpreter = await Interpreter.fromAsset('assets/best_int8.tflite');
    debugPrint('✅ Model loaded');
    debugPrint('   Input  shape: ${_interpreter!.getInputTensor(0).shape}');
    debugPrint('   Output shape: ${_interpreter!.getOutputTensor(0).shape}');
    debugPrint('   Input  type : ${_interpreter!.getInputTensor(0).type}');
  }

  Future<void> loadLabels() async {
    final data = await DefaultAssetBundle.of(context).loadString('assets/labels.txt');
    labels = data.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    debugPrint('✅ Labels: $labels');
  }

  // ──────────────────────────────────────────────
  // PREPROCESS — int8 model pakai Uint8List (0–255), bukan Float32
  // ──────────────────────────────────────────────
  Float32List preprocess(File imageFile) {
    img.Image image   = img.decodeImage(imageFile.readAsBytesSync())!;
    img.Image resized = img.copyResize(image, width: inputSize, height: inputSize);

    final input = Float32List (1 * inputSize * inputSize * 3);
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

  // ──────────────────────────────────────────────
  // RUN MODEL
  // Output [1][4+numClasses][8400]:
  //   row 0–3 = cx, cy, w, h (piksel, skala 0–640)
  //   row 4.. = class scores
  // ──────────────────────────────────────────────
  void runModel(File imageFile) {
    if (_interpreter == null) { debugPrint('❌ Interpreter null'); return; }

    final input = preprocess(imageFile).reshape([1, inputSize, inputSize, 3]);

    final int rows = 4 + numClasses;
    final output = List.generate(1,
      (_) => List.generate(rows, (_) => List<double>.filled(numAnchors, 0.0)));

    _interpreter!.run(input, output);

    // DEBUG — hapus setelah masalah ketemu
// Print 5 anchor pertama untuk lihat nilai mentah
for (int i = 0; i < 5; i++) {
  debugPrint('Anchor $i:');
  debugPrint('  bbox : ${output[0][0][i].toStringAsFixed(4)}, ${output[0][1][i].toStringAsFixed(4)}, ${output[0][2][i].toStringAsFixed(4)}, ${output[0][3][i].toStringAsFixed(4)}');
  for (int c = 0; c < numClasses; c++) {
    debugPrint('  class[$c]: ${output[0][4+c][i].toStringAsFixed(6)}');
  }
}

// Print juga anchor dengan score TERTINGGI
double globalMax = 0; int globalAnchor = 0; int globalClass = 0;
for (int i = 0; i < numAnchors; i++) {
  for (int c = 0; c < numClasses; c++) {
    if (output[0][4+c][i] > globalMax) {
      globalMax = output[0][4+c][i];
      globalAnchor = i; globalClass = c;
    }
  }
}
debugPrint('MAX SCORE: anchor=$globalAnchor, class=$globalClass, score=$globalMax');
debugPrint('  bbox: cx=${output[0][0][globalAnchor]}, cy=${output[0][1][globalAnchor]}, w=${output[0][2][globalAnchor]}, h=${output[0][3][globalAnchor]}');
    debugPrint('✅ Inference selesai');

    final List<Detection> raw = [];
    for (int i = 0; i < numAnchors; i++) {
      double maxScore = 0.0;
      int classIdx = 0;
      for (int c = 0; c < numClasses; c++) {
        final s = output[0][4 + c][i];
        if (s > maxScore) { maxScore = s; classIdx = c; }
      }
      if (maxScore < confThreshold) continue;

      // cx,cy,w,h dalam piksel (0–640) → konversi ke koordinat gambar asli
      final cx = output[0][0][i];
      final cy = output[0][1][i];
      final bw = output[0][2][i];
      final bh = output[0][3][i];

      raw.add(Detection(
        x: cx - bw / 2,  // normalized 0–1
        y: cy - bh / 2,
        w: bw,
        h: bh,
        confidence: maxScore,
        classIndex:  classIdx,
      ));
    }

    debugPrint('Raw detections sebelum NMS: ${raw.length}');
    final result = _nms(raw);
    debugPrint('Detections setelah NMS: ${result.length}');
    setState(() => detections = result);
  }

  // ──────────────────────────────────────────────
  // NMS
  // ──────────────────────────────────────────────
  List<Detection> _nms(List<Detection> dets) {
    dets.sort((a, b) => b.confidence.compareTo(a.confidence));
    final out = <Detection>[];
    while (dets.isNotEmpty) {
      final best = dets.removeAt(0);
      out.add(best);
      dets.removeWhere((d) => d.classIndex == best.classIndex && _iou(best, d) > iouThreshold);
    }
    return out;
  }

  double _iou(Detection a, Detection b) {
    final ix1 = a.x > b.x ? a.x : b.x;
    final iy1 = a.y > b.y ? a.y : b.y;
    final ix2 = (a.x + a.w) < (b.x + b.w) ? (a.x + a.w) : (b.x + b.w);
    final iy2 = (a.y + a.h) < (b.y + b.h) ? (a.y + a.h) : (b.y + b.h);
    if (ix2 <= ix1 || iy2 <= iy1) return 0.0;
    final inter = (ix2 - ix1) * (iy2 - iy1);
    return inter / (a.w * a.h + b.w * b.h - inter);
  }

  // ──────────────────────────────────────────────
  // IMAGE PICKER
  // ──────────────────────────────────────────────
  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? picked = await _picker.pickImage(source: source);
      if (picked == null) return;
      final file    = File(picked.path);
      final decoded = img.decodeImage(file.readAsBytesSync())!;
      setState(() {
        _image = file; detections = [];
        originalWidth = decoded.width; originalHeight = decoded.height;
      });
      runModel(file);
    } catch (e) {
      debugPrint('❌ Error: $e');
    }
  }

  void _showPickerOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 20),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              border: Border(top: BorderSide(color: Colors.white.withOpacity(0.2), width: 1.5)),
            ),
            child: Wrap(children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 15),
                child: Center(child: Text('Pilih Sumber Gambar',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: Colors.cyanAccent),
                title: const Text('Galeri', style: TextStyle(color: Colors.white)),
                onTap: () { Navigator.pop(context); _pickImage(ImageSource.gallery); },
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera, color: Colors.greenAccent),
                title: const Text('Kamera', style: TextStyle(color: Colors.white)),
                onTap: () { Navigator.pop(context); _pickImage(ImageSource.camera); },
              ),
              const SizedBox(height: 20),
            ]),
          ),
        ),
      ),
    );
  }

  String getTopDetectionText() {
    if (_image == null) return 'Menunggu input...';
    if (detections.isEmpty) return 'Tidak ada objek terdeteksi';
    final best = detections.reduce((a, b) => a.confidence > b.confidence ? a : b);
    final name = (labels.isNotEmpty && best.classIndex < labels.length)
        ? labels[best.classIndex] : 'Class ${best.classIndex}';
    return 'Terdeteksi: $name (${(best.confidence * 100).toStringAsFixed(1)}%)';
  }

  // ──────────────────────────────────────────────
  // BUILD
  // ──────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Deteksi Real-time'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xff1e293b), Color(0xff0f172a)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Column(children: [
          Expanded(
            flex: 3,
            child: Container(
              margin: const EdgeInsets.only(top: 100, left: 20, right: 20, bottom: 20),
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: _image == null
                  ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.image_not_supported_outlined, size: 50, color: Colors.white38),
                      SizedBox(height: 10),
                      Text('Belum ada gambar', style: TextStyle(color: Colors.white54)),
                    ]))
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: LayoutBuilder(builder: (context, constraints) {
                        final ww = constraints.maxWidth;
                        final wh = constraints.maxHeight;
                        final ia = originalWidth / originalHeight;
                        final wa = ww / wh;
                        double dw, dh, ox = 0, oy = 0;
                        if (ia > wa) { dw = ww; dh = ww / ia; oy = (wh - dh) / 2; }
                        else         { dh = wh; dw = wh * ia; ox = (ww - dw) / 2; }
                        final sx = dw / originalWidth;
                        final sy = dh / originalHeight;

                        return Stack(children: [
                          Center(child: Image.file(_image!, fit: BoxFit.contain)),
                          ...detections.map((d) => Positioned(
                            left:  d.x * dw + ox,
                            top:   d.y * dh + oy,
                            width: d.w * dw,
                            height: d.h * dh,
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.cyanAccent, width: 3),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Align(
                                alignment: Alignment.topLeft,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                  decoration: const BoxDecoration(
                                    color: Colors.cyanAccent,
                                    borderRadius: BorderRadius.only(
                                      topLeft: Radius.circular(4), bottomRight: Radius.circular(8)),
                                  ),
                                  child: Text(
                                    (labels.isNotEmpty && d.classIndex < labels.length)
                                        ? '${labels[d.classIndex]} ${(d.confidence * 100).toStringAsFixed(0)}%'
                                        : 'cls${d.classIndex} ${(d.confidence * 100).toStringAsFixed(0)}%',
                                    style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                            ),
                          )),
                        ]);
                      }),
                    ),
            ),
          ),

          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(30),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  border: Border(top: BorderSide(color: Colors.white.withOpacity(0.1), width: 1.5)),
                ),
                child: SafeArea(
                  top: false,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Text('Hasil Analisis AI',
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 10),
                    Text(getTopDetectionText(),
                        style: const TextStyle(color: Colors.cyanAccent, fontSize: 16, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 30),
                    ElevatedButton.icon(
                      onPressed: () => _showPickerOptions(context),
                      icon: const Icon(Icons.add_a_photo),
                      label: const Text('Pilih Gambar'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white.withOpacity(0.15),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        side: BorderSide(color: Colors.white.withOpacity(0.3)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class Detection {
  final double x, y, w, h, confidence;
  final int classIndex;
  const Detection({
    required this.x, required this.y, required this.w, required this.h,
    required this.confidence, required this.classIndex,
  });
  double get area => w * h;
}