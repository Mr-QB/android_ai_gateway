import '../../../ai_engine/domain/detection.dart';
import '../../../camera/data/coco_labels.dart';
import '../../utils/json_extractor.dart';
import '../../utils/performance_logger.dart';
import '../../output/assistive_output_manager.dart';
import '../../../sense_graph/sense_graph_manager.dart';
import '../base_agent.dart';

class HazardAgentResult {
  final bool hazard;
  final double severity; // 0.0 to 1.0
  final String direction; // center, left, right
  final String reason;
  final String message;
  final bool isImmediateRuleWarning;
  final String rawResponse;
  final double latencyMs;

  const HazardAgentResult({
    required this.hazard,
    required this.severity,
    required this.direction,
    required this.reason,
    required this.message,
    required this.isImmediateRuleWarning,
    required this.rawResponse,
    required this.latencyMs,
  });
}

class HazardAgent extends BasePerceptionAgent {
  HazardAgent({required super.engineManager}) : super(name: 'HazardAgent');

  /// Critical obstacle classes in COCO that pose immediate hazard if close
  static const Set<String> _criticalClasses = {
    'car',
    'motorcycle',
    'bicycle',
    'bus',
    'truck',
    'chair',
    'bench',
    'dog',
  };

  /// Deterministic rule-based pre-check before calling VLM:
  /// Detects whether any object occupies a dangerous area in the center/forward path with high area
  static ({bool hasImmediateHazard, String warningMessage, String direction, double severity}) checkDeterministicSafety(
      List<Detection> detections) {
    for (final det in detections) {
      final className = (det.classId >= 0 && det.classId < cocoLabels.length)
          ? cocoLabels[det.classId]
          : 'object';

      // An object is considered close if area (width * height) is large (> 0.20 of the screen)
      final area = det.width * det.height;
      final centerX = det.x + (det.width / 2);

      final String direction;
      if (centerX < 0.35) {
        direction = 'bên trái';
      } else if (centerX > 0.65) {
        direction = 'bên phải';
      } else {
        direction = 'phía trước';
      }

      if (_criticalClasses.contains(className) && area > 0.20 && det.confidence > 0.60) {
        return (
          hasImmediateHazard: true,
          warningMessage: 'Cảnh báo! Có $className lớn ngay $direction.',
          direction: direction,
          severity: 0.90,
        );
      }
    }

    return (
      hasImmediateHazard: false,
      warningMessage: '',
      direction: 'phía trước',
      severity: 0.0,
    );
  }

  Future<HazardAgentResult> execute({
    required String imagePath,
    List<Detection>? detections,
    String? viewId,
  }) async {
    final startTime = DateTime.now().millisecondsSinceEpoch;

    // STEP 1: Immediate deterministic safety rule-based check
    final ruleCheck = checkDeterministicSafety(detections ?? []);
    if (ruleCheck.hasImmediateHazard) {
      // Dispatch immediate critical warning BEFORE waiting for VLM!
      AssistiveOutputManager().dispatch(
        message: ruleCheck.warningMessage,
        priority: AlertPriority.criticalHazard,
        sourceAgent: '$name (RuleBased)',
      );

      // Record event in SenseGraph
      SenseGraphManager().recordEvent(
        type: 'immediate_hazard',
        description: ruleCheck.warningMessage,
        severity: ruleCheck.severity,
      );
    }

    // STEP 2: VLM semantic hazard confirmation
    final detectionSummary = (detections != null && detections.isNotEmpty)
        ? 'Detections in view: ${detections.map((d) => (d.classId < cocoLabels.length ? cocoLabels[d.classId] : d.classId)).join(", ")}'
        : '';

    final prompt = '''
Safety check for a visually impaired pedestrian:
$detectionSummary
Look for steps, drop-offs, obstacles blocking path, low-hanging items, or moving vehicles.
Respond strictly in JSON:
{
  "hazard": true,
  "severity": 0.85,
  "direction": "center",
  "reason": "short explanation in English",
  "message": "Cảnh báo ngắn gọn bằng tiếng Việt"
}
''';

    final vlmResult = await engineManager.runSmolInference(
      imagePath: imagePath,
      prompt: prompt,
      maxTokens: 96,
    );
    final latency = (DateTime.now().millisecondsSinceEpoch - startTime).toDouble();

    final jsonMap = JsonExtractor.extractJsonMap(vlmResult.text);

    final hazard = (jsonMap['hazard'] == true) || ruleCheck.hasImmediateHazard;
    final severity = (jsonMap['severity'] as num?)?.toDouble() ?? ruleCheck.severity;
    final direction = jsonMap['direction']?.toString() ?? ruleCheck.direction;
    final reason = jsonMap['reason']?.toString() ?? 'Obstacle detected in pathway';
    final message = jsonMap['message']?.toString() ??
        (ruleCheck.hasImmediateHazard ? ruleCheck.warningMessage : 'Đường đi thông thoáng.');

    if (hazard && !ruleCheck.hasImmediateHazard && message.isNotEmpty) {
      // If VLM found a hazard that rule check missed, dispatch high warning
      AssistiveOutputManager().dispatch(
        message: message,
        priority: AlertPriority.highWarning,
        sourceAgent: name,
      );

      SenseGraphManager().recordEvent(
        type: 'semantic_hazard',
        description: message,
        severity: severity,
      );
    }

    // Log benchmark
    await PerformanceLogger.logRecord(
      agent: name,
      model: 'SmolVLM2-500M',
      backend: vlmResult.backend,
      ttftMs: vlmResult.timeToFirstTokenMs,
      generationMs: vlmResult.generationMs,
      totalMs: vlmResult.totalInferenceMs,
      nativeHeapMb: vlmResult.nativeHeapMb,
      javaHeapMb: vlmResult.javaHeapMb,
      triggerReason: 'hazard_check',
    );

    return HazardAgentResult(
      hazard: hazard,
      severity: severity,
      direction: direction,
      reason: reason,
      message: message,
      isImmediateRuleWarning: ruleCheck.hasImmediateHazard,
      rawResponse: vlmResult.text,
      latencyMs: latency,
    );
  }
}
