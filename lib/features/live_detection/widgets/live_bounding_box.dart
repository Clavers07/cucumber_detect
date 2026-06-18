import 'package:flutter/material.dart';
import '../../../../data/models/detection_models.dart';
import '../../../../core/theme/app_colors.dart';

class LiveBoundingBox extends StatelessWidget {
  final List<DetectionBox> detections;
  final Size cameraSize;
  final Size screenSize;
  final List<String> labels;

  const LiveBoundingBox({
    super.key,
    required this.detections,
    required this.cameraSize,
    required this.screenSize,
    required this.labels,
  });

  @override
  Widget build(BuildContext context) {
    if (detections.isEmpty) return const SizedBox.shrink();

    return CustomPaint(
      size: screenSize,
      painter: _LiveBoundingBoxPainter(
        detections: detections,
        cameraSize: cameraSize,
        labels: labels,
      ),
    );
  }
}

class _LiveBoundingBoxPainter extends CustomPainter {
  final List<DetectionBox> detections;
  final Size cameraSize; // The input resolution of the model, typically 640x640
  final List<String> labels;

  _LiveBoundingBoxPainter({
    required this.detections,
    required this.cameraSize,
    required this.labels,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double scaleX = size.width / cameraSize.width;
    final double scaleY = size.height / cameraSize.height;

    final Paint boxPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..color = AppColors.primary;

    final Paint textBgPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = AppColors.primary.withOpacity(0.8);

    for (final det in detections) {
      // Deteksi jika model mengeluarkan normalized coordinates (0.0 - 1.0)
      // Jika ya, kita harus mengalikannya dengan ukuran asli input kamera (640x640)
      final bool isNormalized = det.x <= 2.0 && det.y <= 2.0 && det.w <= 2.0 && det.h <= 2.0;
      
      final double actualX = isNormalized ? det.x * cameraSize.width : det.x;
      final double actualY = isNormalized ? det.y * cameraSize.height : det.y;
      final double actualW = isNormalized ? det.w * cameraSize.width : det.w;
      final double actualH = isNormalized ? det.h * cameraSize.height : det.h;

      // Map coordinate dari input size (640x640) ke screen size
      final double left = actualX * scaleX;
      final double top = actualY * scaleY;
      final double width = actualW * scaleX;
      final double height = actualH * scaleY;

      final Rect rect = Rect.fromLTWH(left, top, width, height);
      
      // Mengubah warna tergantung confidence
      if (det.confidence > 0.7) {
        boxPaint.color = Colors.greenAccent;
        textBgPaint.color = Colors.green.withOpacity(0.8);
      } else {
        boxPaint.color = Colors.orangeAccent;
        textBgPaint.color = Colors.orange.withOpacity(0.8);
      }

      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(8)),
        boxPaint,
      );

      final String labelText = det.classIndex < labels.length ? labels[det.classIndex] : 'Objek';
      final String confText = '${(det.confidence * 100).toStringAsFixed(0)}%';
      final String text = '$labelText $confText';

      final TextSpan span = TextSpan(
        text: text,
        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
      );

      final TextPainter textPainter = TextPainter(
        text: span,
        textAlign: TextAlign.left,
        textDirection: TextDirection.ltr,
      );

      textPainter.layout();
      
      // Draw text background
      final Rect textBgRect = Rect.fromLTWH(
        left,
        top - textPainter.height - 4,
        textPainter.width + 8,
        textPainter.height + 4,
      );
      
      canvas.drawRRect(
        RRect.fromRectAndRadius(textBgRect, const Radius.circular(4)),
        textBgPaint,
      );

      textPainter.paint(canvas, Offset(left + 4, top - textPainter.height - 2));
    }
  }

  @override
  bool shouldRepaint(covariant _LiveBoundingBoxPainter oldDelegate) {
    return true; // Always repaint on stream
  }
}
