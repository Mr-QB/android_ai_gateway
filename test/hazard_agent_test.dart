import 'package:android_ai_gateway/features/ai_engine/domain/detection.dart';
import 'package:android_ai_gateway/features/perception/agents/smol/hazard_agent.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HazardAgent deterministic safety check', () {
    test('does not report a hazard when there are no detections', () {
      final result = HazardAgent.checkDeterministicSafety(const []);

      expect(result.hasImmediateHazard, isFalse);
      expect(result.warningMessage, isEmpty);
    });

    test('reports a large, confident vehicle in the forward path', () {
      final result = HazardAgent.checkDeterministicSafety(const [
        Detection(
          classId: 2,
          confidence: 0.9,
          x: 0.3,
          y: 0.2,
          width: 0.5,
          height: 0.5,
        ),
      ]);

      expect(result.hasImmediateHazard, isTrue);
      expect(result.direction, 'phía trước');
      expect(result.severity, 0.9);
      expect(result.warningMessage, contains('car'));
    });
  });

  group('HazardAgent model response validation', () {
    test('requires successful inference and a boolean hazard field', () {
      expect(
        HazardAgent.isValidVlmAssessment(
          inferenceSucceeded: true,
          response: const {
            'hazard': false,
            'OBJECT': 'none',
            'ACTION': 'none',
            'DIRECTION': 'unknown',
            'DISTANCE': 'unknown',
            'RISK': 'none',
            'TEXT': 'none',
          },
        ),
        isTrue,
      );
      expect(
        HazardAgent.isValidVlmAssessment(
          inferenceSucceeded: true,
          response: const {},
        ),
        isFalse,
      );
      expect(
        HazardAgent.isValidVlmAssessment(
          inferenceSucceeded: false,
          response: const {
            'hazard': false,
            'OBJECT': 'none',
            'ACTION': 'none',
            'DIRECTION': 'unknown',
            'DISTANCE': 'unknown',
            'RISK': 'none',
            'TEXT': 'none',
          },
        ),
        isFalse,
      );
    });

    test('treats elevated risk as a hazard even if the boolean disagrees', () {
      expect(
        HazardAgent.assessmentReportsHazard(const {
          'hazard': false,
          'RISK': 'high',
        }),
        isTrue,
      );
      expect(
        HazardAgent.assessmentReportsHazard(const {
          'hazard': false,
          'RISK': 'none',
        }),
        isFalse,
      );
    });
  });
}
