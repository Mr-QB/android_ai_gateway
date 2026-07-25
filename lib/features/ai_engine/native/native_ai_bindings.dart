import 'dart:ffi' as ffi;
import 'dart:io';

// Native C struct matching AIInferenceResult
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

// C Function Typedefs
typedef CGetVersion = ffi.Int32 Function();
typedef DartGetVersion = int Function();

typedef CProcessImageFrame = NativeAIInferenceResult Function(
  ffi.Pointer<ffi.Uint8> imageBytes,
  ffi.Int32 width,
  ffi.Int32 height,
  ffi.Int32 format,
);

typedef DartProcessImageFrame = NativeAIInferenceResult Function(
  ffi.Pointer<ffi.Uint8> imageBytes,
  int width,
  int height,
  int format,
);

class NativeAIBindings {
  late final ffi.DynamicLibrary _nativeLib;
  late final DartGetVersion _getVersion;
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
      } else if (Platform.isLinux) {
        _nativeLib = ffi.DynamicLibrary.process();
      } else {
        _nativeLib = ffi.DynamicLibrary.process();
      }

      _getVersion = _nativeLib
          .lookup<ffi.NativeFunction<CGetVersion>>('get_ai_engine_version')
          .asFunction();

      _processImageFrame = _nativeLib
          .lookup<ffi.NativeFunction<CProcessImageFrame>>('process_image_frame')
          .asFunction();

      _isLoaded = true;
    } catch (e) {
      _isLoaded = false;
    }
  }

  int getEngineVersion() {
    if (!_isLoaded) return -1;
    return _getVersion();
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
