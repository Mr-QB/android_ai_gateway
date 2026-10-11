import 'dart:ffi' as ffi;
import 'dart:typed_data' as typed;

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import '../domain/camera_frame.dart';
import '../domain/detection.dart';
import '../domain/detection_batch.dart';
import '../domain/inference_backend.dart';
import '../domain/inference_metrics.dart';
import '../native/native_ai_bindings.dart';
import 'model_asset_service.dart';

class AIEngineService {
  final NativeAIBindings _bindings = NativeAIBindings();
  final ModelAssetService _modelAssetService = ModelAssetService();

  int _lastModelLoadCode = -999;
  InferenceBackend _configuredBackend = InferenceBackend.auto;
  int _configuredThreads = 0;

  // Reusable persistent Native pointers (loại bỏ malloc/calloc/free ở từng frame)
  ffi.Pointer<ffi.Uint8>? _reusableBufferPointer;
  int _reusableBufferCapacity = 0;

  ffi.Pointer<NativeDetection>? _reusableOutputPointer;
  final int _maxOutputCapacity = 100;

  ffi.Pointer<NativeAIProfilingMetrics>? _reusableMetricsPointer;
  ffi.Pointer<ffi.Uint64>? _reusableFrameIdPointer;
  ffi.Pointer<ffi.Int32>? _statsReceivedPointer;
  ffi.Pointer<ffi.Int32>? _statsProcessedPointer;
  ffi.Pointer<ffi.Int32>? _statsDroppedPointer;
  int? _lastWorkerFrameId;

  AIEngineService() {
    _ensureNativePointers();
  }

  void _ensureNativePointers() {
    _reusableOutputPointer ??= calloc<NativeDetection>(_maxOutputCapacity);
    _reusableMetricsPointer ??= calloc<NativeAIProfilingMetrics>();
    _reusableFrameIdPointer ??= calloc<ffi.Uint64>();
    _statsReceivedPointer ??= calloc<ffi.Int32>();
    _statsProcessedPointer ??= calloc<ffi.Int32>();
    _statsDroppedPointer ??= calloc<ffi.Int32>();
  }

  ffi.Pointer<ffi.Uint8> _getOrCreateBuffer(int requiredBytes) {
    if (_reusableBufferPointer == null || _reusableBufferCapacity < requiredBytes) {
      if (_reusableBufferPointer != null) {
        calloc.free(_reusableBufferPointer!);
      }
      _reusableBufferCapacity = requiredBytes;
      _reusableBufferPointer = calloc<ffi.Uint8>(requiredBytes);
    }
    return _reusableBufferPointer!;
  }

  bool get isNativeLoaded => _bindings.isLoaded;
  bool get isModelLoaded => _bindings.isYolo26ModelLoaded();
  int get lastModelLoadCode => _lastModelLoadCode;
  int get modelBackend => _bindings.getYolo26Backend();
  int get threadCount => _bindings.getYolo26Threads();
  bool get isWorkerRunning => _bindings.isYolo26WorkerRunning();
  InferenceBackend get configuredBackend => _configuredBackend;
  int get configuredThreads => _configuredThreads;

  String get modelBackendName {
    return switch (modelBackend) {
      1 => 'Vulkan GPU',
      0 => 'CPU',
      _ => 'Chưa load',
    };
  }

  int getVersion() => _bindings.getEngineVersion();
  bool hasVulkanGPU() => _bindings.hasNcnnVulkan();

  /// Khởi tạo model với lựa chọn Backend (AUTO, Vulkan, CPU) và Threads (0 = AUTO)
  Future<bool> initializeModel({
    InferenceBackend backend = InferenceBackend.auto,
    int threads = 0,
    bool? preferGpu,
  }) async {
    if (!_bindings.isLoaded) {
      _lastModelLoadCode = -100;
      return false;
    }

    // Hỗ trợ tham số cũ preferGpu nếu có caller truyền vào
    final effectiveBackend = preferGpu != null
        ? (preferGpu ? InferenceBackend.vulkan : InferenceBackend.cpu)
        : backend;

    _configuredBackend = effectiveBackend;
    _configuredThreads = threads;

    ffi.Pointer<ffi.Char>? paramPathPointer;
    ffi.Pointer<ffi.Char>? binPathPointer;

    try {
      final modelFiles = await _modelAssetService.prepareYolo26Model();
      paramPathPointer = modelFiles.paramPath.toNativeUtf8().cast<ffi.Char>();
      binPathPointer = modelFiles.binPath.toNativeUtf8().cast<ffi.Char>();

      _lastModelLoadCode = _bindings.loadYolo26ModelV2(
        paramPath: paramPathPointer,
        binPath: binPathPointer,
        backendMode: effectiveBackend.nativeMode,
        numThreads: threads,
      );

      debugPrint('YOLO26 load result: $_lastModelLoadCode, backend: $modelBackendName, threads: $threadCount');
      return _lastModelLoadCode == 0 && _bindings.isYolo26ModelLoaded();
    } catch (error, stackTrace) {
      _lastModelLoadCode = -101;
      debugPrint('YOLO26 initialization error: $error');
      debugPrintStack(stackTrace: stackTrace);
      return false;
    } finally {
      if (paramPathPointer != null) calloc.free(paramPathPointer);
      if (binPathPointer != null) calloc.free(binPathPointer);
    }
  }

  // ---------------------------------------------------------------------------
  // Realtime Worker Stream APIs (Zero UI-thread blocking, Queue size = 1)
  // ---------------------------------------------------------------------------

  bool startRealtimeWorker() {
    if (!isModelLoaded) return false;
    final code = _bindings.startYolo26Worker();
    return code == 0;
  }

  void stopRealtimeWorker() {
    _bindings.stopYolo26Worker();
  }

  /// Gửi frame YUV camera vào C++ FrameWorker (thời gian FFI < 0.3ms)
  bool pushCameraFrame(
    CameraFrame frame, {
    double probabilityThreshold = 0.40,
    double nmsThreshold = 0.50,
  }) {
    if (!isWorkerRunning) return false;

    final bytes = frame.yuvBytes;
    final buffer = _getOrCreateBuffer(bytes.length);
    buffer.asTypedList(bytes.length).setAll(0, bytes);

    final ret = _bindings.pushYolo26YuvFrame(
      yuvBytes: buffer,
      width: frame.width,
      height: frame.height,
      rotationDegrees: frame.rotationDegrees,
      isNv12: frame.isNv12 ? 1 : 0,
      probabilityThreshold: probabilityThreshold,
      nmsThreshold: nmsThreshold,
    );

    return ret == 0;
  }

  /// Đọc kết quả nhận diện mới nhất từ FrameWorker
  DetectionBatch? getLatestWorkerDetections() {
    if (!isWorkerRunning) return null;

    final output = _reusableOutputPointer!;
    final metricsPtr = _reusableMetricsPointer!;
    final frameIdPtr = _reusableFrameIdPointer!;

    final count = _bindings.getYolo26LatestResults(
      output: output,
      maxOutput: _maxOutputCapacity,
      metrics: metricsPtr,
      frameId: frameIdPtr,
    );

    if (count < 0) return null;

    final frameId = frameIdPtr.value;
    if (frameId == _lastWorkerFrameId) return null;
    _lastWorkerFrameId = frameId;

    final detections = List<Detection>.generate(count, (index) {
      final native = output[index];
      return Detection(
        classId: native.classId,
        confidence: native.confidence,
        x: native.x,
        y: native.y,
        width: native.width,
        height: native.height,
      );
    }, growable: false);

    final rawMetrics = metricsPtr.ref;
    final metrics = InferenceMetrics(
      preprocessMs: rawMetrics.preprocessTimeMs,
      inferenceMs: rawMetrics.inferenceTimeMs,
      postprocessMs: rawMetrics.postprocessTimeMs,
      totalNativeMs: rawMetrics.totalNativeTimeMs,
      backendName: modelBackendName,
      threadCount: threadCount,
    );

    return DetectionBatch(
      detections: detections,
      inferenceTimeMs: rawMetrics.inferenceTimeMs,
      metrics: metrics,
    );
  }

  void getWorkerStats(int Function(int received, int processed, int dropped) onStats) {
    if (!isWorkerRunning) return;
    _bindings.getYolo26WorkerStats(
      received: _statsReceivedPointer!,
      processed: _statsProcessedPointer!,
      dropped: _statsDroppedPointer!,
    );
    onStats(
      _statsReceivedPointer!.value,
      _statsProcessedPointer!.value,
      _statsDroppedPointer!.value,
    );
  }

  // ---------------------------------------------------------------------------
  // Synchronous Inference APIs (Tái sử dụng buffer)
  // ---------------------------------------------------------------------------

  DetectionBatch detectRgb({
    required typed.Uint8List rgbBytes,
    required int width,
    required int height,
    double probabilityThreshold = 0.40,
    double nmsThreshold = 0.50,
    int maxDetections = 100,
  }) {
    if (!_bindings.isLoaded) throw StateError('Native AI library is not loaded');
    if (!_bindings.isYolo26ModelLoaded()) throw StateError('YOLO26 model is not loaded');
    if (rgbBytes.length != width * height * 3) {
      throw ArgumentError('RGB byte count ${rgbBytes.length} does not match ${width}x$height x 3');
    }

    final rgbBuffer = _getOrCreateBuffer(rgbBytes.length);
    rgbBuffer.asTypedList(rgbBytes.length).setAll(0, rgbBytes);

    final output = _reusableOutputPointer!;
    final metricsPtr = _reusableMetricsPointer!;

    final count = _bindings.detectRgbImageWithMetrics(
      rgbBytes: rgbBuffer,
      width: width,
      height: height,
      probabilityThreshold: probabilityThreshold,
      nmsThreshold: nmsThreshold,
      output: output,
      maxOutput: maxDetections.clamp(1, _maxOutputCapacity),
      metrics: metricsPtr,
    );

    if (count < 0) {
      throw StateError('YOLO26 inference failed with code $count');
    }

    final detections = List<Detection>.generate(count, (index) {
      final native = output[index];
      return Detection(
        classId: native.classId,
        confidence: native.confidence,
        x: native.x,
        y: native.y,
        width: native.width,
        height: native.height,
      );
    }, growable: false);

    final rawMetrics = metricsPtr.ref;
    final metrics = InferenceMetrics(
      preprocessMs: rawMetrics.preprocessTimeMs,
      inferenceMs: rawMetrics.inferenceTimeMs,
      postprocessMs: rawMetrics.postprocessTimeMs,
      totalNativeMs: rawMetrics.totalNativeTimeMs,
      backendName: modelBackendName,
      threadCount: threadCount,
    );

    return DetectionBatch(
      detections: detections,
      inferenceTimeMs: rawMetrics.inferenceTimeMs,
      metrics: metrics,
    );
  }

  DetectionBatch detectYuv420({
    required typed.Uint8List yuvBytes,
    required int width,
    required int height,
    int rotationDegrees = 0,
    bool isNv12 = false,
    double probabilityThreshold = 0.40,
    double nmsThreshold = 0.50,
    int maxDetections = 100,
  }) {
    if (!_bindings.isLoaded) throw StateError('Native AI library is not loaded');
    if (!_bindings.isYolo26ModelLoaded()) throw StateError('YOLO26 model is not loaded');

    final yuvBuffer = _getOrCreateBuffer(yuvBytes.length);
    yuvBuffer.asTypedList(yuvBytes.length).setAll(0, yuvBytes);

    final output = _reusableOutputPointer!;
    final metricsPtr = _reusableMetricsPointer!;

    final count = _bindings.detectYuv420Sp(
      yuvBytes: yuvBuffer,
      width: width,
      height: height,
      rotationDegrees: rotationDegrees,
      isNv12: isNv12 ? 1 : 0,
      probabilityThreshold: probabilityThreshold,
      nmsThreshold: nmsThreshold,
      output: output,
      maxOutput: maxDetections.clamp(1, _maxOutputCapacity),
      metrics: metricsPtr,
    );

    if (count < 0) {
      throw StateError('YOLO26 YUV inference failed with code $count');
    }

    final detections = List<Detection>.generate(count, (index) {
      final native = output[index];
      return Detection(
        classId: native.classId,
        confidence: native.confidence,
        x: native.x,
        y: native.y,
        width: native.width,
        height: native.height,
      );
    }, growable: false);

    final rawMetrics = metricsPtr.ref;
    final metrics = InferenceMetrics(
      preprocessMs: rawMetrics.preprocessTimeMs,
      inferenceMs: rawMetrics.inferenceTimeMs,
      postprocessMs: rawMetrics.postprocessTimeMs,
      totalNativeMs: rawMetrics.totalNativeTimeMs,
      backendName: modelBackendName,
      threadCount: threadCount,
    );

    return DetectionBatch(
      detections: detections,
      inferenceTimeMs: rawMetrics.inferenceTimeMs,
      metrics: metrics,
    );
  }

  void unloadModel() {
    stopRealtimeWorker();
    _bindings.unloadYolo26Model();
  }

  void dispose() {
    unloadModel();
    if (_reusableBufferPointer != null) {
      calloc.free(_reusableBufferPointer!);
      _reusableBufferPointer = null;
    }
    if (_reusableOutputPointer != null) {
      calloc.free(_reusableOutputPointer!);
      _reusableOutputPointer = null;
    }
    if (_reusableMetricsPointer != null) {
      calloc.free(_reusableMetricsPointer!);
      _reusableMetricsPointer = null;
    }
    if (_reusableFrameIdPointer != null) {
      calloc.free(_reusableFrameIdPointer!);
      _reusableFrameIdPointer = null;
    }
    if (_statsReceivedPointer != null) {
      calloc.free(_statsReceivedPointer!);
      _statsReceivedPointer = null;
    }
    if (_statsProcessedPointer != null) {
      calloc.free(_statsProcessedPointer!);
      _statsProcessedPointer = null;
    }
    if (_statsDroppedPointer != null) {
      calloc.free(_statsDroppedPointer!);
      _statsDroppedPointer = null;
    }
  }
}
