import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'live_detection_state.dart';
import '../../../core/services/isolate_inference.dart';
import '../../../core/database/database_service.dart';
import '../../../core/services/ml_service.dart';
import '../../../../data/models/detection_models.dart';


class LiveDetectionCubit extends Cubit<LiveDetectionState> {
  final MLService _staticMlService;
  MLService get mlService => _staticMlService;
  
  CameraController? _cameraController;
  Interpreter? _interpreter;
  bool _isProcessing = false;
  
  // Konfigurasi model
  final int _inputSize = 640;
  final double _confThreshold = 0.25;

  LiveDetectionCubit(this._staticMlService) : super(LiveDetectionInitial());

  Future<void> initCameraAndModel() async {
    try {
      emit(LiveDetectionLoading());

      // Pastikan MLService statis sudah diinisialisasi
      await _staticMlService.init();

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
        imageFormatGroup: ImageFormatGroup.bgra8888, // WAJIB untuk performa 20fps tanpa manual convert
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

    _cameraController!.startImageStream((CameraImage image) async {
      // Manajemen Frame Dinamis: Jika AI masih memproses frame sebelumnya, buang frame baru ini!
      // Ini akan mencegah RAM penuh (buffer overflow) dan menyesuaikan FPS dengan spesifikasi HP secara otomatis.
      if (_isProcessing || _interpreter == null) return;
      _isProcessing = true;

      try {
        final detections = await IsolateInference.runInference(
          image,
          _interpreter!,
          _inputSize,
          _confThreshold,
        );

        // Log Debugging

        // print("✅--- Live AI Check: Ditemukan ${detections.length} objek ---");
        // if (detections.isNotEmpty) {
        //   final first = detections.first;
        //   print("📦 Sample Box 1: x=${first.x.toStringAsFixed(2)}, y=${first.y.toStringAsFixed(2)}, w=${first.w.toStringAsFixed(2)}, h=${first.h.toStringAsFixed(2)}, conf=${first.confidence.toStringAsFixed(2)}");
        // }

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
      
      // Cegah frame baru dari stream diproses
      final tempInterpreter = _interpreter;
      _interpreter = null;

      // KRITIS: Tunggu Isolate selesai membaca buffer YUV di memori Native.
      // Jika kita stopImageStream sekarang, buffer kamera akan dihapus oleh OS, 
      // dan Isolate akan crash (SIGSEGV) karena membaca memori yang sudah hangus.
      while (_isProcessing) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      
      // Hentikan stream (freeze) setelah aman
      await _cameraController!.stopImageStream();
      
      // Kembalikan interpreter untuk sesi berikutnya
      _interpreter = tempInterpreter;
      
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
      String diseaseId = "unknown";
      double topConfidence = 0.0;
      
      if (frozenState.detections.isNotEmpty) {
        final bestDetection = frozenState.detections.reduce((a, b) => a.confidence > b.confidence ? a : b);
        
        const List<String> diseaseIds = [
          'batang_sawit_sehat',
          'buah_sawit_sehat',
          'busuk_pucuk',
          'daun_sehat',
          'hama_tikus',
          'jamur_ganoderma',
        ];

        if (bestDetection.classIndex < diseaseIds.length) {
          diseaseId = diseaseIds[bestDetection.classIndex];
        }
        topConfidence = bestDetection.confidence;
      }

      final entry = HistoryEntry(
        imagePath: frozenState.imagePath,
        boxes: frozenState.detections,
        detectedAt: DateTime.now().millisecondsSinceEpoch,
        inferenceTimeMs: 0, // Not tracked separately here
        diseaseId: diseaseId,
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
    // 1. Putuskan referensi interpreter agar callback stream membuang frame baru
    final interpreterToClose = _interpreter;
    _interpreter = null;
    
    // 2. KRITIS: Tunggu isolate selesai bekerja. 
    // Jika kita men-dispose kamera saat Isolate masih membaca buffer YUV (native memory),
    // aplikasi akan langsung crash (SIGSEGV SEGV_MAPERR) karena OS Android menghancurkan buffer tersebut.
    while (_isProcessing) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
    
    // 3. Setelah isolate 100% aman dan selesai, baru kita hancurkan stream, kamera, dan AI.
    try {
      await _cameraController?.stopImageStream();
    } catch (_) {}
    _cameraController?.dispose();
    interpreterToClose?.close();
    
    return super.close();
  }
}
