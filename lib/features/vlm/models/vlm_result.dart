class VlmModelInfo {
  final String key;
  final String displayName;
  final String filename;
  final String defaultBackend;
  final int recommendedInputResolution;

  const VlmModelInfo({
    required this.key,
    required this.displayName,
    required this.filename,
    this.defaultBackend = 'AUTO',
    this.recommendedInputResolution = 512,
  });

  static const VlmModelInfo smolVlm2 = VlmModelInfo(
    key: 'smolvlm2_500m',
    displayName: 'SmolVLM2-500M',
    filename: 'SmolVLM2-500M.litertlm',
    defaultBackend: 'AUTO',
    recommendedInputResolution: 512,
  );

  static const VlmModelInfo gemma4 = VlmModelInfo(
    key: 'gemma_4_e2b',
    displayName: 'Gemma-4-E2B-it',
    filename: 'gemma-4-E2B-it-gpu.litertlm',
    defaultBackend: 'AUTO',
    recommendedInputResolution: 512,
  );

  static const List<VlmModelInfo> supportedModels = [
    smolVlm2,
    gemma4,
  ];

  static VlmModelInfo fromKey(String key) {
    return supportedModels.firstWhere(
      (m) => m.key == key,
      orElse: () => smolVlm2,
    );
  }
}

class VlmStatus {
  final bool isLoaded;
  final String loadedModelKey;
  final String modelPath;
  final bool modelExists;
  final String requestedBackend;
  final String actualBackend;
  final String expectedPath;
  final int loadTimeMs;
  final bool isInferring;
  final Map<String, bool> modelsAvailable;

  const VlmStatus({
    required this.isLoaded,
    required this.loadedModelKey,
    required this.modelPath,
    required this.modelExists,
    required this.requestedBackend,
    required this.actualBackend,
    required this.expectedPath,
    required this.loadTimeMs,
    required this.isInferring,
    required this.modelsAvailable,
  });

  factory VlmStatus.fromMap(Map<dynamic, dynamic> map) {
    final rawAvailable = map['modelsAvailable'] as Map<dynamic, dynamic>? ?? {};
    final modelsAvailable = <String, bool>{};
    rawAvailable.forEach((k, v) {
      modelsAvailable[k.toString()] = v == true;
    });

    return VlmStatus(
      isLoaded: map['isLoaded'] == true,
      loadedModelKey: map['loadedModelKey']?.toString() ?? 'smolvlm2_500m',
      modelPath: map['modelPath']?.toString() ?? '',
      modelExists: map['modelExists'] == true,
      requestedBackend: map['requestedBackend']?.toString() ?? 'AUTO',
      actualBackend: map['actualBackend']?.toString() ?? 'NONE',
      expectedPath: map['expectedPath']?.toString() ?? '',
      loadTimeMs: (map['loadTimeMs'] as num?)?.toInt() ?? 0,
      isInferring: map['isInferring'] == true,
      modelsAvailable: modelsAvailable,
    );
  }

  factory VlmStatus.empty() {
    return const VlmStatus(
      isLoaded: false,
      loadedModelKey: 'smolvlm2_500m',
      modelPath: '',
      modelExists: false,
      requestedBackend: 'AUTO',
      actualBackend: 'NONE',
      expectedPath: '',
      loadTimeMs: 0,
      isInferring: false,
      modelsAvailable: {},
    );
  }
}

class VlmResult {
  final bool success;
  final String text;
  final double modelLoadMs;
  final double preprocessMs;
  final double? timeToFirstTokenMs;
  final double generationMs;
  final double totalInferenceMs;
  final int generatedTokens;
  final double tokensPerSecond;
  final String backend;
  final String requestedBackend;
  final String modelKey;
  final bool isWarm;
  final double nativeHeapMb;
  final double javaHeapMb;
  final String? error;
  final String? message;

  const VlmResult({
    required this.success,
    required this.text,
    required this.modelLoadMs,
    required this.preprocessMs,
    this.timeToFirstTokenMs,
    required this.generationMs,
    required this.totalInferenceMs,
    required this.generatedTokens,
    required this.tokensPerSecond,
    required this.backend,
    required this.requestedBackend,
    required this.modelKey,
    required this.isWarm,
    required this.nativeHeapMb,
    required this.javaHeapMb,
    this.error,
    this.message,
  });

  factory VlmResult.fromMap(Map<dynamic, dynamic> map) {
    final genTokens = (map['generatedTokens'] as num?)?.toInt() ?? 0;
    final genMs = (map['generationMs'] as num?)?.toDouble() ?? 0.0;
    
    // Compute tokens per second if not provided
    double tps = (map['tokensPerSecond'] as num?)?.toDouble() ?? 0.0;
    if (tps <= 0.0 && genMs > 0 && genTokens > 0) {
      tps = (genTokens / (genMs / 1000.0));
    }

    return VlmResult(
      success: map['success'] == true,
      text: map['text']?.toString() ?? '',
      modelLoadMs: (map['modelLoadMs'] as num?)?.toDouble() ?? 0.0,
      preprocessMs: (map['preprocessMs'] as num?)?.toDouble() ?? 0.0,
      timeToFirstTokenMs: (map['timeToFirstTokenMs'] as num?)?.toDouble(),
      generationMs: genMs,
      totalInferenceMs: (map['totalInferenceMs'] as num?)?.toDouble() ?? 0.0,
      generatedTokens: genTokens,
      tokensPerSecond: tps,
      backend: map['backend']?.toString() ?? 'UNKNOWN',
      requestedBackend: map['requestedBackend']?.toString() ?? 'AUTO',
      modelKey: map['modelKey']?.toString() ?? 'smolvlm2_500m',
      isWarm: map['isWarm'] == true || (map['modelLoadMs'] as num?)?.toDouble() == 0.0,
      nativeHeapMb: (map['nativeHeapMb'] as num?)?.toDouble() ?? 0.0,
      javaHeapMb: (map['javaHeapMb'] as num?)?.toDouble() ?? 0.0,
      error: map['error']?.toString(),
      message: map['message']?.toString(),
    );
  }

  factory VlmResult.failure({
    required String error,
    required String message,
    String modelKey = 'smolvlm2_500m',
  }) {
    return VlmResult(
      success: false,
      text: '',
      modelLoadMs: 0,
      preprocessMs: 0,
      timeToFirstTokenMs: null,
      generationMs: 0,
      totalInferenceMs: 0,
      generatedTokens: 0,
      tokensPerSecond: 0,
      backend: 'NONE',
      requestedBackend: 'AUTO',
      modelKey: modelKey,
      isWarm: false,
      nativeHeapMb: 0,
      javaHeapMb: 0,
      error: error,
      message: message,
    );
  }
}

class VlmBenchmarkRun {
  final int runIndex;
  final bool isWarm;
  final double? ttftMs;
  final double generationMs;
  final double totalMs;
  final int tokenCount;
  final double tokensPerSecond;
  final double nativeHeapMb;
  final double javaHeapMb;
  final String text;

  const VlmBenchmarkRun({
    required this.runIndex,
    required this.isWarm,
    this.ttftMs,
    required this.generationMs,
    required this.totalMs,
    required this.tokenCount,
    required this.tokensPerSecond,
    required this.nativeHeapMb,
    required this.javaHeapMb,
    required this.text,
  });

  factory VlmBenchmarkRun.fromMap(Map<dynamic, dynamic> map, int index) {
    return VlmBenchmarkRun(
      runIndex: (map['runIndex'] as num?)?.toInt() ?? index,
      isWarm: map['isWarm'] == true,
      ttftMs: (map['timeToFirstTokenMs'] as num?)?.toDouble(),
      generationMs: (map['generationMs'] as num?)?.toDouble() ?? 0.0,
      totalMs: (map['totalInferenceMs'] as num?)?.toDouble() ?? 0.0,
      tokenCount: (map['generatedTokens'] as num?)?.toInt() ?? 0,
      tokensPerSecond: (map['tokensPerSecond'] as num?)?.toDouble() ?? 0.0,
      nativeHeapMb: (map['nativeHeapMb'] as num?)?.toDouble() ?? 0.0,
      javaHeapMb: (map['javaHeapMb'] as num?)?.toDouble() ?? 0.0,
      text: map['text']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'runIndex': runIndex,
    'isWarm': isWarm,
    'ttftMs': ttftMs,
    'generationMs': generationMs,
    'totalMs': totalMs,
    'tokenCount': tokenCount,
    'tokensPerSecond': tokensPerSecond,
    'nativeHeapMb': nativeHeapMb,
    'javaHeapMb': javaHeapMb,
  };
}

class VlmBenchmarkReport {
  final String modelKey;
  final String modelDisplayName;
  final String backend;
  final double coldLoadMs;
  final List<VlmBenchmarkRun> runs;
  final double avgWarmTtftMs;
  final double avgWarmGenerationMs;
  final double avgWarmTotalMs;
  final double avgWarmTokensPerSecond;

  const VlmBenchmarkReport({
    required this.modelKey,
    required this.modelDisplayName,
    required this.backend,
    required this.coldLoadMs,
    required this.runs,
    required this.avgWarmTtftMs,
    required this.avgWarmGenerationMs,
    required this.avgWarmTotalMs,
    required this.avgWarmTokensPerSecond,
  });

  factory VlmBenchmarkReport.fromMap(Map<dynamic, dynamic> map) {
    final rawRuns = map['runs'] as List<dynamic>? ?? [];
    final runs = <VlmBenchmarkRun>[];
    for (int i = 0; i < rawRuns.length; i++) {
      if (rawRuns[i] is Map) {
        runs.add(VlmBenchmarkRun.fromMap(rawRuns[i] as Map, i + 1));
      }
    }

    final warmRuns = runs.where((r) => r.isWarm).toList();
    final effectiveWarm = warmRuns.isNotEmpty ? warmRuns : runs;

    double sumTtft = 0;
    int countTtft = 0;
    double sumGen = 0;
    double sumTotal = 0;
    double sumTps = 0;

    for (final r in effectiveWarm) {
      if (r.ttftMs != null) {
        sumTtft += r.ttftMs!;
        countTtft++;
      }
      sumGen += r.generationMs;
      sumTotal += r.totalMs;
      sumTps += r.tokensPerSecond;
    }

    final count = effectiveWarm.isNotEmpty ? effectiveWarm.length : 1;

    return VlmBenchmarkReport(
      modelKey: map['modelKey']?.toString() ?? 'smolvlm2_500m',
      modelDisplayName: map['modelDisplayName']?.toString() ?? 'SmolVLM2-500M',
      backend: map['backend']?.toString() ?? 'UNKNOWN',
      coldLoadMs: (map['coldLoadMs'] as num?)?.toDouble() ?? 0.0,
      runs: runs,
      avgWarmTtftMs: countTtft > 0 ? (sumTtft / countTtft) : 0.0,
      avgWarmGenerationMs: sumGen / count,
      avgWarmTotalMs: sumTotal / count,
      avgWarmTokensPerSecond: sumTps / count,
    );
  }

  Map<String, dynamic> toJson() => {
    'modelKey': modelKey,
    'modelDisplayName': modelDisplayName,
    'backend': backend,
    'coldLoadMs': coldLoadMs,
    'avgWarmTtftMs': avgWarmTtftMs,
    'avgWarmGenerationMs': avgWarmGenerationMs,
    'avgWarmTotalMs': avgWarmTotalMs,
    'avgWarmTokensPerSecond': avgWarmTokensPerSecond,
    'runs': runs.map((r) => r.toJson()).toList(),
  };
}
