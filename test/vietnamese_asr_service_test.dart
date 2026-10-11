import 'package:android_ai_gateway/features/assistant/vietnamese_asr_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const methodChannel = MethodChannel('com.example.android_ai_gateway/asr');
  const eventChannel = EventChannel(
    'com.example.android_ai_gateway/asr/events',
  );
  final calls = <String>[];

  setUp(() {
    calls.clear();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      calls.add(call.method);
      return true;
    });
    messenger.setMockStreamHandler(
      eventChannel,
      MockStreamHandler.inline(
        onListen: (_, events) {
          events.success({'type': 'partial', 'text': 'xin chao'});
          events.success({'type': 'final', 'text': 'nhac toi uong nuoc'});
          events.endOfStream();
        },
      ),
    );
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(methodChannel, null);
    messenger.setMockStreamHandler(eventChannel, null);
  });

  test(
    'starts local Vietnamese recognition and streams partial and final text',
    () async {
      final events = await VietnameseAsrService().listen().toList();
      expect(events.map((event) => event.type), ['partial', 'final']);
      expect(events.last.text, 'nhac toi uong nuoc');
      expect(calls, ['startListening']);
      await VietnameseAsrService().stop();
      expect(calls, ['startListening', 'stopListening']);
    },
  );
}
