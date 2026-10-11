import 'package:flutter_test/flutter_test.dart';
import 'package:android_ai_gateway/features/ai_engine/domain/detection.dart';
import 'package:android_ai_gateway/features/ai_engine/domain/detection_batch.dart';
import 'package:android_ai_gateway/features/ai_engine/domain/inference_backend.dart';
import 'package:android_ai_gateway/features/ai_engine/domain/inference_metrics.dart';

void main() {
  group('InferenceBackend & Metrics Tests', () {
    test('InferenceBackend mapping from native codes', () {
      expect(InferenceBackend.fromNative(1), equals(InferenceBackend.vulkan));
      expect(InferenceBackend.fromNative(0), equals(InferenceBackend.cpu));
      expect(InferenceBackend.fromNative(2), equals(InferenceBackend.auto));
      expect(InferenceBackend.fromNative(-1), equals(InferenceBackend.auto));
    });

    test('InferenceMetrics calculates drop rate and copyWith works', () {
      const metrics = InferenceMetrics(
        preprocessMs: 2.5,
        inferenceMs: 18.0,
        postprocessMs: 1.2,
        totalNativeMs: 21.7,
        cameraFps: 30.0,
        processedFps: 22.0,
        receivedFrames: 60,
        processedFrames: 44,
        droppedFrames: 16,
        backendName: 'Vulkan GPU',
        threadCount: 4,
      );

      expect(metrics.dropRatePercent, closeTo(26.66, 0.05));

      final copied = metrics.copyWith(processedFps: 25.0);
      expect(copied.processedFps, equals(25.0));
      expect(copied.inferenceMs, equals(18.0));
    });

    test('DetectionBatch holds detections and metrics correctly', () {
      const detection = Detection(
        classId: 0,
        confidence: 0.92,
        x: 10.0,
        y: 20.0,
        width: 100.0,
        height: 200.0,
      );

      const batch = DetectionBatch(
        detections: [detection],
        inferenceTimeMs: 15.5,
        metrics: InferenceMetrics(inferenceMs: 15.5),
      );

      expect(batch.detections.length, equals(1));
      expect(batch.detections.first.classId, equals(0));
      expect(batch.inferenceTimeMs, equals(15.5));
      expect(batch.metrics?.inferenceMs, equals(15.5));
    });
  });
}
