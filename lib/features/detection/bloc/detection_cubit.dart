import 'dart:io';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../../../core/services/ml_service.dart';
import '../../../core/database/database_service.dart';
import '../../../data/models/detection_models.dart';
import 'detection_state.dart';

class DetectionCubit extends Cubit<DetectionState> {
  final MLService _mlService;
  final DatabaseService _dbService = DatabaseService.instance;
  final ImagePicker _picker = ImagePicker();

  DetectionCubit(this._mlService) : super(DetectionInitial());

  // Mengambil gambar (Kamera/Galeri) dan langsung menjalankan deteksi
  Future<void> pickImageAndDetect(ImageSource source) async {
    try {
      final XFile? picked = await _picker.pickImage(source: source);
      if (picked == null) return; // User membatalkan picker

      emit(const DetectionLoading('Memproses gambar & AI...'));
      
      final File imageFile = File(picked.path);
      
      // Catat waktu mulai inferensi
      final stopwatch = Stopwatch()..start();
      
      // Panggil ML Service
      final detections = await _mlService.runInference(imageFile);
      
      stopwatch.stop();
      final inferenceTime = stopwatch.elapsedMilliseconds;

      // Persiapkan data untuk disimpan ke SQLite jika ada deteksi
      if (detections.isNotEmpty) {
        // Cari objek dengan confidence tertinggi
        final topDetection = detections.reduce((a, b) => a.confidence > b.confidence ? a : b);
        
        // Simpan gambar secara lokal agar tidak hilang saat cache Android dibersihkan
        final savedImagePath = await _saveImageLocally(imageFile);
        
        final String topLabelName = _mlService.labels.isNotEmpty && topDetection.classIndex < _mlService.labels.length 
            ? _mlService.labels[topDetection.classIndex] 
            : 'Class ${topDetection.classIndex}';

        // Buat model histori
        final historyEntry = HistoryEntry(
          imagePath: savedImagePath,
          boxes: detections,
          detectedAt: DateTime.now().millisecondsSinceEpoch,
          inferenceTimeMs: inferenceTime,
          topLabel: topLabelName,
          topConfidence: topDetection.confidence,
        );

        // Simpan ke SQLite via Background Service (Asinkronus)
        await _dbService.insertHistory(historyEntry);
      }

      emit(DetectionSuccess(
        image: imageFile,
        detections: detections,
        inferenceTime: inferenceTime,
        labels: _mlService.labels,
      ));

    } catch (e) {
      emit(DetectionError('Gagal memproses gambar: $e'));
    }
  }

  // Fungsi utilitas untuk mengamankan file gambar dari temporary folder ke app document
  Future<String> _saveImageLocally(File imageFile) async {
    final directory = await getApplicationDocumentsDirectory();
    final fileName = '${DateTime.now().millisecondsSinceEpoch}_${path.basename(imageFile.path)}';
    final savedImage = await imageFile.copy('${directory.path}/$fileName');
    return savedImage.path;
  }

  void resetState() {
    emit(DetectionInitial());
  }
}