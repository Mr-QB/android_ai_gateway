import 'slam_enums.dart';

class SlamStatus {
  final int apiVersion;
  final SlamRunState runState;
  final SlamTrackingState trackingState;
  final SlamSensorMode sensorMode;
  final int currentFrame;
  final int totalFrames;
  final int keyframeCount;
  final int mapPointCount;
  final double datasetTimestampSeconds;
  final double lastTrackMs;
  final double averageTrackMs;
  final double replayElapsedSeconds;
  final bool finished;
  final SlamReplayMode replayMode;
  final int errorCode;

  const SlamStatus({
    this.apiVersion = 1,
    this.runState = SlamRunState.uninitialized,
    this.trackingState = SlamTrackingState.systemNotReady,
    this.sensorMode = SlamSensorMode.monocular,
    this.replayMode = SlamReplayMode.realtime,
    this.currentFrame = 0,
    this.totalFrames = 0,
    this.keyframeCount = 0,
    this.mapPointCount = 0,
    double? datasetTimestampSeconds,
    double? datasetTimestampS,
    this.lastTrackMs = 0.0,
    this.averageTrackMs = 0.0,
    this.replayElapsedSeconds = 0.0,
    this.finished = false,
    this.errorCode = 0,
  }) : datasetTimestampSeconds = datasetTimestampSeconds ?? datasetTimestampS ?? 0.0;

  factory SlamStatus.uninitialized() => const SlamStatus();

  bool get hasError => errorCode != 0 || runState == SlamRunState.error;

  double get effectiveFps => trackingFpsEstimate;

  double get progress =>
      totalFrames > 0 ? (currentFrame / totalFrames).clamp(0.0, 1.0) : 0.0;

  double get trackingFpsEstimate =>
      lastTrackMs > 0.0 ? 1000.0 / lastTrackMs : 0.0;

  double get averageTrackingFpsEstimate =>
      averageTrackMs > 0.0 ? 1000.0 / averageTrackMs : 0.0;
}

