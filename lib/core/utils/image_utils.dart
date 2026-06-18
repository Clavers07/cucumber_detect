import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;

class ImageUtils {
  static img.Image? convertCameraImage(CameraImage image) {
    if (image.format.group == ImageFormatGroup.yuv420) {
      return _convertYUV420(image);
    } else if (image.format.group == ImageFormatGroup.bgra8888) {
      return _convertBGRA8888(image);
    }
    return null;
  }

  static img.Image _convertYUV420(CameraImage image) {
    final width = image.width;
    final height = image.height;
    final imgData = img.Image(width: width, height: height);

    final yBuffer = image.planes[0].bytes;
    final uBuffer = image.planes[1].bytes;
    final vBuffer = image.planes[2].bytes;

    final yRowStride = image.planes[0].bytesPerRow;
    final uvRowStride = image.planes[1].bytesPerRow;
    final uvPixelStride = image.planes[1].bytesPerPixel ?? 1;

    for (int y = 0; y < height; y++) {
      int uvRow = y >> 1;
      for (int x = 0; x < width; x++) {
        int uvCol = x >> 1;
        int yIndex = (y * yRowStride) + x;
        int uvIndex = (uvRow * uvRowStride) + (uvCol * uvPixelStride);

        int yp = yBuffer[yIndex];
        int up = uBuffer[uvIndex] - 128;
        int vp = vBuffer[uvIndex] - 128;

        int r = (yp + vp * 1436 / 1024).round().clamp(0, 255);
        int g = (yp - up * 46549 / 131072 - vp * 93604 / 131072).round().clamp(0, 255);
        int b = (yp + up * 1814 / 1024).round().clamp(0, 255);

        imgData.setPixelRgb(x, y, r, g, b);
      }
    }
    return imgData;
  }

  static img.Image _convertBGRA8888(CameraImage image) {
    return img.Image.fromBytes(
      width: image.width,
      height: image.height,
      bytes: image.planes[0].bytes.buffer,
      order: img.ChannelOrder.bgra,
    );
  }
}
