import '../../../sense_graph/sense_graph_manager.dart';
import '../../utils/json_extractor.dart';
import '../../utils/performance_logger.dart';
import '../../output/assistive_output_manager.dart';
import '../base_agent.dart';

class ReasoningAgentResult {
  final String answer;
  final double confidence;
  final List<String> referencedNodes;
  final String rawResponse;
  final double latencyMs;

  const ReasoningAgentResult({
    required this.answer,
    required this.confidence,
    required this.referencedNodes,
    required this.rawResponse,
    required this.latencyMs,
  });
}

class ReasoningAgent extends BasePerceptionAgent {
  ReasoningAgent({required super.engineManager}) : super(name: 'ReasoningAgent');

  Future<ReasoningAgentResult> execute({
    required String imagePath,
    required String userQuery,
    String? viewId,
  }) async {
    final startTime = DateTime.now().millisecondsSinceEpoch;

    // STEP 1: Retrieve relevant subgraph context (avoid sending full graph)
    final subgraph = SenseGraphManager().retriever.retrieveSubgraph(viewId: viewId);
    final subgraphContextText = subgraph.formatForPrompt();

    final prompt = '''
You are a spatial perception reasoning assistant for a visually impaired user.
Based on the current image and structured memory subgraph:

$subgraphContextText

USER QUERY: "$userQuery"

Answer clearly, accurately, and concisely in Vietnamese.
Respond strictly in JSON:
{
  "answer": "câu trả lời súc tích bằng tiếng Việt",
  "confidence": 0.90,
  "referencedNodes": ["id of nodes used"]
}
''';

    final vlmResult = await engineManager.runGemmaInference(
      imagePath: imagePath,
      prompt: prompt,
      maxTokens: 128,
    );
    final latency = (DateTime.now().millisecondsSinceEpoch - startTime).toDouble();

    final jsonMap = JsonExtractor.extractJsonMap(vlmResult.text);

    final answer = jsonMap['answer']?.toString() ??
        (vlmResult.text.isNotEmpty ? vlmResult.text : 'Không tìm thấy thông tin phù hợp với câu hỏi.');
    final confidence = (jsonMap['confidence'] as num?)?.toDouble() ?? 0.85;
    final referencedNodes = (jsonMap['referencedNodes'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];

    // Speak answer to user
    AssistiveOutputManager().dispatch(
      message: answer,
      priority: AlertPriority.userQuery,
      sourceAgent: name,
    );

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
      triggerReason: 'user_complex_reasoning',
    );

    return ReasoningAgentResult(
      answer: answer,
      confidence: confidence,
      referencedNodes: referencedNodes,
      rawResponse: vlmResult.text,
      latencyMs: latency,
    );
  }
}
