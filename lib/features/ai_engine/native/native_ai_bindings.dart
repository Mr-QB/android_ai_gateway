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

typedef CGetVersion = ffi.Int32 Function();
typedef DartGetVersion = int Function();

typedef CGetNcnnVulkan = ffi.Int32 Function();
typedef DartGetNcnnVulkan = int Function();

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

typedef CUnloadYolo26Model = ffi.Void Function();
typedef DartUnloadYolo26Model = void Function();

// Aliases for legacy NanoDet bindings
typedef CLoadNanoDetModel = CLoadYolo26Model;
typedef DartLoadNanoDetModel = DartLoadYolo26Model;
typedef CIsNanoDetModelLoaded = CIsYolo26ModelLoaded;
typedef DartIsNanoDetModelLoaded = DartIsYolo26ModelLoaded;
typedef CGetNanoDetBackend = CGetYolo26Backend;
typedef DartGetNanoDetBackend = DartGetYolo26Backend;
typedef CUnloadNanoDetModel = CUnloadYolo26Model;
typedef DartUnloadNanoDetModel = DartUnloadYolo26Model;

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
  late final DartLoadYolo26Model _loadYolo26Model;
  late final DartIsYolo26ModelLoaded _isYolo26ModelLoaded;
  late final DartGetYolo26Backend _getYolo26Backend;
  late final DartUnloadYolo26Model _unloadYolo26Model;
  late final DartDetectRgbImage _detectRgbImage;
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

      // Look up YOLO26 symbols, or fallback to legacy symbols
      try {
        _loadYolo26Model = _nativeLib
            .lookup<ffi.NativeFunction<CLoadYolo26Model>>('load_yolo26_model')
            .asFunction();
        _isYolo26ModelLoaded = _nativeLib
            .lookup<ffi.NativeFunction<CIsYolo26ModelLoaded>>(
              'is_yolo26_model_loaded',
            )
            .asFunction();
        _getYolo26Backend = _nativeLib
            .lookup<ffi.NativeFunction<CGetYolo26Backend>>('get_yolo26_backend')
            .asFunction();
        _unloadYolo26Model = _nativeLib
            .lookup<ffi.NativeFunction<CUnloadYolo26Model>>(
              'unload_yolo26_model',
            )
            .asFunction();
      } catch (_) {
        _loadYolo26Model = _nativeLib
            .lookup<ffi.NativeFunction<CLoadNanoDetModel>>('load_nanodet_model')
            .asFunction();
        _isYolo26ModelLoaded = _nativeLib
            .lookup<ffi.NativeFunction<CIsNanoDetModelLoaded>>(
              'is_nanodet_model_loaded',
            )
            .asFunction();
        _getYolo26Backend = _nativeLib
            .lookup<ffi.NativeFunction<CGetNanoDetBackend>>('get_nanodet_backend')
            .asFunction();
        _unloadYolo26Model = _nativeLib
            .lookup<ffi.NativeFunction<CUnloadNanoDetModel>>(
              'unload_nanodet_model',
            )
            .asFunction();
      }

      _detectRgbImage = _nativeLib
          .lookup<ffi.NativeFunction<CDetectRgbImage>>('detect_rgb_image')
          .asFunction();
      _processImageFrame = _nativeLib
          .lookup<ffi.NativeFunction<CProcessImageFrame>>('process_image_frame')
          .asFunction();

      _isLoaded = true;
    } catch (_) {
      _isLoaded = false;
    }
  }

  int getEngineVersion() {
    if (!_isLoaded) return -1;
    return _getVersion();
  }

  bool hasNcnnVulkan() {
    if (!_isLoaded) return false;
    return _getNcnnVulkan() == 1;
  }

  int loadYolo26Model(
    ffi.Pointer<ffi.Char> paramPath,
    ffi.Pointer<ffi.Char> binPath,
    bool useGpu,
  ) {
    if (!_isLoaded) return -100;
    return _loadYolo26Model(paramPath, binPath, useGpu ? 1 : 0);
  }

  bool isYolo26ModelLoaded() {
    if (!_isLoaded) return false;
    return _isYolo26ModelLoaded() == 1;
  }

  int getYolo26Backend() {
    if (!_isLoaded) return -1;
    return _getYolo26Backend();
  }

  void unloadYolo26Model() {
    if (!_isLoaded) return;
    _unloadYolo26Model();
  }

  // Legacy NanoDet aliases for backward compatibility
  int loadNanoDetModel(
    ffi.Pointer<ffi.Char> paramPath,
    ffi.Pointer<ffi.Char> binPath,
    bool useGpu,
  ) => loadYolo26Model(paramPath, binPath, useGpu);

  bool isNanoDetModelLoaded() => isYolo26ModelLoaded();

  int getNanoDetBackend() => getYolo26Backend();

  void unloadNanoDetModel() => unloadYolo26Model();

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
}
