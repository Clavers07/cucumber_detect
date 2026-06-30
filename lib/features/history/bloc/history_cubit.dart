import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/database/database_service.dart';
import '../../../data/models/detection_models.dart';
import 'history_state.dart';

class HistoryCubit extends Cubit<HistoryState> {
  final DatabaseService _dbService = DatabaseService.instance;

  HistoryCubit() : super(HistoryInitial());

  // Mengambil seluruh riwayat dari SQLite
  Future<void> loadHistory() async {
    try {
      emit(HistoryLoading());
      final history = await _dbService.getAllHistoryWithDetail();
      
      // Default sort: Terbaru
      final sortedHistory = List<HistoryWithDetail>.from(history)
        ..sort((a, b) => b.detectedAt.compareTo(a.detectedAt));

      emit(HistoryLoaded(
        originalHistory: sortedHistory,
        historyList: sortedHistory,
      ));
    } catch (e) {
      emit(HistoryError('Gagal memuat riwayat: $e'));
    }
  }

  // Menghapus satu entri riwayat
  Future<void> deleteHistory(int id) async {
    try {
      await _dbService.deleteHistory(id);
      // Muat ulang data setelah berhasil dihapus
      await loadHistory();
    } catch (e) {
      emit(HistoryError('Gagal menghapus riwayat: $e'));
    }
  }

  // --- FILTER, SORT & PAGINATION OPERATIONS ---

  void changeSearchQuery(String query) {
    final currentState = state;
    if (currentState is HistoryLoaded) {
      final filteredList = _applyFiltersAndSort(
        list: currentState.originalHistory,
        query: query,
        category: currentState.selectedCategory,
        diseaseId: currentState.selectedDiseaseId,
        dateFilter: currentState.selectedDateFilter,
        sortBy: currentState.sortBy,
      );
      emit(currentState.copyWith(
        searchQuery: query,
        historyList: filteredList,
        currentPage: 1, // Reset ke halaman 1 saat filter berubah
      ));
    }
  }

  void changeCategory(String? category) {
    final currentState = state;
    if (currentState is HistoryLoaded) {
      final filteredList = _applyFiltersAndSort(
        list: currentState.originalHistory,
        query: currentState.searchQuery,
        category: category,
        diseaseId: currentState.selectedDiseaseId,
        dateFilter: currentState.selectedDateFilter,
        sortBy: currentState.sortBy,
      );
      emit(currentState.copyWith(
        selectedCategory: () => category,
        historyList: filteredList,
        currentPage: 1, // Reset ke halaman 1
      ));
    }
  }

  void changeDisease(String? diseaseId) {
    final currentState = state;
    if (currentState is HistoryLoaded) {
      final filteredList = _applyFiltersAndSort(
        list: currentState.originalHistory,
        query: currentState.searchQuery,
        category: currentState.selectedCategory,
        diseaseId: diseaseId,
        dateFilter: currentState.selectedDateFilter,
        sortBy: currentState.sortBy,
      );
      emit(currentState.copyWith(
        selectedDiseaseId: () => diseaseId,
        historyList: filteredList,
        currentPage: 1, // Reset ke halaman 1
      ));
    }
  }

  void changeDateFilter(String dateFilter) {
    final currentState = state;
    if (currentState is HistoryLoaded) {
      final filteredList = _applyFiltersAndSort(
        list: currentState.originalHistory,
        query: currentState.searchQuery,
        category: currentState.selectedCategory,
        diseaseId: currentState.selectedDiseaseId,
        dateFilter: dateFilter,
        sortBy: currentState.sortBy,
      );
      emit(currentState.copyWith(
        selectedDateFilter: dateFilter,
        historyList: filteredList,
        currentPage: 1, // Reset ke halaman 1
      ));
    }
  }

  void changeSort(String sortBy) {
    final currentState = state;
    if (currentState is HistoryLoaded) {
      final filteredList = _applyFiltersAndSort(
        list: currentState.originalHistory,
        query: currentState.searchQuery,
        category: currentState.selectedCategory,
        diseaseId: currentState.selectedDiseaseId,
        dateFilter: currentState.selectedDateFilter,
        sortBy: sortBy,
      );
      emit(currentState.copyWith(
        sortBy: sortBy,
        historyList: filteredList,
        currentPage: 1, // Reset ke halaman 1
      ));
    }
  }

  void changePage(int page) {
    final currentState = state;
    if (currentState is HistoryLoaded) {
      final totalPages = (currentState.historyList.length / currentState.pageSize).ceil();
      if (page >= 1 && page <= (totalPages == 0 ? 1 : totalPages)) {
        emit(currentState.copyWith(currentPage: page));
      }
    }
  }

  void changePageSize(int pageSize) {
    final currentState = state;
    if (currentState is HistoryLoaded) {
      emit(currentState.copyWith(
        pageSize: pageSize,
        currentPage: 1, // Reset ke halaman 1 saat ukuran halaman berubah
      ));
    }
  }

  void resetFilters() {
    final currentState = state;
    if (currentState is HistoryLoaded) {
      final filteredList = _applyFiltersAndSort(
        list: currentState.originalHistory,
        query: '',
        category: null,
        diseaseId: null,
        dateFilter: 'all',
        sortBy: 'newest',
      );
      emit(currentState.copyWith(
        searchQuery: '',
        selectedCategory: () => null,
        selectedDiseaseId: () => null,
        selectedDateFilter: 'all',
        sortBy: 'newest',
        currentPage: 1,
        historyList: filteredList,
      ));
    }
  }

  // Helper internal untuk memproses filter dan pengurutan
  List<HistoryWithDetail> _applyFiltersAndSort({
    required List<HistoryWithDetail> list,
    required String query,
    required String? category,
    required String? diseaseId,
    required String dateFilter,
    required String sortBy,
  }) {
    List<HistoryWithDetail> filtered = List.from(list);

    // 1. Filter Pencarian (Nama Penyakit atau Nama Latin)
    if (query.isNotEmpty) {
      final lowerQuery = query.toLowerCase();
      filtered = filtered.where((item) =>
          item.disease.nama.toLowerCase().contains(lowerQuery) ||
          item.disease.namaLatin.toLowerCase().contains(lowerQuery)).toList();
    }

    // 2. Filter Kategori
    if (category != null && category.isNotEmpty) {
      filtered = filtered.where((item) => item.disease.kategori.toLowerCase() == category.toLowerCase()).toList();
    }

    // 3. Filter Jenis Penyakit/Label
    if (diseaseId != null && diseaseId.isNotEmpty) {
      filtered = filtered.where((item) => item.disease.id == diseaseId).toList();
    }

    // 4. Filter Waktu/Tanggal
    if (dateFilter != 'all') {
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      
      filtered = filtered.where((item) {
        final date = DateTime.fromMillisecondsSinceEpoch(item.detectedAt);
        if (dateFilter == 'today') {
          return date.isAfter(todayStart);
        } else if (dateFilter == 'week') {
          final weekAgo = now.subtract(const Duration(days: 7));
          return date.isAfter(weekAgo);
        } else if (dateFilter == 'month') {
          final monthAgo = now.subtract(const Duration(days: 30));
          return date.isAfter(monthAgo);
        }
        return true;
      }).toList();
    }

    // 5. Urutkan (Sorting)
    if (sortBy == 'newest') {
      filtered.sort((a, b) => b.detectedAt.compareTo(a.detectedAt));
    } else if (sortBy == 'oldest') {
      filtered.sort((a, b) => a.detectedAt.compareTo(b.detectedAt));
    } else if (sortBy == 'confidence_high') {
      filtered.sort((a, b) => b.topConfidence.compareTo(a.topConfidence));
    } else if (sortBy == 'confidence_low') {
      filtered.sort((a, b) => a.topConfidence.compareTo(b.topConfidence));
    }

    return filtered;
  }
}