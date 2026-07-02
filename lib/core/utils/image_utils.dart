import 'dart:io';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../../data/models/detection_models.dart';

class ImageUtils {
  // Konversi CameraImage ke paket Image
  // Karena kita sekarang secara eksklusif menggunakan BGRA8888, ini sangat cepat.
  static img.Image convertCameraImage(CameraImage image) {
    if (image.format.group == ImageFormatGroup.bgra8888) {
      return img.Image.fromBytes(
        width: image.width,
        height: image.height,
        bytes: image.planes[0].bytes.buffer,
        order: img.ChannelOrder.bgra,
      );
    } else {
      // Fallback jika tidak terduga format lain masuk
      throw Exception('Format kamera harus BGRA8888, tapi mendapat: ${image.format.group}');
    }
  }

  // Menggambar bounding box dan teks label secara permanen pada piksel gambar
  static Future<File> drawDetectionsOnImage(
      File imageFile, List<DetectionBox> detections, List<String> labels) async {
    if (detections.isEmpty) return imageFile;

    try {
      final bytes = await imageFile.readAsBytes();
      final img.Image? originalImage = img.decodeImage(bytes);

      if (originalImage != null) {
        final originalWidth = originalImage.width;
        final originalHeight = originalImage.height;

        // Daftar warna untuk bounding box
        final List<img.Color> colors = [
          img.ColorRgb8(255, 0, 0),     // Red
          img.ColorRgb8(0, 0, 255),     // Blue
          img.ColorRgb8(0, 255, 0),     // Green
          img.ColorRgb8(255, 165, 0),   // Orange
          img.ColorRgb8(128, 0, 128),   // Purple
          img.ColorRgb8(0, 255, 255),   // Cyan
        ];

        for (var box in detections) {
          // Hitung koordinat piksel absolut pada gambar asli
          final int x1 = (box.x * originalWidth).round().clamp(0, originalWidth - 1);
          final int y1 = (box.y * originalHeight).round().clamp(0, originalHeight - 1);
          final int x2 = ((box.x + box.w) * originalWidth).round().clamp(0, originalWidth - 1);
          final int y2 = ((box.y + box.h) * originalHeight).round().clamp(0, originalHeight - 1);

          final img.Color color = colors[box.classIndex % colors.length];

          // Hitung ketebalan garis proporsional terhadap ukuran gambar (misal 0.5% dari lebar gambar, minimal 2)
          final int thickness = (originalWidth * 0.005).round().clamp(2, 8);

          // Gambar kotak deteksi
          img.drawRect(
            originalImage,
            x1: x1,
            y1: y1,
            x2: x2,
            y2: y2,
            color: color,
            thickness: thickness,
          );
        }

        // Encode kembali gambar ke format JPG dengan kualitas tinggi
        final encoded = img.encodeJpg(originalImage, quality: 90);
        await imageFile.writeAsBytes(encoded);
      }
    } catch (e) {
      // Fallback jika terjadi error (misal Out of Memory)
      print('❌ Gagal menggambar bounding box pada gambar: $e');
    }

    return imageFile;
  }

  // Mengamankan file gambar dari temporary folder ke app document dan menggambar deteksi
  static Future<String> saveImageLocallyWithDetections(
      File imageFile, List<DetectionBox> detections, List<String> labels) async {
    final directory = await getApplicationDocumentsDirectory();
    final fileName = '${DateTime.now().millisecondsSinceEpoch}_${path.basename(imageFile.path)}';
    final String destinationPath = '${directory.path}/$fileName';

    final File savedImage = await imageFile.copy(destinationPath);
    await drawDetectionsOnImage(savedImage, detections, labels);

    return savedImage.path;
  }
}
