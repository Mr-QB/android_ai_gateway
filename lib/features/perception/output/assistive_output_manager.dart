import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

enum AlertPriority {
  criticalHazard(5),       // Immediate safety alert (can interrupt anything)
  highWarning(4),          // Important warning
  userQuery(3),            // Direct answer to user
  normalDescription(2),    // Periodic scene summary
  backgroundSemantic(1);   // Background graph update notification

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
  static final AssistiveOutputManager _instance = AssistiveOutputManager._internal();
  factory AssistiveOutputManager() => _instance;
  AssistiveOutputManager._internal() {
    _initTts();
  }

  final FlutterTts _tts = FlutterTts();
  bool _isSpeaking = false;
  AlertPriority? _currentSpeakingPriority;

  final ValueNotifier<AlertMessage?> latestAlert = ValueNotifier<AlertMessage?>(null);

  Future<void> _initTts() async {
    try {
      await _tts.setLanguage('vi-VN');
      await _tts.setSpeechRate(0.5);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);

      _tts.setCompletionHandler(() {
        _isSpeaking = false;
        _currentSpeakingPriority = null;
      });

      _tts.setErrorHandler((_) {
        _isSpeaking = false;
        _currentSpeakingPriority = null;
      });
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
    debugPrint('[AssistiveOutput] [${priority.name}] from $sourceAgent: "$message"');

    if (!speak || message.trim().isEmpty) return;

    // Check if we should interrupt current speaking
    if (_isSpeaking && _currentSpeakingPriority != null) {
      if (priority.level > _currentSpeakingPriority!.level) {
        debugPrint('[AssistiveOutput] Interrupting lower priority speech for ${priority.name}');
        await _tts.stop();
      } else {
        // Drop or skip lower priority speech while higher priority is active
        debugPrint('[AssistiveOutput] Ignored lower priority speech (${priority.name} vs active ${_currentSpeakingPriority!.name})');
        return;
      }
    }

    _isSpeaking = true;
    _currentSpeakingPriority = priority;
    try {
      await _tts.speak(message);
    } catch (e) {
      debugPrint('[AssistiveOutput] TTS speak error: $e');
      _isSpeaking = false;
      _currentSpeakingPriority = null;
    }
  }

  Future<void> stop() async {
    await _tts.stop();
    _isSpeaking = false;
    _currentSpeakingPriority = null;
  }
}
