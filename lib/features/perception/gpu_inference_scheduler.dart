import 'dart:async';
import 'package:flutter/foundation.dart';

enum GpuPriority {
  yoloRealtime,
  smolOccasional,
  gemmaDeep,
}

class GpuInferenceScheduler {
  static final GpuInferenceScheduler _instance = GpuInferenceScheduler._internal();
  factory GpuInferenceScheduler() => _instance;
  GpuInferenceScheduler._internal();

  Completer<void>? _activeInferenceLock;
  final ValueNotifier<bool> isGemmaActive = ValueNotifier<bool>(false);

  /// Acquires GPU access for an inference task.
  /// If Gemma is running, other GPU tasks queue or wait.
  Future<T> runWithGpuLock<T>({
    required GpuPriority priority,
    required Future<T> Function() action,
  }) async {
    while (_activeInferenceLock != null && !_activeInferenceLock!.isCompleted) {
      await _activeInferenceLock!.future;
    }

    final currentLock = Completer<void>();
    _activeInferenceLock = currentLock;

    if (priority == GpuPriority.gemmaDeep) {
      isGemmaActive.value = true;
      debugPrint('[GpuScheduler] Gemma deep reasoning acquiring GPU, throttling YOLO frequency...');
    }

    try {
      final result = await action();
      return result;
    } finally {
      if (priority == GpuPriority.gemmaDeep) {
        isGemmaActive.value = false;
        debugPrint('[GpuScheduler] Gemma finished, restoring YOLO inference rate.');
      }
      currentLock.complete();
      if (_activeInferenceLock == currentLock) {
        _activeInferenceLock = null;
      }
    }
  }
}
