import 'detection.dart';
import 'inference_metrics.dart';

class DetectionBatch {
  final List<Detection> detections;
  final double inferenceTimeMs;
  final InferenceMetrics? metrics;

  const DetectionBatch({
    required this.detections,
    required this.inferenceTimeMs,
    this.metrics,
  });
}
