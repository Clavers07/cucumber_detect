import 'package:camera/camera.dart';
import 'package:equatable/equatable.dart';
import '../../../../data/models/detection_models.dart';

abstract class LiveDetectionState extends Equatable {
  const LiveDetectionState();

  @override
  List<Object?> get props => [];
}

class LiveDetectionInitial extends LiveDetectionState {}

class LiveDetectionLoading extends LiveDetectionState {}

class LiveDetectionActive extends LiveDetectionState {
  final CameraController cameraController;
  final List<DetectionBox> currentDetections;
  final bool isDetecting;

  const LiveDetectionActive({
    required this.cameraController,
    required this.currentDetections,
    this.isDetecting = false,
  });

  LiveDetectionActive copyWith({
    CameraController? cameraController,
    List<DetectionBox>? currentDetections,
    bool? isDetecting,
  }) {
    return LiveDetectionActive(
      cameraController: cameraController ?? this.cameraController,
      currentDetections: currentDetections ?? this.currentDetections,
      isDetecting: isDetecting ?? this.isDetecting,
    );
  }

  @override
  List<Object?> get props => [cameraController, currentDetections, isDetecting];
}

class LiveDetectionFrozen extends LiveDetectionState {
  final XFile imageFile;
  final List<DetectionBox> detections;
  final String imagePath;
  
  const LiveDetectionFrozen({
    required this.imageFile,
    required this.detections,
    required this.imagePath,
  });

  @override
  List<Object?> get props => [imageFile, detections, imagePath];
}

class LiveDetectionError extends LiveDetectionState {
  final String message;
  
  const LiveDetectionError(this.message);
  
  @override
  List<Object?> get props => [message];
}
