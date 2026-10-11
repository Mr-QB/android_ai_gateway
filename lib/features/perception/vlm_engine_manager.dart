import 'package:flutter/foundation.dart';
import '../vlm/models/vlm_result.dart';
import '../vlm/models/vlm_stream_event.dart';
import '../vlm/services/vlm_service.dart';
import 'gpu_inference_scheduler.dart';

enum EngineStatus { unloaded, loading, ready, error }

class VlmEngineManager {
  static final VlmEngineManager _instance = VlmEngineManager._internal();
  factory VlmEngineManager() => _instance;
  VlmEngineManager._internal();

  final VlmService _vlmService = VlmService();
  final GpuInferenceScheduler _gpuScheduler = GpuInferenceScheduler();

  EngineStatus smolStatus = EngineStatus.unloaded;
  EngineStatus gemmaStatus = EngineStatus.unloaded;

  String? currentlyLoadedModelKey;
  String activeBackend = 'NONE';
  String requestedBackend = 'AUTO';

  Future<bool> isModelAvailable(String modelKey) async =>
      (await _vlmService.getStatus(modelKey: modelKey)).modelExists;

  /// Preloads or checks SmolVLM2 (warm engine)
  Future<bool> ensureSmolReady({
    String backend = 'AUTO',
    String modelKey = 'smolvlm2_500m',
  }) async {
    if (smolStatus == EngineStatus.ready &&
        currentlyLoadedModelKey == modelKey) {
      return true;
    }

    smolStatus = EngineStatus.loading;
    requestedBackend = backend;

    final initRes = await _vlmService.initialize(
      modelKey: modelKey,
      backend: backend,
    );

    if (initRes['success'] == true) {
      smolStatus = EngineStatus.ready;
      currentlyLoadedModelKey = modelKey;
      activeBackend = initRes['backend']?.toString() ?? backend;
      // Gemma engine is swapped out to protect memory
      gemmaStatus = EngineStatus.unloaded;
      return true;
    } else {
      smolStatus = EngineStatus.error;
      return false;
    }
  }

  /// Lazy-loads Gemma 4 on demand
  Future<bool> ensureGemmaReady({String backend = 'AUTO'}) async {
    if (gemmaStatus == EngineStatus.ready &&
        currentlyLoadedModelKey == VlmModelInfo.gemma4.key) {
      return true;
    }

    gemmaStatus = EngineStatus.loading;
    requestedBackend = backend;

    // To prevent OOM on 8GB RAM device, unload Smol before loading 2GB Gemma
    smolStatus = EngineStatus.unloaded;

    final initRes = await _vlmService.initialize(
      modelKey: VlmModelInfo.gemma4.key,
      backend: backend,
    );

    if (initRes['success'] == true) {
      gemmaStatus = EngineStatus.ready;
      currentlyLoadedModelKey = VlmModelInfo.gemma4.key;
      activeBackend = initRes['backend']?.toString() ?? backend;
      return true;
    } else {
      gemmaStatus = EngineStatus.error;
      return false;
    }
  }

  /// Executes inference on SmolVLM with GPU scheduler protection
  Future<VlmResult> runSmolInference({
    required String imagePath,
    required String prompt,
    int maxTokens = 64,
    int targetResolution = 512,
    String? structuredOutputFormat,
    String modelKey = 'smolvlm2_500m',
  }) async {
    if (!await ensureSmolReady(backend: requestedBackend, modelKey: modelKey)) {
      throw StateError('Could not load VLM model: $modelKey');
    }

    return _gpuScheduler.runWithGpuLock(
      priority: GpuPriority.smolOccasional,
      action: () async {
        return await _vlmService.analyzeImage(
          imagePath: imagePath,
          prompt: prompt,
          maxTokens: maxTokens,
          targetResolution: targetResolution,
          structuredOutputFormat: structuredOutputFormat,
        );
      },
    );
  }

  Stream<VlmStreamEvent> streamSmolInference({
    required String imagePath,
    required String prompt,
    int maxTokens = 64,
    int targetResolution = 512,
    String? structuredOutputFormat,
    String modelKey = 'smolvlm2_500m',
  }) async* {
    if (!await ensureSmolReady(backend: requestedBackend, modelKey: modelKey)) {
      throw StateError('Could not load VLM model: $modelKey');
    }

    yield* _gpuScheduler.runStreamWithGpuLock(
      priority: GpuPriority.smolOccasional,
      action: () => _vlmService.generateStream(
        VlmRequest(
          imagePath: imagePath,
          prompt: prompt,
          maxTokens: maxTokens,
          targetResolution: targetResolution,
          structuredOutputFormat: structuredOutputFormat,
        ),
      ),
    );
  }

  /// Executes inference on Gemma 4 with GPU scheduler protection & YOLO throttling
  Future<VlmResult> runGemmaInference({
    required String imagePath,
    required String prompt,
    int maxTokens = 64,
    int targetResolution = 512,
  }) async {
    await ensureGemmaReady(backend: requestedBackend);

    return _gpuScheduler.runWithGpuLock(
      priority: GpuPriority.gemmaDeep,
      action: () async {
        return await _vlmService.analyzeImage(
          imagePath: imagePath,
          prompt: prompt,
          maxTokens: maxTokens,
          targetResolution: targetResolution,
        );
      },
    );
  }

  /// Memory pressure handler: release whichever VLM is resident.
  Future<void> handleMemoryPressure() async {
    if (currentlyLoadedModelKey == null &&
        smolStatus != EngineStatus.ready &&
        gemmaStatus != EngineStatus.ready) {
      return;
    }

    debugPrint('[VlmEngineManager] Memory pressure detected; releasing VLM');
    await _vlmService.cancel();
    await _vlmService.dispose();
    smolStatus = EngineStatus.unloaded;
    gemmaStatus = EngineStatus.unloaded;
    currentlyLoadedModelKey = null;
    activeBackend = 'NONE';
  }

  /// Disposes active engines
  Future<void> disposeAll() async {
    await _vlmService.dispose();
    smolStatus = EngineStatus.unloaded;
    gemmaStatus = EngineStatus.unloaded;
    currentlyLoadedModelKey = null;
    activeBackend = 'NONE';
  }
}
