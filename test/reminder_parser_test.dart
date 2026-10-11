import 'package:android_ai_gateway/features/assistant/reminder_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ReminderParser', () {
    test('extracts Vietnamese reminder message and minute delay', () {
      final request = ReminderParser.parseCreate(
        'Nhắc tôi uống nước sau 10 phút.',
      );

      expect(request?.message, 'uống nước');
      expect(request?.delayMinutes, 10);
    });

    test('converts hours and days to minutes', () {
      expect(
        ReminderParser.parseCreate(
          'Nhắc mình gọi cho An sau 2 giờ',
        )?.delayMinutes,
        120,
      );
      expect(
        ReminderParser.parseCreate(
          'Nhắc tôi uống thuốc sau 1 ngày',
        )?.delayMinutes,
        1440,
      );
    });

    test(
      'rejects unsupported, empty, zero, and excessively long reminders',
      () {
        expect(ReminderParser.parseCreate('Nhắc tôi việc gì đó'), isNull);
        expect(ReminderParser.parseCreate('Nhắc tôi sau 10 phút'), isNull);
        expect(
          ReminderParser.parseCreate('Nhắc tôi uống nước sau 0 phút'),
          isNull,
        );
        expect(
          ReminderParser.parseCreate('Nhắc tôi uống nước sau 31 ngày'),
          isNull,
        );
      },
    );
  });
}
