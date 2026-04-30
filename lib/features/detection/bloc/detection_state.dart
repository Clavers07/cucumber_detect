import 'dart:io';
import 'package:equatable/equatable.dart';
import '../../../data/models/detection_models.dart';

abstract class DetectionState extends Equatable {
  const DetectionState();

  @override
  List<Object?> get props => [];
}

class DetectionInitial extends DetectionState {}

class DetectionLoading extends DetectionState {
  final String message;
  const DetectionLoading(this.message);

  @override
  List<Object?> get props => [message];
}

class DetectionSuccess extends DetectionState {
  final File image;
  final List<DetectionBox> detections;
  final int inferenceTime;
  final List<String> labels;

  const DetectionSuccess({
    required this.image,
    required this.detections,
    required this.inferenceTime,
    required this.labels,
  });

  @override
  List<Object?> get props => [image, detections, inferenceTime, labels];
}

class DetectionError extends DetectionState {
  final String errorMessage;
  const DetectionError(this.errorMessage);

  @override
  List<Object?> get props => [errorMessage];
}
