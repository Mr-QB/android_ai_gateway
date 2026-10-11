import 'package:android_ai_gateway/features/assistant/visual_observation.dart';
import 'package:android_ai_gateway/features/assistant/vietnamese_response_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StructuredVlmParser', () {
    test('parses canonical fields and ignores unknown fields', () {
      final result = StructuredVlmParser.parse('''
OBJECT=motorcycle
ACTION=approaching
DIRECTION=front_right
DISTANCE=near
RISK=high
TEXT=none
EXTRA=ignored
''');

      expect(result.object, 'motorcycle');
      expect(result.action, 'approaching');
      expect(result.direction, 'front_right');
      expect(result.distance, 'near');
      expect(result.risk, 'high');
      expect(result.text, isNull);
    });

    test('returns empty known fields for explicit none values', () {
      final result = StructuredVlmParser.parse('OBJECT=none\nRISK=none');
      expect(result.isEmpty, isTrue);
    });

    test('parses constrained JSON output and preserves OCR text', () {
      final result = StructuredVlmParser.parse('''
{"OBJECT":"motorcycle","ACTION":"approaching","DIRECTION":"front_right","DISTANCE":"near","RISK":"high","TEXT":"STOP"}
''');

      expect(result.object, 'motorcycle');
      expect(result.action, 'approaching');
      expect(result.direction, 'front_right');
      expect(result.distance, 'near');
      expect(result.risk, 'high');
      expect(result.text, 'STOP');
    });

    test('rejects malformed output without recognized fields', () {
      expect(
        () => StructuredVlmParser.parse('A motorcycle is approaching.'),
        throwsFormatException,
      );
    });
  });

  group('VietnameseResponseBuilder', () {
    test('verbalizes high-risk canonical labels in Vietnamese', () {
      final response = VietnameseResponseBuilder.build(
        const VisualObservation(
          object: 'motorcycle',
          action: 'approaching',
          direction: 'front_right',
          distance: 'near',
          risk: 'high',
        ),
      );

      expect(response, contains('xe máy'));
      expect(response, contains('đang tiến lại gần'));
      expect(response, contains('phía trước bên phải'));
      expect(response, startsWith('Cẩn thận'));
    });

    test('verbalizes OCR text without translating it', () {
      expect(
        VietnameseResponseBuilder.build(const VisualObservation(text: 'STOP')),
        'Trước mặt có dòng chữ: STOP',
      );
    });

    test('returns null when there is no usable semantic field', () {
      expect(
        VietnameseResponseBuilder.build(const VisualObservation()),
        isNull,
      );
    });
  });
}
