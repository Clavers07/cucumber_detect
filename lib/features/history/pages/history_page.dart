import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart'; // Jangan lupa tambahkan dependensi 'intl' di pubspec.yaml nanti
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_card.dart';
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
            if (state.historyList.isEmpty) {
              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.history_toggle_off, size: 64, color: Colors.grey),
                    SizedBox(height: 16),
                    Text('Belum ada riwayat deteksi.', style: TextStyle(color: Colors.grey)),
                  ],
                ),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: state.historyList.length,
              itemBuilder: (context, index) {
                final entry = state.historyList[index];
                final date = DateTime.fromMillisecondsSinceEpoch(entry.detectedAt);
                final formattedDate = DateFormat('dd MMM yyyy, HH:mm').format(date); // Butuh package intl
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
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }
}