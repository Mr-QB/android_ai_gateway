class PoseEstimate {
  final List<double> position; // [x, y, z]
  final List<double> orientation; // [qx, qy, qz, qw]
  final double confidence;
  final int timestamp;

  const PoseEstimate({
    required this.position,
    required this.orientation,
    required this.confidence,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'position': position,
        'orientation': orientation,
        'confidence': confidence,
        'timestamp': timestamp,
      };

  factory PoseEstimate.fromJson(Map<String, dynamic> json) => PoseEstimate(
        position: (json['position'] as List<dynamic>).map((e) => (e as num).toDouble()).toList(),
        orientation: (json['orientation'] as List<dynamic>).map((e) => (e as num).toDouble()).toList(),
        confidence: (json['confidence'] as num?)?.toDouble() ?? 1.0,
        timestamp: json['timestamp'] as int,
      );
}

abstract class LocalizationProvider {
  /// Returns the current camera 6-DoF pose estimate if available from VO/SLAM.
  /// Returns null if visual odometry is not yet integrated or tracking is lost.
  Future<PoseEstimate?> getCurrentPose();
}

class DefaultLocalizationProvider implements LocalizationProvider {
  @override
  Future<PoseEstimate?> getCurrentPose() async {
    // Return null since full VO/SLAM is not yet integrated. No fake pose.
    return null;
  }
}
