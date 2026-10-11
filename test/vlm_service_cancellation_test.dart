import 'package:android_ai_gateway/features/vlm/models/vlm_stream_event.dart';
import 'package:android_ai_gateway/features/vlm/services/vlm_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.example.android_ai_gateway/vlm');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  test('preserves native cancellation as a typed exception', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'analyzeImage') {
        return {'success': false, 'error': 'CANCELLED'};
      }
      return null;
    });

    await expectLater(
      VlmService().analyzeImage(
        imagePath: 'missing-test-image.jpg',
        prompt: 'test',
      ),
      throwsA(isA<VlmInferenceCancelled>()),
    );

    messenger.setMockMethodCallHandler(channel, null);
  });
}
