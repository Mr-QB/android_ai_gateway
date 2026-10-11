import 'canonical_vocabulary.dart';
import 'visual_observation.dart';

class VietnameseResponseBuilder {
  static String? build(VisualObservation observation) {
    if (observation.isEmpty) return null;

    final visibleText = observation.text?.trim();
    if (visibleText != null && visibleText.isNotEmpty) {
      return 'Trước mặt có dòng chữ: $visibleText';
    }

    final object = _lookup(CanonicalVocabulary.objects, observation.object);
    final action = _lookup(CanonicalVocabulary.actions, observation.action);
    final direction = _lookup(
      CanonicalVocabulary.directions,
      observation.direction,
    );
    final distance = _lookup(
      CanonicalVocabulary.distances,
      observation.distance,
    );

    final risk = observation.risk?.trim().toLowerCase();
    final isHighRisk = risk == 'high';
    if (object == null &&
        action == null &&
        direction == null &&
        distance == null) {
      if (isHighRisk) return 'Cẩn thận, có vật cản phía trước.';
      return null;
    }

    final parts = <String>[];
    if (object != null) {
      parts.add(object);
    } else {
      parts.add(isHighRisk ? 'vật cản' : 'một vật thể');
    }
    if (action != null) parts.add(action);
    if (distance != null &&
        observation.action?.toLowerCase() != 'approaching') {
      parts.add(distance);
    }

    final location = direction ?? 'phía trước';
    final description = '${parts.join(' ')} $location';
    if (isHighRisk) return 'Cẩn thận, có $description.';
    return '${_capitalize(location)} có ${parts.join(' ')}.';
  }

  static String? _lookup(Map<String, String> vocabulary, String? value) {
    final key = value?.trim().toLowerCase();
    if (key == null || key.isEmpty || key == 'none' || key == 'unknown') {
      return null;
    }
    return vocabulary[key];
  }

  static String _capitalize(String value) =>
      value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';
}
