import 'package:android_ai_gateway/features/assistant/device_command_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(
    'com.example.android_ai_gateway/device_commands',
  );
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return {'success': true, 'action': call.arguments['action']};
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('invokes native execution with the parsed action', () async {
    expect(await DeviceCommandService().execute('volume_up'), 'volume_up');
    expect(calls.single.method, 'executeDeviceCommand');
    expect(calls.single.arguments, {'action': 'volume_up'});
  });
}
