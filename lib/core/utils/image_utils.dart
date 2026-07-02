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
}
