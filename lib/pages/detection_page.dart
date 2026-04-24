import 'dart:io';
import 'dart:math';
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
  
  // Konfigurasi Model Anda
  final int inputSize = 640;
  final int numClasses = 3;
  final double confThreshold = 0.1;
  final double iouThreshold = 0.1;
  int originalWidth = 0;
  int originalHeight = 0;

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    loadModel();
  }

  // --- LOGIKA TFLITE (Dipertahankan dari kode asli Anda) ---

  Future<void> loadModel() async {
    _interpreter = await Interpreter.fromAsset('assets/best.tflite');
    print("Model Loaded");
  }

  Future<void> loadLabels() async {
    final data = await DefaultAssetBundle.of(context).loadString("assets/labels.txt");
    labels = data.split('\n');
  }

  Float32List preprocess(File imageFile) {
    img.Image image = img.decodeImage(imageFile.readAsBytesSync())!;
    img.Image resized = img.copyResize(image, width: 640, height: 640);
    var input = Float32List(1 * 640 * 640 * 3);
    int index = 0;
    for (int y = 0; y < inputSize; y++) {
      for (int x = 0; x < inputSize; x++) {
        final pixel = resized.getPixel(x, y);
        input[index++] = pixel.r / 255.0;
        input[index++] = pixel.g / 255.0;
        input[index++] = pixel.b / 255.0;
      }
    }
    return input;
  }

  void runModel(File imageFile) {
    print("🚀 RUN MODEL CALLED");
    print("🧠 INPUT SHAPE: ${_interpreter!.getInputTensor(0).shape}");
    print("🧠 OUTPUT SHAPE: ${_interpreter!.getOutputTensor(0).shape}");
    print("🧠 OUTPUT TYPE: ${_interpreter!.getOutputTensor(0).type}");
    if (_interpreter == null) return;
    var input = preprocess(imageFile);

    // YOLO26 End-to-End shape: [1, 300, 6]
    var output = List.generate(
      1,
      (_) => List.generate(10, (_) => List.filled(8400, 0.0)),
    );

    _interpreter!.run(input.reshape([1, 640, 640, 3]), output);

    List<Detection> results = [];

    // for (int i = 0; i < 300; i++) {
    //   double confidence = output[0][i][4];
    //   int classIndex = output[0][i][5].toInt();

    //   if (confidence > confThreshold) {
    //     // YOLO26 natively uses x1, y1, x2, y2 (normalized 0-640)
    //     double x1 = output[0][i][0];
    //     double y1 = output[0][i][1];
    //     double x2 = output[0][i][2];
    //     double y2 = output[0][i][3];

    //     // Convert to original image scale
    //     double finalX1 = x1 * originalWidth;
    //     double finalY1 = y1 * originalHeight;
    //     double finalW = (x2 - x1) * originalWidth;
    //     double finalH = (y2 - y1) * originalHeight;

    //     results.add(
    //       Detection(
    //         x: finalX1, 
    //         y: finalY1,
    //         w: finalW,
    //         h: finalH,
    //         confidence: confidence,
    //         classIndex: classIndex,
    //       ),
    //     );
    //   }
    // }
    int rawCount = 0;
    double maxObj = 0;

    for (int i = 0; i < 8400; i++) {
      double obj = output[0][4][i];
      if (obj > 0.01) rawCount++;
      if (obj > maxObj) maxObj = obj;
    }

    for (int i = 0; i < 8400; i++) {
      double obj = output[0][4][i];

      double maxClass = 0;
      int classIndex = -1;

      for (int c = 0; c < numClasses; c++) {
        double score = output[0][5 + c][i];
        if (score > maxClass) {
          maxClass = score;
          classIndex = c;
        }
      }

      double confidence = obj * maxClass;

      if (confidence > confThreshold) {
        double cx = output[0][0][i];
        double cy = output[0][1][i];
        double w = output[0][2][i];
        double h = output[0][3][i];

        /// CHECK NORMALIZATION
        bool normalized = cx <= 1 && cy <= 1;

        double finalX = normalized ? cx * originalWidth : cx;
        double finalY = normalized ? cy * originalHeight : cy;
        double finalW = normalized ? w * originalWidth : w;
        double finalH = normalized ? h * originalHeight : h;

        /// DEBUG FINAL BBOX
        if (results.length < 3) {
          print("📐 FINAL BOX:");
          print("x=$finalX y=$finalY w=$finalW h=$finalH");
        }

        // kalau normalized
        cx *= originalWidth;
        cy *= originalHeight;
        w *= originalWidth;
        h *= originalHeight;

        results.add(
          Detection(
            x: cx,
            y: cy,
            w: w,
            h: h,
            confidence: confidence,
            classIndex: classIndex,
          ),
        );
      }
    }
    setState(() {
      detections = results;
    });
  }

  // --- LOGIKA UI PICKER ---

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(source: source);
      if (pickedFile != null) {
        setState(() {
          _image = File(pickedFile.path);
          detections = []; // Reset deteksi
        });
        
        // Ambil dimensi asli untuk perhitungan bounding box
        img.Image decoded = img.decodeImage(_image!.readAsBytesSync())!;
        originalWidth = decoded.width;
        originalHeight = decoded.height;
        
        await loadLabels();
        runModel(_image!);
      }
    } catch (e) {
      debugPrint("Error picking image: $e");
    }
  }

  void _showPickerOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext bc) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 20),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                border: Border(top: BorderSide(color: Colors.white.withOpacity(0.2), width: 1.5)),
              ),
              child: Wrap(
                children: <Widget>[
                  const Padding(
                    padding: EdgeInsets.only(bottom: 15),
                    child: Center(
                      child: Text("Pilih Sumber Gambar", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.photo_library, color: Colors.cyanAccent),
                    title: const Text('Galeri', style: TextStyle(color: Colors.white)),
                    onTap: () {
                      Navigator.of(context).pop();
                      _pickImage(ImageSource.gallery);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.photo_camera, color: Colors.greenAccent),
                    title: const Text('Kamera', style: TextStyle(color: Colors.white)),
                    onTap: () {
                      Navigator.of(context).pop();
                      _pickImage(ImageSource.camera);
                    },
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // Menentukan teks hasil deteksi tertinggi untuk ditampilkan di panel kaca
  String getTopDetectionText() {
    if (_image == null) return "Menunggu input...";
    if (detections.isEmpty) return "Memproses atau tidak ada objek...";
    
    // Cari deteksi dengan confidence tertinggi
    Detection best = detections.reduce((curr, next) => curr.confidence > next.confidence ? curr : next);
    
    // Pastikan label sudah di-load agar tidak index out of bounds
    String labelName = labels.isNotEmpty && best.classIndex < labels.length 
        ? labels[best.classIndex] 
        : "Class ${best.classIndex}";
        
    return "Terdeteksi: $labelName (${(best.confidence * 100).toStringAsFixed(1)}%)";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text("Deteksi Real-time"),
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
        child: Column(
          children: [
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
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.image_not_supported_outlined, size: 50, color: Colors.white38),
                            SizedBox(height: 10),
                            Text("Belum ada gambar", style: TextStyle(color: Colors.white54)),
                          ],
                        ),
                      )
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        // --- LOGIKA LAYOUT BUILDER & STACK (Dipertahankan) ---
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            double widgetWidth = constraints.maxWidth;
                            double widgetHeight = constraints.maxHeight;
                            double imageAspect = originalWidth / originalHeight;
                            double widgetAspect = widgetWidth / widgetHeight;
                            double displayWidth;
                            double displayHeight;
                            double offsetX = 0;
                            double offsetY = 0;
                            
                            if (imageAspect > widgetAspect) {
                              displayWidth = widgetWidth;
                              displayHeight = widgetWidth / imageAspect;
                              offsetY = (widgetHeight - displayHeight) / 2;
                            } else {
                              displayHeight = widgetHeight;
                              displayWidth = widgetHeight * imageAspect;
                              offsetX = (widgetWidth - displayWidth) / 2;
                            }
                            double scaleX = displayWidth / originalWidth;
                            double scaleY = displayHeight / originalHeight;

                            return Stack(
                              children: [
                                Center(child: Image.file(_image!, fit: BoxFit.contain)),
                                ...detections.map((d) {
                                  // Menyesuaikan style bounding box agar cocok dengan tema
                                  return Positioned(
                                    left: d.left * scaleX + offsetX,
                                    top: d.top * scaleY + offsetY,
                                    width: d.w * scaleX,
                                    height: d.h * scaleY,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        border: Border.all(color: Colors.cyanAccent, width: 3),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                            decoration: const BoxDecoration(
                                              color: Colors.cyanAccent,
                                              borderRadius: BorderRadius.only(topLeft: Radius.circular(4), bottomRight: Radius.circular(8)),
                                            ),
                                            child: Text(
                                              labels.isNotEmpty && d.classIndex < labels.length 
                                                ? "${labels[d.classIndex]} ${(d.confidence * 100).toStringAsFixed(0)}%" 
                                                : "${(d.confidence * 100).toStringAsFixed(0)}%",
                                              style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }),
                              ],
                            );
                          },
                        ),
                      ),
              ),
            ),
            
            // --- PANEL HASIL BAWAH ---
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
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text("Hasil Analisis AI", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 10),
                        // Menampilkan deteksi tertinggi
                        Text(
                          getTopDetectionText(), 
                          style: const TextStyle(color: Colors.cyanAccent, fontSize: 16, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 30),
                        ElevatedButton.icon(
                          onPressed: () => _showPickerOptions(context), 
                          icon: const Icon(Icons.add_a_photo),
                          label: const Text("Pilih Gambar"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white.withOpacity(0.15),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            side: BorderSide(color: Colors.white.withOpacity(0.3)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                          ),
                        )
                      ],
                    ),
                  ),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}

// Class asli Anda
class Detection {
  final double x, y, w, h, confidence;
  final int classIndex;
  Detection({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.confidence,
    required this.classIndex,
  });
  double get left => x;
  double get top => y;
  double get right => x + w / 2;
  double get bottom => y + h / 2;
  double get area => w * h;
}