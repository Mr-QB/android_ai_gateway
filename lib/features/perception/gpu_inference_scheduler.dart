import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

enum GpuPriority { yoloRealtime, smolOccasional, gemmaDeep }

class _GpuWaiter {
  final ready = Completer<_GpuLease?>();
  _GpuLease? lease;
  bool cancelled = false;
}

class _GpuLease {
  _GpuLease(this._release);
  final VoidCallback _release;
  bool _released = false;

  void release() {
    if (_released) return;
    _released = true;
    _release();
  }
}

class GpuInferenceScheduler {
  static final GpuInferenceScheduler _instance =
      GpuInferenceScheduler._internal();
  factory GpuInferenceScheduler() => _instance;
  GpuInferenceScheduler._internal();

  final Queue<_GpuWaiter> _waiters = Queue<_GpuWaiter>();
  bool _gpuHeld = false;
  final ValueNotifier<bool> isGemmaActive = ValueNotifier<bool>(false);

  Future<T> runWithGpuLock<T>({
    required GpuPriority priority,
    required Future<T> Function() action,
  }) async {
    final lease = await _acquire(_GpuWaiter());
    if (priority == GpuPriority.gemmaDeep) {
      isGemmaActive.value = true;
      debugPrint(
        '[GpuScheduler] Gemma deep reasoning acquiring GPU, throttling YOLO frequency...',
      );
    }
    try {
      return await action();
    } finally {
      if (priority == GpuPriority.gemmaDeep) {
        isGemmaActive.value = false;
        debugPrint(
          '[GpuScheduler] Gemma finished, restoring YOLO inference rate.',
        );
      }
      lease?.release();
    }
  }

  Stream<T> runStreamWithGpuLock<T>({
    required GpuPriority priority,
    required Stream<T> Function() action,
  }) {
    final waiter = _GpuWaiter();
    _GpuLease? lease;
    StreamSubscription<T>? source;
    late StreamController<T> controller;
    controller = StreamController<T>(
      sync: true,
      onListen: () async {
        lease = await _acquire(waiter);
        if (lease == null || controller.isClosed) {
          lease?.release();
          return;
        }
        if (priority == GpuPriority.gemmaDeep) {
          isGemmaActive.value = true;
        }
        try {
          source = action().listen(
            controller.add,
            onError: controller.addError,
            onDone: () {
              if (priority == GpuPriority.gemmaDeep) {
                isGemmaActive.value = false;
              }
              lease?.release();
              if (!controller.isClosed) unawaited(controller.close());
            },
          );
        } catch (error, stack) {
          if (priority == GpuPriority.gemmaDeep) isGemmaActive.value = false;
          lease?.release();
          controller.addError(error, stack);
          unawaited(controller.close());
        }
      },
      onCancel: () async {
        waiter.cancelled = true;
        if (_waiters.remove(waiter) && !waiter.ready.isCompleted) {
          waiter.ready.complete(null);
        }
        await source?.cancel();
        if (priority == GpuPriority.gemmaDeep) isGemmaActive.value = false;
        lease?.release();
      },
    );
    return controller.stream;
  }

  Future<_GpuLease?> _acquire(_GpuWaiter waiter) {
    if (waiter.cancelled) {
      waiter.ready.complete(null);
    } else if (!_gpuHeld) {
      _gpuHeld = true;
      _grant(waiter);
    } else {
      _waiters.addLast(waiter);
    }
    return waiter.ready.future;
  }

  void _grant(_GpuWaiter waiter) {
    final lease = _GpuLease(_releaseGpu);
    waiter.lease = lease;
    waiter.ready.complete(lease);
  }

  void _releaseGpu() {
    while (_waiters.isNotEmpty) {
      final next = _waiters.removeFirst();
      if (next.cancelled) {
        if (!next.ready.isCompleted) next.ready.complete(null);
        continue;
      }
      _grant(next);
      return;
    }
    _gpuHeld = false;
  }
}
