import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:camera/camera.dart';
import '../bloc/live_detection_cubit.dart';
import '../bloc/live_detection_state.dart';
import '../widgets/live_bounding_box.dart';
import '../../../../core/theme/app_colors.dart';
import '../../detection/pages/detection_page.dart';
import '../../detection/bloc/detection_cubit.dart';
import '../../../../core/services/ml_service.dart';

class LiveDetectionPage extends StatefulWidget {
  const LiveDetectionPage({super.key});

  @override
  State<LiveDetectionPage> createState() => _LiveDetectionPageState();
}

class _LiveDetectionPageState extends State<LiveDetectionPage> {
  @override
  void initState() {
    super.initState();
    // Inisialisasi kamera dan model saat halaman dibuka
    context.read<LiveDetectionCubit>().initCameraAndModel();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: BlocConsumer<LiveDetectionCubit, LiveDetectionState>(
        listener: (context, state) {
          if (state is LiveDetectionError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.message), backgroundColor: AppColors.error),
            );
          }
        },
        builder: (context, state) {
          if (state is LiveDetectionLoading || state is LiveDetectionInitial) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: AppColors.primary),
                  SizedBox(height: 16),
                  Text("Mempersiapkan Kamera & AI...", style: TextStyle(color: Colors.white)),
                ],
              ),
            );
          }

          if (state is LiveDetectionActive) {
            return _buildLiveCameraView(context, state);
          }

          if (state is LiveDetectionFrozen) {
            return _buildFrozenView(context, state);
          }

          return const Center(child: Text("Terjadi kesalahan", style: TextStyle(color: Colors.white)));
        },
      ),
    );
  }

  Widget _buildLiveCameraView(BuildContext context, LiveDetectionActive state) {
    final size = MediaQuery.of(context).size;
    // Asumsi input model 640x640. Jika berbeda, sesuaikan.
    const cameraInputSize = Size(640, 640);

    return Stack(
      fit: StackFit.expand,
      children: [
        // Camera Preview
        CameraPreview(state.cameraController),
        
        // Bounding Box Overlay
        LiveBoundingBox(
          detections: state.currentDetections,
          cameraSize: cameraInputSize,
          screenSize: size,
          labels: context.read<LiveDetectionCubit>().mlService.labels,
        ),

        // UI Tambahan (Back Button & Info)
        Positioned(
          top: 40,
          left: 16,
          child: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 30),
            onPressed: () => Navigator.pop(context),
          ),
        ),

        // Shutter Button
        Positioned(
          bottom: 40,
          left: 0,
          right: 0,
          child: Center(
            child: GestureDetector(
              onTap: () async {
                try {
                  // Berikan feedback loading
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Menangkap gambar...'), duration: Duration(seconds: 1)),
                  );
                  
                  // Hentikan stream
                  await state.cameraController.stopImageStream();
                  await Future.delayed(const Duration(milliseconds: 200));
                  
                  final XFile imageFile = await state.cameraController.takePicture();
                  
                  if (context.mounted) {
                    final existingMlService = context.read<LiveDetectionCubit>().mlService;
                    
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => BlocProvider(
                          create: (_) => DetectionCubit(existingMlService),
                          child: DetectionPage(initialImage: File(imageFile.path)),
                        ),
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Gagal: $e')),
                    );
                    context.read<LiveDetectionCubit>().resumeLive();
                  }
                }
              },
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 4),
                  color: AppColors.primary.withOpacity(0.5),
                ),
                child: const Icon(Icons.camera, color: Colors.white, size: 40),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFrozenView(BuildContext context, LiveDetectionFrozen state) {
    final size = MediaQuery.of(context).size;
    const cameraInputSize = Size(640, 640);

    return Stack(
      fit: StackFit.expand,
      children: [
        // Frozen Image
        Image.file(File(state.imagePath), fit: BoxFit.cover),

        // Bounding Box untuk gambar yang difreeze
        LiveBoundingBox(
          detections: state.detections,
          cameraSize: cameraInputSize,
          screenSize: size,
          labels: context.read<LiveDetectionCubit>().mlService.labels,
        ),

        // UI Panel Bawah (Glassmorphism effect)
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.7),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "Hasil Deteksi",
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  state.detections.isNotEmpty 
                    ? "Ditemukan ${state.detections.length} objek" 
                    : "Tidak ada objek yang jelas terdeteksi",
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () {
                        context.read<LiveDetectionCubit>().resumeLive();
                      },
                      icon: const Icon(Icons.refresh, color: Colors.white),
                      label: const Text("Ulangi", style: TextStyle(color: Colors.white)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white),
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () {
                        context.read<LiveDetectionCubit>().saveToDatabase();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Berhasil disimpan ke Riwayat!")),
                        );
                      },
                      icon: const Icon(Icons.save, color: Colors.white),
                      label: const Text("Simpan", style: TextStyle(color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      ),
                    ),
                  ],
                )
              ],
            ),
          ),
        ),
      ],
    );
  }
}
