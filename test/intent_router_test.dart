import 'package:android_ai_gateway/features/assistant/intent_router.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('IntentRouter', () {
    test('routes Vietnamese vision questions', () {
      expect(
        IntentRouter.route('Có gì trước mặt?').type,
        IntentType.visionQuery,
      );
      expect(
        IntentRouter.route('Phía trước tôi có gì').type,
        IntentType.visionQuery,
      );
    });

    test('routes scene, safety, and OCR requests', () {
      expect(
        IntentRouter.route('Mô tả khung cảnh').type,
        IntentType.sceneDescription,
      );
      expect(
        IntentRouter.route('Có gì nguy hiểm không?').type,
        IntentType.safetyAlert,
      );
      expect(
        IntentRouter.route('Đọc chữ trên biển kia').type,
        IntentType.ocrQuery,
      );
    });

    test('extracts reminder delay and message without model inference', () {
      final result = IntentRouter.route('Nhắc tôi uống nước sau 10 phút');

      expect(result.type, IntentType.reminderCreate);
      expect(result.slots, {'delay_minutes': 10, 'message': 'uống nước'});
    });

    test('converts reminder hours to minutes', () {
      final result = IntentRouter.route('Nhắc tôi gọi cho Phong sau 2 giờ nữa');

      expect(result.type, IntentType.reminderCreate);
      expect(result.slots['delay_minutes'], 120);
      expect(result.slots['message'], 'gọi cho Phong');
    });

    test('routes reminder management and device commands', () {
      expect(IntentRouter.route('Hủy nhắc').type, IntentType.reminderCancel);
      expect(
        IntentRouter.route('Danh sách nhắc').type,
        IntentType.reminderList,
      );
      expect(IntentRouter.route('Tắt đèn').type, IntentType.deviceCommand);
    });

    test('leaves unrelated text unknown instead of defaulting to a VLM', () {
      expect(IntentRouter.route('xin chào').type, IntentType.unknown);
      expect(IntentRouter.route('').type, IntentType.unknown);
      expect(IntentRouter.route('xin chào').confidence, 0.35);
    });
  });
}
