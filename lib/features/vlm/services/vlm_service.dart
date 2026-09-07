import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import '../models/vlm_result.dart';

abstract class IVlmService {
  Future<VlmStatus> getStatus({String modelKey = 'smolvlm2_500m'});

  Future<Map<String, dynamic>> initialize({
    String modelKey = 'smolvlm2_500m',
    String backend = 'AUTO',
    int maxTokens = 64,
    String? modelPath,
  });

  Future<VlmResult> analyzeImage({
    required String imagePath,
    required String prompt,
    int maxTokens = 64,
    int targetResolution = 512,
  });

  Future<VlmBenchmarkReport?> runBenchmarkX5({
    required String modelKey,
    required String backend,
    required String imagePath,
    required String prompt,
    int maxTokens = 64,
    int targetResolution = 512,
  });

  Future<void> dispose();
}

class VlmService implements IVlmService {
  static const MethodChannel _channel = MethodChannel(
    'com.example.android_ai_gateway/vlm',
  );

  // Singleton instance
  static final VlmService _instance = VlmService._internal();
  factory VlmService() => _instance;
  VlmService._internal();

  @override
  Future<VlmStatus> getStatus({String modelKey = 'smolvlm2_500m'}) async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getVlmStatus',
        {'modelKey': modelKey},
      );
      if (result != null) {
        return VlmStatus.fromMap(result);
      }
    } catch (e) {
      debugPrint('[VLM] getStatus error: $e');
    }
    return VlmStatus.empty();
  }

  @override
  Future<Map<String, dynamic>> initialize({
    String modelKey = 'smolvlm2_500m',
    String backend = 'AUTO',
    int maxTokens = 64,
    String? modelPath,
  }) async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'initializeVlm',
        {
          'modelKey': modelKey,
          'backend': backend,
          'maxTokens': maxTokens,
          'modelPath': modelPath,
        },
      );
      return Map<String, dynamic>.from(result ?? {});
    } catch (e) {
      debugPrint('[VLM] initializeVlm error: $e');
      return {
        'success': false,
        'error': 'EXCEPTION',
        'message': e.toString(),
      };
    }
  }

  @override
  Future<VlmResult> analyzeImage({
    required String imagePath,
    required String prompt,
    int maxTokens = 64,
    int targetResolution = 512,
  }) async {
    try {
      // Preprocess image to target resolution preserving aspect ratio
      final preprocessedPath = await _preprocessImage(imagePath, maxSize: targetResolution);

      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'analyzeImage',
        {
          'imagePath': preprocessedPath,
          'prompt': prompt,
          'maxTokens': maxTokens,
        },
      );

      if (result != null) {
        return VlmResult.fromMap(result);
      }
      return VlmResult.failure(
        error: 'EMPTY_RESPONSE',
        message: 'No response received from native VLM service',
      );
    } catch (e) {
      debugPrint('[VLM] analyzeImage error: $e');
      return VlmResult.failure(
        error: 'EXCEPTION',
        message: e.toString(),
      );
    }
  }

  @override
  Future<VlmBenchmarkReport?> runBenchmarkX5({
    required String modelKey,
    required String backend,
    required String imagePath,
    required String prompt,
    int maxTokens = 64,
    int targetResolution = 512,
  }) async {
    try {
      // Preprocess image once for all 5 runs
      final preprocessedPath = await _preprocessImage(imagePath, maxSize: targetResolution);

      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'runBenchmarkX5',
        {
          'modelKey': modelKey,
          'backend': backend,
          'imagePath': preprocessedPath,
          'prompt': prompt,
          'maxTokens': maxTokens,
        },
      );

      if (result != null && result['success'] == true) {
        return VlmBenchmarkReport.fromMap(result);
      } else {
        debugPrint('[VLM Benchmark] Error: ${result?['message']}');
        return null;
      }
    } catch (e) {
      debugPrint('[VLM Benchmark] Exception: $e');
      return null;
    }
  }

  @override
  Future<void> dispose() async {
    try {
      await _channel.invokeMethod('disposeVlm');
    } catch (e) {
      debugPrint('[VLM] disposeVlm error: $e');
    }
  }

  /// Downscale image to max maxSize preserving aspect ratio without stretching
  Future<String> _preprocessImage(String originalPath, {int maxSize = 512}) async {
    try {
      final file = File(originalPath);
      if (!await file.exists()) return originalPath;

      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return originalPath;

      // If already small enough, use directly
      if (decoded.width <= maxSize && decoded.height <= maxSize) {
        return originalPath;
      }

      final oriented = img.bakeOrientation(decoded);
      final img.Image resized;

      if (oriented.width > oriented.height) {
        final newHeight = (oriented.height * maxSize / oriented.width).round();
        resized = img.copyResize(
          oriented,
          width: maxSize,
          height: newHeight,
          interpolation: img.Interpolation.linear,
        );
      } else {
        final newWidth = (oriented.width * maxSize / oriented.height).round();
        resized = img.copyResize(
          oriented,
          width: newWidth,
          height: maxSize,
          interpolation: img.Interpolation.linear,
        );
      }

      final tempDir = await getTemporaryDirectory();
      final preprocessedFile = File(
        '${tempDir.path}/vlm_input_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await preprocessedFile.writeAsBytes(img.encodeJpg(resized, quality: 85));
      return preprocessedFile.path;
    } catch (e) {
      debugPrint('[VLM] Preprocess error, using original image: $e');
      return originalPath;
    }
  }
}
