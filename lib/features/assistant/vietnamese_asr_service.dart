import 'dart:async';

import 'package:flutter/services.dart';

class VietnameseAsrEvent {
  const VietnameseAsrEvent({required this.type, this.text = ''});

  final String type;
  final String text;

  factory VietnameseAsrEvent.fromMap(Map<dynamic, dynamic> map) {
    final type = map['type']?.toString();
    if (type == null) throw const FormatException('ASR event has no type');
    return VietnameseAsrEvent(type: type, text: map['text']?.toString() ?? '');
  }
}

class VietnameseAsrService {
  static const _channel = MethodChannel('com.example.android_ai_gateway/asr');
  static const _events = EventChannel(
    'com.example.android_ai_gateway/asr/events',
  );

  Stream<VietnameseAsrEvent> listen() async* {
    final controller = StreamController<VietnameseAsrEvent>();
    final subscription = _events.receiveBroadcastStream().listen(
      (event) {
        if (event is Map) controller.add(VietnameseAsrEvent.fromMap(event));
      },
      onError: controller.addError,
      onDone: controller.close,
    );
    try {
      await _channel.invokeMethod<bool>('startListening');
      await for (final event in controller.stream) {
        yield event;
        if (event.type == 'final') break;
      }
    } finally {
      await subscription.cancel();
      if (!controller.isClosed) await controller.close();
    }
  }

  Future<void> stop() async => _channel.invokeMethod<void>('stopListening');
}
