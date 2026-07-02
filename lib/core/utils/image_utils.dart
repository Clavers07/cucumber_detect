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

  // Mengamankan file gambar dari temporary folder ke app document secara bersih (raw)
  static Future<String> saveImageLocally(File imageFile) async {
    final directory = await getApplicationDocumentsDirectory();
    final fileName = '${DateTime.now().millisecondsSinceEpoch}_${path.basename(imageFile.path)}';
    final String destinationPath = '${directory.path}/$fileName';

    final File savedImage = await imageFile.copy(destinationPath);
    return savedImage.path;
  }

  // Membuat duplikat gambar dengan bounding box digambar permanen pada pikselnya (berdasarkan confidence threshold)
  static Future<File?> generateOverlayImage({
    required File originalImageFile,
    required List<DetectionBox> detections,
    required double confidenceThreshold,
  }) async {
    try {
      final bytes = await originalImageFile.readAsBytes();
      final img.Image? decoded = img.decodeImage(bytes);

      if (decoded != null) {
        final originalWidth = decoded.width;
        final originalHeight = decoded.height;

        final List<img.Color> colors = [
          img.ColorRgb8(255, 0, 0),     // Red
          img.ColorRgb8(0, 0, 255),     // Blue
          img.ColorRgb8(0, 255, 0),     // Green
          img.ColorRgb8(255, 165, 0),   // Orange
          img.ColorRgb8(128, 0, 128),   // Purple
          img.ColorRgb8(0, 255, 255),   // Cyan
        ];

        // Filter deteksi berdasarkan confidence threshold
        final filtered = detections.where((box) => box.confidence >= confidenceThreshold).toList();

        for (var box in filtered) {
          final int x1 = (box.x * originalWidth).round().clamp(0, originalWidth - 1);
          final int y1 = (box.y * originalHeight).round().clamp(0, originalHeight - 1);
          final int x2 = ((box.x + box.w) * originalWidth).round().clamp(0, originalWidth - 1);
          final int y2 = ((box.y + box.h) * originalHeight).round().clamp(0, originalHeight - 1);

          final img.Color color = colors[box.classIndex % colors.length];
          final int thickness = (originalWidth * 0.005).round().clamp(2, 8);

          img.drawRect(
            decoded,
            x1: x1,
            y1: y1,
            x2: x2,
            y2: y2,
            color: color,
            thickness: thickness,
          );
        }

        // Simpan sebagai file temporer di cache directory
        final tempDir = await getTemporaryDirectory();
        final tempFile = File('${tempDir.path}/temp_overlay_${DateTime.now().millisecondsSinceEpoch}.jpg');
        final encoded = img.encodeJpg(decoded, quality: 90);
        await tempFile.writeAsBytes(encoded);
        return tempFile;
      }
    } catch (e) {
      print('❌ Gagal membuat overlay gambar: $e');
    }
    return null;
  }
}
