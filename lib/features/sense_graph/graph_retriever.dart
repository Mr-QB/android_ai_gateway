import 'models/sense_node.dart';
import 'models/sense_edge.dart';
import 'sense_graph.dart';

class SubgraphContext {
  final ViewNode? currentView;
  final List<ObjectNode> currentObjects;
  final List<TextNode> currentTexts;
  final List<SenseEdge> currentRelations;
  final List<ViewNode> recentViews;
  final List<EventNode> recentEvents;

  const SubgraphContext({
    this.currentView,
    required this.currentObjects,
    required this.currentTexts,
    required this.currentRelations,
    required this.recentViews,
    required this.recentEvents,
  });

  /// Formats the subgraph into a compact markdown prompt context for Gemma ReasoningAgent
  String formatForPrompt() {
    final buffer = StringBuffer();

    if (currentView != null) {
      buffer.writeln('### CURRENT VIEW (${currentView!.id})');
      if (currentView!.sceneType != null && currentView!.sceneType!.isNotEmpty) {
        buffer.writeln('- Scene Type: ${currentView!.sceneType}');
      }
    }

    buffer.writeln('### CURRENT OBJECTS:');
    if (currentObjects.isEmpty) {
      buffer.writeln('- None detected');
    } else {
      for (final obj in currentObjects) {
        final box = obj.bbox.map((v) => (v * 100).toStringAsFixed(0)).join(', ');
        buffer.writeln('- [${obj.id}] ${obj.className} (conf: ${(obj.confidence * 100).toStringAsFixed(0)}%, bbox% [x,y,w,h]: [$box])');
      }
    }

    buffer.writeln('### CURRENT TEXT / OCR:');
    if (currentTexts.isEmpty) {
      buffer.writeln('- None detected');
    } else {
      for (final t in currentTexts) {
        final textToShow = t.normalizedText ?? t.rawText;
        final typeInfo = t.semanticType != null ? ' (${t.semanticType}, ${t.importance ?? "info"})' : '';
        buffer.writeln('- [${t.id}] "$textToShow"$typeInfo (conf: ${(t.confidence * 100).toStringAsFixed(0)}%)');
      }
    }

    if (currentRelations.isNotEmpty) {
      buffer.writeln('### SPATIAL RELATIONS:');
      for (final rel in currentRelations) {
        buffer.writeln('- ${rel.sourceId} ${rel.relation.name} ${rel.targetId}');
      }
    }

    if (recentEvents.isNotEmpty) {
      buffer.writeln('### RECENT EVENTS:');
      for (final ev in recentEvents.take(3)) {
        buffer.writeln('- ${ev.type}: ${ev.description} (sev: ${ev.severity})');
      }
    }

    if (recentViews.length > 1) {
      buffer.writeln('### RECENT HISTORY:');
      for (final v in recentViews.skip(1).take(2)) {
        buffer.writeln('- View ${v.id}: ${v.sceneType ?? "unknown scene"} with ${v.objectIds.length} objects, ${v.textIds.length} texts');
      }
    }

    return buffer.toString().trim();
  }
}

class GraphRetriever {
  final SenseGraph graph;

  const GraphRetriever(this.graph);

  /// Retrieves a focused subgraph around the latest or specified view
  SubgraphContext retrieveSubgraph({
    String? viewId,
    int maxRecentViews = 3,
    int maxRecentEvents = 5,
  }) {
    final currentView = viewId != null
        ? graph.getNode<ViewNode>(viewId)
        : graph.getLatestView();

    final List<ObjectNode> objects;
    final List<TextNode> texts;
    final List<SenseEdge> relations = [];

    if (currentView != null) {
      objects = graph.getObjectsForView(currentView.id);
      texts = graph.getTextsForView(currentView.id);

      // Collect relations involving current objects or texts
      final nodeIds = <String>{
        currentView.id,
        ...objects.map((o) => o.id),
        ...texts.map((t) => t.id),
      };

      for (final id in nodeIds) {
        final edges = graph.getEdgesForNode(id);
        for (final edge in edges) {
          if (!relations.contains(edge)) {
            relations.add(edge);
          }
        }
      }
    } else {
      objects = graph.getNodesByType<ObjectNode>();
      texts = graph.getNodesByType<TextNode>();
      relations.addAll(graph.allEdges);
    }

    final allViews = graph.getNodesByType<ViewNode>()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final recentViews = allViews.take(maxRecentViews).toList();

    final allEvents = graph.getNodesByType<EventNode>()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final recentEvents = allEvents.take(maxRecentEvents).toList();

    return SubgraphContext(
      currentView: currentView,
      currentObjects: objects,
      currentTexts: texts,
      currentRelations: relations,
      recentViews: recentViews,
      recentEvents: recentEvents,
    );
  }
}
