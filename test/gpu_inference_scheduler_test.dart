import 'dart:async';

import 'package:android_ai_gateway/features/perception/gpu_inference_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'keeps the GPU lock for the full stream and releases on cancel',
    () async {
      final scheduler = GpuInferenceScheduler();
      final controller = StreamController<int>();
      final events = <String>[];
      final subscription = scheduler
          .runStreamWithGpuLock(
            priority: GpuPriority.smolOccasional,
            action: () {
              events.add('stream-start');
              return controller.stream;
            },
          )
          .listen((_) {});
      await Future<void>.delayed(Duration.zero);
      final queuedAction = scheduler.runWithGpuLock(
        priority: GpuPriority.yoloRealtime,
        action: () async => events.add('action'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(events, ['stream-start']);
      await subscription.cancel();
      await queuedAction.timeout(const Duration(seconds: 1));
      expect(events, ['stream-start', 'action']);
      await controller.close();
    },
  );
  test('canceling a queued stream does not strand the GPU lock', () async {
    final scheduler = GpuInferenceScheduler();
    final releaseFirst = Completer<void>();
    final firstStarted = Completer<void>();
    final first = scheduler.runWithGpuLock(
      priority: GpuPriority.gemmaDeep,
      action: () async {
        firstStarted.complete();
        await releaseFirst.future;
      },
    );
    await firstStarted.future;
    var streamStarted = false;
    final pending = scheduler
        .runStreamWithGpuLock(
          priority: GpuPriority.smolOccasional,
          action: () {
            streamStarted = true;
            return const Stream<int>.empty();
          },
        )
        .listen((_) {});
    await pending.cancel();
    final after = scheduler.runWithGpuLock(
      priority: GpuPriority.yoloRealtime,
      action: () async => true,
    );
    releaseFirst.complete();
    await first;
    expect(await after.timeout(const Duration(seconds: 1)), isTrue);
    expect(streamStarted, isFalse);
  });
}
