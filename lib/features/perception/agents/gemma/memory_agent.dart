import '../../../sense_graph/models/sense_edge.dart';
import '../../../sense_graph/sense_graph_manager.dart';
import '../../utils/json_extractor.dart';
import '../../utils/performance_logger.dart';
import '../base_agent.dart';

class MergeProposal {
  final bool mergeCandidate;
  final String nodeA;
  final String nodeB;
  final double confidence;
  final String? suggestedLabel;

  const MergeProposal({
    required this.mergeCandidate,
    required this.nodeA,
    required this.nodeB,
    required this.confidence,
    this.suggestedLabel,
  });

  Map<String, dynamic> toJson() => {
        'mergeCandidate': mergeCandidate,
        'nodeA': nodeA,
        'nodeB': nodeB,
        'confidence': confidence,
        'suggestedLabel': suggestedLabel,
      };
}

class MemoryAgentResult {
  final List<MergeProposal> proposals;
  final String rawResponse;
  final double latencyMs;

  const MemoryAgentResult({
    required this.proposals,
    required this.rawResponse,
    required this.latencyMs,
  });
}

class MemoryAgent extends BasePerceptionAgent {
  MemoryAgent({required super.engineManager}) : super(name: 'MemoryAgent');

  Future<MemoryAgentResult> execute({
    required String imagePath,
    String? viewId,
  }) async {
    final startTime = DateTime.now().millisecondsSinceEpoch;

    final subgraph = SenseGraphManager().retriever.retrieveSubgraph(viewId: viewId);
    final contextText = subgraph.formatForPrompt();

    final prompt = '''
Examine the recent nodes in the world graph memory:
$contextText

Identify if any two entities observed across different views likely represent the SAME physical real-world object (e.g. same doorway, same table, same exit sign seen again).
Do NOT force merge. Only PROPOSE candidate associations.
Respond strictly in JSON:
{
  "proposals": [
    {
      "mergeCandidate": true,
      "nodeA": "node_id_1",
      "nodeB": "node_id_2",
      "confidence": 0.84,
      "suggestedLabel": "Exit Door"
    }
  ]
}
''';

    final vlmResult = await engineManager.runGemmaInference(
      imagePath: imagePath,
      prompt: prompt,
      maxTokens: 128,
    );
    final latency = (DateTime.now().millisecondsSinceEpoch - startTime).toDouble();

    final jsonMap = JsonExtractor.extractJsonMap(vlmResult.text);
    final rawList = jsonMap['proposals'] as List<dynamic>? ?? [];

    final proposals = <MergeProposal>[];
    for (final item in rawList) {
      if (item is Map<String, dynamic> && item['mergeCandidate'] == true) {
        final a = item['nodeA']?.toString() ?? '';
        final b = item['nodeB']?.toString() ?? '';
        final conf = (item['confidence'] as num?)?.toDouble() ?? 0.80;
        final label = item['suggestedLabel']?.toString();

        if (a.isNotEmpty && b.isNotEmpty) {
          final proposal = MergeProposal(
            mergeCandidate: true,
            nodeA: a,
            nodeB: b,
            confidence: conf,
            suggestedLabel: label,
          );
          proposals.add(proposal);

          // Add a tentative POSSIBLE_SAME_ENTITY edge (does NOT delete nodes)
          SenseGraphManager().addRelation(
            a,
            SenseRelation.POSSIBLE_SAME_ENTITY,
            b,
            confidence: conf,
          );
        }
      }
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
      triggerReason: 'memory_association_proposal',
    );

    return MemoryAgentResult(
      proposals: proposals,
      rawResponse: vlmResult.text,
      latencyMs: latency,
    );
  }
}
