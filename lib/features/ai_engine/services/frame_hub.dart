import 'dart:async';
import 'dart:typed_data' as typed;
import 'package:camera/camera.dart';

import '../domain/camera_frame.dart';

typedef RealtimeFrameConsumer = Future<void> Function(CameraFrame frame);

class FrameHubStats {
  final double cameraFps;
  final double processedFps;
  final int receivedFrames;
  final int processedFrames;
  final int droppedFrames;

  const FrameHubStats({
    required this.cameraFps,
    required this.processedFps,
    required this.receivedFrames,
    required this.processedFrames,
    required this.droppedFrames,
  });

  double get dropRatePercent {
    if (receivedFrames <= 0) return 0.0;
    return (droppedFrames / receivedFrames) * 100.0;
  }
}

/// Quản lý luồng khung hình camera theo kiến trúc Latest-Frame (Queue capacity <= 1)
/// Hỗ trợ Multi-consumer: Realtime YOLO và On-demand VLM Snapshot
class FrameHub {
  typed.Uint8List? _reusableNv21Buffer;
  int _allocatedBufferCapacity = 0;

  CameraFrame? _latestPendingFrame;
  bool _isConsumerBusy = false;
  RealtimeFrameConsumer? _realtimeConsumer;

  Completer<CameraFrame>? _snapshotCompleter;

  // Thống kê FPS
  int _receivedFrames = 0;
  int _processedFrames = 0;
  int _droppedFrames = 0;

  DateTime _lastFpsCheckTime = DateTime.now();
  int _lastReceivedCount = 0;
  int _lastProcessedCount = 0;
  double _calculatedCameraFps = 0.0;
  double _calculatedProcessedFps = 0.0;

  CameraFrame? get latestFrame => _latestPendingFrame;

  void subscribeRealtimeConsumer(RealtimeFrameConsumer consumer) {
    _realtimeConsumer = consumer;
  }

  void unsubscribeRealtimeConsumer() {
    _realtimeConsumer = null;
    _latestPendingFrame = null;
    _isConsumerBusy = false;
  }

  /// Yêu cầu 1 snapshot chất lượng cao mới nhất cho VLM mà không gián đoạn stream
  Future<CameraFrame> requestSnapshot({Duration timeout = const Duration(seconds: 3)}) {
    if (_snapshotCompleter != null && !_snapshotCompleter!.isCompleted) {
      return _snapshotCompleter!.future;
    }
    final completer = Completer<CameraFrame>();
    _snapshotCompleter = completer;

    return completer.future.timeout(
      timeout,
      onTimeout: () {
        if (_snapshotCompleter == completer) {
          _snapshotCompleter = null;
        }
        throw TimeoutException('FrameHub snapshot request timed out');
      },
    );
  }

  /// Tiếp nhận CameraImage trực tiếp từ controller.startImageStream
  void onCameraImage(CameraImage image, int rotationDegrees) {
    _receivedFrames++;
    _updateFpsMetrics();

    final width = image.width;
    final height = image.height;
    final requiredSize = width * height * 3 ~/ 2;

    // Tái sử dụng buffer NV21 (chỉ allocate 1 lần duy nhất)
    if (_reusableNv21Buffer == null || _allocatedBufferCapacity < requiredSize) {
      _reusableNv21Buffer = typed.Uint8List(requiredSize);
      _allocatedBufferCapacity = requiredSize;
    }

    try {
      CameraFrame.packCameraImageToNv21(image, _reusableNv21Buffer!);
    } catch (_) {
      return;
    }

    final frame = CameraFrame(
      width: width,
      height: height,
      rotationDegrees: rotationDegrees,
      timestampUs: DateTime.now().microsecondsSinceEpoch,
      isNv12: false,
      yuvBytes: _reusableNv21Buffer!,
    );

    // 1. Phục vụ yêu cầu Snapshot cho VLM nếu có
    if (_snapshotCompleter != null && !_snapshotCompleter!.isCompleted) {
      // Copy độc lập buffer cho snapshot để tránh bị ghi đè bởi frame kế tiếp
      final snapshotBytes = typed.Uint8List(requiredSize)
        ..setRange(0, requiredSize, frame.yuvBytes);
      final snapshotFrame = CameraFrame(
        width: width,
        height: height,
        rotationDegrees: rotationDegrees,
        timestampUs: frame.timestampUs,
        isNv12: false,
        yuvBytes: snapshotBytes,
      );
      _snapshotCompleter!.complete(snapshotFrame);
      _snapshotCompleter = null;
    }

    // 2. Phục vụ Consumer Realtime YOLO với quy tắc Drop-frame (Queue size = 1)
    if (_realtimeConsumer == null) {
      return;
    }

    if (_isConsumerBusy) {
      // Consumer đang bận xử lý frame trước: ghi đè pending frame (drop frame cũ)
      if (_latestPendingFrame != null) {
        _droppedFrames++;
      }
      _latestPendingFrame = frame;
    } else {
      _processFrameLoop(frame);
    }
  }

  Future<void> _processFrameLoop(CameraFrame initialFrame) async {
    _isConsumerBusy = true;
    CameraFrame? current = initialFrame;

    while (current != null) {
      try {
        _processedFrames++;
        await _realtimeConsumer!(current);
      } catch (_) {}

      // Lấy frame mới nhất được push vào trong lúc consumer đang chạy
      current = _latestPendingFrame;
      _latestPendingFrame = null;
    }

    _isConsumerBusy = false;
  }

  void _updateFpsMetrics() {
    final now = DateTime.now();
    final elapsedMs = now.difference(_lastFpsCheckTime).inMilliseconds;
    if (elapsedMs >= 1000) {
      final recDiff = _receivedFrames - _lastReceivedCount;
      final procDiff = _processedFrames - _lastProcessedCount;
      _calculatedCameraFps = (recDiff * 1000.0) / elapsedMs;
      _calculatedProcessedFps = (procDiff * 1000.0) / elapsedMs;

      _lastReceivedCount = _receivedFrames;
      _lastProcessedCount = _processedFrames;
      _lastFpsCheckTime = now;
    }
  }

  FrameHubStats getStats() {
    return FrameHubStats(
      cameraFps: _calculatedCameraFps,
      processedFps: _calculatedProcessedFps,
      receivedFrames: _receivedFrames,
      processedFrames: _processedFrames,
      droppedFrames: _droppedFrames,
    );
  }

  void resetStats() {
    _receivedFrames = 0;
    _processedFrames = 0;
    _droppedFrames = 0;
    _lastReceivedCount = 0;
    _lastProcessedCount = 0;
    _calculatedCameraFps = 0.0;
    _calculatedProcessedFps = 0.0;
    _lastFpsCheckTime = DateTime.now();
  }

  void dispose() {
    unsubscribeRealtimeConsumer();
    _reusableNv21Buffer = null;
    _allocatedBufferCapacity = 0;
  }
}
