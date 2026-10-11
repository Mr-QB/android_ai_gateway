import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import '../models/vlm_result.dart';
import '../models/vlm_stream_event.dart';

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
    String? structuredOutputFormat,
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
  static const EventChannel _streamChannel = EventChannel(
    'com.example.android_ai_gateway/vlm/stream',
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
      final result = await _channel
          .invokeMethod<Map<dynamic, dynamic>>('initializeVlm', {
            'modelKey': modelKey,
            'backend': backend,
            'maxTokens': maxTokens,
            'modelPath': modelPath,
          });
      return Map<String, dynamic>.from(result ?? {});
    } catch (e) {
      debugPrint('[VLM] initializeVlm error: $e');
      return {'success': false, 'error': 'EXCEPTION', 'message': e.toString()};
    }
  }

  @override
  Future<VlmResult> analyzeImage({
    required String imagePath,
    required String prompt,
    int maxTokens = 64,
    int targetResolution = 512,
    String? structuredOutputFormat,
  }) async {
    try {
      // Preprocess image to target resolution preserving aspect ratio
      final preprocessedPath = await _preprocessImage(
        imagePath,
        maxSize: targetResolution,
      );
      try {
        final result = await _channel
            .invokeMethod<Map<dynamic, dynamic>>('analyzeImage', {
              'imagePath': preprocessedPath,
              'prompt': prompt,
              'maxTokens': maxTokens,
              'structuredOutputFormat': structuredOutputFormat,
            });

        if (result != null) {
          if (result['error'] == 'CANCELLED') {
            throw const VlmInferenceCancelled();
          }
          return VlmResult.fromMap(result);
        }
        return VlmResult.failure(
          error: 'EMPTY_RESPONSE',
          message: 'No response received from native VLM service',
        );
      } finally {
        await _deletePreprocessedImage(imagePath, preprocessedPath);
      }
    } on VlmInferenceCancelled {
      rethrow;
    } catch (e) {
      debugPrint('[VLM] analyzeImage error: $e');
      return VlmResult.failure(error: 'EXCEPTION', message: e.toString());
    }
  }

  Stream<VlmStreamEvent> generateStream(VlmRequest request) async* {
    final preprocessWatch = Stopwatch()..start();
    final preprocessedPath = await _preprocessImage(
      request.imagePath,
      maxSize: request.targetResolution,
    );
    preprocessWatch.stop();
    try {
      await for (final rawEvent in _streamChannel.receiveBroadcastStream({
        'imagePath': preprocessedPath,
        'prompt': request.prompt,
        'maxTokens': request.maxTokens,
        'preprocessMs': preprocessWatch.elapsedMilliseconds,
        'structuredOutputFormat': request.structuredOutputFormat,
      })) {
        if (rawEvent is! Map) {
          throw const FormatException('Invalid VLM stream event');
        }

        final event = VlmStreamEvent.fromMap(rawEvent);
        if (event case VlmStreamCompleted(:final result)) {
          debugPrint(
            '[VLM] mode=english_default, structured_output=${request.structuredOutputFormat ?? 'none'}, '
            'preprocess_ms=${result.preprocessMs}, '
            'vision_encode_ms=${result.visionEncodeMs ?? 'unavailable'}, '
            'ttft_ms=${result.timeToFirstTokenMs}, '
            'sdk_ttft_ms=${result.sdkTimeToFirstTokenMs}, '
            'decode_ms_per_token=${result.decodeMsPerToken}, '
            'tokens_per_second=${result.tokensPerSecond}, '
            'tokens=${result.generatedTokens}, '
            'total_generation_ms=${result.generationMs}',
          );
        }
        yield event;
      }
    } finally {
      await _deletePreprocessedImage(request.imagePath, preprocessedPath);
    }
  }

  Future<void> cancel() async {
    try {
      await _channel.invokeMethod<bool>('cancelInference');
    } catch (e) {
      debugPrint('[VLM] cancelInference error: $e');
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
      final preprocessedPath = await _preprocessImage(
        imagePath,
        maxSize: targetResolution,
      );
      try {
        final result = await _channel
            .invokeMethod<Map<dynamic, dynamic>>('runBenchmarkX5', {
              'modelKey': modelKey,
              'backend': backend,
              'imagePath': preprocessedPath,
              'prompt': prompt,
              'maxTokens': maxTokens,
            });

        if (result != null && result['success'] == true) {
          return VlmBenchmarkReport.fromMap(result);
        } else {
          debugPrint('[VLM Benchmark] Error: ${result?['message']}');
          return null;
        }
      } finally {
        await _deletePreprocessedImage(imagePath, preprocessedPath);
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
  Future<String> _preprocessImage(
    String originalPath, {
    int maxSize = 512,
  }) async {
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

      final orientation = decoded.exif.imageIfd.orientation ?? 1;
      final swapsDimensions = orientation >= 5 && orientation <= 8;
      final orientedWidth = swapsDimensions ? decoded.height : decoded.width;
      final orientedHeight = swapsDimensions ? decoded.width : decoded.height;
      final resizedWidth = orientedWidth >= orientedHeight
          ? maxSize
          : (orientedWidth * maxSize / orientedHeight).round();
      final resizedHeight = orientedHeight >= orientedWidth
          ? maxSize
          : (orientedHeight * maxSize / orientedWidth).round();

      // copyResize applies EXIF orientation itself. Avoid baking it first,
      // which would keep an extra full-resolution pixel buffer alive.
      final resized = img.copyResize(
        decoded,
        width: resizedWidth,
        height: resizedHeight,
        interpolation: img.Interpolation.linear,
      );
      decoded.data = null;

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

  Future<void> _deletePreprocessedImage(
    String originalPath,
    String preprocessedPath,
  ) async {
    if (preprocessedPath == originalPath) return;
    try {
      await File(preprocessedPath).delete();
    } on FileSystemException catch (error) {
      debugPrint('[VLM] Could not delete temporary image: $error');
    }
  }
}
