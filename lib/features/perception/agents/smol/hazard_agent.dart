import '../../../ai_engine/domain/detection.dart';
import '../../../camera/data/coco_labels.dart';
import '../../utils/json_extractor.dart';
import '../../utils/performance_logger.dart';
import '../../output/assistive_output_manager.dart';
import '../../../assistant/visual_observation.dart';
import '../../../assistant/vietnamese_response_builder.dart';
import '../../../sense_graph/sense_graph_manager.dart';
import '../base_agent.dart';

class HazardAgentResult {
  final bool hazard;
  final double severity; // 0.0 to 1.0
  final String direction; // center, left, right
  final String reason;
  final String message;
  final bool isImmediateRuleWarning;
  final bool analysisSucceeded;
  final String rawResponse;
  final double latencyMs;

  const HazardAgentResult({
    required this.hazard,
    required this.severity,
    required this.direction,
    required this.reason,
    required this.message,
    required this.isImmediateRuleWarning,
    required this.analysisSucceeded,
    required this.rawResponse,
    required this.latencyMs,
  });
}

class HazardAgent extends BasePerceptionAgent {
  HazardAgent({required super.engineManager}) : super(name: 'HazardAgent');

  static const _requiredStructuredFields = {
    'OBJECT',
    'ACTION',
    'DIRECTION',
    'DISTANCE',
    'RISK',
    'TEXT',
  };

  static bool isValidVlmAssessment({
    required bool inferenceSucceeded,
    required Map<String, dynamic> response,
  }) =>
      inferenceSucceeded &&
      response['hazard'] is bool &&
      _requiredStructuredFields.every((key) => response[key] is String);

  static bool assessmentReportsHazard(Map<String, dynamic> response) =>
      response['hazard'] == true ||
      const {
        'high',
        'medium',
      }.contains(response['RISK']?.toString().toLowerCase());

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
  static ({
    bool hasImmediateHazard,
    String warningMessage,
    String direction,
    double severity,
  })
  checkDeterministicSafety(List<Detection> detections) {
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

      if (_criticalClasses.contains(className) &&
          area > 0.20 &&
          det.confidence > 0.60) {
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

    final prompt =
        '''
Safety check for a visually impaired pedestrian:
$detectionSummary
Look for steps, drop-offs, obstacles blocking the path, low-hanging items, or moving vehicles.
Return only compact JSON with hazard (boolean), OBJECT, ACTION, DIRECTION, DISTANCE, RISK, and TEXT fields. Use short canonical labels and no prose. TEXT is exact visible text or "none".
''';
    final vlmResult = await engineManager.runSmolInference(
      imagePath: imagePath,
      prompt: prompt,
      maxTokens: 96,
      structuredOutputFormat: 'hazard',
    );
    final latency = (DateTime.now().millisecondsSinceEpoch - startTime)
        .toDouble();

    final jsonMap = JsonExtractor.extractJsonMap(vlmResult.text);

    VisualObservation? observation;
    try {
      observation = StructuredVlmParser.parse(vlmResult.text);
    } on FormatException {
      // Preserve the deterministic rule warning and report an inconclusive check.
    }
    final safetyObservation = observation == null
        ? null
        : VisualObservation(
            object: observation.object,
            action: observation.action,
            direction: observation.direction,
            distance: observation.distance,
            risk: observation.risk,
          );
    final analysisSucceeded = isValidVlmAssessment(
      inferenceSucceeded: vlmResult.success,
      response: jsonMap,
    );
    final risk = safetyObservation?.risk?.toLowerCase();
    final hazard =
        (analysisSucceeded && assessmentReportsHazard(jsonMap)) ||
        ruleCheck.hasImmediateHazard;
    final severity = switch (risk) {
      'high' => 0.95,
      'medium' => 0.65,
      'low' => 0.25,
      _ => ruleCheck.severity,
    };
    final direction = safetyObservation?.direction ?? ruleCheck.direction;
    final reason = analysisSucceeded
        ? safetyObservation?.object ?? 'Visual hazard analysis completed'
        : vlmResult.message ?? 'VLM hazard analysis failed';
    final message = ruleCheck.hasImmediateHazard
        ? ruleCheck.warningMessage
        : !analysisSucceeded
        ? ''
        : hazard
        ? VietnameseResponseBuilder.build(safetyObservation!) ??
              'C\u1ea3nh b\u00e1o, c\u00f3 th\u1ec3 c\u00f3 v\u1eadt c\u1ea3n ph\u00eda tr\u01b0\u1edbc.'
        : '\u0110\u01b0\u1eddng \u0111i th\u00f4ng tho\u00e1ng.';
    if (hazard && !ruleCheck.hasImmediateHazard && message.isNotEmpty) {
      // If VLM found a hazard that rule check missed, dispatch high warning
      AssistiveOutputManager().dispatch(
        message: message,
        priority: risk == 'high'
            ? AlertPriority.criticalHazard
            : AlertPriority.highWarning,
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
      analysisSucceeded: analysisSucceeded,
      rawResponse: vlmResult.text,
      latencyMs: latency,
    );
  }
}
