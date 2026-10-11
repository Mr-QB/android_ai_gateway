import 'dart:convert';

import 'visual_observation.dart';
import 'vietnamese_response_builder.dart';

class VisualSpeechUpdate {
  const VisualSpeechUpdate(this.text, {required this.isSafetyWarning});

  final String text;
  final bool isSafetyWarning;
}

/// Converts only a complete structured observation to speech; model field labels stay private.
class StructuredVlmSpeechAdapter {
  static const _requiredFields = {
    'OBJECT',
    'ACTION',
    'DIRECTION',
    'DISTANCE',
    'RISK',
  };

  final Map<String, String> _fields = {};
  String _pending = '';
  bool _jsonMode = false;
  bool _emitted = false;
  bool get hasEmitted => _emitted;

  VisualSpeechUpdate? push(String fragment) {
    _pending += fragment;
    if (_jsonMode || _pending.trimLeft().startsWith('{')) {
      _jsonMode = true;
      _readJsonFields();
      return _buildIfReady();
    }
    while (true) {
      final newline = _pending.indexOf('\n');
      if (newline < 0) break;
      _readLine(_pending.substring(0, newline));
      _pending = _pending.substring(newline + 1);
    }
    return _buildIfReady();
  }

  VisualSpeechUpdate? finish() {
    if (_pending.trim().isNotEmpty) _readLine(_pending);
    _pending = '';
    return _buildIfReady();
  }

  void _readLine(String line) {
    final separator = line.indexOf('=');
    if (separator < 1) return;
    final key = line.substring(0, separator).trim().toUpperCase();
    if (_requiredFields.contains(key)) {
      _fields[key] = line.substring(separator + 1).trim();
    }
  }

  void _readJsonFields() {
    for (final key in _requiredFields) {
      if (_fields.containsKey(key)) continue;
      final match = RegExp(
        '"$key"\\s*:\\s*"((?:\\\\.|[^"\\\\])*)"',
      ).firstMatch(_pending);
      if (match == null) continue;
      try {
        _fields[key] = jsonDecode('"${match.group(1)}"') as String;
      } on FormatException {
        // Wait for the remainder of this streamed JSON string.
      }
    }
  }

  VisualSpeechUpdate? _buildIfReady() {
    if (_emitted || !_fields.keys.toSet().containsAll(_requiredFields)) {
      return null;
    }
    try {
      final observation = StructuredVlmParser.parse(
        _fields.entries
            .map((entry) => '${entry.key}=${entry.value}')
            .join('\n'),
      );
      final text = VietnameseResponseBuilder.build(observation);
      if (text == null || text.isEmpty) return null;
      _emitted = true;
      return VisualSpeechUpdate(
        text,
        isSafetyWarning: _fields['RISK']?.toLowerCase() == 'high',
      );
    } on FormatException {
      return null;
    }
  }
}
