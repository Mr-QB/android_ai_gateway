import 'package:android_ai_gateway/features/assistant/reminder_parser.dart';
import 'package:android_ai_gateway/features/assistant/reminder_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.example.android_ai_gateway/reminders');

  test('native reminder service maps create, list, and cancel calls', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return switch (call.method) {
            'createReminder' => {
              'success': true,
              'id': '42',
              'message': 'uống nước',
              'scheduledAt': 120000,
              'notificationsEnabled': true,
            },
            'listReminders' => [
              {
                'id': '42',
                'message': 'uống nước',
                'scheduledAt': 120000,
                'notificationsEnabled': true,
              },
            ],
            'cancelReminder' => true,
            _ => null,
          };
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    final service = NativeReminderService();
    final created = await service.create(
      const ReminderRequest(message: 'uống nước', delayMinutes: 2),
    );
    final reminders = await service.list();
    final cancelled = await service.cancel(created.id);

    expect(created.id, '42');
    expect(created.scheduledAt, DateTime.fromMillisecondsSinceEpoch(120000));
    expect(reminders.single.message, 'uống nước');
    expect(cancelled, isTrue);
    expect(calls.map((call) => call.method), [
      'createReminder',
      'listReminders',
      'cancelReminder',
    ]);
  });
}
