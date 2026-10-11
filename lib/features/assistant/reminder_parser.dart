import 'vietnamese_text.dart';

class ReminderRequest {
  const ReminderRequest({required this.message, required this.delayMinutes});

  final String message;
  final int delayMinutes;

  Map<String, Object> toSlots() => {
    'message': message,
    'delay_minutes': delayMinutes,
  };
}

class ReminderParser {
  static ReminderRequest? parseCreate(String input) {
    final normalized = VietnameseText.normalize(input);
    final match = RegExp(
      r'nhac (?:toi|minh) (.+?) sau (\d+) (phut|gio|ngay)(?: nua)?$',
    ).firstMatch(normalized);
    if (match == null) return null;

    final amount = int.tryParse(match.group(2)!);
    if (amount == null || amount < 1) return null;
    final delayMinutes = switch (match.group(3)) {
      'gio' => amount * 60,
      'ngay' => amount * 1440,
      _ => amount,
    };
    if (delayMinutes > 43200) return null;

    final original = input.trim().replaceFirst(RegExp(r'[.!?]+$'), '');
    final originalMatch = RegExp(
      r'nh\u1eafc (?:t\u00f4i|m\u00ecnh) (.+?) sau \d+ (?:ph\u00fat|gi\u1edd|ng\u00e0y)(?: n\u1eefa)?$',
      caseSensitive: false,
    ).firstMatch(original);
    final message = originalMatch?.group(1)?.trim() ?? match.group(1)!.trim();
    if (message.isEmpty) return null;

    return ReminderRequest(message: message, delayMinutes: delayMinutes);
  }

  static String? parseCancelTarget(String input) {
    final normalized = VietnameseText.normalize(input);
    final match = RegExp(
      r'^(?:huy|xoa|bo) nhac(?: (.+))?$',
    ).firstMatch(normalized);
    final target = match?.group(1)?.trim();
    return target == null || target.isEmpty ? null : target;
  }
}
