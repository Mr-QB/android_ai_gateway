import 'models/sense_node.dart';
import 'models/sense_edge.dart';

class SenseGraph {
  final Map<String, SenseNode> _nodes = {};
  final List<SenseEdge> _edges = [];

  // Indices for rapid adjacency lookups
  final Map<String, List<SenseEdge>> _outgoing = {};
  final Map<String, List<SenseEdge>> _incoming = {};

  SenseGraph();

  int get nodeCount => _nodes.length;
  int get edgeCount => _edges.length;

  List<SenseNode> get allNodes => _nodes.values.toList();
  List<SenseEdge> get allEdges => List.unmodifiable(_edges);

  void addNode(SenseNode node) {
    _nodes[node.id] = node;
  }

  void addNodes(Iterable<SenseNode> nodes) {
    for (final n in nodes) {
      addNode(n);
    }
  }

  T? getNode<T extends SenseNode>(String id) {
    final n = _nodes[id];
    return n is T ? n : null;
  }

  bool hasNode(String id) => _nodes.containsKey(id);

  List<T> getNodesByType<T extends SenseNode>() {
    return _nodes.values.whereType<T>().toList();
  }

  void addEdge(SenseEdge edge) {
    // Avoid exact duplicate edges
    final exists = _edges.any((e) =>
        e.sourceId == edge.sourceId &&
        e.targetId == edge.targetId &&
        e.relation == edge.relation);
    if (!exists) {
      _edges.add(edge);
      _outgoing.putIfAbsent(edge.sourceId, () => []).add(edge);
      _incoming.putIfAbsent(edge.targetId, () => []).add(edge);
    }
  }

  void addEdges(Iterable<SenseEdge> edges) {
    for (final e in edges) {
      addEdge(e);
    }
  }

  List<SenseEdge> getOutgoingEdges(String sourceId) {
    return _outgoing[sourceId] ?? const [];
  }

  List<SenseEdge> getIncomingEdges(String targetId) {
    return _incoming[targetId] ?? const [];
  }

  List<SenseEdge> getEdgesForNode(String nodeId) {
    final outE = _outgoing[nodeId] ?? const [];
    final inE = _incoming[nodeId] ?? const [];
    return [...outE, ...inE];
  }

  List<ObjectNode> getObjectsForView(String viewId) {
    final view = getNode<ViewNode>(viewId);
    if (view == null) return [];
    return view.objectIds
        .map((id) => getNode<ObjectNode>(id))
        .whereType<ObjectNode>()
        .toList();
  }

  List<TextNode> getTextsForView(String viewId) {
    final view = getNode<ViewNode>(viewId);
    if (view == null) return [];
    return view.textIds
        .map((id) => getNode<TextNode>(id))
        .whereType<TextNode>()
        .toList();
  }

  ViewNode? getLatestView() {
    final views = getNodesByType<ViewNode>();
    if (views.isEmpty) return null;
    views.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return views.first;
  }

  void clear() {
    _nodes.clear();
    _edges.clear();
    _outgoing.clear();
    _incoming.clear();
  }
}
