import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import '../../data/models/detection_models.dart';

// Kelas argument untuk Isolate compute
class ImageProcessInput {
  final String imagePath;
  final List<DetectionBox> detections;
  final double threshold;

  ImageProcessInput({
    required this.imagePath,
    required this.detections,
    required this.threshold,
  });
}

// Global top-level function untuk Isolate compute
Future<Uint8List?> processImageForPdf(ImageProcessInput input) async {
  try {
    final file = File(input.imagePath);
    if (!await file.exists()) return null;

    final bytes = await file.readAsBytes();
    img.Image? decoded = img.decodeImage(bytes);
    if (decoded == null) return null;

    // 1. Downscale ke maksimal 400px (2x lebih kecil dari 800px) untuk hemat RAM & space
    const int maxDimension = 400;
    if (decoded.width > maxDimension || decoded.height > maxDimension) {
      decoded = img.copyResize(
        decoded,
        width: decoded.width > decoded.height ? maxDimension : null,
        height: decoded.height >= decoded.width ? maxDimension : null,
      );
    }

    final int originalWidth = decoded.width;
    final int originalHeight = decoded.height;

    // 2. Tempel bounding box sesuai warna label
    final List<img.Color> colors = [
      img.ColorRgb8(255, 0, 0),     // Red
      img.ColorRgb8(0, 0, 255),     // Blue
      img.ColorRgb8(0, 255, 0),     // Green
      img.ColorRgb8(255, 165, 0),   // Orange
      img.ColorRgb8(128, 0, 128),   // Purple
      img.ColorRgb8(0, 255, 255),   // Cyan
    ];

    final filtered = input.detections.where((box) => box.confidence >= input.threshold).toList();

    for (var box in filtered) {
      final int x1 = (box.x * originalWidth).round().clamp(0, originalWidth - 1);
      final int y1 = (box.y * originalHeight).round().clamp(0, originalHeight - 1);
      final int x2 = ((box.x + box.w) * originalWidth).round().clamp(0, originalWidth - 1);
      final int y2 = ((box.y + box.h) * originalHeight).round().clamp(0, originalHeight - 1);

      final img.Color color = colors[box.classIndex % colors.length];
      final int thickness = (originalWidth * 0.005).round().clamp(2, 6);

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

    // 3. Kompresi JPEG kualitas 80%
    return Uint8List.fromList(img.encodeJpg(decoded, quality: 80));
  } catch (e) {
    debugPrint('❌ Gagal memproses gambar untuk PDF: $e');
    return null;
  }
}

class PdfExportService {
  static Future<Uint8List> generatePdfReport({
    required List<HistoryWithDetail> entries,
    required List<String> labels,
    required double confidenceThreshold,
    required Function(int processed, int total) onProgress,
  }) async {
    final pdf = pw.Document();
    
    // 1. Proses semua gambar satu-satu di background Isolate (hemat RAM)
    final List<Uint8List?> processedImages = [];
    final int total = entries.length;
    
    for (int i = 0; i < total; i++) {
      onProgress(i, total);
      final entry = entries[i];
      final input = ImageProcessInput(
        imagePath: entry.imagePath,
        detections: entry.boxList,
        threshold: confidenceThreshold,
      );
      
      final processedBytes = await compute(processImageForPdf, input);
      processedImages.add(processedBytes);
    }
    onProgress(total, total);

    // 2. Ambil Font agar teks PDF mendukung karakter bahasa dengan rapi
    final fontTitle = await PdfGoogleFonts.openSansBold();
    final fontBody = await PdfGoogleFonts.openSansRegular();

    // Halaman Laporan Utama berbentuk Tabel (Split otomatis ke halaman baru via MultiPage)
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            // Kop Laporan Resmi
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'LAPORAN DETEKSI KESEHATAN KELAPA SAWIT',
                      style: pw.TextStyle(font: fontTitle, fontSize: 16, color: PdfColors.teal800),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Aplikasi Cucumber Detect - Hasil Analisis Citra AI',
                      style: pw.TextStyle(font: fontBody, fontSize: 10, color: PdfColors.grey700),
                    ),
                  ],
                ),
              ],
            ),
            pw.Divider(thickness: 2, color: PdfColors.teal800),
            pw.SizedBox(height: 16),

            // Ringkasan Laporan
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Tanggal Cetak: ${DateFormat('dd MMMM yyyy, HH:mm').format(DateTime.now())}',
                  style: pw.TextStyle(font: fontBody, fontSize: 9, color: PdfColors.grey600),
                ),
                pw.Text(
                  'Total Sampel: $total | Min. Confidence: ${(confidenceThreshold * 100).toStringAsFixed(0)}%',
                  style: pw.TextStyle(font: fontBody, fontSize: 9, color: PdfColors.grey600),
                ),
              ],
            ),
            pw.SizedBox(height: 16),

            // Tabel Utama Riwayat Deteksi
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey400),
              columnWidths: {
                0: const pw.FlexColumnWidth(0.6), // No
                1: const pw.FlexColumnWidth(2.2), // Gambar (2x lebih kecil)
                2: const pw.FlexColumnWidth(4.7), // Summary Label (ke bawah, comma separated)
                3: const pw.FlexColumnWidth(2.5), // Tanggal
              },
              children: [
                // Header Table
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.teal100),
                  children: [
                    _buildTableHeaderCell(fontTitle, 'No'),
                    _buildTableHeaderCell(fontTitle, 'Gambar'),
                    _buildTableHeaderCell(fontTitle, 'Hasil Deteksi AI'),
                    _buildTableHeaderCell(fontTitle, 'Tanggal'),
                  ],
                ),
                // Data Rows
                ...List.generate(entries.length, (index) {
                  final entry = entries[index];
                  final imageBytes = processedImages[index];
                  final dateStr = DateFormat('dd MMM yyyy\nHH:mm').format(DateTime.fromMillisecondsSinceEpoch(entry.detectedAt));

                  final filteredBoxes = entry.boxList.where((box) => box.confidence >= confidenceThreshold).toList();
                  final Map<String, List<double>> dynamicGrouped = {};
                  for (var box in filteredBoxes) {
                    final String label = labels.isNotEmpty && box.classIndex < labels.length ? labels[box.classIndex] : 'Class ${box.classIndex}';
                    dynamicGrouped.putIfAbsent(label, () => []).add(box.confidence);
                  }

                  final List<String> dynamicList = [];
                  for (var grp in dynamicGrouped.entries) {
                    final avgConf = grp.value.reduce((a, b) => a + b) / grp.value.length;
                    dynamicList.add('${grp.value.length}x ${grp.key} (${(avgConf * 100).toStringAsFixed(1)}%)');
                  }
                  final String summaryText = dynamicList.isNotEmpty ? dynamicList.join(',\n') : 'Tidak ada penyakit terdeteksi';

                  return pw.TableRow(
                    verticalAlignment: pw.TableCellVerticalAlignment.middle,
                    children: [
                      // No
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text('${index + 1}', style: pw.TextStyle(font: fontBody, fontSize: 9), textAlign: pw.TextAlign.center),
                      ),
                      // Gambar (2x lebih kecil: layout height 60px)
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: imageBytes != null
                            ? pw.Container(
                                height: 60,
                                alignment: pw.Alignment.center,
                                child: pw.Image(
                                  pw.MemoryImage(imageBytes),
                                  fit: pw.BoxFit.contain,
                                ),
                              )
                            : pw.Container(
                                height: 60,
                                color: PdfColors.grey200,
                                child: pw.Center(
                                  child: pw.Text('No Image', style: pw.TextStyle(font: fontBody, fontSize: 7)),
                                ),
                              ),
                      ),
                      // Summary Label (ke bawah, comma separated)
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        child: pw.Text(summaryText, style: pw.TextStyle(font: fontBody, fontSize: 9)),
                      ),
                      // Tanggal
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text(dateStr, style: pw.TextStyle(font: fontBody, fontSize: 8), textAlign: pw.TextAlign.center),
                      ),
                    ],
                  );
                }),
              ],
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  static pw.Widget _buildReportSummaryRow(pw.Font titleFont, pw.Font bodyFont, String label, String value) {
    return pw.Row(
      children: [
        pw.SizedBox(
          width: 140,
          child: pw.Text(label, style: pw.TextStyle(font: titleFont, fontSize: 10, color: PdfColors.grey800)),
        ),
        pw.Text(value, style: pw.TextStyle(font: bodyFont, fontSize: 10, color: PdfColors.grey900)),
      ],
    );
  }

  static pw.Widget _buildTableHeaderCell(pw.Font font, String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.teal900),
        textAlign: pw.TextAlign.center,
      ),
    );
  }

  static pw.Widget _buildTableCell(pw.Font font, String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        style: pw.TextStyle(font: font, fontSize: 9),
        textAlign: pw.TextAlign.center,
      ),
    );
  }
}
