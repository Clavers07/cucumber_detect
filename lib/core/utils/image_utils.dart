import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;

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
}
