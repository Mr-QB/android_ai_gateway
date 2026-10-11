import 'dart:convert';

class VisualObservation {
  final String? object;
  final String? action;
  final String? direction;
  final String? distance;
  final String? risk;
  final String? text;

  const VisualObservation({
    this.object,
    this.action,
    this.direction,
    this.distance,
    this.risk,
    this.text,
  });

  bool get isEmpty =>
      object == null &&
      action == null &&
      direction == null &&
      distance == null &&
      risk == null &&
      text == null;
}

class StructuredVlmParser {
  static const _allowedKeys = {
    'OBJECT',
    'ACTION',
    'DIRECTION',
    'DISTANCE',
    'RISK',
    'TEXT',
  };

  static VisualObservation parse(String response) {
    final values = <String, String>{};
    if (response.trimLeft().startsWith('{')) {
      final decoded = jsonDecode(response);
      if (decoded is! Map) {
        throw const FormatException(
          'Structured visual output must be an object',
        );
      }
      for (final entry in decoded.entries) {
        final key = entry.key.toString().toUpperCase();
        if (_allowedKeys.contains(key) && entry.value is String) {
          values[key] = (entry.value as String).trim();
        }
      }
    } else {
      for (final line in response.split(RegExp(r'\r?\n'))) {
        final separator = line.indexOf('=');
        if (separator < 1) continue;
        final key = line.substring(0, separator).trim().toUpperCase();
        if (!_allowedKeys.contains(key)) continue;
        final value = line.substring(separator + 1).trim();
        if (value.isNotEmpty) values[key] = value;
      }
    }

    if (values.isEmpty) {
      throw const FormatException('No structured visual fields found');
    }

    String? field(String name) {
      final value = values[name];
      if (value == null || value.toLowerCase() == 'none') return null;
      return value;
    }

    return VisualObservation(
      object: field('OBJECT'),
      action: field('ACTION'),
      direction: field('DIRECTION'),
      distance: field('DISTANCE'),
      risk: field('RISK'),
      text: field('TEXT'),
    );
  }
}
