import '../../../sense_graph/models/sense_node.dart';
import '../../../sense_graph/sense_graph_manager.dart';
import '../../utils/json_extractor.dart';
import '../../utils/performance_logger.dart';
import '../../output/assistive_output_manager.dart';
import '../base_agent.dart';

class TextAgentResult {
  final String normalizedText;
  final String semanticType;
  final String summary;
  final String importance;
  final String rawResponse;
  final double latencyMs;

  const TextAgentResult({
    required this.normalizedText,
    required this.semanticType,
    required this.summary,
    required this.importance,
    required this.rawResponse,
    required this.latencyMs,
  });
}

class TextAgent extends BasePerceptionAgent {
  TextAgent({required super.engineManager}) : super(name: 'TextAgent');

  Future<TextAgentResult> execute({
    required String imagePath,
    required TextNode textNode,
    List<ObjectNode>? nearbyObjects,
  }) async {
    final startTime = DateTime.now().millisecondsSinceEpoch;

    final nearbyContext = (nearbyObjects != null && nearbyObjects.isNotEmpty)
        ? 'Nearby objects: ${nearbyObjects.map((o) => o.className).join(", ")}'
        : '';

    final prompt = '''
Analyze this recognized text in context:
Raw OCR text: "${textNode.rawText}"
$nearbyContext
Tasks:
1. Correct any obvious OCR typos.
2. Classify semantic type (warning_sign, room_label, direction, instruction, brand).
3. Classify importance (critical, warning, info).
4. Provide a 1-sentence explanation in Vietnamese.

Respond strictly in JSON:
{
  "normalizedText": "corrected text",
  "semanticType": "warning_sign",
  "summary": "giải thích ngắn bằng tiếng Việt",
  "importance": "critical"
}
''';

    final vlmResult = await engineManager.runGemmaInference(
      imagePath: imagePath,
      prompt: prompt,
      maxTokens: 128,
    );
    final latency = (DateTime.now().millisecondsSinceEpoch - startTime).toDouble();

    final jsonMap = JsonExtractor.extractJsonMap(vlmResult.text);

    final normalizedText = jsonMap['normalizedText']?.toString() ?? textNode.rawText;
    final semanticType = jsonMap['semanticType']?.toString() ?? 'info';
    final summary = jsonMap['summary']?.toString() ?? 'Chữ trên ảnh: $normalizedText';
    final importance = jsonMap['importance']?.toString() ?? 'info';

    // Enrich TextNode in SenseGraph without overwriting rawText
    SenseGraphManager().enrichTextNode(
      textNode.id,
      normalizedText: normalizedText,
      semanticType: semanticType,
      importance: importance,
    );

    // If critical importance, announce via TTS
    if (importance.toLowerCase() == 'critical' || importance.toLowerCase() == 'warning') {
      AssistiveOutputManager().dispatch(
        message: summary,
        priority: importance.toLowerCase() == 'critical' ? AlertPriority.highWarning : AlertPriority.normalDescription,
        sourceAgent: name,
      );
    }

    // Log benchmark
    await PerformanceLogger.logRecord(
      agent: name,
      model: 'Gemma-4-E2B-it',
      backend: vlmResult.backend,
      ttftMs: vlmResult.timeToFirstTokenMs,
      generationMs: vlmResult.generationMs,
      totalMs: vlmResult.totalInferenceMs,
      nativeHeapMb: vlmResult.nativeHeapMb,
      javaHeapMb: vlmResult.javaHeapMb,
      triggerReason: 'ocr_explanation',
    );

    return TextAgentResult(
      normalizedText: normalizedText,
      semanticType: semanticType,
      summary: summary,
      importance: importance,
      rawResponse: vlmResult.text,
      latencyMs: latency,
    );
  }
}
