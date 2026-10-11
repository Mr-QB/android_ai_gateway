import 'package:android_ai_gateway/features/assistant/structured_vlm_speech_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'waits for safety fields and emits Vietnamese without canonical labels',
    () {
      final adapter = StructuredVlmSpeechAdapter();
      expect(
        adapter.push(
          'OBJECT=motorcycle\nACTION=approaching\nDIRECTION=front_right\nDISTANCE=near\n',
        ),
        isNull,
      );

      final update = adapter.push('RISK=high\n');
      expect(update, isNotNull);
      expect(update!.isSafetyWarning, isTrue);
      expect(update.text, contains('xe m\u00e1y'));
      expect(update.text, isNot(contains('OBJECT=')));
      expect(adapter.finish(), isNull);
    },
  );

  test('emits a normal description only after all required fields', () {
    final adapter = StructuredVlmSpeechAdapter();
    final update = adapter.push(
      'OBJECT=person\nACTION=walking\nDIRECTION=front\nDISTANCE=near\nRISK=low\n',
    );
    expect(update, isNotNull);
    expect(update!.isSafetyWarning, isFalse);
  });

  test('parses constrained JSON progressively across streamed chunks', () {
    final adapter = StructuredVlmSpeechAdapter();
    expect(
      adapter.push('{"OBJECT":"motorcycle","ACTION":"approaching",'),
      isNull,
    );
    expect(
      adapter
          .push('"DIRECTION":"front_right","DISTANCE":"near","RISK":"high",')
          ?.isSafetyWarning,
      isTrue,
    );
  });
}
