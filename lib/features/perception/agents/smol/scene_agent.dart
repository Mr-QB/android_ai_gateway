import '../../utils/json_extractor.dart';
import '../../utils/performance_logger.dart';
import '../../output/assistive_output_manager.dart';
import '../../../sense_graph/sense_graph_manager.dart';
import '../base_agent.dart';

class SceneAgentResult {
  final String sceneType;
  final String summary;
  final List<String> importantObjects;
  final double confidence;
  final bool needEscalation;
  final String rawResponse;
  final double latencyMs;

  const SceneAgentResult({
    required this.sceneType,
    required this.summary,
    required this.importantObjects,
    required this.confidence,
    required this.needEscalation,
    required this.rawResponse,
    required this.latencyMs,
  });
}

class SceneAgent extends BasePerceptionAgent {
  SceneAgent({required super.engineManager}) : super(name: 'SceneAgent');

  Future<SceneAgentResult> execute({
    required String imagePath,
    String? viewId,
    List<String>? detectedObjects,
    List<String>? ocrTexts,
  }) async {
    final contextInfo = StringBuffer();
    if (detectedObjects != null && detectedObjects.isNotEmpty) {
      contextInfo.writeln('Objects detected: ${detectedObjects.take(8).join(", ")}');
    }
    if (ocrTexts != null && ocrTexts.isNotEmpty) {
      contextInfo.writeln('Visible text: ${ocrTexts.take(4).join(", ")}');
    }

    final prompt = '''
Analyze this scene for a visually impaired user.
$contextInfo
Respond strictly with a JSON object:
{
  "sceneType": "brief type like indoor room, corridor, street, sidewalk, crosswalk",
  "summary": "concise description in Vietnamese (1-2 short sentences)",
  "importantObjects": ["key items to be aware of"],
  "confidence": 0.85,
  "needEscalation": false
}
''';

    final startTime = DateTime.now().millisecondsSinceEpoch;
    final vlmResult = await engineManager.runSmolInference(
      imagePath: imagePath,
      prompt: prompt,
      maxTokens: 128,
    );
    final latency = (DateTime.now().millisecondsSinceEpoch - startTime).toDouble();

    final jsonMap = JsonExtractor.extractJsonMap(vlmResult.text);

    final sceneType = jsonMap['sceneType']?.toString() ?? 'Không gian chung';
    final summary = jsonMap['summary']?.toString() ??
        (vlmResult.text.isNotEmpty ? vlmResult.text : 'Đang ở trong không gian trước mắt.');
    final importantObjects = (jsonMap['importantObjects'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];
    final confidence = (jsonMap['confidence'] as num?)?.toDouble() ?? 0.80;
    final needEscalation = jsonMap['needEscalation'] == true;

    // Update SenseGraph ViewNode if viewId was provided
    if (viewId != null) {
      SenseGraphManager().updateSceneType(viewId, sceneType);
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
      triggerReason: 'scene_description',
    );

    // Speak description
    if (summary.isNotEmpty) {
      AssistiveOutputManager().dispatch(
        message: summary,
        priority: AlertPriority.normalDescription,
        sourceAgent: name,
      );
    }

    return SceneAgentResult(
      sceneType: sceneType,
      summary: summary,
      importantObjects: importantObjects,
      confidence: confidence,
      needEscalation: needEscalation,
      rawResponse: vlmResult.text,
      latencyMs: latency,
    );
  }
}
