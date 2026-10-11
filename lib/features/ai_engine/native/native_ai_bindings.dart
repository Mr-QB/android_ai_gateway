import 'dart:ffi' as ffi;
import 'dart:io';

final class NativeAIInferenceResult extends ffi.Struct {
  @ffi.Int32()
  external int width;

  @ffi.Int32()
  external int height;

  @ffi.Int32()
  external int channels;

  @ffi.Float()
  external double inferenceTimeMs;

  @ffi.Int32()
  external int detectedClassId;

  @ffi.Float()
  external double confidence;
}

final class NativeDetection extends ffi.Struct {
  @ffi.Int32()
  external int classId;

  @ffi.Float()
  external double confidence;

  @ffi.Float()
  external double x;

  @ffi.Float()
  external double y;

  @ffi.Float()
  external double width;

  @ffi.Float()
  external double height;
}

final class NativeAIProfilingMetrics extends ffi.Struct {
  @ffi.Float()
  external double preprocessTimeMs;

  @ffi.Float()
  external double inferenceTimeMs;

  @ffi.Float()
  external double postprocessTimeMs;

  @ffi.Float()
  external double totalNativeTimeMs;
}

typedef CGetVersion = ffi.Int32 Function();
typedef DartGetVersion = int Function();

typedef CGetNcnnVulkan = ffi.Int32 Function();
typedef DartGetNcnnVulkan = int Function();

typedef CLoadYolo26ModelV2 =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Char> paramPath,
      ffi.Pointer<ffi.Char> binPath,
      ffi.Int32 backendMode,
      ffi.Int32 numThreads,
    );
typedef DartLoadYolo26ModelV2 =
    int Function(
      ffi.Pointer<ffi.Char> paramPath,
      ffi.Pointer<ffi.Char> binPath,
      int backendMode,
      int numThreads,
    );

typedef CLoadYolo26Model =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Char> paramPath,
      ffi.Pointer<ffi.Char> binPath,
      ffi.Int32 useGpu,
    );
typedef DartLoadYolo26Model =
    int Function(
      ffi.Pointer<ffi.Char> paramPath,
      ffi.Pointer<ffi.Char> binPath,
      int useGpu,
    );

typedef CIsYolo26ModelLoaded = ffi.Int32 Function();
typedef DartIsYolo26ModelLoaded = int Function();

typedef CGetYolo26Backend = ffi.Int32 Function();
typedef DartGetYolo26Backend = int Function();

typedef CGetYolo26Threads = ffi.Int32 Function();
typedef DartGetYolo26Threads = int Function();

typedef CUnloadYolo26Model = ffi.Void Function();
typedef DartUnloadYolo26Model = void Function();

typedef CDetectRgbImage =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Uint8> rgbBytes,
      ffi.Int32 width,
      ffi.Int32 height,
      ffi.Float probabilityThreshold,
      ffi.Float nmsThreshold,
      ffi.Pointer<NativeDetection> output,
      ffi.Int32 maxOutput,
      ffi.Pointer<ffi.Float> inferenceTimeMs,
    );
typedef DartDetectRgbImage =
    int Function(
      ffi.Pointer<ffi.Uint8> rgbBytes,
      int width,
      int height,
      double probabilityThreshold,
      double nmsThreshold,
      ffi.Pointer<NativeDetection> output,
      int maxOutput,
      ffi.Pointer<ffi.Float> inferenceTimeMs,
    );

typedef CDetectRgbImageWithMetrics =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Uint8> rgbBytes,
      ffi.Int32 width,
      ffi.Int32 height,
      ffi.Float probabilityThreshold,
      ffi.Float nmsThreshold,
      ffi.Pointer<NativeDetection> output,
      ffi.Int32 maxOutput,
      ffi.Pointer<NativeAIProfilingMetrics> metrics,
    );
typedef DartDetectRgbImageWithMetrics =
    int Function(
      ffi.Pointer<ffi.Uint8> rgbBytes,
      int width,
      int height,
      double probabilityThreshold,
      double nmsThreshold,
      ffi.Pointer<NativeDetection> output,
      int maxOutput,
      ffi.Pointer<NativeAIProfilingMetrics> metrics,
    );

typedef CDetectYuv420Sp =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Uint8> yuvBytes,
      ffi.Int32 width,
      ffi.Int32 height,
      ffi.Int32 rotationDegrees,
      ffi.Int32 isNv12,
      ffi.Float probabilityThreshold,
      ffi.Float nmsThreshold,
      ffi.Pointer<NativeDetection> output,
      ffi.Int32 maxOutput,
      ffi.Pointer<NativeAIProfilingMetrics> metrics,
    );
typedef DartDetectYuv420Sp =
    int Function(
      ffi.Pointer<ffi.Uint8> yuvBytes,
      int width,
      int height,
      int rotationDegrees,
      int isNv12,
      double probabilityThreshold,
      double nmsThreshold,
      ffi.Pointer<NativeDetection> output,
      int maxOutput,
      ffi.Pointer<NativeAIProfilingMetrics> metrics,
    );

// Worker FFI Typedefs
typedef CStartYolo26Worker = ffi.Int32 Function();
typedef DartStartYolo26Worker = int Function();

typedef CStopYolo26Worker = ffi.Void Function();
typedef DartStopYolo26Worker = void Function();

typedef CIsYolo26WorkerRunning = ffi.Int32 Function();
typedef DartIsYolo26WorkerRunning = int Function();

typedef CPushYolo26YuvFrame =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Uint8> yuvBytes,
      ffi.Int32 width,
      ffi.Int32 height,
      ffi.Int32 rotationDegrees,
      ffi.Int32 isNv12,
      ffi.Float probabilityThreshold,
      ffi.Float nmsThreshold,
    );
typedef DartPushYolo26YuvFrame =
    int Function(
      ffi.Pointer<ffi.Uint8> yuvBytes,
      int width,
      int height,
      int rotationDegrees,
      int isNv12,
      double probabilityThreshold,
      double nmsThreshold,
    );

typedef CGetYolo26LatestResults =
    ffi.Int32 Function(
      ffi.Pointer<NativeDetection> output,
      ffi.Int32 maxOutput,
      ffi.Pointer<NativeAIProfilingMetrics> metrics,
      ffi.Pointer<ffi.Uint64> frameId,
    );
typedef DartGetYolo26LatestResults =
    int Function(
      ffi.Pointer<NativeDetection> output,
      int maxOutput,
      ffi.Pointer<NativeAIProfilingMetrics> metrics,
      ffi.Pointer<ffi.Uint64> frameId,
    );

typedef CGetYolo26WorkerStats =
    ffi.Void Function(
      ffi.Pointer<ffi.Int32> received,
      ffi.Pointer<ffi.Int32> processed,
      ffi.Pointer<ffi.Int32> dropped,
    );
typedef DartGetYolo26WorkerStats =
    void Function(
      ffi.Pointer<ffi.Int32> received,
      ffi.Pointer<ffi.Int32> processed,
      ffi.Pointer<ffi.Int32> dropped,
    );

typedef CResetYolo26WorkerStats = ffi.Void Function();
typedef DartResetYolo26WorkerStats = void Function();

// Legacy Aliases
typedef CLoadNanoDetModel = CLoadYolo26Model;
typedef DartLoadNanoDetModel = DartLoadYolo26Model;
typedef CIsNanoDetModelLoaded = CIsYolo26ModelLoaded;
typedef DartIsNanoDetModelLoaded = DartIsYolo26ModelLoaded;
typedef CGetNanoDetBackend = CGetYolo26Backend;
typedef DartGetNanoDetBackend = DartGetYolo26Backend;
typedef CUnloadNanoDetModel = CUnloadYolo26Model;
typedef DartUnloadNanoDetModel = DartUnloadYolo26Model;

typedef CProcessImageFrame =
    NativeAIInferenceResult Function(
      ffi.Pointer<ffi.Uint8> imageBytes,
      ffi.Int32 width,
      ffi.Int32 height,
      ffi.Int32 format,
    );
typedef DartProcessImageFrame =
    NativeAIInferenceResult Function(
      ffi.Pointer<ffi.Uint8> imageBytes,
      int width,
      int height,
      int format,
    );

class NativeAIBindings {
  late final ffi.DynamicLibrary _nativeLib;

  late final DartGetVersion _getVersion;
  late final DartGetNcnnVulkan _getNcnnVulkan;
  late final DartLoadYolo26ModelV2 _loadYolo26ModelV2;
  late final DartLoadYolo26Model _loadYolo26Model;
  late final DartIsYolo26ModelLoaded _isYolo26ModelLoaded;
  late final DartGetYolo26Backend _getYolo26Backend;
  late final DartGetYolo26Threads _getYolo26Threads;
  late final DartUnloadYolo26Model _unloadYolo26Model;
  late final DartDetectRgbImage _detectRgbImage;
  late final DartDetectRgbImageWithMetrics _detectRgbImageWithMetrics;
  late final DartDetectYuv420Sp _detectYuv420Sp;

  // Worker functions
  late final DartStartYolo26Worker _startYolo26Worker;
  late final DartStopYolo26Worker _stopYolo26Worker;
  late final DartIsYolo26WorkerRunning _isYolo26WorkerRunning;
  late final DartPushYolo26YuvFrame _pushYolo26YuvFrame;
  late final DartGetYolo26LatestResults _getYolo26LatestResults;
  late final DartGetYolo26WorkerStats _getYolo26WorkerStats;
  late final DartResetYolo26WorkerStats _resetYolo26WorkerStats;

  late final DartProcessImageFrame _processImageFrame;

  bool _isLoaded = false;
  bool get isLoaded => _isLoaded;

  NativeAIBindings() {
    _loadLibrary();
  }

  void _loadLibrary() {
    try {
      if (Platform.isAndroid) {
        _nativeLib = ffi.DynamicLibrary.open('libnative_ai_engine.so');
      } else {
        _nativeLib = ffi.DynamicLibrary.process();
      }

      _getVersion = _nativeLib
          .lookup<ffi.NativeFunction<CGetVersion>>('get_ai_engine_version')
          .asFunction();
      _getNcnnVulkan = _nativeLib
          .lookup<ffi.NativeFunction<CGetNcnnVulkan>>('get_ncnn_has_vulkan')
          .asFunction();

      // Load v2 & legacy load
      try {
        _loadYolo26ModelV2 = _nativeLib
            .lookup<ffi.NativeFunction<CLoadYolo26ModelV2>>('load_yolo26_model_v2')
            .asFunction();
      } catch (_) {
        _loadYolo26ModelV2 = (param, bin, mode, threads) => -1;
      }

      try {
        _loadYolo26Model = _nativeLib
            .lookup<ffi.NativeFunction<CLoadYolo26Model>>('load_yolo26_model')
            .asFunction();
      } catch (_) {
        _loadYolo26Model = _nativeLib
            .lookup<ffi.NativeFunction<CLoadNanoDetModel>>('load_nanodet_model')
            .asFunction();
      }

      try {
        _isYolo26ModelLoaded = _nativeLib
            .lookup<ffi.NativeFunction<CIsYolo26ModelLoaded>>('is_yolo26_model_loaded')
            .asFunction();
        _getYolo26Backend = _nativeLib
            .lookup<ffi.NativeFunction<CGetYolo26Backend>>('get_yolo26_backend')
            .asFunction();
        _unloadYolo26Model = _nativeLib
            .lookup<ffi.NativeFunction<CUnloadYolo26Model>>('unload_yolo26_model')
            .asFunction();
      } catch (_) {
        _isYolo26ModelLoaded = _nativeLib
            .lookup<ffi.NativeFunction<CIsNanoDetModelLoaded>>('is_nanodet_model_loaded')
            .asFunction();
        _getYolo26Backend = _nativeLib
            .lookup<ffi.NativeFunction<CGetNanoDetBackend>>('get_nanodet_backend')
            .asFunction();
        _unloadYolo26Model = _nativeLib
            .lookup<ffi.NativeFunction<CUnloadNanoDetModel>>('unload_nanodet_model')
            .asFunction();
      }

      try {
        _getYolo26Threads = _nativeLib
            .lookup<ffi.NativeFunction<CGetYolo26Threads>>('get_yolo26_threads')
            .asFunction();
      } catch (_) {
        _getYolo26Threads = () => 0;
      }

      _detectRgbImage = _nativeLib
          .lookup<ffi.NativeFunction<CDetectRgbImage>>('detect_rgb_image')
          .asFunction();

      try {
        _detectRgbImageWithMetrics = _nativeLib
            .lookup<ffi.NativeFunction<CDetectRgbImageWithMetrics>>('detect_rgb_image_with_metrics')
            .asFunction();
      } catch (_) {
        _detectRgbImageWithMetrics = (b, w, h, p, n, o, m, met) => -1;
      }

      try {
        _detectYuv420Sp = _nativeLib
            .lookup<ffi.NativeFunction<CDetectYuv420Sp>>('detect_yuv420_sp')
            .asFunction();
      } catch (_) {
        _detectYuv420Sp = (b, w, h, r, i, p, n, o, m, met) => -1;
      }

      // Worker functions lookup
      try {
        _startYolo26Worker = _nativeLib
            .lookup<ffi.NativeFunction<CStartYolo26Worker>>('start_yolo26_worker')
            .asFunction();
        _stopYolo26Worker = _nativeLib
            .lookup<ffi.NativeFunction<CStopYolo26Worker>>('stop_yolo26_worker')
            .asFunction();
        _isYolo26WorkerRunning = _nativeLib
            .lookup<ffi.NativeFunction<CIsYolo26WorkerRunning>>('is_yolo26_worker_running')
            .asFunction();
        _pushYolo26YuvFrame = _nativeLib
            .lookup<ffi.NativeFunction<CPushYolo26YuvFrame>>('push_yolo26_yuv_frame')
            .asFunction();
        _getYolo26LatestResults = _nativeLib
            .lookup<ffi.NativeFunction<CGetYolo26LatestResults>>('get_yolo26_latest_results')
            .asFunction();
        _getYolo26WorkerStats = _nativeLib
            .lookup<ffi.NativeFunction<CGetYolo26WorkerStats>>('get_yolo26_worker_stats')
            .asFunction();
        _resetYolo26WorkerStats = _nativeLib
            .lookup<ffi.NativeFunction<CResetYolo26WorkerStats>>('reset_yolo26_worker_stats')
            .asFunction();
      } catch (_) {
        _startYolo26Worker = () => -1;
        _stopYolo26Worker = () {};
        _isYolo26WorkerRunning = () => 0;
        _pushYolo26YuvFrame = (b, w, h, r, i, p, n) => -1;
        _getYolo26LatestResults = (o, m, met, id) => 0;
        _getYolo26WorkerStats = (r, p, d) {};
        _resetYolo26WorkerStats = () {};
      }

      try {
        _processImageFrame = _nativeLib
            .lookup<ffi.NativeFunction<CProcessImageFrame>>('process_image_frame')
            .asFunction();
      } catch (_) {}

      _isLoaded = true;
    } catch (_) {
      _isLoaded = false;
    }
  }

  int getEngineVersion() => !_isLoaded ? -1 : _getVersion();
  bool hasNcnnVulkan() => !_isLoaded ? false : _getNcnnVulkan() == 1;

  int loadYolo26ModelV2({
    required ffi.Pointer<ffi.Char> paramPath,
    required ffi.Pointer<ffi.Char> binPath,
    required int backendMode,
    required int numThreads,
  }) {
    if (!_isLoaded) return -100;
    return _loadYolo26ModelV2(paramPath, binPath, backendMode, numThreads);
  }

  int loadYolo26Model(
    ffi.Pointer<ffi.Char> paramPath,
    ffi.Pointer<ffi.Char> binPath,
    bool useGpu,
  ) {
    if (!_isLoaded) return -100;
    return _loadYolo26Model(paramPath, binPath, useGpu ? 1 : 0);
  }

  bool isYolo26ModelLoaded() => !_isLoaded ? false : _isYolo26ModelLoaded() == 1;
  int getYolo26Backend() => !_isLoaded ? -1 : _getYolo26Backend();
  int getYolo26Threads() => !_isLoaded ? 0 : _getYolo26Threads();
  void unloadYolo26Model() {
    if (_isLoaded) _unloadYolo26Model();
  }

  int detectRgbImage({
    required ffi.Pointer<ffi.Uint8> rgbBytes,
    required int width,
    required int height,
    required double probabilityThreshold,
    required double nmsThreshold,
    required ffi.Pointer<NativeDetection> output,
    required int maxOutput,
    required ffi.Pointer<ffi.Float> inferenceTimeMs,
  }) {
    if (!_isLoaded) return -100;
    return _detectRgbImage(
      rgbBytes,
      width,
      height,
      probabilityThreshold,
      nmsThreshold,
      output,
      maxOutput,
      inferenceTimeMs,
    );
  }

  int detectRgbImageWithMetrics({
    required ffi.Pointer<ffi.Uint8> rgbBytes,
    required int width,
    required int height,
    required double probabilityThreshold,
    required double nmsThreshold,
    required ffi.Pointer<NativeDetection> output,
    required int maxOutput,
    required ffi.Pointer<NativeAIProfilingMetrics> metrics,
  }) {
    if (!_isLoaded) return -100;
    return _detectRgbImageWithMetrics(
      rgbBytes,
      width,
      height,
      probabilityThreshold,
      nmsThreshold,
      output,
      maxOutput,
      metrics,
    );
  }

  int detectYuv420Sp({
    required ffi.Pointer<ffi.Uint8> yuvBytes,
    required int width,
    required int height,
    required int rotationDegrees,
    required int isNv12,
    required double probabilityThreshold,
    required double nmsThreshold,
    required ffi.Pointer<NativeDetection> output,
    required int maxOutput,
    required ffi.Pointer<NativeAIProfilingMetrics> metrics,
  }) {
    if (!_isLoaded) return -100;
    return _detectYuv420Sp(
      yuvBytes,
      width,
      height,
      rotationDegrees,
      isNv12,
      probabilityThreshold,
      nmsThreshold,
      output,
      maxOutput,
      metrics,
    );
  }

  // Worker methods
  int startYolo26Worker() => !_isLoaded ? -1 : _startYolo26Worker();
  void stopYolo26Worker() {
    if (_isLoaded) _stopYolo26Worker();
  }
  bool isYolo26WorkerRunning() => !_isLoaded ? false : _isYolo26WorkerRunning() == 1;

  int pushYolo26YuvFrame({
    required ffi.Pointer<ffi.Uint8> yuvBytes,
    required int width,
    required int height,
    required int rotationDegrees,
    required int isNv12,
    required double probabilityThreshold,
    required double nmsThreshold,
  }) {
    if (!_isLoaded) return -100;
    return _pushYolo26YuvFrame(
      yuvBytes,
      width,
      height,
      rotationDegrees,
      isNv12,
      probabilityThreshold,
      nmsThreshold,
    );
  }

  int getYolo26LatestResults({
    required ffi.Pointer<NativeDetection> output,
    required int maxOutput,
    required ffi.Pointer<NativeAIProfilingMetrics> metrics,
    required ffi.Pointer<ffi.Uint64> frameId,
  }) {
    if (!_isLoaded) return -100;
    return _getYolo26LatestResults(output, maxOutput, metrics, frameId);
  }

  void getYolo26WorkerStats({
    required ffi.Pointer<ffi.Int32> received,
    required ffi.Pointer<ffi.Int32> processed,
    required ffi.Pointer<ffi.Int32> dropped,
  }) {
    if (_isLoaded) {
      _getYolo26WorkerStats(received, processed, dropped);
    }
  }

  void resetYolo26WorkerStats() {
    if (_isLoaded) _resetYolo26WorkerStats();
  }

  NativeAIInferenceResult processFrame(
    ffi.Pointer<ffi.Uint8> bytes,
    int width,
    int height,
    int format,
  ) {
    if (!_isLoaded) {
      throw StateError('Native AI library is not loaded');
    }
    return _processImageFrame(bytes, width, height, format);
  }

  // Legacy
  int loadNanoDetModel(ffi.Pointer<ffi.Char> p, ffi.Pointer<ffi.Char> b, bool g) =>
      loadYolo26Model(p, b, g);
  bool isNanoDetModelLoaded() => isYolo26ModelLoaded();
  int getNanoDetBackend() => getYolo26Backend();
  void unloadNanoDetModel() => unloadYolo26Model();
}

