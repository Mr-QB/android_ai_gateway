import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'streaming_speech_pipeline.dart';
import 'vietnamese_tts_queue.dart';

enum AlertPriority {
  criticalHazard(5), // Immediate safety alert (can interrupt anything)
  highWarning(4), // Important warning
  userQuery(3), // Direct answer to user
  normalDescription(2), // Periodic scene summary
  backgroundSemantic(1); // Background graph update notification

  final int level;
  const AlertPriority(this.level);
}

class AlertMessage {
  final String message;
  final AlertPriority priority;
  final String sourceAgent;
  final int timestamp;

  const AlertMessage({
    required this.message,
    required this.priority,
    required this.sourceAgent,
    required this.timestamp,
  });
}

class AssistiveOutputManager {
  static final AssistiveOutputManager _instance =
      AssistiveOutputManager._internal();
  factory AssistiveOutputManager() => _instance;
  AssistiveOutputManager._internal() {
    _initTts();
  }

  final FlutterTts _tts = FlutterTts();
  late final VietnameseTtsQueue _speechQueue = VietnameseTtsQueue(
    speaker: FlutterTtsSpeaker(_tts),
  );
  late final StreamingSpeechPipeline _speechPipeline = StreamingSpeechPipeline(
    queue: _speechQueue,
  );

  final ValueNotifier<AlertMessage?> latestAlert = ValueNotifier<AlertMessage?>(
    null,
  );

  Future<void> _initTts() async {
    try {
      await _tts.setLanguage('vi-VN');
      await _tts.setSpeechRate(0.5);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      await _tts.awaitSpeakCompletion(true);
    } catch (e) {
      debugPrint('[AssistiveOutputManager] TTS init warning: $e');
    }
  }

  /// Dispatches an alert/speech with strict priority checks
  Future<void> dispatch({
    required String message,
    required AlertPriority priority,
    required String sourceAgent,
    bool speak = true,
  }) async {
    final alert = AlertMessage(
      message: message,
      priority: priority,
      sourceAgent: sourceAgent,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    latestAlert.value = alert;
    debugPrint(
      '[AssistiveOutput] priority=${priority.name} source=$sourceAgent',
    );

    if (!speak || message.trim().isEmpty) return;

    await _speechQueue.enqueue(message, priority: priority.level);
  }

  Future<void> enqueueSegment(
    String message, {
    required AlertPriority priority,
  }) => _speechQueue.enqueue(message, priority: priority.level);

  Future<void> speakStream(
    Stream<String> fragments, {
    required AlertPriority priority,
    required String sourceAgent,
  }) async {
    final segmentCount = await _speechPipeline.speak(
      fragments,
      priority: priority.level,
    );
    debugPrint('[TTS] source=$sourceAgent segments=$segmentCount');
  }

  Future<void> interrupt() => _speechQueue.interrupt();

  void clearQueue() => _speechQueue.clear();

  Future<void> stop() => _speechQueue.stop();
}
