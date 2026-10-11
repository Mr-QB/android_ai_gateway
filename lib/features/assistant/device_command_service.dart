import 'package:flutter/services.dart';

class DeviceCommandService {
  static const _channel = MethodChannel(
    'com.example.android_ai_gateway/device_commands',
  );

  Future<String> execute(String action) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'executeDeviceCommand',
      {'action': action},
    );
    if (result?['success'] != true) {
      throw PlatformException(
        code: result?['error']?.toString() ?? 'DEVICE_COMMAND_FAILED',
        message: result?['message']?.toString() ?? 'Device command failed',
      );
    }
    return result?['action']?.toString() ?? action;
  }
}
