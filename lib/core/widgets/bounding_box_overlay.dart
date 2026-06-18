import 'dart:io';
import 'package:flutter/material.dart';
import '../../data/models/detection_models.dart';

class BoundingBoxOverlay extends StatelessWidget {
  final File image;
  final List<DetectionBox> detections;
  final double originalWidth;
  final double originalHeight;
  final List<String> labels;

  const BoundingBoxOverlay({
    super.key,
    required this.image,
    required this.detections,
    required this.originalWidth,
    required this.originalHeight,
    required this.labels,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final ww = constraints.maxWidth;
        final wh = constraints.maxHeight;
        final ia = originalWidth / originalHeight;
        final wa = ww / wh;
        double dw, dh, ox = 0, oy = 0;
        
        // Logika rasio gambar asli
        if (ia > wa) {
          dw = ww;
          dh = ww / ia;
          oy = (wh - dh) / 2;
        } else {
          dh = wh;
          dw = wh * ia;
          ox = (ww - dw) / 2;
        }

        return Stack(
          children: [
            Center(child: Image.file(image, fit: BoxFit.contain)),
            ...detections.map((d) {
              final className = labels.isNotEmpty && d.classIndex < labels.length 
                  ? labels[d.classIndex] 
                  : 'Class ${d.classIndex}';

              // Daftar warna berdasarkan class index
              final List<Color> classColors = [
                Colors.redAccent,
                Colors.blueAccent,
                Colors.greenAccent,
                Colors.orangeAccent,
                Colors.purpleAccent,
                Colors.cyanAccent,
                Colors.pinkAccent,
                Colors.tealAccent,
                Colors.amberAccent,
                Colors.indigoAccent,
              ];
              
              final Color baseColor = classColors[d.classIndex % classColors.length];

              return Positioned(
                left: d.x * dw + ox,
                top: d.y * dh + oy,
                width: d.w * dw,
                height: d.h * dh,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: baseColor, width: 2.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: baseColor.withOpacity(0.8),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(5),
                          bottomRight: Radius.circular(8),
                        ),
                      ),
                      child: Text(
                        '$className ${(d.confidence * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        );
      },
    );
  }
}