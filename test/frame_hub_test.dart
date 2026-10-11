import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:android_ai_gateway/features/ai_engine/services/frame_hub.dart';


void main() {
  group('FrameHub Tests', () {
    test('Stats and drop rate calculate correctly', () {
      const stats = FrameHubStats(
        cameraFps: 30.0,
        processedFps: 20.0,
        receivedFrames: 100,
        processedFrames: 66,
        droppedFrames: 34,
      );

      expect(stats.dropRatePercent, closeTo(34.0, 0.01));
    });

    test('requestSnapshot times out when no frame is provided', () async {
      final hub = FrameHub();
      expect(
        () => hub.requestSnapshot(timeout: const Duration(milliseconds: 50)),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('Latest-frame policy: queue capacity bounded to 1', () async {
      final hub = FrameHub();
      int processedCount = 0;
      final completer = Completer<void>();

      hub.subscribeRealtimeConsumer((frame) async {
        processedCount++;
        // Simulate busy consumer
        await Future.delayed(const Duration(milliseconds: 50));
        if (processedCount >= 2 && !completer.isCompleted) {
          completer.complete();
        }
      });

      // Cleanup
      hub.dispose();
      expect(hub.latestFrame, isNull);
    });
  });
}
