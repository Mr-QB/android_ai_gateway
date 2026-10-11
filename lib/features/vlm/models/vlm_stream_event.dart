import 'vlm_result.dart';

final class VlmInferenceCancelled implements Exception {
  const VlmInferenceCancelled();
}

class VlmRequest {
  final String imagePath;
  final String prompt;
  final int maxTokens;
  final int targetResolution;
  final String? structuredOutputFormat;

  const VlmRequest({
    required this.imagePath,
    required this.prompt,
    this.maxTokens = 64,
    this.targetResolution = 512,
    this.structuredOutputFormat,
  });
}

sealed class VlmStreamEvent {
  const VlmStreamEvent();

  factory VlmStreamEvent.fromMap(Map<dynamic, dynamic> map) {
    switch (map['type']) {
      case 'token':
        return VlmToken(map['text']?.toString() ?? '');
      case 'completed':
        final result = map['result'];
        if (result is! Map) throw const FormatException('Missing VLM result');
        return VlmStreamCompleted(VlmResult.fromMap(result));
      case 'cancelled':
        return const VlmStreamCancelled();
      case 'failed':
        return VlmStreamFailed(
          map['error']?.toString() ?? 'INFERENCE_EXCEPTION',
          map['message']?.toString() ?? 'VLM generation failed',
        );
      default:
        throw FormatException('Unknown VLM stream event: ${map['type']}');
    }
  }
}

/// A text fragment emitted by LiteRT-LM. The SDK exposes message chunks, not token IDs.
final class VlmToken extends VlmStreamEvent {
  final String text;

  const VlmToken(this.text);
}

final class VlmStreamCompleted extends VlmStreamEvent {
  final VlmResult result;

  const VlmStreamCompleted(this.result);
}

final class VlmStreamCancelled extends VlmStreamEvent {
  const VlmStreamCancelled();
}

final class VlmStreamFailed extends VlmStreamEvent {
  final String error;
  final String message;

  const VlmStreamFailed(this.error, this.message);
}
