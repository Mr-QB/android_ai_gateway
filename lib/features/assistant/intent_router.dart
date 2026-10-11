import 'reminder_parser.dart';
import 'vietnamese_text.dart';

enum IntentType {
  visionQuery,
  sceneDescription,
  safetyAlert,
  ocrQuery,
  reminderCreate,
  reminderCancel,
  reminderList,
  deviceCommand,
  unknown,
}

extension IntentTypeName on IntentType {
  String get wireName => switch (this) {
    IntentType.visionQuery => 'VISION_QUERY',
    IntentType.sceneDescription => 'SCENE_DESCRIPTION',
    IntentType.safetyAlert => 'SAFETY_ALERT',
    IntentType.ocrQuery => 'OCR_QUERY',
    IntentType.reminderCreate => 'REMINDER_CREATE',
    IntentType.reminderCancel => 'REMINDER_CANCEL',
    IntentType.reminderList => 'REMINDER_LIST',
    IntentType.deviceCommand => 'DEVICE_COMMAND',
    IntentType.unknown => 'UNKNOWN',
  };
}

class IntentResult {
  final IntentType type;
  final Map<String, Object> slots;
  final double confidence;

  const IntentResult({
    required this.type,
    this.slots = const {},
    required this.confidence,
  });
}

/// Lightweight Vietnamese query routing. It performs no model inference.
class IntentRouter {
  static IntentResult route(String input) {
    final query = VietnameseText.normalize(input);
    if (query.isEmpty) return _result(IntentType.unknown, 0);

    if (_matches(query, const ['huy nhac', 'xoa nhac', 'bo nhac'])) {
      final target = ReminderParser.parseCancelTarget(input);
      return IntentResult(
        type: IntentType.reminderCancel,
        slots: target == null ? const {} : {'target': target},
        confidence: 0.98,
      );
    }
    if (_matches(query, const ['danh sach nhac', 'cac nhac hen', 'nhac nao'])) {
      return _result(IntentType.reminderList, 0.96);
    }
    final reminder = ReminderParser.parseCreate(input);
    if (reminder != null) {
      return IntentResult(
        type: IntentType.reminderCreate,
        slots: reminder.toSlots(),
        confidence: 0.98,
      );
    }

    const deviceActions = {
      'tang am luong': 'volume_up',
      'to am len': 'volume_up',
      'giam am luong': 'volume_down',
      'nho am xuong': 'volume_down',
      'bat den pin': 'flashlight_on',
      'tat den pin': 'flashlight_off',
      'bat den': 'light_unspecified',
      'tat den': 'light_unspecified',
      'mo camera': 'open_camera',
      'dung camera': 'close_camera',
      'chup anh': 'capture_photo',
      'tang do sang': 'brightness_up',
      'giam do sang': 'brightness_down',
      'tam dung': 'pause',
      'tiep tuc': 'resume',
    };
    for (final entry in deviceActions.entries) {
      if (query.contains(entry.key)) {
        return IntentResult(
          type: IntentType.deviceCommand,
          slots: {'action': entry.value},
          confidence: 0.94,
        );
      }
    }

    if (_matches(query, const [
      'nguy hiem',
      'vat can',
      'chuong ngai',
      'co an toan',
      'can tranh',
      'co nen tranh',
      'danger',
      'hazard',
    ])) {
      return _result(IntentType.safetyAlert, 0.96);
    }

    if (_matches(query, const [
      'doc chu',
      'doc bien',
      'bien bao ghi gi',
      'chu ghi gi',
      'noi dung tren',
      'read text',
      'ocr',
    ])) {
      return _result(IntentType.ocrQuery, 0.95);
    }

    if (_matches(query, const [
      'mo ta',
      'khung canh',
      'toan canh',
      'mo ta xung quanh',
      'describe scene',
    ])) {
      return _result(IntentType.sceneDescription, 0.91);
    }

    if (_matches(query, const [
      'co gi',
      'la gi',
      'o dau',
      'ben trai',
      'ben phai',
      'phia truoc',
      'toi dang nhin thay',
      'xung quanh',
      'what is',
      'what do you see',
    ])) {
      return _result(IntentType.visionQuery, 0.88);
    }

    return _result(IntentType.unknown, 0.35);
  }

  static IntentResult _result(IntentType type, double confidence) =>
      IntentResult(type: type, confidence: confidence);

  static bool _matches(String query, List<String> phrases) =>
      phrases.any(query.contains);
}
