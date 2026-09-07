class EscalationManager {
  static const double escalationThreshold = 0.55;

  /// Computes a composite uncertainty score [0.0 - 1.0] from multiple perception sources
  static double computeUncertainty({
    required double yoloAvgConfidence,
    required double? ocrConfidence,
    required double smolConfidence,
    required bool smolRequestedEscalation,
    double sceneNovelty = 0.0,
    double graphConsistency = 0.8,
  }) {
    // Inverse confidences represent uncertainty
    final yoloUncertainty = (1.0 - yoloAvgConfidence).clamp(0.0, 1.0);
    final smolUncertainty = (1.0 - smolConfidence).clamp(0.0, 1.0);
    final ocrUncertainty = ocrConfidence != null ? (1.0 - ocrConfidence).clamp(0.0, 1.0) : 0.2;
    final graphInconsistency = (1.0 - graphConsistency).clamp(0.0, 1.0);

    // Weighted uncertainty formula
    double score = (0.30 * smolUncertainty) +
        (0.25 * yoloUncertainty) +
        (0.20 * ocrUncertainty) +
        (0.15 * sceneNovelty) +
        (0.10 * graphInconsistency);

    // If Smol explicitly requested escalation, add boost
    if (smolRequestedEscalation) {
      score += 0.25;
    }

    return score.clamp(0.0, 1.0);
  }

  /// Evaluates whether current context should escalate from Smol to Gemma
  static bool shouldEscalateToGemma({
    required double yoloAvgConfidence,
    required double? ocrConfidence,
    required double smolConfidence,
    required bool smolRequestedEscalation,
    double sceneNovelty = 0.0,
    double graphConsistency = 0.8,
  }) {
    final uncertainty = computeUncertainty(
      yoloAvgConfidence: yoloAvgConfidence,
      ocrConfidence: ocrConfidence,
      smolConfidence: smolConfidence,
      smolRequestedEscalation: smolRequestedEscalation,
      sceneNovelty: sceneNovelty,
      graphConsistency: graphConsistency,
    );

    return uncertainty >= escalationThreshold;
  }
}
