import 'package:android_ai_gateway/features/perception/vlm_engine_manager.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.example.android_ai_gateway/vlm');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  test('memory pressure cancels inference and releases a resident VLM', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return true;
    });

    final manager = VlmEngineManager();
    manager.smolStatus = EngineStatus.ready;
    manager.gemmaStatus = EngineStatus.unloaded;
    manager.currentlyLoadedModelKey = 'smolvlm2_500m';
    manager.activeBackend = 'CPU';

    await manager.handleMemoryPressure();

    expect(calls, ['cancelInference', 'disposeVlm']);
    expect(manager.smolStatus, EngineStatus.unloaded);
    expect(manager.gemmaStatus, EngineStatus.unloaded);
    expect(manager.currentlyLoadedModelKey, isNull);
    expect(manager.activeBackend, 'NONE');

    messenger.setMockMethodCallHandler(channel, null);
  });
}
