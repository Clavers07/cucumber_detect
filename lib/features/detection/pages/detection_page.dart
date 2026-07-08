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
import '../../dictionary/models/disease_model.dart';
import '../../dictionary/services/dictionary_service.dart';
import '../../dictionary/pages/disease_detail_page.dart';

class DetectionPage extends StatefulWidget {
  final File? initialImage;
  
  const DetectionPage({super.key, this.initialImage});

  @override
  State<DetectionPage> createState() => _DetectionPageState();
}

class _DetectionPageState extends State<DetectionPage> {
  double _confidenceThreshold = 0.40; // Default threshold
  bool _showLabels = true; // State untuk menampilkan label deteksi

  @override
  void initState() {
    super.initState();
    if (widget.initialImage != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.read<DetectionCubit>().detectFromImage(widget.initialImage!);
        }
      });
    }
  }

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
                if (state is DetectionSuccess) _buildSliderCard(state),
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
      final filteredDetections = state.detections
          .where((box) => box.confidence >= _confidenceThreshold)
          .toList();

      return FutureBuilder<ImageInfo>(
        future: _getImageInfo(state.image),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          
          return BoundingBoxOverlay(
            image: state.image,
            detections: filteredDetections,
            originalWidth: snapshot.data!.image.width.toDouble(),
            originalHeight: snapshot.data!.image.height.toDouble(),
            labels: state.labels,
            showLabels: _showLabels,
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
      final filteredDetections = state.detections
          .where((box) => box.confidence >= _confidenceThreshold)
          .toList();

      return _DetectionResultTabs(
        detections: filteredDetections, 
        labels: state.labels,
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildSliderCard(DetectionSuccess state) {
    return AppCard(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Minimal Confidence',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${(_confidenceThreshold * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppColors.primary,
              inactiveTrackColor: AppColors.primary.withOpacity(0.15),
              thumbColor: AppColors.primary,
              overlayColor: AppColors.primary.withOpacity(0.12),
              valueIndicatorColor: AppColors.primary,
              trackHeight: 4,
            ),
            child: Slider(
              value: _confidenceThreshold,
              min: 0.1,
              max: 1.0,
              divisions: 18,
              label: '${(_confidenceThreshold * 100).toStringAsFixed(0)}%',
              onChanged: (value) {
                setState(() {
                  _confidenceThreshold = value;
                });
              },
            ),
          ),
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Tampilkan Label Deteksi',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),
              Switch(
                value: _showLabels,
                activeColor: AppColors.primary,
                onChanged: (value) {
                  setState(() {
                    _showLabels = value;
                  });
                },
              ),
            ],
          ),
        ],
      ),
    );
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
  final DictionaryService _dictionaryService = DictionaryService();
  List<DiseaseModel> _diseases = [];

  @override
  void initState() {
    super.initState();
    _groupDetections();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _loadDiseases();
  }

  Future<void> _loadDiseases() async {
    final data = await _dictionaryService.loadDiseases();
    if (mounted) {
      setState(() {
        _diseases = data;
      });
    }
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
            tabs: _tabs.map((t) {
              final firstDet = _grouped[t]!.first;
              // Daftar warna disinkronkan dengan BoundingBoxOverlay
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
              final Color baseColor = classColors[firstDet.classIndex % classColors.length];
              
              return Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: baseColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text('$t (${_grouped[t]!.length})'),
                  ],
                ),
              );
            }).toList(),
          ),
          AnimatedBuilder(
            animation: _tabController,
            builder: (context, _) {
              if (_tabs.isEmpty) return const SizedBox.shrink();
              final selectedTab = _tabs[_tabController.index];
              final items = _grouped[selectedTab]!;
              
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_diseases.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 16.0, right: 16.0, left: 16.0, bottom: 8.0),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            final targetId = selectedTab.toLowerCase().replaceAll(' ', '_');
                            final index = _diseases.indexWhere((d) => d.id == targetId);
                            if (index != -1) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => DiseaseDetailPage(disease: _diseases[index]),
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.menu_book_rounded, size: 20),
                          label: const Text(
                            'Lihat Penanganan Lengkap',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                        ),
                      ),
                    ),
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(), // Scroll mengikuti SingleChildScrollView parent
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                  ),
                ],
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