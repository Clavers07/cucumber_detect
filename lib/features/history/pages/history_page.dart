import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/bounding_box_overlay.dart';
import '../../../data/models/detection_models.dart';
import '../../../core/database/database_service.dart';
import '../../../core/utils/image_utils.dart';
import '../../../core/services/pdf_export_service.dart';
import '../../dictionary/pages/disease_detail_page.dart';
import '../bloc/history_cubit.dart';
import '../bloc/history_state.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<String> _labels = [];
  bool _isSelectionMode = false;
  final Set<int> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _loadLabels();
    // Memuat data secara otomatis saat halaman dibuka
    context.read<HistoryCubit>().loadHistory();
  }

  Future<void> _loadLabels() async {
    try {
      final labelsData = await rootBundle.loadString('assets/labels.txt');
      if (mounted) {
        setState(() {
          _labels = const LineSplitter().convert(labelsData).map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
        });
      }
    } catch (e) {
      debugPrint('❌ Gagal memuat labels.txt di HistoryPage: $e');
    }
  }

  Future<void> _exportSelectedToPdf(BuildContext context, List<int> selectedIds) async {
    final int totalCount = selectedIds.length;
    final ValueNotifier<int> progressNotifier = ValueNotifier<int>(0);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return ValueListenableBuilder<int>(
          valueListenable: progressNotifier,
          builder: (context, value, child) {
            return AlertDialog(
              title: const Text('Membuat Laporan PDF'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: AppColors.primary),
                  const SizedBox(height: 16),
                  Text('Memproses gambar: $value dari $totalCount...'),
                ],
              ),
            );
          },
        );
      },
    );

    try {
      final historyCubit = context.read<HistoryCubit>();
      final List<HistoryWithDetail> selectedEntries = [];
      
      final state = historyCubit.state;
      if (state is HistoryLoaded) {
        for (var id in selectedIds) {
          final entry = state.historyList.firstWhere((e) => e.id == id);
          selectedEntries.add(entry);
        }
      }

      if (selectedEntries.isEmpty) {
        if (context.mounted) Navigator.of(context).pop();
        return;
      }

      final pdfBytes = await PdfExportService.generatePdfReport(
        entries: selectedEntries,
        labels: _labels,
        confidenceThreshold: 0.40,
        onProgress: (processed, total) {
          progressNotifier.value = processed;
        },
      );

      if (context.mounted) {
        Navigator.of(context).pop(); // Tutup loading dialog
        
        setState(() {
          _isSelectionMode = false;
          _selectedIds.clear();
        });

        await Printing.layoutPdf(
          onLayout: (PdfPageFormat format) async => pdfBytes,
          name: 'laporan_kesehatan_sawit_${DateTime.now().millisecondsSinceEpoch}.pdf',
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop(); // Tutup loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengekspor PDF: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _isSelectionMode
          ? AppBar(
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  setState(() {
                    _isSelectionMode = false;
                    _selectedIds.clear();
                  });
                },
              ),
              title: Text('${_selectedIds.length} Terpilih'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.select_all),
                  tooltip: 'Pilih Semua',
                  onPressed: () {
                    final historyState = context.read<HistoryCubit>().state;
                    if (historyState is HistoryLoaded) {
                      final startIndex = (historyState.currentPage - 1) * historyState.pageSize;
                      final endIndex = (startIndex + historyState.pageSize) < historyState.historyList.length 
                          ? (startIndex + historyState.pageSize) 
                          : historyState.historyList.length;
                      final pageItems = historyState.historyList.sublist(startIndex, endIndex);

                      setState(() {
                        final allSelected = pageItems.every((item) => _selectedIds.contains(item.id));
                        if (allSelected) {
                          for (var item in pageItems) {
                            _selectedIds.remove(item.id);
                          }
                        } else {
                          for (var item in pageItems) {
                            _selectedIds.add(item.id);
                          }
                        }
                      });
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.picture_as_pdf),
                  tooltip: 'Cetak/Ekspor PDF',
                  onPressed: _selectedIds.isEmpty
                      ? null
                      : () => _exportSelectedToPdf(context, _selectedIds.toList()),
                ),
              ],
            )
          : AppBar(
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
            final startIndex = (state.currentPage - 1) * state.pageSize;
            final endIndex = (startIndex + state.pageSize) < state.historyList.length 
                ? (startIndex + state.pageSize) 
                : state.historyList.length;
            final pageItems = state.historyList.sublist(startIndex, endIndex);

            return Column(
              children: [
                _buildSearchBar(context, state),
                _buildFilterChips(context, state),
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
                          itemCount: pageItems.length,
                          itemBuilder: (context, index) {
                            final entry = pageItems[index];
                            final date = DateTime.fromMillisecondsSinceEpoch(entry.detectedAt);
                            final formattedDate = DateFormat('dd MMM yyyy, HH:mm').format(date);
                            final File imageFile = File(entry.imagePath);

                            return GestureDetector(
                              onTap: () {
                                if (_isSelectionMode) {
                                  setState(() {
                                    if (_selectedIds.contains(entry.id)) {
                                      _selectedIds.remove(entry.id);
                                      if (_selectedIds.isEmpty) {
                                        _isSelectionMode = false;
                                      }
                                    } else {
                                      _selectedIds.add(entry.id);
                                    }
                                  });
                                } else {
                                  _showDetailBottomSheet(context, entry);
                                }
                              },
                              onLongPress: () {
                                if (!_isSelectionMode) {
                                  setState(() {
                                    _isSelectionMode = true;
                                    _selectedIds.add(entry.id);
                                  });
                                }
                              },
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 16),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  border: _isSelectionMode && _selectedIds.contains(entry.id)
                                      ? Border.all(color: AppColors.primary, width: 1.5)
                                      : null,
                                ),
                                child: AppCard(
                                  margin: EdgeInsets.zero,
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                  children: [
                                    // Checkbox untuk Selection Mode
                                    if (_isSelectionMode) ...[
                                      Checkbox(
                                        activeColor: AppColors.primary,
                                        value: _selectedIds.contains(entry.id),
                                        onChanged: (bool? checked) {
                                          setState(() {
                                            if (checked == true) {
                                              _selectedIds.add(entry.id);
                                            } else {
                                              _selectedIds.remove(entry.id);
                                              if (_selectedIds.isEmpty) {
                                                _isSelectionMode = false;
                                              }
                                            }
                                          });
                                        },
                                      ),
                                      const SizedBox(width: 8),
                                    ],
                                    // Thumbnail Gambar
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: imageFile.existsSync()
                                          ? Image.file(
                                              imageFile,
                                              width: 80,
                                              height: 80,
                                              fit: BoxFit.cover,
                                              cacheWidth: 160,
                                              cacheHeight: 160,
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
                                          Row(
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  entry.disease.nama,
                                                  style: const TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.bold,
                                                    color: AppColors.textPrimary,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              if (entry.diseaseList.length > 1) ...[
                                                const SizedBox(width: 6),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: Colors.grey[200],
                                                    borderRadius: BorderRadius.circular(6),
                                                    border: Border.all(color: Colors.grey[300]!, width: 0.5),
                                                  ),
                                                  child: Text(
                                                    '+${entry.diseaseList.length - 1}',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.bold,
                                                      color: Colors.grey[700],
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          Wrap(
                                            spacing: 4,
                                            runSpacing: 4,
                                            children: entry.labelSummaries.map((summary) {
                                              return Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: AppColors.primary.withOpacity(0.08),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  summary,
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                    color: AppColors.primary,
                                                  ),
                                                ),
                                              );
                                            }).toList(),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            formattedDate,
                                            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                          ),
                                        ],
                                      ),
                                    ),
                                    // Tombol Hapus (hanya tampil jika tidak dalam selection mode)
                                    if (!_isSelectionMode)
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
                              ),
                            ),
                          );
                          },
                        ),
                ),
                _buildPaginationControl(context, state),
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

  Widget _buildPaginationControl(BuildContext context, HistoryLoaded state) {
    if (state.historyList.isEmpty) return const SizedBox.shrink();

    final totalItems = state.historyList.length;
    final totalPages = (totalItems / state.pageSize).ceil();
    final currentPage = state.currentPage;

    final startIndex = (currentPage - 1) * state.pageSize + 1;
    final endIndex = (currentPage * state.pageSize) < totalItems 
        ? (currentPage * state.pageSize) 
        : totalItems;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey[200]!)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                '$startIndex-$endIndex',
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            
            // Dropdown Pilihan Jumlah Data (Page Size: 5, 10, 20, 50)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Tampilkan: ', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                DropdownButton<int>(
                  value: state.pageSize,
                  items: [5, 10, 20, 50].map((size) {
                    return DropdownMenuItem<int>(
                      value: size,
                      child: Text('$size', style: const TextStyle(fontSize: 13)),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      context.read<HistoryCubit>().changePageSize(val);
                    }
                  },
                  underline: const SizedBox.shrink(),
                ),
              ],
            ),
            const SizedBox(width: 8),

            // Tombol Navigasi Halaman (Prev / Next)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left, size: 20),
                  onPressed: currentPage > 1 
                      ? () => context.read<HistoryCubit>().changePage(currentPage - 1) 
                      : null,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 4),
                Text(
                  '$currentPage / ${totalPages == 0 ? 1 : totalPages}', 
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.chevron_right, size: 20),
                  onPressed: currentPage < totalPages 
                      ? () => context.read<HistoryCubit>().changePage(currentPage + 1) 
                      : null,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ],
        ),
      ),
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

  void _showDetailBottomSheet(BuildContext context, HistoryWithDetail entry) {
    final date = DateTime.fromMillisecondsSinceEpoch(entry.detectedAt);
    final formattedDate = DateFormat('dd MMMM yyyy, HH:mm').format(date);
    final File imageFile = File(entry.imagePath);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (modalContext) {
        double localThreshold = 0.40; // State threshold lokal untuk modal ini

        return StatefulBuilder(
          builder: (stContext, setState) {
            final filteredBoxes = entry.boxList
                .where((box) => box.confidence >= localThreshold)
                .toList();

            final Map<String, List<double>> dynamicGrouped = {};
            for (var box in filteredBoxes) {
              final String label = _labels.isNotEmpty && box.classIndex < _labels.length ? _labels[box.classIndex] : 'Class ${box.classIndex}';
              dynamicGrouped.putIfAbsent(label, () => []).add(box.confidence);
            }

            final List<String> dynamicList = [];
            for (var entry in dynamicGrouped.entries) {
              final labelName = entry.key;
              final count = entry.value.length;
              final avgConf = entry.value.reduce((a, b) => a + b) / entry.value.length;
              final percentage = (avgConf * 100).toStringAsFixed(1);
              dynamicList.add('${count}x $labelName ($percentage%)');
            }

            return FutureBuilder<List<String>>(
              future: DatabaseService.instance.getAllDiseases().then((list) => list.map((d) => d.id).toList()),
              builder: (context, snapshot) {
                final availableIds = snapshot.data ?? const [];

                return DraggableScrollableSheet(
                  initialChildSize: 0.65,
                  maxChildSize: 0.90,
                  minChildSize: 0.4,
                  expand: false,
                  builder: (stScrollContext, scrollController) {
                    return SingleChildScrollView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Drag Handle
                          Center(
                            child: Container(
                              width: 40,
                              height: 5,
                              decoration: BoxDecoration(
                                color: Colors.grey[300],
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          
                          // Image Preview dengan BoundingBoxOverlay Dinamis + Download/Share Buttons
                          Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: imageFile.existsSync()
                                    ? Container(
                                        height: 200,
                                        width: double.infinity,
                                        color: Colors.black,
                                        child: FutureBuilder<ImageInfo>(
                                          future: _getImageInfo(imageFile),
                                          builder: (context, infoSnapshot) {
                                            if (!infoSnapshot.hasData) {
                                              return const Center(child: CircularProgressIndicator());
                                            }
                                            return BoundingBoxOverlay(
                                              image: imageFile,
                                              detections: filteredBoxes,
                                              originalWidth: infoSnapshot.data!.image.width.toDouble(),
                                              originalHeight: infoSnapshot.data!.image.height.toDouble(),
                                              labels: const [], // labels tidak dipakai di BoundingBoxOverlay
                                            );
                                          },
                                        ),
                                      )
                                    : Container(
                                        width: double.infinity,
                                        height: 200,
                                        color: Colors.grey[200],
                                        child: const Icon(Icons.image_not_supported, size: 64, color: Colors.grey),
                                      ),
                              ),
                              // Tombol Download dan Share
                              if (imageFile.existsSync())
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _buildImageOverlayButton(
                                        icon: Icons.download,
                                        onTap: () async {
                                          ScaffoldMessenger.of(stContext).showSnackBar(
                                            const SnackBar(content: Text('Menyiapkan file gambar...'), duration: Duration(milliseconds: 500)),
                                          );
                                          
                                          final overlayFile = await ImageUtils.generateOverlayImage(
                                            originalImageFile: imageFile,
                                            detections: entry.boxList,
                                            confidenceThreshold: localThreshold,
                                          );
                                          
                                          if (overlayFile == null) {
                                            if (modalContext.mounted) {
                                              ScaffoldMessenger.of(modalContext).showSnackBar(
                                                const SnackBar(content: Text('Gagal membuat overlay gambar.'), backgroundColor: AppColors.error),
                                              );
                                            }
                                            return;
                                          }
                                          
                                          final fileName = 'cucumber_detect_${DateTime.now().millisecondsSinceEpoch}.jpg';
                                          
                                          // Coba simpan ke folder Download umum Android terlebih dahulu
                                          if (Platform.isAndroid) {
                                            try {
                                              const publicDownloadPath = '/storage/emulated/0/Download';
                                              final File destFile = File('$publicDownloadPath/$fileName');
                                              await overlayFile.copy(destFile.path);
                                              
                                              if (modalContext.mounted) {
                                                ScaffoldMessenger.of(modalContext).showSnackBar(
                                                  const SnackBar(
                                                    content: Text('Gambar berhasil diunduh ke folder Download!'),
                                                    backgroundColor: Colors.green,
                                                  ),
                                                );
                                              }
                                              return;
                                            } catch (e) {
                                              debugPrint('⚠️ Gagal menyimpan ke Download umum: $e. Menggunakan folder alternatif...');
                                            }
                                          }
                                          
                                          try {
                                            final downloadPath = await getPublicDownloadPath();
                                            if (downloadPath != null) {
                                              final File destFile = File('$downloadPath/$fileName');
                                              await overlayFile.copy(destFile.path);
                                              
                                              if (modalContext.mounted) {
                                                ScaffoldMessenger.of(modalContext).showSnackBar(
                                                  SnackBar(
                                                    content: Text('Gambar berhasil diunduh ke: $downloadPath/$fileName'),
                                                    backgroundColor: Colors.green,
                                                  ),
                                                );
                                              }
                                            }
                                          } catch (e) {
                                            if (modalContext.mounted) {
                                              ScaffoldMessenger.of(modalContext).showSnackBar(
                                                SnackBar(content: Text('Gagal menyimpan gambar: $e'), backgroundColor: AppColors.error),
                                              );
                                            }
                                          }
                                        },
                                      ),
                                      const SizedBox(width: 8),
                                      _buildImageOverlayButton(
                                        icon: Icons.share,
                                        onTap: () async {
                                          ScaffoldMessenger.of(stContext).showSnackBar(
                                            const SnackBar(content: Text('Menyiapkan file untuk dibagikan...'), duration: Duration(milliseconds: 500)),
                                          );
                                          
                                          final overlayFile = await ImageUtils.generateOverlayImage(
                                            originalImageFile: imageFile,
                                            detections: entry.boxList,
                                            confidenceThreshold: localThreshold,
                                          );
                                          
                                          if (overlayFile == null) {
                                            if (modalContext.mounted) {
                                              ScaffoldMessenger.of(modalContext).showSnackBar(
                                                const SnackBar(content: Text('Gagal membuat file sharing.'), backgroundColor: AppColors.error),
                                              );
                                            }
                                            return;
                                          }

                                          await Share.shareXFiles(
                                            [XFile(overlayFile.path)],
                                            text: 'Hasil Deteksi AI Penyakit Kelapa Sawit (${entry.disease.nama})',
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // List Info Deteksi Dinamis
                          if (dynamicList.isNotEmpty) ...[
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: dynamicList.map((info) {
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: AppColors.primary.withOpacity(0.15), width: 1),
                                  ),
                                  child: Text(
                                    info,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 16),
                          ],

                          // Slider Confidence Dinamis di bawah gambar
                          if (entry.boxList.isNotEmpty) ...[
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Filter Confidence',
                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '${(localThreshold * 100).toStringAsFixed(0)}%',
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
                                value: localThreshold,
                                min: 0.1,
                                max: 1.0,
                                divisions: 18,
                                label: '${(localThreshold * 100).toStringAsFixed(0)}%',
                                onChanged: (value) {
                                  setState(() {
                                    localThreshold = value;
                                  });
                                },
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],

                          // Title (Top Label)
                          Text(
                            entry.disease.nama,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            entry.disease.namaLatin,
                            style: const TextStyle(
                              fontSize: 14,
                              fontStyle: FontStyle.italic,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Metadata Row (Kategori & Waktu)
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: AppColors.secondary.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  entry.disease.kategori,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.secondary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                formattedDate,
                                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                          const Divider(height: 32),

                          // Section: Semua Label Terdeteksi (Interactive CTA Badges)
                          const Text(
                            'Hasil Deteksi Multi-Label',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: List.generate(entry.diseaseList.length, (index) {
                              final String diseaseId = entry.diseaseList[index];
                              final bool isAvailable = availableIds.contains(diseaseId);
                              final String summary = entry.labelSummaries[index];
                              
                              return Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: isAvailable
                                      ? () async {
                                          final disease = await DatabaseService.instance.getDiseaseById(diseaseId);
                                          if (disease != null && modalContext.mounted) {
                                            // Tutup sheet terlebih dahulu
                                            Navigator.pop(modalContext);
                                            // Navigasi ke halaman detail
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => DiseaseDetailPage(disease: disease),
                                              ),
                                            );
                                          }
                                        }
                                      : null,
                                  borderRadius: BorderRadius.circular(10),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: isAvailable 
                                          ? AppColors.primary.withOpacity(0.08)
                                          : Colors.grey[100],
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: isAvailable 
                                            ? AppColors.primary.withOpacity(0.2)
                                            : Colors.grey[300]!,
                                        width: 1,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          summary,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: isAvailable ? AppColors.primary : Colors.grey[600],
                                          ),
                                        ),
                                        if (isAvailable) ...[
                                          const SizedBox(width: 6),
                                          const Icon(
                                            Icons.open_in_new,
                                            size: 13,
                                            color: AppColors.primary,
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
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

  Future<String?> getPublicDownloadPath() async {
    if (Platform.isAndroid) {
      // Menggunakan folder Downloads eksternal khusus aplikasi (bebas izin di Android 10+ / Scoped Storage)
      final List<Directory>? dirs = await getExternalStorageDirectories(type: StorageDirectory.downloads);
      if (dirs != null && dirs.isNotEmpty) {
        await dirs.first.create(recursive: true);
        return dirs.first.path;
      }
      return '/storage/emulated/0/Download';
    } else if (Platform.isIOS) {
      final dir = await getApplicationDocumentsDirectory();
      return dir.path;
    } else {
      final dir = await getDownloadsDirectory();
      return dir?.path;
    }
  }

  Widget _buildImageOverlayButton({required IconData icon, required VoidCallback onTap}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.10),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withOpacity(0.20), width: 1),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
        ),
      ),
    );
  }
}