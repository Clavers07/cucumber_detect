import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

void main() {
  runApp(const DetectionPage());
}

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
  final int inputSize = 640;
  final int numClasses = 3;
  final double confThreshold = 0.1;
  final double iouThreshold = 0.1;
  int originalWidth = 0;
  int originalHeight = 0;
  @override
  void initState() {
    super.initState();
    loadModel();
  }

  Future<void> loadModel() async {
    _interpreter = await Interpreter.fromAsset('assets/best.tflite');
    print("Model Loaded");
  }

  Future<void> loadLabels() async {
    final data = await DefaultAssetBundle.of(
      context,
    ).loadString("assets/labels.txt");
    labels = data.split('\n');
  }

  Future<void> pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final XFile? picked = await picker.pickImage(
      source: source,
      preferredCameraDevice: CameraDevice.front,
    );
    if (picked != null) {
      _image = File(picked.path);
      img.Image decoded = img.decodeImage(_image!.readAsBytesSync())!;
      originalWidth = decoded.width;
      originalHeight = decoded.height;
      await loadLabels();
      runModel(_image!);
    }
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

  // void runModel(File imageFile) {
  //   if (_interpreter == null) return;
  //   var input = preprocess(imageFile);
  //   var output = List.generate(
  //     1,
  //     (_) => List.generate(300, (_) => List.filled(6, 0.0)),
  //   );
  //   _interpreter!.run(input.reshape([1, 640, 640, 3]), output);
  //   List<Detection> results = [];
  //   for (int i = 0; i < 8400; i++) {
  //     double maxScore = 0;
  //     int classIndex = -1;
  //     for (int c = 0; c < numClasses; c++) {
  //       double classScore = output[0][4 + c][i];
  //       if (classScore > maxScore) {
  //         maxScore = classScore;
  //         classIndex = c;
  //       }
  //     }
  //     if (maxScore > confThreshold) {
  //       double x = output[0][0][i];
  //       double y = output[0][1][i];
  //       double w = output[0][2][i];
  //       double h = output[0][3][i];
  //       // OUTPUT MODEL ANDA NORMALIZED (0-1)
  //       x *= originalWidth;
  //       y *= originalHeight;
  //       w *= originalWidth;
  //       h *= originalHeight;
  //       results.add(
  //         Detection(
  //           x: x,
  //           y: y,
  //           w: w,
  //           h: h,
  //           confidence: maxScore,
  //           classIndex: classIndex,
  //         ),
  //       );
  //     }
  //   }
  //   detections = nonMaxSuppression(results);
  //   setState(() {});
  // }

  void runModel(File imageFile) {
  if (_interpreter == null) return;
  var input = preprocess(imageFile);
  
  // YOLO26 End-to-End shape: [1, 300, 6]
  var output = List.generate(1, (_) => 
                 List.generate(300, (_) => 
                   List.filled(6, 0.0)));

  _interpreter!.run(input.reshape([1, 640, 640, 3]), output);

  List<Detection> results = [];
  
  for (int i = 0; i < 300; i++) {
    double confidence = output[0][i][4];
    int classIndex = output[0][i][5].toInt();

    // Inside the for loop in runModel
    if (confidence > confThreshold) {
      print("DEBUG: Found ${labels[classIndex]} with $confidence confidence");
      // ... rest of your results.add logic
    }


    if (confidence > confThreshold) {
      // YOLO26 natively uses x1, y1, x2, y2 (normalized 0-640)
      double x1 = output[0][i][0];
      double y1 = output[0][i][1];
      double x2 = output[0][i][2];
      double y2 = output[0][i][3];

      // Convert to original image scale
      double finalX1 = x1 * (originalWidth / 640);
      double finalY1 = y1 * (originalHeight / 640);
      double finalW = (x2 - x1) * (originalWidth / 640);
      double finalH = (y2 - y1) * (originalHeight / 640);

      results.add(Detection(
        x: finalX1 + (finalW / 2), // Adjust based on your Detection class needs
        y: finalY1 + (finalH / 2),
        w: finalW,
        h: finalH,
        confidence: confidence,
        classIndex: classIndex,
      ));
    }
  }
  
  setState(() {
    // Note: YOLO26 is NMS-free, so you might not even need nonMaxSuppression()
    detections = results; 
  });
}


  List<Detection> nonMaxSuppression(List<Detection> boxes) {
    boxes.sort((a, b) => b.confidence.compareTo(a.confidence));
    List<Detection> finalBoxes = [];
    for (var box in boxes) {
      bool keep = true;
      for (var selected in finalBoxes) {
        if (iou(box, selected) > iouThreshold) {
          keep = false;
          break;
        }
      }
      if (keep) finalBoxes.add(box);
    }
    return finalBoxes;
  }

  double iou(Detection a, Detection b) {
    double x1 = max(a.left, b.left);
    double y1 = max(a.top, b.top);
    double x2 = min(a.right, b.right);
    double y2 = min(a.bottom, b.bottom);
    double interArea = max(0, x2 - x1) * max(0, y2 - y1);
    double unionArea = a.area + b.area - interArea;
    return unionArea == 0 ? 0 : interArea / unionArea;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text("Deteksi Bahasa Isyarat"),
        backgroundColor: Colors.white.withOpacity(1),
        elevation: 0,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xff1f1c2c), Color(0xff928dab)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: () => pickImage(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt),
                    label: const Text("Ambil Gambar"),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 25,
                        vertical: 15,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      backgroundColor: const Color(0xff4facfe),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Expanded(
                child: _image == null
                    ? const Center(
                        child: Text(
                          "Belum ada gambar",
                          style: TextStyle(color: Colors.white70, fontSize: 16),
                        ),
                      )
                    : LayoutBuilder(
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
                              Center(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(20),
                                  child: Image.file(
                                    _image!,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                              ...detections.map((d) {
                                return Positioned(
                                  left: d.left * scaleX + offsetX,
                                  top: d.top * scaleY + offsetY,
                                  width: d.w * scaleX,
                                  height: d.h * scaleY,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: Colors.greenAccent,
                                        width: 3,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Align(
                                      alignment: Alignment.topLeft,
                                      child: Container(
                                        color: Colors.greenAccent,
                                        padding: const EdgeInsets.all(3),
                                        child: Text(
                                          "${labels[d.classIndex]} ${(d.confidence * 100).toStringAsFixed(1)}%",
                                          style: const TextStyle(
                                            color: Colors.black,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ],
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
  double get left => x - w / 2;
  double get top => y - h / 2;
  double get right => x + w / 2;
  double get bottom => y + h / 2;
  double get area => w * h;
}
