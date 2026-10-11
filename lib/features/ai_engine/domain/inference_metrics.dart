class InferenceMetrics {
  final double preprocessMs;
  final double inferenceMs;
  final double postprocessMs;
  final double totalNativeMs;

  final double cameraFps;
  final double processedFps;
  final int receivedFrames;
  final int processedFrames;
  final int droppedFrames;
  final String backendName;
  final int threadCount;

  const InferenceMetrics({
    this.preprocessMs = 0.0,
    this.inferenceMs = 0.0,
    this.postprocessMs = 0.0,
    this.totalNativeMs = 0.0,
    this.cameraFps = 0.0,
    this.processedFps = 0.0,
    this.receivedFrames = 0,
    this.processedFrames = 0,
    this.droppedFrames = 0,
    this.backendName = 'Unknown',
    this.threadCount = 0,
  });

  double get dropRatePercent {
    if (receivedFrames <= 0) return 0.0;
    return (droppedFrames / receivedFrames) * 100.0;
  }

  InferenceMetrics copyWith({
    double? preprocessMs,
    double? inferenceMs,
    double? postprocessMs,
    double? totalNativeMs,
    double? cameraFps,
    double? processedFps,
    int? receivedFrames,
    int? processedFrames,
    int? droppedFrames,
    String? backendName,
    int? threadCount,
  }) {
    return InferenceMetrics(
      preprocessMs: preprocessMs ?? this.preprocessMs,
      inferenceMs: inferenceMs ?? this.inferenceMs,
      postprocessMs: postprocessMs ?? this.postprocessMs,
      totalNativeMs: totalNativeMs ?? this.totalNativeMs,
      cameraFps: cameraFps ?? this.cameraFps,
      processedFps: processedFps ?? this.processedFps,
      receivedFrames: receivedFrames ?? this.receivedFrames,
      processedFrames: processedFrames ?? this.processedFrames,
      droppedFrames: droppedFrames ?? this.droppedFrames,
      backendName: backendName ?? this.backendName,
      threadCount: threadCount ?? this.threadCount,
    );
  }
}
