abstract class SenseNode {
  final String id;
  final int timestamp;

  const SenseNode({
    required this.id,
    required this.timestamp,
  });

  Map<String, dynamic> toJson();
}

class ViewNode extends SenseNode {
  final String? sceneType;
  final List<String> objectIds;
  final List<String> textIds;
  final String? placeId;
  final Map<String, dynamic>? pose;
  final String? visualDescriptor;
  final String? keypointsReference;

  ViewNode({
    required super.id,
    required super.timestamp,
    this.sceneType,
    List<String>? objectIds,
    List<String>? textIds,
    this.placeId,
    this.pose,
    this.visualDescriptor,
    this.keypointsReference,
  })  : objectIds = objectIds ?? [],
        textIds = textIds ?? [];

  ViewNode copyWith({
    String? sceneType,
    List<String>? objectIds,
    List<String>? textIds,
    String? placeId,
    Map<String, dynamic>? pose,
    String? visualDescriptor,
    String? keypointsReference,
  }) {
    return ViewNode(
      id: id,
      timestamp: timestamp,
      sceneType: sceneType ?? this.sceneType,
      objectIds: objectIds ?? this.objectIds,
      textIds: textIds ?? this.textIds,
      placeId: placeId ?? this.placeId,
      pose: pose ?? this.pose,
      visualDescriptor: visualDescriptor ?? this.visualDescriptor,
      keypointsReference: keypointsReference ?? this.keypointsReference,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'type': 'ViewNode',
        'timestamp': timestamp,
        'sceneType': sceneType,
        'objectIds': objectIds,
        'textIds': textIds,
        'placeId': placeId,
        'pose': pose,
        'visualDescriptor': visualDescriptor,
        'keypointsReference': keypointsReference,
      };

  factory ViewNode.fromJson(Map<String, dynamic> json) => ViewNode(
        id: json['id'] as String,
        timestamp: json['timestamp'] as int,
        sceneType: json['sceneType'] as String?,
        objectIds: (json['objectIds'] as List<dynamic>?)?.cast<String>(),
        textIds: (json['textIds'] as List<dynamic>?)?.cast<String>(),
        placeId: json['placeId'] as String?,
        pose: json['pose'] as Map<String, dynamic>?,
        visualDescriptor: json['visualDescriptor'] as String?,
        keypointsReference: json['keypointsReference'] as String?,
      );
}

class ObjectNode extends SenseNode {
  final String className;
  final int? trackId;
  final List<double> bbox; // [x, y, w, h] normalized 0.0 - 1.0
  final double confidence;
  final Map<String, dynamic> attributes;

  const ObjectNode({
    required super.id,
    required super.timestamp,
    required this.className,
    this.trackId,
    required this.bbox,
    required this.confidence,
    this.attributes = const {},
  });

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'type': 'ObjectNode',
        'timestamp': timestamp,
        'className': className,
        'trackId': trackId,
        'bbox': bbox,
        'confidence': confidence,
        'attributes': attributes,
      };

  factory ObjectNode.fromJson(Map<String, dynamic> json) => ObjectNode(
        id: json['id'] as String,
        timestamp: json['timestamp'] as int,
        className: json['className'] as String? ?? json['class'] as String? ?? 'unknown',
        trackId: json['trackId'] as int?,
        bbox: (json['bbox'] as List<dynamic>).map((e) => (e as num).toDouble()).toList(),
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
        attributes: (json['attributes'] as Map<String, dynamic>?) ?? {},
      );
}

class TextNode extends SenseNode {
  final String rawText;
  final String? normalizedText;
  final List<double> bbox; // [x, y, w, h] normalized
  final double confidence;
  final String? semanticType; // e.g. warning_sign, exit, instruction, label
  final String? importance;   // critical, warning, info

  const TextNode({
    required super.id,
    required super.timestamp,
    required this.rawText,
    this.normalizedText,
    required this.bbox,
    required this.confidence,
    this.semanticType,
    this.importance,
  });

  TextNode copyWith({
    String? normalizedText,
    String? semanticType,
    String? importance,
  }) {
    return TextNode(
      id: id,
      timestamp: timestamp,
      rawText: rawText,
      normalizedText: normalizedText ?? this.normalizedText,
      bbox: bbox,
      confidence: confidence,
      semanticType: semanticType ?? this.semanticType,
      importance: importance ?? this.importance,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'type': 'TextNode',
        'timestamp': timestamp,
        'rawText': rawText,
        'normalizedText': normalizedText,
        'bbox': bbox,
        'confidence': confidence,
        'semanticType': semanticType,
        'importance': importance,
      };

  factory TextNode.fromJson(Map<String, dynamic> json) => TextNode(
        id: json['id'] as String,
        timestamp: json['timestamp'] as int,
        rawText: json['rawText'] as String? ?? '',
        normalizedText: json['normalizedText'] as String?,
        bbox: (json['bbox'] as List<dynamic>).map((e) => (e as num).toDouble()).toList(),
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
        semanticType: json['semanticType'] as String?,
        importance: json['importance'] as String?,
      );
}

class PlaceNode extends SenseNode {
  final String name;
  final String? semanticLabel;
  final List<String> viewIds;
  final int firstSeen;
  final int lastSeen;

  PlaceNode({
    required super.id,
    required super.timestamp,
    required this.name,
    this.semanticLabel,
    List<String>? viewIds,
    required this.firstSeen,
    required this.lastSeen,
  }) : viewIds = viewIds ?? [];

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'type': 'PlaceNode',
        'timestamp': timestamp,
        'name': name,
        'semanticLabel': semanticLabel,
        'viewIds': viewIds,
        'firstSeen': firstSeen,
        'lastSeen': lastSeen,
      };

  factory PlaceNode.fromJson(Map<String, dynamic> json) => PlaceNode(
        id: json['id'] as String,
        timestamp: json['timestamp'] as int,
        name: json['name'] as String? ?? 'Unnamed Place',
        semanticLabel: json['semanticLabel'] as String?,
        viewIds: (json['viewIds'] as List<dynamic>?)?.cast<String>(),
        firstSeen: json['firstSeen'] as int? ?? json['timestamp'] as int,
        lastSeen: json['lastSeen'] as int? ?? json['timestamp'] as int,
      );
}

class EventNode extends SenseNode {
  final String type; // e.g. hazard_detected, text_detected, user_interaction
  final String description;
  final double severity; // 0.0 to 1.0
  final List<String> relatedNodeIds;

  EventNode({
    required super.id,
    required super.timestamp,
    required this.type,
    required this.description,
    this.severity = 0.0,
    List<String>? relatedNodeIds,
  }) : relatedNodeIds = relatedNodeIds ?? [];

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'type': 'EventNode',
        'timestamp': timestamp,
        'eventType': type,
        'description': description,
        'severity': severity,
        'relatedNodeIds': relatedNodeIds,
      };

  factory EventNode.fromJson(Map<String, dynamic> json) => EventNode(
        id: json['id'] as String,
        timestamp: json['timestamp'] as int,
        type: json['eventType'] as String? ?? json['type'] as String? ?? 'event',
        description: json['description'] as String? ?? '',
        severity: (json['severity'] as num?)?.toDouble() ?? 0.0,
        relatedNodeIds: (json['relatedNodeIds'] as List<dynamic>?)?.cast<String>(),
      );
}
