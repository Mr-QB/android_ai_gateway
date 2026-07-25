import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import '../domain/ai_inference_result.dart';
import '../native/native_ai_bindings.dart';

class AIEngineService {
  final NativeAIBindings _bindings = NativeAIBindings();

  bool get isNativeLoaded => _bindings.isLoaded;

  int getVersion() {
    return _bindings.getEngineVersion();
  }

  bool hasVulkanGPU() {
    return _bindings.hasNcnnVulkan();
  }

  AIInferenceResultModel processFrame({
    required Uint8List bytes,
    required int width,
    required int height,
    required int format,
  }) {
    if (!_bindings.isLoaded) {
      return AIInferenceResultModel.empty();
    }

    final ffi.Pointer<ffi.Uint8> ptr = calloc<ffi.Uint8>(bytes.length);
    final Uint8List nativeList = ptr.asTypedList(bytes.length);
    nativeList.setAll(0, bytes);

    try {
      final nativeResult = _bindings.processFrame(ptr, width, height, format);
      return AIInferenceResultModel(
        width: nativeResult.width,
        height: nativeResult.height,
        inferenceTimeMs: nativeResult.inferenceTimeMs,
        detectedClassId: nativeResult.detectedClassId,
        confidence: nativeResult.confidence,
      );
    } catch (e) {
      debugPrint('NCNN AI Processing error: $e');
      return AIInferenceResultModel.empty();
    } finally {
      calloc.free(ptr);
    }
  }
}
