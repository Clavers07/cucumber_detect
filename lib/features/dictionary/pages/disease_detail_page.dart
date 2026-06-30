import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../models/disease_model.dart';

class DiseaseDetailPage extends StatefulWidget {
  final DiseaseModel disease;

  const DiseaseDetailPage({super.key, required this.disease});

  @override
  State<DiseaseDetailPage> createState() => _DiseaseDetailPageState();
}

class _DiseaseDetailPageState extends State<DiseaseDetailPage> {
  List<String> _imagePaths = [];
  final PageController _pageController = PageController();
  int _currentIndex = 0;

  DiseaseModel get disease => widget.disease;

  @override
  void initState() {
    super.initState();
    _imagePaths = [disease.imagePath];
    _loadAllImages();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadAllImages() async {
    try {
      final manifestContent = await rootBundle.loadString('AssetManifest.json');
      final Map<String, dynamic> manifestMap = json.decode(manifestContent);
      
      final regExp = RegExp(
        r'^assets/images/diseases/' + disease.id + r'(?:_\d+)?\.(jpg|jpeg|png)$',
        caseSensitive: false,
      );
      
      final paths = manifestMap.keys.where((key) => regExp.hasMatch(key)).toList();
      paths.sort();
      
      if (paths.isNotEmpty && mounted) {
        setState(() {
          _imagePaths = paths;
        });
      }
    } catch (e) {
      debugPrint('Error loading manifest: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Menghitung 30% dari tinggi layar
    final double imageHeight = MediaQuery.of(context).size.height * 0.3;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: imageHeight,
            pinned: true,
            backgroundColor: AppColors.primary,
            iconTheme: const IconThemeData(color: Colors.white),
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                disease.nama,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  shadows: [
                    Shadow(
                      offset: Offset(0, 1),
                      blurRadius: 3.0,
                      color: Colors.black45,
                    ),
                  ],
                ),
              ),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  PageView.builder(
                    controller: _pageController,
                    onPageChanged: (index) {
                      setState(() {
                        _currentIndex = index;
                      });
                    },
                    itemCount: _imagePaths.length,
                    itemBuilder: (context, index) {
                      return Image.asset(
                        _imagePaths[index],
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: AppColors.primary.withOpacity(0.5),
                            child: const Center(
                              child: Icon(Icons.image_not_supported, size: 60, color: Colors.white54),
                            ),
                          );
                        },
                      );
                    },
                  ),
                  // Gradient overlay agar teks judul lebih mudah dibaca
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black54,
                        ],
                      ),
                    ),
                  ),
                  // Tombol navigasi Previous
                  if (_imagePaths.length > 1 && _currentIndex > 0)
                    Positioned(
                      left: 16,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black.withOpacity(0.3),
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.chevron_left, color: Colors.white, size: 32),
                            onPressed: () {
                              _pageController.previousPage(
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeInOut,
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  // Tombol navigasi Next
                  if (_imagePaths.length > 1 && _currentIndex < _imagePaths.length - 1)
                    Positioned(
                      right: 16,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black.withOpacity(0.3),
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.chevron_right, color: Colors.white, size: 32),
                            onPressed: () {
                              _pageController.nextPage(
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeInOut,
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_imagePaths.length > 1)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(_imagePaths.length, (index) {
                          return GestureDetector(
                            onTap: () {
                              _pageController.animateToPage(
                                index, 
                                duration: const Duration(milliseconds: 300), 
                                curve: Curves.easeInOut,
                              );
                            },
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              width: _currentIndex == index ? 24 : 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: _currentIndex == index ? AppColors.primary : Colors.grey[300],
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                  _buildHeaderInfo(),
                  const SizedBox(height: AppSpacing.lg),
                  _buildSection('Deskripsi', disease.deskripsi),
                  const SizedBox(height: AppSpacing.md),
                  _buildListSection('Ciri-ciri', disease.ciriCiri),
                  const SizedBox(height: AppSpacing.md),
                  _buildSection('Penyebab', disease.penyebab),
                  const SizedBox(height: AppSpacing.md),
                  _buildListSection('Penanganan', disease.penanganan),
                  const SizedBox(height: AppSpacing.md),
                  _buildListSection('Pencegahan', disease.pencegahan),
                  const SizedBox(height: 40), // Spacing bawah
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderInfo() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Nama Latin',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              Text(
                disease.namaLatin,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  fontStyle: FontStyle.italic,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.secondary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.secondary.withOpacity(0.5)),
          ),
          child: Text(
            disease.kategori,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: AppColors.secondary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSection(String title, String content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          content,
          style: const TextStyle(
            fontSize: 14,
            height: 1.5,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildListSection(String title, List<String> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        ...items.map((item) => Padding(
          padding: const EdgeInsets.only(bottom: 6.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('• ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.secondary)),
              Expanded(
                child: Text(
                  item,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        )),
      ],
    );
  }
}
