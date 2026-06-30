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
  final List<HistoryWithDetail> historyList;

  const HistoryLoaded(this.historyList);

  @override
  List<Object?> get props => [historyList];
}

class HistoryError extends HistoryState {
  final String message;

  const HistoryError(this.message);

  @override
  List<Object?> get props => [message];
}