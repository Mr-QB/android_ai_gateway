import 'package:flutter/foundation.dart';
import '../ai_engine/domain/detection.dart';
import '../camera/data/coco_labels.dart';
import 'models/sense_node.dart';
import 'models/sense_edge.dart';
import 'sense_graph.dart';
import 'graph_retriever.dart';
import 'storage/sense_graph_storage.dart';
import 'localization/localization_provider.dart';

class SenseGraphManager {
  static final SenseGraphManager _instance = SenseGraphManager._internal();
  factory SenseGraphManager() => _instance;
  SenseGraphManager._internal();

  final SenseGraph _graph = SenseGraph();
  final ISenseGraphStorage _storage = JsonFileGraphStorage();
  final LocalizationProvider _localization = DefaultLocalizationProvider();

  int _viewCounter = 0;
  int _objectCounter = 0;
  int _textCounter = 0;
  int _eventCounter = 0;

  SenseGraph get graph => _graph;
  GraphRetriever get retriever => GraphRetriever(_graph);

  Future<void> init() async {
    final loaded = await _storage.loadGraph();
    _graph.clear();
    _graph.addNodes(loaded.allNodes);
    _graph.addEdges(loaded.allEdges);

    // Sync counters
    _viewCounter = _graph.getNodesByType<ViewNode>().length;
    _objectCounter = _graph.getNodesByType<ObjectNode>().length;
    _textCounter = _graph.getNodesByType<TextNode>().length;
    _eventCounter = _graph.getNodesByType<EventNode>().length;
  }

  /// Creates a new ViewNode for the current camera frame or test image
  Future<ViewNode> createView({String? sceneType}) async {
    _viewCounter++;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final viewId = 'view_$_viewCounter';

    final pose = await _localization.getCurrentPose();

    final prevView = _graph.getLatestView();

    final view = ViewNode(
      id: viewId,
      timestamp: timestamp,
      sceneType: sceneType,
      pose: pose?.toJson(),
    );

    _graph.addNode(view);

    // Link consecutive views with NEXT_VIEW edge
    if (prevView != null) {
      _graph.addEdge(SenseEdge(
        sourceId: prevView.id,
        targetId: view.id,
        relation: SenseRelation.NEXT_VIEW,
        timestamp: timestamp,
      ));
    }

    await _autoSave();
    return view;
  }

  /// Ingests YOLO detections into the current view
  void ingestDetections(String viewId, List<Detection> detections) {
    final view = _graph.getNode<ViewNode>(viewId);
    if (view == null) return;

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final newObjectIds = <String>[];

    for (final det in detections) {
      _objectCounter++;
      final objId = 'obj_$_objectCounter';
      final className = (det.classId >= 0 && det.classId < cocoLabels.length)
          ? cocoLabels[det.classId]
          : 'object_${det.classId}';

      final objNode = ObjectNode(
        id: objId,
        timestamp: timestamp,
        className: className,
        confidence: det.confidence,
        bbox: [det.x, det.y, det.width, det.height],
      );

      _graph.addNode(objNode);
      newObjectIds.add(objId);

      // Edge: obj SEEN_IN view
      _graph.addEdge(SenseEdge(
        sourceId: objId,
        targetId: viewId,
        relation: SenseRelation.SEEN_IN,
        confidence: det.confidence,
        timestamp: timestamp,
      ));
    }

    // Update view's objectIds
    view.objectIds.addAll(newObjectIds);
    _autoSave();
  }

  /// Ingests OCR recognized text blocks into the current view
  void ingestOcrTexts(
    String viewId,
    List<({String text, List<double> bbox, double confidence})> ocrResults,
  ) {
    final view = _graph.getNode<ViewNode>(viewId);
    if (view == null) return;

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final newTextIds = <String>[];

    for (final item in ocrResults) {
      if (item.text.trim().isEmpty) continue;
      _textCounter++;
      final textId = 'text_$_textCounter';

      final textNode = TextNode(
        id: textId,
        timestamp: timestamp,
        rawText: item.text.trim(),
        bbox: item.bbox,
        confidence: item.confidence,
      );

      _graph.addNode(textNode);
      newTextIds.add(textId);

      // Edge: text SEEN_IN view
      _graph.addEdge(SenseEdge(
        sourceId: textId,
        targetId: viewId,
        relation: SenseRelation.SEEN_IN,
        confidence: item.confidence,
        timestamp: timestamp,
      ));
    }

    view.textIds.addAll(newTextIds);
    _autoSave();
  }

  /// Updates ViewNode sceneType from SceneAgent output
  void updateSceneType(String viewId, String sceneType) {
    final view = _graph.getNode<ViewNode>(viewId);
    if (view != null) {
      final updated = view.copyWith(sceneType: sceneType);
      _graph.addNode(updated);
      _autoSave();
    }
  }

  /// Ingests extracted spatial relations from RelationAgent
  void addRelation(String sourceId, SenseRelation relation, String targetId, {double confidence = 1.0}) {
    if (_graph.hasNode(sourceId) && _graph.hasNode(targetId)) {
      _graph.addEdge(SenseEdge(
        sourceId: sourceId,
        targetId: targetId,
        relation: relation,
        confidence: confidence,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ));
      _autoSave();
    }
  }

  /// Records an event (e.g. hazard detection)
  void recordEvent({
    required String type,
    required String description,
    double severity = 0.0,
    List<String>? relatedNodeIds,
  }) {
    _eventCounter++;
    final eventId = 'event_$_eventCounter';
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    final event = EventNode(
      id: eventId,
      timestamp: timestamp,
      type: type,
      description: description,
      severity: severity,
      relatedNodeIds: relatedNodeIds,
    );

    _graph.addNode(event);
    _autoSave();
  }

  /// Enriches TextNode from Gemma TextAgent
  void enrichTextNode(
    String textId, {
    String? normalizedText,
    String? semanticType,
    String? importance,
  }) {
    final node = _graph.getNode<TextNode>(textId);
    if (node != null) {
      final updated = node.copyWith(
        normalizedText: normalizedText,
        semanticType: semanticType,
        importance: importance,
      );
      _graph.addNode(updated);
      _autoSave();
    }
  }

  /// Clears the graph in memory and on disk
  Future<void> clear() async {
    _graph.clear();
    _viewCounter = 0;
    _objectCounter = 0;
    _textCounter = 0;
    _eventCounter = 0;
    await _storage.clear();
  }

  Future<void> _autoSave() async {
    try {
      await _storage.saveGraph(_graph);
    } catch (e) {
      debugPrint('[SenseGraphManager] Auto-save error: $e');
    }
  }
}
