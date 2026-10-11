import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

abstract interface class TtsSpeaker {
  Future<void> speak(String text);
  Future<void> stop();
}

class FlutterTtsSpeaker implements TtsSpeaker {
  FlutterTtsSpeaker(this._tts);

  final FlutterTts _tts;

  @override
  Future<void> speak(String text) async {
    await _tts.speak(text);
  }

  @override
  Future<void> stop() async {
    await _tts.stop();
  }
}

class _QueuedSpeech {
  const _QueuedSpeech(this.text, this.priority, this.sequence);

  final String text;
  final int priority;
  final int sequence;
}

/// Serializes speech and lets higher-priority alerts interrupt narration.
class VietnameseTtsQueue {
  VietnameseTtsQueue({required this._speaker});

  final TtsSpeaker _speaker;
  final List<_QueuedSpeech> _pending = [];
  bool _draining = false;
  int? _currentPriority;
  int _sequence = 0;
  Completer<void>? _idleCompleter;

  int get queuedCount => _pending.length;
  int? get currentPriority => _currentPriority;
  bool get isSpeaking => _currentPriority != null;

  Future<void> enqueue(String text, {required int priority}) async {
    final message = text.trim();
    if (message.isEmpty) return;

    final item = _QueuedSpeech(message, priority, _sequence++);
    final shouldInterrupt =
        _currentPriority != null && priority > _currentPriority!;
    if (shouldInterrupt) {
      _pending.removeWhere((queued) => queued.priority < priority);
      _pending.insert(0, item);
      try {
        await _speaker.stop();
      } catch (error) {
        debugPrint('[TTS] interrupt failed: $error');
      }
    } else {
      _pending.add(item);
      _pending.sort((a, b) {
        final byPriority = b.priority.compareTo(a.priority);
        return byPriority != 0 ? byPriority : a.sequence.compareTo(b.sequence);
      });
    }
    unawaited(_drain());
  }

  /// Drops pending speech but lets the current segment finish.
  void clear() {
    _pending.clear();
    _completeIdleIfNeeded();
  }

  /// Stops current speech and removes pending segments.
  Future<void> interrupt() async {
    _pending.clear();
    try {
      await _speaker.stop();
    } catch (error) {
      debugPrint('[TTS] stop failed: $error');
    }
  }

  Future<void> stop() => interrupt();

  Future<void> waitUntilIdle() {
    if (!_draining && _pending.isEmpty && _currentPriority == null) {
      return Future<void>.value();
    }
    return (_idleCompleter ??= Completer<void>()).future;
  }

  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    try {
      while (_pending.isNotEmpty) {
        final item = _pending.removeAt(0);
        _currentPriority = item.priority;
        try {
          await _speaker.speak(item.text);
        } catch (error) {
          debugPrint('[TTS] speak failed: $error');
        } finally {
          _currentPriority = null;
        }
      }
    } finally {
      _draining = false;
      _completeIdleIfNeeded();
      if (_pending.isNotEmpty) unawaited(_drain());
    }
  }

  void _completeIdleIfNeeded() {
    if (_draining || _pending.isNotEmpty || _currentPriority != null) return;
    final completer = _idleCompleter;
    _idleCompleter = null;
    if (completer != null && !completer.isCompleted) completer.complete();
  }
}
