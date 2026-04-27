import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'dart:math' as math;

class DetectionPage extends StatefulWidget {
  const DetectionPage({super.key});

  @override
  State<DetectionPage> createState() => _DetectionPageState();
}

double calculateIoU(Detection a, Detection b) {
  double x1 = math.max(a.x, b.x);
  double y1 = math.max(a.y, b.y);
  double x2 = math.min(a.x + a.w, b.x + b.w);
  double y2 = math.min(a.y + a.h, b.y + b.h);

  double interArea = math.max(0, x2 - x1) * math.max(0, y2 - y1);

  double unionArea = a.w * a.h + b.w * b.h - interArea;

  return interArea / unionArea;
}

List<Detection> applyNMS(List<Detection> boxes, double iouThreshold) {
  boxes.sort((a, b) => b.confidence.compareTo(a.confidence));

  List<Detection> selected = [];

  for (var box in boxes) {
    bool keep = true;

    for (var sel in selected) {
      double iou = calculateIoU(box, sel);
      if (iou > iouThreshold) {
        keep = false;
        break;
      }
    }

    if (keep) selected.add(box);
  }

  return selected;
}

class _DetectionPageState extends State<DetectionPage> {
  Interpreter? _interpreter;
  File? _image;

  List<Detection> detections = [];
  List<String> labels = [];

  final int inputSize = 640;
  final int numClasses = 3;

  final double confThreshold = 0.25; // lebih masuk akal
  final ImagePicker _picker = ImagePicker();

  int originalWidth = 0;
  int originalHeight = 0;

  @override
  void initState() {
    super.initState();
    loadModel();
  }

  // ================= MODEL =================

  Future<void> loadModel() async {
    debugPrint("[MODEL] Loading model...");
    _interpreter = await Interpreter.fromAsset('assets/best.tflite');
    debugPrint("[MODEL] Loaded");

    debugPrint("[MODEL] Loading labels...");
    final data = await DefaultAssetBundle.of(context)
        .loadString("assets/labels.txt");
    labels = data.split('\n');
    debugPrint("[MODEL] Labels loaded: ${labels.length}");
  }

  // ================= PREPROCESS =================
  img.Image letterbox(img.Image src) {
    int newSize = 640;

    double r = (newSize / src.width < newSize / src.height)
        ? newSize / src.width
        : newSize / src.height;

    int newW = (src.width * r).round();
    int newH = (src.height * r).round();

    img.Image resized = img.copyResize(src, width: newW, height: newH);

    img.Image canvas = img.Image(width: newSize, height: newSize);

    // warna padding YOLO (114,114,114)
    img.fill(canvas, color: img.ColorRgb8(114, 114, 114));

    int dx = (newSize - newW) ~/ 2;
    int dy = (newSize - newH) ~/ 2;

    // img.copyInto(canvas, resized, dstX: dx, dstY: dy);
    img.compositeImage(canvas, resized, dstX: dx, dstY: dy);

    return canvas;
  }

  Float32List preprocess(File imageFile) {
    debugPrint("[PREPROCESS] Start");

    img.Image image = img.decodeImage(imageFile.readAsBytesSync())!;
    img.Image resized = letterbox(image);

    var input = Float32List(1 * inputSize * inputSize * 3);

    int index = 0;
    for (int y = 0; y < inputSize; y++) {
      for (int x = 0; x < inputSize; x++) {
        final pixel = resized.getPixel(x, y);

        // 🔥 TEST 1: YOLO NORMAL
        input[index++] = pixel.r.toDouble();
        input[index++] = pixel.g.toDouble();
        input[index++] = pixel.b.toDouble();

        // 🔥 ALTERNATIVE (kalau mau tes)
        // input[index++] = (pixel.r - 127.5) / 127.5;
        // input[index++] = (pixel.g - 127.5) / 127.5;
        // input[index++] = (pixel.b - 127.5) / 127.5;
      }
    }

    debugPrint("[PREPROCESS] Done");
    return input;
  }

  double sigmoid(double x) {
    return 1 / (1 + math.exp(-x));
  }
  // ================= INFERENCE =================

  void runModel(File imageFile) {
    debugPrint("\n================ RUN MODEL =================");

    if (_interpreter == null) {
      debugPrint("[ERROR] Interpreter null");
      return;
    }

    debugPrint("INPUT TYPE: ${_interpreter!.getInputTensor(0).type}");
    debugPrint("OUTPUT TYPE: ${_interpreter!.getOutputTensor(0).type}");

    var input = preprocess(imageFile);

    var output = List.generate(
      1,
      (_) => List.generate(10, (_) => List.filled(8400, 0.0)),
    );

    _interpreter!.run(input.reshape([1, 640, 640, 3]), output);

    debugPrint("[INFERENCE] Done");

    // ================= BREAKPOINT 1 =================
    double maxObj = 0;
    double minObj = 999;

    for (int i = 0; i < 8400; i++) {
      double obj = output[0][4][i];
      if (obj > maxObj) maxObj = obj;
      if (obj < minObj) minObj = obj;
    }

    debugPrint("[CHECK] OBJ RANGE: min=$minObj max=$maxObj");

    // ================= BREAKPOINT 2 =================
    for (int i = 0; i < 5; i++) {
      double maxClass = 0;
      for (int c = 0; c < numClasses; c++) {
        double score = output[0][5 + c][i];
        if (score > maxClass) maxClass = score;
      }
      debugPrint("[CHECK] i=$i class=$maxClass");
    }

    // ================= POSTPROCESS =================
    debugPrint("[POSTPROCESS] Start");

    List<Detection> results = [];

    for (int i = 0; i < 8400; i++) {
      // 🔥 TEST SWITCH
      double obj = output[0][4][i];
      double maxClass = 0;
      int classIndex = -1;

      for (int c = 0; c < numClasses; c++) {
        double score = output[0][5 + c][i];

        // 🔥 AKTIFKAN INI kalau mau tes sigmoid
        // score = sigmoid(score);

        if (score > maxClass) {
          maxClass = score;
          classIndex = c;
        }
      }

      // 🔥 AKTIFKAN kalau mau tes sigmoid
      // obj = sigmoid(obj);

      double confidence = obj * maxClass;

      // 🔥 DEBUG EARLY SAMPLE
      if (i < 5) {
        debugPrint(
            "[SAMPLE] i=$i obj=$obj class=$maxClass conf=$confidence");
      }

      if (confidence > confThreshold) {
        double cx = output[0][0][i];
        double cy = output[0][1][i];
        double w = output[0][2][i];
        double h = output[0][3][i];

        bool normalized = cx <= 1 && cy <= 1;

        if (normalized) {
          cx *= originalWidth;
          cy *= originalHeight;
          w *= originalWidth;
          h *= originalHeight;
        }

        double x = cx - w / 2;
        double y = cy - h / 2;

        results.add(
          Detection(
            x: x,
            y: y,
            w: w,
            h: h,
            confidence: confidence,
            classIndex: classIndex,
          ),
        );
      }
    }

    debugPrint("[POSTPROCESS] Total detections: ${results.length}");

    final filtered = applyNMS(results, 0.5);

    debugPrint("[POSTPROCESS] After NMS: ${filtered.length}");

    setState(() {
      detections = results;
    });
  }
  // ================= IMAGE PICK =================

  Future<void> _pickImage(ImageSource source) async {
    try {
      debugPrint("[IMAGE] Picking image from $source");

      final XFile? pickedFile = await _picker.pickImage(source: source);

      if (pickedFile != null) {
        _image = File(pickedFile.path);

        img.Image decoded =
            img.decodeImage(_image!.readAsBytesSync())!;

        originalWidth = decoded.width;
        originalHeight = decoded.height;

        debugPrint("[IMAGE] Path: ${_image!.path}");
        debugPrint(
            "[IMAGE] Original size: $originalWidth x $originalHeight");

        setState(() {
          detections = [];
        });

        runModel(_image!);
      }
    } catch (e) {
      debugPrint("[ERROR] Image picking: $e");
    }
  }

  // ================= UI =================

  void _showPickerOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (_) => Wrap(
        children: [
          ListTile(
            title: const Text("Gallery"),
            onTap: () {
              Navigator.pop(context);
              _pickImage(ImageSource.gallery);
            },
          ),
          ListTile(
            title: const Text("Camera"),
            onTap: () {
              Navigator.pop(context);
              _pickImage(ImageSource.camera);
            },
          ),
        ],
      ),
    );
  }

  String getTopDetectionText() {
    if (_image == null) return "No image";
    if (detections.isEmpty) return "No detection";

    Detection best = detections.reduce(
        (a, b) => a.confidence > b.confidence ? a : b);

    String labelName =
        labels.isNotEmpty && best.classIndex < labels.length
            ? labels[best.classIndex]
            : "Class ${best.classIndex}";

    return "$labelName ${(best.confidence * 100).toStringAsFixed(1)}%";
  }

  // ================= BUILD =================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("YOLO Prototype")),
      body: Column(
        children: [
          Expanded(
            child: _image == null
                ? const Center(child: Text("No Image"))
                : LayoutBuilder(
                    builder: (context, constraints) {
                      double w = constraints.maxWidth;
                      double h = constraints.maxHeight;

                      // double scaleX = w / originalWidth;
                      // double scaleY = h / originalHeight;

                      double imageAspect = originalWidth / originalHeight;
                      double widgetAspect = w / h;

                      double displayWidth, displayHeight;
                      double offsetX = 0, offsetY = 0;

                      if (imageAspect > widgetAspect) {
                        displayWidth = w;
                        displayHeight = w / imageAspect;
                        offsetY = (h - displayHeight) / 2;
                      } else {
                        displayHeight = h;
                        displayWidth = h * imageAspect;
                        offsetX = (w - displayWidth) / 2;
                      }

                      double scaleX = displayWidth / originalWidth;
                      double scaleY = displayHeight / originalHeight;

                      debugPrint(
                          "[RENDER] scaleX=$scaleX scaleY=$scaleY");

                      return Stack(
                        children: [
                          Image.file(_image!,
                              width: w,
                              height: h,
                              fit: BoxFit.contain),

                          ...detections.map((d) {
                            return Positioned(
                              left: d.x * scaleX,
                              top: d.y * scaleY,
                              width: d.w * scaleX,
                              height: d.h * scaleY,
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                      color: Colors.red, width: 2),
                                ),
                                child: Text(
                                  "${labels.isNotEmpty ? labels[d.classIndex] : d.classIndex} ${(d.confidence * 100).toStringAsFixed(0)}%",
                                  style: const TextStyle(
                                      color: Colors.white,
                                      backgroundColor: Colors.black),
                                ),
                              ),
                            );
                          }),
                        ],
                      );
                    },
                  ),
          ),
          Text(getTopDetectionText()),
          ElevatedButton(
            onPressed: () => _showPickerOptions(context),
            child: const Text("Pick Image"),
          )
        ],
      ),
    );
  }
}

// ================= MODEL =================

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
}