// ignore_for_file: constant_identifier_names

enum SenseRelation {
  LEFT_OF,
  RIGHT_OF,
  IN_FRONT_OF,
  BEHIND,
  ABOVE,
  BELOW,
  NEAR,
  BLOCKS,
  PART_OF,
  SEEN_IN,
  NEXT_VIEW,
  POSSIBLE_SAME_ENTITY,
  POSSIBLE_LOOP,
  LOOP_CONFIRMED;

  static SenseRelation fromString(String name) {
    return SenseRelation.values.firstWhere(
      (r) => r.name.toUpperCase() == name.trim().toUpperCase(),
      orElse: () => SenseRelation.NEAR,
    );
  }
}

class SenseEdge {
  final String sourceId;
  final String targetId;
  final SenseRelation relation;
  final double confidence;
  final int timestamp;
  final Map<String, dynamic> metadata;

  const SenseEdge({
    required this.sourceId,
    required this.targetId,
    required this.relation,
    this.confidence = 1.0,
    required this.timestamp,
    this.metadata = const {},
  });

  Map<String, dynamic> toJson() => {
        'sourceId': sourceId,
        'targetId': targetId,
        'relation': relation.name,
        'confidence': confidence,
        'timestamp': timestamp,
        'metadata': metadata,
      };

  factory SenseEdge.fromJson(Map<String, dynamic> json) => SenseEdge(
        sourceId: json['sourceId'] as String,
        targetId: json['targetId'] as String,
        relation: SenseRelation.fromString(json['relation'] as String? ?? 'NEAR'),
        confidence: (json['confidence'] as num?)?.toDouble() ?? 1.0,
        timestamp: json['timestamp'] as int? ?? 0,
        metadata: (json['metadata'] as Map<String, dynamic>?) ?? {},
      );

  @override
  String toString() => '$sourceId ${relation.name} $targetId';
}
