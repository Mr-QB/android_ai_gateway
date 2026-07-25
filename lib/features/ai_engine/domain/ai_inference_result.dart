class AIInferenceResultModel {
  final int width;
  final int height;
  final double inferenceTimeMs;
  final int detectedClassId;
  final double confidence;

  const AIInferenceResultModel({
    required this.width,
    required this.height,
    required this.inferenceTimeMs,
    required this.detectedClassId,
    required this.confidence,
  });

  factory AIInferenceResultModel.empty() {
    return const AIInferenceResultModel(
      width: 0,
      height: 0,
      inferenceTimeMs: 0.0,
      detectedClassId: -1,
      confidence: 0.0,
    );
  }
}
