import 'package:android_ai_gateway/features/vlm/presentation/vlm_test_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const vlmChannel = MethodChannel('com.example.android_ai_gateway/vlm');
  const reminderChannel = MethodChannel(
    'com.example.android_ai_gateway/reminders',
  );
  const deviceChannel = MethodChannel(
    'com.example.android_ai_gateway/device_commands',
  );
  final vlmCalls = <String>[];
  final reminderCalls = <String>[];
  final deviceCalls = <String>[];

  setUp(() {
    vlmCalls.clear();
    reminderCalls.clear();
    deviceCalls.clear();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(vlmChannel, (call) async {
      vlmCalls.add(call.method);
      if (call.method == 'getVlmStatus') {
        return {
          'isLoaded': false,
          'loadedModelKey': 'smolvlm2_500m',
          'modelExists': true,
          'modelsAvailable': <String, bool>{},
        };
      }
      return null;
    });
    messenger.setMockMethodCallHandler(reminderChannel, (call) async {
      reminderCalls.add(call.method);
      if (call.method == 'createReminder') {
        return {
          'success': true,
          'id': 'test-id',
          'message': 'u\u1ed1ng n\u01b0\u1edbc',
          'scheduledAt': DateTime.now().millisecondsSinceEpoch + 600000,
          'notificationsEnabled': true,
        };
      }
      return null;
    });
    messenger.setMockMethodCallHandler(deviceChannel, (call) async {
      deviceCalls.add(call.method);
      return {'success': true, 'action': 'volume_up'};
    });
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(vlmChannel, null);
    messenger.setMockMethodCallHandler(reminderChannel, null);
    messenger.setMockMethodCallHandler(deviceChannel, null);
  });

  testWidgets('reminder query is routed without calling VLM', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: VlmTestPage()));
    await tester.pumpAndSettle();

    final queryField = find.byType(TextField);
    await _scrollUntilFound(tester, queryField);
    await tester.ensureVisible(queryField);
    await tester.enterText(
      queryField,
      '\u004e\u0068\u1eafc t\u00f4i u\u1ed1ng n\u01b0\u1edbc sau 10 ph\u00fat',
    );
    final routeButton = find.text(
      '\u0110\u1ecbnh tuy\u1ebfn c\u00e2u h\u1ecfi',
    );
    await _scrollUntilFound(tester, routeButton);
    await tester.ensureVisible(routeButton);
    await tester.tap(routeButton);
    await tester.pumpAndSettle();

    expect(reminderCalls, ['createReminder']);
    expect(vlmCalls, ['getVlmStatus']);
    expect(find.textContaining('REMINDER_CREATE'), findsOneWidget);
    expect(
      find.textContaining('\u0110\u00e3 \u0111\u1eb7t nh\u1eafc'),
      findsOneWidget,
    );
  });

  testWidgets('device command invokes native action without calling VLM', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: VlmTestPage()));
    await tester.pumpAndSettle();
    final queryField = find.byType(TextField);
    await _scrollUntilFound(tester, queryField);
    await tester.ensureVisible(queryField);
    await tester.enterText(queryField, 'tang am luong');
    final routeButton = find.text('Định tuyến câu hỏi');
    await _scrollUntilFound(tester, routeButton);
    await tester.ensureVisible(routeButton);
    await tester.tap(routeButton);
    await tester.pumpAndSettle();

    expect(deviceCalls, ['executeDeviceCommand']);
    expect(vlmCalls, ['getVlmStatus']);
  });
}

Future<void> _scrollUntilFound(WidgetTester tester, Finder target) async {
  final scrollable = find.byType(Scrollable).last;
  for (var attempt = 0; attempt < 12 && target.evaluate().isEmpty; attempt++) {
    await tester.drag(scrollable, const Offset(0, -450));
    await tester.pumpAndSettle();
  }
}
