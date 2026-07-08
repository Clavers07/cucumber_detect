import 'dart:io';
import 'package:flutter/material.dart';
import '../../data/models/detection_models.dart';

class BoundingBoxOverlay extends StatelessWidget {
  final File image;
  final List<DetectionBox> detections;
  final double originalWidth;
  final double originalHeight;
  final List<String> labels;
  final bool showLabels;

  const BoundingBoxOverlay({
    super.key,
    required this.image,
    required this.detections,
    required this.originalWidth,
    required this.originalHeight,
    required this.labels,
    this.showLabels = true,
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
                Colors.indigoAccent,
                Colors.orangeAccent,
                Colors.purpleAccent,
                Colors.cyanAccent,
                Colors.pinkAccent,
                Colors.tealAccent,
                Colors.amberAccent,
              ];
              
              final Color baseColor = classColors[d.classIndex % classColors.length];

              final double leftPos = d.x * dw + ox;
              final double topPos = d.y * dh + oy;
              final double widthPos = d.w * dw;
              final double heightPos = d.h * dh;
              final bool showLabelAbove = topPos > 20;

              return Positioned(
                left: leftPos,
                top: showLabelAbove ? topPos - 18 : topPos,
                width: widthPos,
                height: showLabelAbove ? heightPos + 18 : heightPos,
                child: Stack(
                  children: [
                    // Bounding box outline (kotak tajam tanpa corner radius)
                    Positioned(
                      left: 0,
                      top: showLabelAbove ? 18 : 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: baseColor, width: 1.5),
                        ),
                      ),
                    ),
                    // Label badge
                    if (showLabels)
                      Positioned(
                        left: 0,
                        top: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          color: baseColor,
                          child: Text(
                            '$className ${(d.confidence * 100).toStringAsFixed(0)}%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              height: 1.0,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            }),
          ],
        );
      },
    );
  }
}