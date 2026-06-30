import 'package:equatable/equatable.dart';
import '../../../data/models/detection_models.dart';

abstract class HistoryState extends Equatable {
  const HistoryState();

  @override
  List<Object?> get props => [];
}

class HistoryInitial extends HistoryState {}

class HistoryLoading extends HistoryState {}

class HistoryLoaded extends HistoryState {
  final List<HistoryWithDetail> originalHistory;
  final List<HistoryWithDetail> historyList; // Ini adalah filteredHistory, dipertahankan namanya agar tidak memecah UI lama
  
  final String searchQuery;
  final String? selectedCategory;
  final String? selectedDiseaseId;
  final String selectedDateFilter; // 'all', 'today', 'week', 'month'
  final String sortBy;             // 'newest', 'oldest', 'confidence_high', 'confidence_low'

  const HistoryLoaded({
    required this.originalHistory,
    required this.historyList,
    this.searchQuery = '',
    this.selectedCategory,
    this.selectedDiseaseId,
    this.selectedDateFilter = 'all',
    this.sortBy = 'newest',
  });

  HistoryLoaded copyWith({
    List<HistoryWithDetail>? originalHistory,
    List<HistoryWithDetail>? historyList,
    String? searchQuery,
    String? Function()? selectedCategory,
    String? Function()? selectedDiseaseId,
    String? selectedDateFilter,
    String? sortBy,
  }) {
    return HistoryLoaded(
      originalHistory: originalHistory ?? this.originalHistory,
      historyList: historyList ?? this.historyList,
      searchQuery: searchQuery ?? this.searchQuery,
      selectedCategory: selectedCategory != null ? selectedCategory() : this.selectedCategory,
      selectedDiseaseId: selectedDiseaseId != null ? selectedDiseaseId() : this.selectedDiseaseId,
      selectedDateFilter: selectedDateFilter ?? this.selectedDateFilter,
      sortBy: sortBy ?? this.sortBy,
    );
  }

  @override
  List<Object?> get props => [
        originalHistory,
        historyList,
        searchQuery,
        selectedCategory,
        selectedDiseaseId,
        selectedDateFilter,
        sortBy,
      ];
}

class HistoryError extends HistoryState {
  final String message;

  const HistoryError(this.message);

  @override
  List<Object?> get props => [message];
}