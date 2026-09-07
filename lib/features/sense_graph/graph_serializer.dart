import 'models/sense_node.dart';
import 'models/sense_edge.dart';
import 'sense_graph.dart';

class GraphSerializer {
  static Map<String, dynamic> toJson(SenseGraph graph) {
    return {
      'version': 1,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'nodes': graph.allNodes.map((n) => n.toJson()).toList(),
      'edges': graph.allEdges.map((e) => e.toJson()).toList(),
    };
  }

  static SenseGraph fromJson(Map<String, dynamic> json) {
    final graph = SenseGraph();

    final rawNodes = json['nodes'] as List<dynamic>? ?? [];
    for (final raw in rawNodes) {
      if (raw is Map<String, dynamic>) {
        final type = raw['type'] as String?;
        SenseNode? node;
        switch (type) {
          case 'ViewNode':
            node = ViewNode.fromJson(raw);
            break;
          case 'ObjectNode':
            node = ObjectNode.fromJson(raw);
            break;
          case 'TextNode':
            node = TextNode.fromJson(raw);
            break;
          case 'PlaceNode':
            node = PlaceNode.fromJson(raw);
            break;
          case 'EventNode':
            node = EventNode.fromJson(raw);
            break;
        }
        if (node != null) {
          graph.addNode(node);
        }
      }
    }

    final rawEdges = json['edges'] as List<dynamic>? ?? [];
    for (final raw in rawEdges) {
      if (raw is Map<String, dynamic>) {
        graph.addEdge(SenseEdge.fromJson(raw));
      }
    }

    return graph;
  }
}
