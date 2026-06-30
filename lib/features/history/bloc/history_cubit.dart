import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/database/database_service.dart';
import 'history_state.dart';

class HistoryCubit extends Cubit<HistoryState> {
  final DatabaseService _dbService = DatabaseService.instance;

  HistoryCubit() : super(HistoryInitial());

  // Mengambil seluruh riwayat dari SQLite
  Future<void> loadHistory() async {
    try {
      emit(HistoryLoading());
      // Pemanggilan ini berjalan asinkronus dengan query JOIN
      final history = await _dbService.getAllHistoryWithDetail();
      emit(HistoryLoaded(history));
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
}