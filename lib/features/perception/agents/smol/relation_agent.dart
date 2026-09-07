import '../../../sense_graph/models/sense_edge.dart';
import '../../../sense_graph/models/sense_node.dart';
import '../../../sense_graph/sense_graph_manager.dart';
import '../../utils/json_extractor.dart';
import '../../utils/performance_logger.dart';
import '../base_agent.dart';

class ExtractedRelation {
  final String subject;
  final String relation;
  final String object;

  const ExtractedRelation({
    required this.subject,
    required this.relation,
    required this.object,
  });

  Map<String, dynamic> toJson() => {
        'subject': subject,
        'relation': relation,
        'object': object,
      };
}

class RelationAgentResult {
  final List<ExtractedRelation> relations;
  final String rawResponse;
  final double latencyMs;

  const RelationAgentResult({
    required this.relations,
    required this.rawResponse,
    required this.latencyMs,
  });
}

class RelationAgent extends BasePerceptionAgent {
  RelationAgent({required super.engineManager}) : super(name: 'RelationAgent');

  Future<RelationAgentResult> execute({
    required String imagePath,
    String? viewId,
    List<ObjectNode>? objects,
    List<TextNode>? texts,
  }) async {
    final startTime = DateTime.now().millisecondsSinceEpoch;

    final entityList = StringBuffer();
    if (objects != null && objects.isNotEmpty) {
      entityList.writeln('Objects: ${objects.map((o) => "${o.id} (${o.className})").join(", ")}');
    }
    if (texts != null && texts.isNotEmpty) {
      entityList.writeln('Texts: ${texts.map((t) => "${t.id} (\"${t.rawText}\")").join(", ")}');
    }

    final prompt = '''
Identify spatial and semantic relationships between visible entities:
$entityList
Allowed relations: LEFT_OF, RIGHT_OF, IN_FRONT_OF, BEHIND, ABOVE, BELOW, NEAR, BLOCKS.
Respond strictly in JSON:
{
  "relations": [
    {
      "subject": "entity_id",
      "relation": "ABOVE",
      "object": "target_entity_id"
    }
  ]
}
''';

    final vlmResult = await engineManager.runSmolInference(
      imagePath: imagePath,
      prompt: prompt,
      maxTokens: 128,
    );
    final latency = (DateTime.now().millisecondsSinceEpoch - startTime).toDouble();

    final jsonMap = JsonExtractor.extractJsonMap(vlmResult.text);
    final rawList = jsonMap['relations'] as List<dynamic>? ?? [];

    final extracted = <ExtractedRelation>[];
    for (final item in rawList) {
      if (item is Map<String, dynamic>) {
        final sub = item['subject']?.toString() ?? '';
        final relStr = item['relation']?.toString() ?? 'NEAR';
        final obj = item['object']?.toString() ?? '';

        if (sub.isNotEmpty && obj.isNotEmpty) {
          extracted.add(ExtractedRelation(subject: sub, relation: relStr, object: obj));

          // Ingest into SenseGraph
          SenseGraphManager().addRelation(
            sub,
            SenseRelation.fromString(relStr),
            obj,
            confidence: 0.85,
          );
        }
      }
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
      triggerReason: 'relation_extraction',
    );

    return RelationAgentResult(
      relations: extracted,
      rawResponse: vlmResult.text,
      latencyMs: latency,
    );
  }
}
