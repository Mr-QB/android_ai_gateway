package com.example.android_ai_gateway

import android.content.Context
import android.os.Debug
import android.os.SystemClock
import android.util.Log
import com.google.ai.edge.litertlm.Backend
import com.google.ai.edge.litertlm.Content
import com.google.ai.edge.litertlm.Contents
import com.google.ai.edge.litertlm.Conversation
import com.google.ai.edge.litertlm.ConversationConfig
import com.google.ai.edge.litertlm.Engine
import com.google.ai.edge.litertlm.EngineConfig
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean

class VlmNativeService(private val context: Context) {

    companion object {
        private const val TAG = "VLM"

        const val MODEL_KEY_SMOLVLM = "smolvlm2_500m"
        const val MODEL_KEY_GEMMA = "gemma_4_e2b"

        const val FILENAME_SMOLVLM = "SmolVLM2-500M.litertlm"
        const val FILENAME_GEMMA_GPU = "gemma-4-E2B-it-gpu.litertlm"
        const val FILENAME_GEMMA_CPU = "gemma-4-E2B-it.litertlm"

        @Volatile
        private var instance: VlmNativeService? = null

        fun getInstance(context: Context): VlmNativeService =
            instance ?: synchronized(this) {
                instance ?: VlmNativeService(context.applicationContext).also { instance = it }
            }
    }

    private var engine: Engine? = null
    private var loadedModelKey: String? = null
    private var loadedModelPath: String? = null
    private var activeBackend: String = "NONE"
    private var requestedBackend: String = "AUTO"
    private var lastLoadTimeMs: Long = 0

    private val isInferring = AtomicBoolean(false)
    private val mutex = Mutex()

    private fun getCandidateFilenames(modelKey: String): List<String> {
        return when (modelKey) {
            MODEL_KEY_GEMMA -> listOf(FILENAME_GEMMA_GPU, FILENAME_GEMMA_CPU)
            else -> listOf(FILENAME_SMOLVLM)
        }
    }

    private fun getCandidateModelPaths(modelKey: String): List<File> {
        val filenames = getCandidateFilenames(modelKey)
        val candidates = mutableListOf<File>()

        for (fname in filenames) {
            // 1. App internal files/models/
            candidates.add(File(File(context.filesDir, "models"), fname))
            // 2. App internal files/
            candidates.add(File(context.filesDir, fname))
            // 3. App external files/models/ and files/
            context.getExternalFilesDir(null)?.let {
                candidates.add(File(File(it, "models"), fname))
                candidates.add(File(it, fname))
            }
            // 4. Download directory
            candidates.add(File("/sdcard/Download", fname))
            // 5. /data/local/tmp
            candidates.add(File("/data/local/tmp", fname))
        }
        return candidates
    }

    fun findExistingModelFile(modelKey: String): File? {
        for (candidate in getCandidateModelPaths(modelKey)) {
            if (candidate.exists() && candidate.canRead() && candidate.length() > 1024 * 1024) {
                return candidate
            }
        }
        return null
    }

    fun getExpectedModelPath(modelKey: String): String {
        return findExistingModelFile(modelKey)?.absolutePath
            ?: File(File(context.filesDir, "models"), getCandidateFilenames(modelKey).first()).absolutePath
    }

    fun getStatus(modelKey: String = MODEL_KEY_SMOLVLM): Map<String, Any?> {
        val smolExists = findExistingModelFile(MODEL_KEY_SMOLVLM) != null
        val gemmaExists = findExistingModelFile(MODEL_KEY_GEMMA) != null

        val targetKey = if (engine != null && loadedModelKey != null) loadedModelKey!! else modelKey
        val foundFile = findExistingModelFile(targetKey)
        val expectedPath = foundFile?.absolutePath ?: getExpectedModelPath(targetKey)
        val fileExists = foundFile != null
        val isLoaded = engine != null

        return mapOf(
            "isLoaded" to isLoaded,
            "loadedModelKey" to (loadedModelKey ?: targetKey),
            "modelPath" to (loadedModelPath ?: expectedPath),
            "modelExists" to fileExists,
            "requestedBackend" to requestedBackend,
            "actualBackend" to activeBackend,
            "expectedPath" to expectedPath,
            "loadTimeMs" to lastLoadTimeMs,
            "isInferring" to isInferring.get(),
            "modelsAvailable" to mapOf(
                MODEL_KEY_SMOLVLM to smolExists,
                MODEL_KEY_GEMMA to gemmaExists
            )
        )
    }

    suspend fun loadModel(
        modelKey: String = MODEL_KEY_SMOLVLM,
        modelPath: String? = null,
        backendPref: String = "AUTO",
        maxTokens: Int = 64
    ): Map<String, Any?> = mutex.withLock {
        val targetPath = modelPath ?: getExpectedModelPath(modelKey)
        val modelFile = File(targetPath)

        Log.i(TAG, "[VLM] Requested load: modelKey=$modelKey, backend=$backendPref, path=$targetPath")

        if (!modelFile.exists()) {
            Log.e(TAG, "[VLM] Model file not found at: $targetPath")
            return mapOf(
                "success" to false,
                "error" to "MODEL_NOT_FOUND",
                "message" to "Model file for $modelKey not found at $targetPath",
                "expectedPath" to targetPath,
                "modelKey" to modelKey
            )
        }

        // Check if engine is already loaded and warm with compatible backend
        val isCompatibleBackend = when (backendPref) {
            "AUTO" -> activeBackend == "GPU" || activeBackend == "CPU" || activeBackend == "GPU (Vision CPU)"
            "GPU" -> activeBackend == "GPU" || activeBackend == "GPU (Vision CPU)"
            "CPU" -> activeBackend == "CPU"
            else -> activeBackend == backendPref
        }

        if (engine != null && loadedModelKey == modelKey && loadedModelPath == targetPath && isCompatibleBackend) {
            Log.i(TAG, "[VLM] Model $modelKey already warm on backend $activeBackend (reusing engine, 0 ms load)")
            return mapOf(
                "success" to true,
                "backend" to activeBackend,
                "requestedBackend" to requestedBackend,
                "modelKey" to modelKey,
                "loadTimeMs" to 0L,
                "reused" to true
            )
        }

        // When switching models or backends, explicitly unload previous engine and run GC
        if (engine != null) {
            Log.i(TAG, "[VLM] Unloading previous model ($loadedModelKey on $activeBackend) before loading $modelKey...")
            unloadInternal()
            System.gc()
            System.runFinalization()
        }

        requestedBackend = backendPref
        val startLoad = SystemClock.elapsedRealtime()

        var initializedBackend = "CPU"
        var createdEngine: Engine? = null

        val tryGpuFirst = backendPref == "GPU" || backendPref == "AUTO"

        if (tryGpuFirst) {
            Log.i(TAG, "[VLM] Initializing $modelKey with GPU backend (Mali-G610 MC6)...")
            try {
                val gpuConfig = EngineConfig(
                    modelPath = targetPath,
                    backend = Backend.GPU(),
                    visionBackend = Backend.GPU(),
                    maxNumImages = 1
                )
                val testEngine = Engine(gpuConfig)
                testEngine.initialize()
                createdEngine = testEngine
                initializedBackend = "GPU"
                Log.i(TAG, "[VLM] Full GPU initialization succeeded for $modelKey")
            } catch (gpuError: Throwable) {
                Log.w(TAG, "[VLM] Full GPU initialization failed: ${gpuError.message}. Trying GPU (text) + CPU (vision)...", gpuError)
                try {
                    val gpuCpuConfig = EngineConfig(
                        modelPath = targetPath,
                        backend = Backend.GPU(),
                        visionBackend = Backend.CPU(),
                        maxNumImages = 1
                    )
                    val testEngine = Engine(gpuCpuConfig)
                    testEngine.initialize()
                    createdEngine = testEngine
                    initializedBackend = "GPU (Vision CPU)"
                    Log.i(TAG, "[VLM] GPU text + CPU vision succeeded for $modelKey")
                } catch (gpuCpuError: Throwable) {
                    Log.w(TAG, "[VLM] GPU+CPU vision failed: ${gpuCpuError.message}. Falling back to full CPU...", gpuCpuError)
                }
            }
        }

        if (createdEngine == null) {
            Log.i(TAG, "[VLM] Initializing $modelKey with full CPU backend...")
            try {
                val cpuConfig = EngineConfig(
                    modelPath = targetPath,
                    backend = Backend.CPU(),
                    visionBackend = Backend.CPU(),
                    maxNumImages = 1
                )
                val cpuEngine = Engine(cpuConfig)
                cpuEngine.initialize()
                createdEngine = cpuEngine
                initializedBackend = "CPU"
                Log.i(TAG, "[VLM] CPU backend initialized successfully for $modelKey")
            } catch (cpuError: Throwable) {
                Log.e(TAG, "[VLM] CPU initialization failed: ${cpuError.message}", cpuError)
                return mapOf(
                    "success" to false,
                    "error" to "MODEL_LOAD_FAILED",
                    "message" to (cpuError.message ?: "Failed to initialize LiteRT-LM Engine for $modelKey"),
                    "modelKey" to modelKey
                )
            }
        }

        engine = createdEngine
        loadedModelKey = modelKey
        loadedModelPath = targetPath
        activeBackend = initializedBackend
        lastLoadTimeMs = SystemClock.elapsedRealtime() - startLoad

        Log.i(TAG, "[VLM] $modelKey successfully loaded in $lastLoadTimeMs ms. Backend: $activeBackend")

        return mapOf(
            "success" to true,
            "backend" to activeBackend,
            "requestedBackend" to requestedBackend,
            "modelKey" to modelKey,
            "loadTimeMs" to lastLoadTimeMs,
            "reused" to false
        )
    }

    suspend fun analyzeImage(
        imagePath: String,
        prompt: String,
        maxTokens: Int = 64
    ): Map<String, Any?> {
        if (!isInferring.compareAndSet(false, true)) {
            Log.w(TAG, "[VLM] Inference already running, request ignored")
            return mapOf(
                "success" to false,
                "error" to "BUSY",
                "message" to "Another inference is currently in progress"
            )
        }

        try {
            val currentEngine = engine
            if (currentEngine == null) {
                Log.e(TAG, "[VLM] Model is not loaded. Call initializeVlm first.")
                return mapOf(
                    "success" to false,
                    "error" to "MODEL_NOT_LOADED",
                    "message" to "Model is not loaded"
                )
            }

            // Create fresh conversation session on warm engine (< 5ms)
            // This reuses GPU weights while preventing KV-cache token limit overflow
            val conv = currentEngine.createConversation(ConversationConfig())
            try {
                Log.i(TAG, "[VLM] Starting inference: model=$loadedModelKey, backend=$activeBackend, prompt='$prompt'")
                val startTotal = SystemClock.elapsedRealtime()

                // Preprocess: read image file
                val startPreprocess = SystemClock.elapsedRealtime()
                val imageFile = File(imagePath)
                if (!imageFile.exists() || imageFile.length() == 0L) {
                    Log.e(TAG, "[VLM] Image file does not exist or is empty: $imagePath")
                    return mapOf(
                        "success" to false,
                        "error" to "INVALID_IMAGE",
                        "message" to "Image file not found or invalid: $imagePath"
                    )
                }

                val imageBytes = imageFile.readBytes()
                val preprocessMs = SystemClock.elapsedRealtime() - startPreprocess
                Log.i(TAG, "[VLM] Image ready: $preprocessMs ms (size: ${imageBytes.size} bytes)")

                // Build multimodal message: Text prompt + ImageBytes
                val contentsList = mutableListOf<Content>()
                contentsList.add(Content.Text(prompt))
                contentsList.add(Content.ImageBytes(imageBytes))
                val multimodalInput = Contents.of(contentsList)

                // Measure generation and TTFT via streaming flow or fallback
                val startGeneration = SystemClock.elapsedRealtime()
                var firstTokenTimeMs: Long? = null
                var tokenCount = 0
                val fullResponseBuilder = StringBuilder()

                try {
                    // Collect streaming chunks to accurately capture Time To First Token (TTFT)
                    conv.sendMessageAsync(multimodalInput).collect { msg ->
                        if (firstTokenTimeMs == null) {
                            firstTokenTimeMs = SystemClock.elapsedRealtime() - startGeneration
                            Log.i(TAG, "[VLM] TTFT captured: $firstTokenTimeMs ms")
                        }
                        val textChunks = msg.contents.contents
                            .filterIsInstance<Content.Text>()
                            .joinToString("") { it.text }
                        if (textChunks.isNotEmpty()) {
                            fullResponseBuilder.append(textChunks)
                            tokenCount++
                        }
                    }
                } catch (flowErr: Throwable) {
                    Log.w(TAG, "[VLM] Flow streaming exception: ${flowErr.message}, trying synchronous sendMessage fallback...", flowErr)
                    val syncResp = conv.sendMessage(multimodalInput)
                    val text = syncResp.contents.contents
                        .filterIsInstance<Content.Text>()
                        .joinToString("\n") { it.text }
                    fullResponseBuilder.append(text)
                }

                val generationMs = SystemClock.elapsedRealtime() - startGeneration
                val totalInferenceMs = SystemClock.elapsedRealtime() - startTotal

                var responseText = fullResponseBuilder.toString().trim()
                if (responseText.isBlank()) {
                    responseText = "No response generated."
                }

                // If token count from chunks is 0, estimate from word/subword count
                val finalTokenCount = if (tokenCount > 0) {
                    tokenCount
                } else {
                    responseText.split(Regex("\\s+")).size
                }

                val generationSec = if (generationMs > 0) generationMs / 1000.0 else 0.001
                val tokensPerSecond = finalTokenCount / generationSec

                val runtime = Runtime.getRuntime()
                val javaHeapMb = (runtime.totalMemory() - runtime.freeMemory()) / (1024.0 * 1024.0)
                val nativeHeapMb = Debug.getNativeHeapAllocatedSize() / (1024.0 * 1024.0)

                Log.i(
                    TAG,
                    "[VLM] Finished: total=${totalInferenceMs}ms, TTFT=${firstTokenTimeMs ?: 0}ms, " +
                    "gen=${generationMs}ms, tokens=$finalTokenCount (~${"%.2f".format(tokensPerSecond)} tps)"
                )

                return mapOf(
                    "success" to true,
                    "text" to responseText,
                    "modelKey" to (loadedModelKey ?: MODEL_KEY_SMOLVLM),
                    "modelLoadMs" to 0L, // Warm inference
                    "isWarm" to true,
                    "preprocessMs" to preprocessMs,
                    "timeToFirstTokenMs" to firstTokenTimeMs,
                    "generationMs" to generationMs,
                    "totalInferenceMs" to totalInferenceMs,
                    "generatedTokens" to finalTokenCount,
                    "tokensPerSecond" to tokensPerSecond,
                    "backend" to activeBackend,
                    "requestedBackend" to requestedBackend,
                    "nativeHeapMb" to nativeHeapMb,
                    "javaHeapMb" to javaHeapMb
                )
            } finally {
                try {
                    conv.close()
                } catch (ce: Throwable) {
                    Log.w(TAG, "[VLM] Note during conv.close(): ${ce.message}")
                }
            }
        } catch (e: Throwable) {
            Log.e(TAG, "[VLM] Unexpected error during analyzeImage: ${e.message}", e)
            return mapOf(
                "success" to false,
                "error" to "INFERENCE_EXCEPTION",
                "message" to (e.message ?: "Unknown exception during VLM inference")
            )
        } finally {
            isInferring.set(false)
        }
    }

    suspend fun runBenchmarkX5(
        modelKey: String,
        backendPref: String,
        imagePath: String,
        prompt: String,
        maxTokens: Int = 64
    ): Map<String, Any?> {
        val runs = mutableListOf<Map<String, Any?>>()

        // Step 1: Ensure model is loaded; note cold load time if newly loaded
        var coldLoadMs = 0L
        if (engine == null || loadedModelKey != modelKey || activeBackend == "NONE") {
            val initRes = loadModel(modelKey = modelKey, backendPref = backendPref, maxTokens = maxTokens)
            if (initRes["success"] != true) {
                return mapOf(
                    "success" to false,
                    "error" to (initRes["error"] ?: "LOAD_FAILED"),
                    "message" to (initRes["message"] ?: "Failed to initialize model for benchmark")
                )
            }
            coldLoadMs = (initRes["loadTimeMs"] as? Long) ?: 0L
        }

        Log.i(TAG, "[VLM Benchmark] Running 5-run benchmark for $modelKey on $activeBackend...")

        for (i in 1..5) {
            Log.i(TAG, "[VLM Benchmark] Executing Run #$i of 5...")
            val runResult = analyzeImage(imagePath, prompt, maxTokens)
            if (runResult["success"] != true) {
                Log.w(TAG, "[VLM Benchmark] Run #$i failed: ${runResult["message"]}")
            }
            val runMap = runResult.toMutableMap()
            runMap["runIndex"] = i
            // The very first run can be marked cold if coldLoadMs > 0 and i == 1
            runMap["isWarm"] = !(i == 1 && coldLoadMs > 0)
            runs.add(runMap)
        }

        return mapOf(
            "success" to true,
            "modelKey" to modelKey,
            "modelDisplayName" to if (modelKey == MODEL_KEY_GEMMA) "Gemma-4-E2B-it" else "SmolVLM2-500M",
            "backend" to activeBackend,
            "coldLoadMs" to coldLoadMs,
            "runs" to runs
        )
    }

    private fun unloadInternal() {
        try {
            engine?.close()
        } catch (e: Exception) {
            Log.w(TAG, "[VLM] Error closing engine: ${e.message}")
        }
        engine = null
        loadedModelKey = null
        loadedModelPath = null
        activeBackend = "NONE"
        Log.i(TAG, "[VLM] Engine resources unloaded")
    }

    suspend fun unloadModel(): Unit = mutex.withLock {
        unloadInternal()
        System.gc()
        System.runFinalization()
    }
}
