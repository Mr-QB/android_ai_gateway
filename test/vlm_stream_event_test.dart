import 'package:android_ai_gateway/features/vlm/models/vlm_result.dart';
import 'package:android_ai_gateway/features/vlm/models/vlm_stream_event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VlmStreamEvent', () {
    test('parses text fragments', () {
      final event = VlmStreamEvent.fromMap({'type': 'token', 'text': 'Hello'});

      expect(event, isA<VlmToken>());
      expect((event as VlmToken).text, 'Hello');
    });

    test('parses completed inference metrics', () {
      final event = VlmStreamEvent.fromMap({
        'type': 'completed',
        'result': {
          'success': true,
          'text': 'A person is walking.',
          'timeToFirstTokenMs': 250,
          'sdkTimeToFirstTokenMs': 175,
          'decodeMsPerToken': 60,
          'generatedTokens': 10,
          'tokensPerSecond': 16.7,
        },
      });

      expect(event, isA<VlmStreamCompleted>());
      final result = (event as VlmStreamCompleted).result;
      expect(result, isA<VlmResult>());
      expect(result.timeToFirstTokenMs, 250);
      expect(result.sdkTimeToFirstTokenMs, 175);
      expect(result.decodeMsPerToken, 60);
      expect(result.generatedTokens, 10);
    });

    test('parses cancellation and failures', () {
      expect(
        VlmStreamEvent.fromMap({'type': 'cancelled'}),
        isA<VlmStreamCancelled>(),
      );
      expect(
        VlmStreamEvent.fromMap({
          'type': 'failed',
          'error': 'INVALID_IMAGE',
          'message': 'Image is missing',
        }),
        isA<VlmStreamFailed>(),
      );
    });

    test('rejects unknown event types', () {
      expect(
        () => VlmStreamEvent.fromMap({'type': 'other'}),
        throwsFormatException,
      );
    });
  });
}
