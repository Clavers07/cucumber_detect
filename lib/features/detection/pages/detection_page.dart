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
import '../../../data/models/detection_models.dart';

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
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                AppCard(
                  padding: EdgeInsets.zero,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: ConstrainedBox(
                      // Membatasi tinggi gambar agar tidak terlalu besar dan proporsional
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.45,
                        minHeight: 250,
                        minWidth: double.infinity,
                      ),
                      child: _buildImageSection(context, state),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                _buildActionSection(context, state),
                // Spacing ekstra di bawah agar tidak tertutup floating action button
                const SizedBox(height: 100),
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
        color: Colors.grey[100],
        width: double.infinity,
        child: Center(
          child: _SkeletonLoader(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.document_scanner, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(4)),
                  width: 150, height: 16, 
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(4)),
                  width: 100, height: 12, 
                ),
              ],
            ),
          ),
        ),
      );
    } else if (state is DetectionSuccess) {
      return FutureBuilder<ImageInfo>(
        future: _getImageInfo(state.image),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          
          return BoundingBoxOverlay(
            image: state.image,
            detections: state.detections,
            originalWidth: snapshot.data!.image.width.toDouble(),
            originalHeight: snapshot.data!.image.height.toDouble(),
            labels: state.labels,
          );
        },
      );
    }

    return Container(
      color: Colors.grey[200],
      width: double.infinity,
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
    if (state is DetectionLoading) {
      return AppCard(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'Menganalisis Objek...',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            const LinearProgressIndicator(color: AppColors.primary),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: _SkeletonLoader(
                child: Column(
                  children: List.generate(3, (index) => Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: Row(
                      children: [
                        Container(
                          width: 24, height: 24, 
                          decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(4)),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 120, height: 16, 
                                decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(4)),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                width: 80, height: 12, 
                                decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(4)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )),
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (state is DetectionSuccess) {
      return _DetectionResultTabs(
        detections: state.detections, 
        labels: state.labels,
      );
    }
    return const SizedBox.shrink();
  }

  Future<ImageInfo> _getImageInfo(File file) async {
    final Completer<ImageInfo> completer = Completer();
    final ImageStream stream = FileImage(file).resolve(const ImageConfiguration());
    stream.addListener(ImageStreamListener((ImageInfo info, bool _) {
      if (!completer.isCompleted) completer.complete(info);
    }));
    return completer.future;
  }
}

class _DetectionResultTabs extends StatefulWidget {
  final List<DetectionBox> detections;
  final List<String> labels;

  const _DetectionResultTabs({
    required this.detections,
    required this.labels,
  });

  @override
  State<_DetectionResultTabs> createState() => _DetectionResultTabsState();
}

class _DetectionResultTabsState extends State<_DetectionResultTabs> with TickerProviderStateMixin {
  late TabController _tabController;
  late Map<String, List<DetectionBox>> _grouped;
  late List<String> _tabs;

  @override
  void initState() {
    super.initState();
    _groupDetections();
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void didUpdateWidget(covariant _DetectionResultTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.detections != widget.detections) {
      _groupDetections();
      _tabController.dispose();
      _tabController = TabController(length: _tabs.length, vsync: this);
    }
  }

  void _groupDetections() {
    _grouped = {};
    for (var d in widget.detections) {
      final className = widget.labels.isNotEmpty && d.classIndex < widget.labels.length 
          ? widget.labels[d.classIndex] 
          : 'Class ${d.classIndex}';
      if (!_grouped.containsKey(className)) {
        _grouped[className] = [];
      }
      _grouped[className]!.add(d);
    }
    _tabs = _grouped.keys.toList();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_tabs.isEmpty) {
      return AppCard(
        child: const Padding(
          padding: EdgeInsets.all(16.0),
          child: Text('Tidak ada objek yang terdeteksi.', style: TextStyle(color: AppColors.textSecondary)),
        ),
      );
    }

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Hasil Deteksi (${widget.detections.length} objek)',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          TabBar(
            controller: _tabController,
            isScrollable: true,
            labelColor: AppColors.primary,
            unselectedLabelColor: Colors.grey,
            indicatorColor: AppColors.primary,
            tabs: _tabs.map((t) => Tab(text: '$t (${_grouped[t]!.length})')).toList(),
          ),
          AnimatedBuilder(
            animation: _tabController,
            builder: (context, _) {
              if (_tabs.isEmpty) return const SizedBox.shrink();
              final selectedTab = _tabs[_tabController.index];
              final items = _grouped[selectedTab]!;
              
              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(), // Scroll mengikuti SingleChildScrollView parent
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final d = items[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.crop_free, color: AppColors.secondary),
                    title: Text('Confidence: ${(d.confidence * 100).toStringAsFixed(1)}%'),
                    subtitle: Text('Posisi: x=${d.x.toStringAsFixed(2)}, y=${d.y.toStringAsFixed(2)}'),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SkeletonLoader extends StatefulWidget {
  final Widget child;
  const _SkeletonLoader({required this.child});

  @override
  State<_SkeletonLoader> createState() => _SkeletonLoaderState();
}

class _SkeletonLoaderState extends State<_SkeletonLoader> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.3, end: 0.7).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) => Opacity(opacity: _animation.value, child: widget.child),
    );
  }
}