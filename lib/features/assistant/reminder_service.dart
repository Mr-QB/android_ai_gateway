import 'package:flutter/services.dart';

import 'reminder_parser.dart';

class ReminderRecord {
  const ReminderRecord({
    required this.id,
    required this.message,
    required this.scheduledAt,
    required this.notificationsEnabled,
  });

  final String id;
  final String message;
  final DateTime scheduledAt;
  final bool notificationsEnabled;

  factory ReminderRecord.fromMap(Map<dynamic, dynamic> map) {
    final timestamp = (map['scheduledAt'] as num?)?.toInt();
    if (timestamp == null) {
      throw const FormatException('Reminder has no scheduledAt timestamp');
    }
    return ReminderRecord(
      id: map['id']?.toString() ?? '',
      message: map['message']?.toString() ?? '',
      scheduledAt: DateTime.fromMillisecondsSinceEpoch(timestamp),
      notificationsEnabled: map['notificationsEnabled'] != false,
    );
  }
}

abstract interface class ReminderService {
  Future<ReminderRecord> create(ReminderRequest request);
  Future<bool> cancel(String id);
  Future<List<ReminderRecord>> list();
}

class NativeReminderService implements ReminderService {
  static const MethodChannel _channel = MethodChannel(
    'com.example.android_ai_gateway/reminders',
  );

  @override
  Future<ReminderRecord> create(ReminderRequest request) async {
    final response = await _channel.invokeMapMethod<String, dynamic>(
      'createReminder',
      {'message': request.message, 'delayMinutes': request.delayMinutes},
    );
    if (response == null || response['success'] != true) {
      throw PlatformException(
        code: 'REMINDER_CREATE_FAILED',
        message:
            response?['message']?.toString() ?? 'Could not create reminder',
      );
    }
    return ReminderRecord.fromMap(response);
  }

  @override
  Future<bool> cancel(String id) async =>
      await _channel.invokeMethod<bool>('cancelReminder', {'id': id}) ?? false;

  @override
  Future<List<ReminderRecord>> list() async {
    final response = await _channel.invokeListMethod<dynamic>('listReminders');
    return (response ?? const [])
        .whereType<Map>()
        .map(ReminderRecord.fromMap)
        .toList(growable: false);
  }
}
