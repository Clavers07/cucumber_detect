import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_card.dart';
import '../../../data/models/detection_models.dart';
import '../bloc/history_cubit.dart';
import '../bloc/history_state.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  @override
  void initState() {
    super.initState();
    // Memuat data secara otomatis saat halaman dibuka
    context.read<HistoryCubit>().loadHistory();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Riwayat Deteksi'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => context.read<HistoryCubit>().loadHistory(),
          )
        ],
      ),
      body: BlocBuilder<HistoryCubit, HistoryState>(
        builder: (context, state) {
          if (state is HistoryLoading) {
            return const Center(child: CircularProgressIndicator(color: AppColors.primary));
          } else if (state is HistoryError) {
            return Center(
              child: Text(state.message, style: const TextStyle(color: AppColors.error)),
            );
          } else if (state is HistoryLoaded) {
            return Column(
              children: [
                _buildSearchBar(context, state),
                _buildFilterChips(context, state),
                _buildStatsCard(state.originalHistory),
                Expanded(
                  child: state.historyList.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.history_toggle_off, size: 64, color: Colors.grey),
                              SizedBox(height: 16),
                              Text('Tidak ada riwayat ditemukan.', style: TextStyle(color: Colors.grey)),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          itemCount: state.historyList.length,
                          itemBuilder: (context, index) {
                            final entry = state.historyList[index];
                            final date = DateTime.fromMillisecondsSinceEpoch(entry.detectedAt);
                            final formattedDate = DateFormat('dd MMM yyyy, HH:mm').format(date);
                            final File imageFile = File(entry.imagePath);

                            return AppCard(
                              margin: const EdgeInsets.only(bottom: 16),
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  // Thumbnail Gambar
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: imageFile.existsSync()
                                        ? Image.file(
                                            imageFile,
                                            width: 80,
                                            height: 80,
                                            fit: BoxFit.cover,
                                          )
                                        : Container(
                                            width: 80,
                                            height: 80,
                                            color: Colors.grey[300],
                                            child: const Icon(Icons.image_not_supported, color: Colors.grey),
                                          ),
                                  ),
                                  const SizedBox(width: 16),
                                  // Info Deteksi
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          entry.disease.nama,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.textPrimary,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Confidence: ${(entry.topConfidence * 100).toStringAsFixed(1)}%',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: entry.topConfidence > 0.5 ? AppColors.primary : AppColors.secondary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          formattedDate,
                                          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Tombol Hapus
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: AppColors.error),
                                    onPressed: () {
                                      showDialog(
                                        context: context,
                                        builder: (BuildContext dialogContext) {
                                          return AlertDialog(
                                            title: const Text('Hapus Riwayat'),
                                            content: const Text('Apakah Anda yakin ingin menghapus data riwayat ini?'),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.of(dialogContext).pop(),
                                                child: const Text('Batal'),
                                              ),
                                              TextButton(
                                                onPressed: () {
                                                  Navigator.of(dialogContext).pop();
                                                  context.read<HistoryCubit>().deleteHistory(entry.id);
                                                },
                                                child: const Text(
                                                  'Hapus',
                                                  style: TextStyle(color: AppColors.error),
                                                ),
                                              ),
                                            ],
                                          );
                                        },
                                      );
                                    },
                                  )
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context, HistoryLoaded state) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
              ),
              child: TextField(
                onChanged: (val) => context.read<HistoryCubit>().changeSearchQuery(val),
                decoration: const InputDecoration(
                  hintText: 'Cari riwayat...',
                  prefixIcon: Icon(Icons.search, color: Colors.grey),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            decoration: BoxDecoration(
              color: (state.selectedCategory != null || 
                      state.selectedDiseaseId != null || 
                      state.selectedDateFilter != 'all' || 
                      state.sortBy != 'newest')
                  ? AppColors.primary.withOpacity(0.1)
                  : Colors.grey[200],
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: Icon(
                Icons.filter_list,
                color: (state.selectedCategory != null || 
                        state.selectedDiseaseId != null || 
                        state.selectedDateFilter != 'all' || 
                        state.sortBy != 'newest')
                    ? AppColors.primary
                    : Colors.grey[700],
              ),
              onPressed: () => _showFilterBottomSheet(context, state),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips(BuildContext context, HistoryLoaded state) {
    final chips = <Widget>[];

    if (state.selectedCategory != null) {
      chips.add(
        Chip(
          label: Text('Kategori: ${state.selectedCategory}'),
          onDeleted: () => context.read<HistoryCubit>().changeCategory(null),
          deleteIconColor: AppColors.error,
          backgroundColor: AppColors.secondary.withOpacity(0.1),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }

    if (state.selectedDiseaseId != null && state.originalHistory.isNotEmpty) {
      final match = state.originalHistory.where((e) => e.disease.id == state.selectedDiseaseId);
      final diseaseName = match.isNotEmpty ? match.first.disease.nama : 'Penyakit';
      chips.add(
        Chip(
          label: Text('Penyakit: $diseaseName'),
          onDeleted: () => context.read<HistoryCubit>().changeDisease(null),
          deleteIconColor: AppColors.error,
          backgroundColor: AppColors.secondary.withOpacity(0.1),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }

    if (state.selectedDateFilter != 'all') {
      var dateLabel = '';
      if (state.selectedDateFilter == 'today') dateLabel = 'Hari Ini';
      if (state.selectedDateFilter == 'week') dateLabel = '7 Hari Terakhir';
      if (state.selectedDateFilter == 'month') dateLabel = '30 Hari Terakhir';
      
      chips.add(
        Chip(
          label: Text('Waktu: $dateLabel'),
          onDeleted: () => context.read<HistoryCubit>().changeDateFilter('all'),
          deleteIconColor: AppColors.error,
          backgroundColor: AppColors.secondary.withOpacity(0.1),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }

    if (state.sortBy != 'newest') {
      var sortLabel = '';
      if (state.sortBy == 'oldest') sortLabel = 'Terlama';
      if (state.sortBy == 'confidence_high') sortLabel = 'Confidence Tertinggi';
      if (state.sortBy == 'confidence_low') sortLabel = 'Confidence Terendah';
      
      chips.add(
        Chip(
          label: Text('Urutan: $sortLabel'),
          onDeleted: () => context.read<HistoryCubit>().changeSort('newest'),
          deleteIconColor: AppColors.error,
          backgroundColor: AppColors.secondary.withOpacity(0.1),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 50,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        children: [
          ...chips.map((chip) => Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: chip,
              )),
          TextButton.icon(
            onPressed: () => context.read<HistoryCubit>().resetFilters(),
            icon: const Icon(Icons.clear_all, size: 16, color: AppColors.error),
            label: const Text('Reset', style: TextStyle(color: AppColors.error, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsCard(List<HistoryWithDetail> originalHistory) {
    if (originalHistory.isEmpty) return const SizedBox.shrink();
    
    final total = originalHistory.length;
    final avgConf = originalHistory.map((e) => e.topConfidence).reduce((a, b) => a + b) / total;
    final avgConfPct = (avgConf * 100).toStringAsFixed(1);
    
    final catCounts = <String, int>{};
    for (final item in originalHistory) {
      final cat = item.disease.kategori;
      catCounts[cat] = (catCounts[cat] ?? 0) + 1;
    }
    
    var topCategory = '-';
    var maxCount = 0;
    catCounts.forEach((cat, count) {
      if (count > maxCount) {
        maxCount = count;
        topCategory = cat;
      }
    });

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        gradient: LinearGradient(
          colors: [AppColors.primary.withOpacity(0.05), Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem('Total Deteksi', '$total', Icons.analytics_outlined),
          _buildStatItem('Rerata Akurasi', '$avgConfPct%', Icons.offline_bolt_outlined),
          _buildStatItem('Dominan', topCategory, Icons.spa_outlined),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: AppColors.secondary, size: 24),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  void _showFilterBottomSheet(BuildContext context, HistoryLoaded state) {
    final uniqueDiseases = <String, String>{};
    for (final item in state.originalHistory) {
      uniqueDiseases[item.disease.id] = item.disease.nama;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (modalContext) {
        return StatefulBuilder(
          builder: (stContext, setStateForSheet) {
            return Padding(
              padding: const EdgeInsets.all(20.0),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Filter & Urutkan',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                        ),
                        TextButton(
                          onPressed: () {
                            context.read<HistoryCubit>().resetFilters();
                            Navigator.pop(modalContext);
                          },
                          child: const Text('Reset Semua', style: TextStyle(color: AppColors.error)),
                        ),
                      ],
                    ),
                    const Divider(),
                    const SizedBox(height: 12),
                    
                    const Text('Kategori Bagian', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: ['Semua', 'Batang', 'Buah', 'Daun'].map((cat) {
                        final isSelected = (cat == 'Semua' && state.selectedCategory == null) ||
                            (state.selectedCategory != null && state.selectedCategory!.toLowerCase() == cat.toLowerCase());
                        return ChoiceChip(
                          label: Text(cat),
                          selected: isSelected,
                          onSelected: (selected) {
                            if (selected) {
                              context.read<HistoryCubit>().changeCategory(cat == 'Semua' ? null : cat);
                              Navigator.pop(modalContext);
                            }
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),

                    const Text('Rentang Waktu', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        {'id': 'all', 'label': 'Semua'},
                        {'id': 'today', 'label': 'Hari Ini'},
                        {'id': 'week', 'label': '7 Hari Terakhir'},
                        {'id': 'month', 'label': '30 Hari Terakhir'},
                      ].map((dateOption) {
                        final isSelected = state.selectedDateFilter == dateOption['id'];
                        return ChoiceChip(
                          label: Text(dateOption['label']!),
                          selected: isSelected,
                          onSelected: (selected) {
                            if (selected) {
                              context.read<HistoryCubit>().changeDateFilter(dateOption['id']!);
                              Navigator.pop(modalContext);
                            }
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),

                    if (uniqueDiseases.isNotEmpty) ...[
                      const Text('Jenis Penyakit / Label', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String?>(
                        initialValue: state.selectedDiseaseId,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: Colors.grey[100],
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        hint: const Text('Pilih penyakit...'),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('Semua Penyakit'),
                          ),
                          ...uniqueDiseases.entries.map((entry) => DropdownMenuItem<String?>(
                                value: entry.key,
                                child: Text(entry.value),
                              )),
                        ],
                        onChanged: (val) {
                          context.read<HistoryCubit>().changeDisease(val);
                          Navigator.pop(modalContext);
                        },
                      ),
                      const SizedBox(height: 20),
                    ],

                    const Text('Urutkan Berdasarkan', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        {'id': 'newest', 'label': 'Terbaru'},
                        {'id': 'oldest', 'label': 'Terlama'},
                        {'id': 'confidence_high', 'label': 'Confidence Tertinggi'},
                        {'id': 'confidence_low', 'label': 'Confidence Terendah'},
                      ].map((sortOption) {
                        final isSelected = state.sortBy == sortOption['id'];
                        return ChoiceChip(
                          label: Text(sortOption['label']!),
                          selected: isSelected,
                          onSelected: (selected) {
                            if (selected) {
                              context.read<HistoryCubit>().changeSort(sortOption['id']!);
                              Navigator.pop(modalContext);
                            }
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}