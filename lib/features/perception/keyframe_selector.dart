import '../ai_engine/domain/detection.dart';

enum TriggerReason {
  none,
  sceneChange,
  newImportantObject,
  newTextDetected,
  hazardCandidate,
  userQuery,
  periodicHeartbeat,
  highUncertainty,
}

class KeyframeDecision {
  final bool shouldTriggerSmol;
  final bool shouldTriggerGemma;
  final TriggerReason reason;
  final String description;

  const KeyframeDecision({
    required this.shouldTriggerSmol,
    required this.shouldTriggerGemma,
    required this.reason,
    required this.description,
  });

  static const KeyframeDecision pass = KeyframeDecision(
    shouldTriggerSmol: false,
    shouldTriggerGemma: false,
    reason: TriggerReason.none,
    description: 'No trigger criteria met',
  );
}

class KeyframeSelector {
  static const Duration smolCooldown = Duration(milliseconds: 1500);
  DateTime? _lastSmolTriggerTime;

  List<Detection> _previousDetections = [];
  Set<String> _previousTextSet = {};

  static const Set<int> _importantClassIds = {
    0,  // person
    1,  // bicycle
    2,  // car
    3,  // motorcycle
    5,  // bus
    7,  // truck
    9,  // traffic light
    11, // stop sign
    56, // chair
  };

  /// Evaluates incoming frame data to decide if Smol or Gemma should be triggered
  KeyframeDecision evaluateFrame({
    required List<Detection> currentDetections,
    List<String>? detectedTexts,
    bool isUserQuery = false,
    bool isHazardCandidate = false,
    bool isHighUncertainty = false,
  }) {
    final now = DateTime.now();

    // 1. User query always triggers
    if (isUserQuery) {
      _lastSmolTriggerTime = now;
      return const KeyframeDecision(
        shouldTriggerSmol: true,
        shouldTriggerGemma: true,
        reason: TriggerReason.userQuery,
        description: 'Direct user query triggered perception',
      );
    }

    // 2. Immediate hazard candidate triggers Smol immediately
    if (isHazardCandidate) {
      _lastSmolTriggerTime = now;
      return const KeyframeDecision(
        shouldTriggerSmol: true,
        shouldTriggerGemma: false,
        reason: TriggerReason.hazardCandidate,
        description: 'Potential hazard candidate in path',
      );
    }

    // 3. High uncertainty escalates to Gemma
    if (isHighUncertainty) {
      return const KeyframeDecision(
        shouldTriggerSmol: false,
        shouldTriggerGemma: true,
        reason: TriggerReason.highUncertainty,
        description: 'High semantic uncertainty triggered Gemma escalation',
      );
    }

    // Enforce cooldown for periodic automatic triggers
    if (_lastSmolTriggerTime != null && now.difference(_lastSmolTriggerTime!) < smolCooldown) {
      return KeyframeDecision.pass;
    }

    // 4. Check for new important object classes
    final prevClasses = _previousDetections.map((d) => d.classId).toSet();
    for (final d in currentDetections) {
      if (_importantClassIds.contains(d.classId) && !prevClasses.contains(d.classId)) {
        _lastSmolTriggerTime = now;
        _previousDetections = currentDetections;
        return KeyframeDecision(
          shouldTriggerSmol: true,
          shouldTriggerGemma: false,
          reason: TriggerReason.newImportantObject,
          description: 'New important object class ${d.classId} entered view',
        );
      }
    }

    // 5. Check for new OCR text
    if (detectedTexts != null && detectedTexts.isNotEmpty) {
      final currentTextSet = detectedTexts.map((t) => t.trim().toLowerCase()).toSet();
      final hasNewText = currentTextSet.difference(_previousTextSet).isNotEmpty;
      if (hasNewText) {
        _lastSmolTriggerTime = now;
        _previousTextSet = currentTextSet;
        return const KeyframeDecision(
          shouldTriggerSmol: true,
          shouldTriggerGemma: false,
          reason: TriggerReason.newTextDetected,
          description: 'New visible text identified by OCR',
        );
      }
    }

    // 6. Check significant scene change (bounding box shift)
    if (_hasSignificantSceneChange(_previousDetections, currentDetections)) {
      _lastSmolTriggerTime = now;
      _previousDetections = currentDetections;
      return const KeyframeDecision(
        shouldTriggerSmol: true,
        shouldTriggerGemma: false,
        reason: TriggerReason.sceneChange,
        description: 'Substantial spatial displacement detected',
      );
    }

    // 7. Periodic heartbeat (every 8 seconds if static)
    if (_lastSmolTriggerTime == null || now.difference(_lastSmolTriggerTime!) > const Duration(seconds: 8)) {
      _lastSmolTriggerTime = now;
      _previousDetections = currentDetections;
      return const KeyframeDecision(
        shouldTriggerSmol: true,
        shouldTriggerGemma: false,
        reason: TriggerReason.periodicHeartbeat,
        description: 'Periodic scene heartbeat update',
      );
    }

    return KeyframeDecision.pass;
  }

  bool _hasSignificantSceneChange(List<Detection> prev, List<Detection> curr) {
    if ((prev.length - curr.length).abs() >= 2) return true;
    if (prev.isEmpty && curr.isNotEmpty) return true;

    // Check center shift
    double prevCenterX = 0;
    for (final d in prev) {
      prevCenterX += (d.x + d.width / 2);
    }
    prevCenterX = prev.isNotEmpty ? prevCenterX / prev.length : 0.5;

    double currCenterX = 0;
    for (final d in curr) {
      currCenterX += (d.x + d.width / 2);
    }
    currCenterX = curr.isNotEmpty ? currCenterX / curr.length : 0.5;

    return (prevCenterX - currCenterX).abs() > 0.30;
  }
}
