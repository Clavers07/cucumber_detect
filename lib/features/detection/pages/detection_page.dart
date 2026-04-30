import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/bounding_box_overlay.dart';
import '../bloc/detection_cubit.dart';
import '../bloc/detection_state.dart';

class DetectionPage extends StatelessWidget {
  const DetectionPage({super.key});

  void _showPickerOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'Pilih Sumber Gambar',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: AppColors.primary),
              title: const Text('Galeri'),
              onTap: () {
                Navigator.pop(context);
                context.read<DetectionCubit>().pickImageAndDetect(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera, color: AppColors.primary),
              title: const Text('Kamera'),
              onTap: () {
                Navigator.pop(context);
                context.read<DetectionCubit>().pickImageAndDetect(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Deteksi AI'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => context.read<DetectionCubit>().resetState(),
          )
        ],
      ),
      body: BlocConsumer<DetectionCubit, DetectionState>(
        listener: (context, state) {
          if (state is DetectionError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.errorMessage), backgroundColor: AppColors.error),
            );
          }
        },
        builder: (context, state) {
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Expanded(
                  child: AppCard(
                    padding: EdgeInsets.zero,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: _buildImageSection(context, state),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                _buildActionSection(context, state),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showPickerOptions(context),
        icon: const Icon(Icons.add_a_photo, color: Colors.white),
        label: const Text('Analisis Baru', style: TextStyle(color: Colors.white)),
        backgroundColor: AppColors.primary,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildImageSection(BuildContext context, DetectionState state) {
    if (state is DetectionLoading) {
      return Container(
        color: AppColors.surface,
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: AppColors.primary),
              SizedBox(height: 16),
              Text('AI Sedang Menganalisis...'),
            ],
          ),
        ),
      );
    } else if (state is DetectionSuccess) {
      // Decode image dimensions to accurately draw bounding boxes
      return FutureBuilder<ImageInfo>(
        future: _getImageInfo(state.image),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          
          return BoundingBoxOverlay(
            image: state.image,
            detections: state.detections,
            originalWidth: snapshot.data!.image.width.toDouble(),
            originalHeight: snapshot.data!.image.height.toDouble(),
            // TODO: Inject labels dari ML Service, sementara kosong/hardcoded
            labels: const ['Healthy', 'Disease A', 'Disease B', 'Disease C', 'Disease D', 'Disease E'],
          );
        },
      );
    }

    return Container(
      color: Colors.grey[200],
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.image_search, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('Pilih foto dari kamera atau galeri', style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _buildActionSection(BuildContext context, DetectionState state) {
    if (state is DetectionSuccess) {
      return AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Hasil Deteksi',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              state.detections.isEmpty 
                  ? 'Tidak ada objek yang terdeteksi.'
                  : 'Ditemukan ${state.detections.length} objek. Waktu inferensi: ${state.inferenceTime} ms',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            // Disini bisa ditambahkan navigasi ke ResultPage secara spesifik
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }

  // Helper untuk mendapatkan dimensi asli gambar tanpa memblokir UI
  Future<ImageInfo> _getImageInfo(File file) async {
    final Completer<ImageInfo> completer = Completer();
    final ImageStream stream = FileImage(file).resolve(const ImageConfiguration());
    stream.addListener(ImageStreamListener((ImageInfo info, bool _) {
      completer.complete(info);
    }));
    return completer.future;
  }
}