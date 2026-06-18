import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'live_detection_state.dart';
import '../../../core/services/isolate_inference.dart';
import '../../../core/database/database_service.dart';
import '../../../core/services/ml_service.dart';
import '../../../../data/models/detection_models.dart';
import 'package:flutter/services.dart';

class LiveDetectionCubit extends Cubit<LiveDetectionState> {
  final MLService _staticMlService;
  MLService get mlService => _staticMlService;
  
  CameraController? _cameraController;
  Interpreter? _interpreter;
  bool _isProcessing = false;
  List<String> _labels = [];
  
  // Konfigurasi model
  final int _inputSize = 640;
  final double _confThreshold = 0.25;

  LiveDetectionCubit(this._staticMlService) : super(LiveDetectionInitial());

  Future<void> initCameraAndModel() async {
    try {
      emit(LiveDetectionLoading());

      // Pastikan MLService statis sudah diinisialisasi
      await _staticMlService.init();

      // 1. Load Labels
      final labelsData = await rootBundle.loadString('assets/labels.txt');
      _labels = labelsData.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

      // 2. Load Interpreter untuk stream (tetap dipertahankan address-nya)
      _interpreter = await Interpreter.fromAsset('assets/best_float16.tflite');

      // 3. Init Camera
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        emit(const LiveDetectionError("Tidak ada kamera yang ditemukan."));
        return;
      }

      _cameraController = CameraController(
        cameras.first,
        ResolutionPreset.medium, // Medium agar FPS tetap bagus
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.yuv420 : ImageFormatGroup.bgra8888,
      );

      await _cameraController!.initialize();

      // Mulai stream
      _startStream();

    } catch (e) {
      emit(LiveDetectionError("Gagal inisialisasi: $e"));
    }
  }

  void _startStream() {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;

    emit(LiveDetectionActive(
      cameraController: _cameraController!,
      currentDetections: const [],
    ));

    int frameCount = 0;

    _cameraController!.startImageStream((CameraImage image) async {
      frameCount++;
      // Proses hanya 1 dari setiap 10 frame untuk menghindari penumpukan memori (buffer overflow)
      if (frameCount % 10 != 0) return;

      if (_isProcessing || _interpreter == null) return;
      _isProcessing = true;

      try {
        final detections = await IsolateInference.runInference(
          image,
          _interpreter!,
          _inputSize,
          _confThreshold,
        );

        print("✅--- Live AI Check: Ditemukan ${detections.length} objek ---");

        if (state is LiveDetectionActive) {
          emit((state as LiveDetectionActive).copyWith(currentDetections: detections));
        }
      } catch (e) {
        print("LiveDetection Stream Error: $e");
      } finally {
        _isProcessing = false;
      }
    });
  }

  Future<void> freezeAndCapture() async {
    if (state is! LiveDetectionActive || _cameraController == null) return;

    try {
      emit(LiveDetectionLoading());
      
      // Hentikan stream (freeze)
      await _cameraController!.stopImageStream();
      
      // Tunggu sebentar agar kamera stabil setelah stop stream
      await Future.delayed(const Duration(milliseconds: 300));

      // Ambil foto kualitas tinggi
      final XFile imageFile = await _cameraController!.takePicture();

      // Proses foto HD dengan MLService statis untuk mendapatkan box yang lebih presisi pada gambar besar
      final File file = File(imageFile.path);
      final detections = await _staticMlService.runInference(file);

      emit(LiveDetectionFrozen(
        imageFile: imageFile,
        detections: detections,
        imagePath: imageFile.path,
      ));
    } catch (e) {
      emit(LiveDetectionError("Gagal mengambil gambar: $e"));
    }
  }

  Future<void> saveToDatabase() async {
    if (state is! LiveDetectionFrozen) return;
    
    final frozenState = state as LiveDetectionFrozen;
    
    try {
      String topLabel = "Unknown";
      double topConfidence = 0.0;
      
      if (frozenState.detections.isNotEmpty) {
        final bestDetection = frozenState.detections.reduce((a, b) => a.confidence > b.confidence ? a : b);
        if (bestDetection.classIndex < _labels.length) {
          topLabel = _labels[bestDetection.classIndex];
        } else {
          topLabel = "Class ${bestDetection.classIndex}";
        }
        topConfidence = bestDetection.confidence;
      }

      final entry = HistoryEntry(
        imagePath: frozenState.imagePath,
        boxes: frozenState.detections,
        detectedAt: DateTime.now().millisecondsSinceEpoch,
        inferenceTimeMs: 0, // Not tracked separately here
        topLabel: topLabel,
        topConfidence: topConfidence,
      );

      await DatabaseService.instance.insertHistory(entry);
      
      // Kembali ke mode live setelah berhasil simpan
      resumeLive();
    } catch (e) {
      emit(LiveDetectionError("Gagal menyimpan: $e"));
    }
  }

  void resumeLive() {
    if (_cameraController != null && _cameraController!.value.isInitialized) {
      _startStream();
    }
  }

  @override
  Future<void> close() async {
    _cameraController?.stopImageStream();
    _cameraController?.dispose();
    
    // Tunggu isolate selesai bekerja sebelum menghancurkan interpreter C++
    // Mencegah crash SIGSEGV jika pengguna keluar halaman saat AI sedang memproses frame
    int maxWait = 20; // max 1 detik
    while (_isProcessing && maxWait > 0) {
      await Future.delayed(const Duration(milliseconds: 50));
      maxWait--;
    }
    
    _interpreter?.close();
    return super.close();
  }
}
