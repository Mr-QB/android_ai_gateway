package com.example.android_ai_gateway

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.example.android_ai_gateway/vlm"
    private val activityScope = CoroutineScope(Dispatchers.Default + Job())
    private lateinit var vlmService: VlmNativeService

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        vlmService = VlmNativeService.getInstance(applicationContext)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getVlmStatus" -> {
                    val modelKey = call.argument<String>("modelKey") ?: VlmNativeService.MODEL_KEY_SMOLVLM
                    activityScope.launch {
                        val status = vlmService.getStatus(modelKey)
                        withContext(Dispatchers.Main) {
                            result.success(status)
                        }
                    }
                }

                "initializeVlm" -> {
                    val modelKey = call.argument<String>("modelKey") ?: VlmNativeService.MODEL_KEY_SMOLVLM
                    val modelPath = call.argument<String>("modelPath")
                    val backend = call.argument<String>("backend") ?: "AUTO"
                    val maxTokens = call.argument<Int>("maxTokens") ?: 64

                    activityScope.launch {
                        val initResult = vlmService.loadModel(
                            modelKey = modelKey,
                            modelPath = modelPath,
                            backendPref = backend,
                            maxTokens = maxTokens
                        )
                        withContext(Dispatchers.Main) {
                            result.success(initResult)
                        }
                    }
                }

                "analyzeImage" -> {
                    val imagePath = call.argument<String>("imagePath")
                    val prompt = call.argument<String>("prompt") ?: "Describe this image."
                    val maxTokens = call.argument<Int>("maxTokens") ?: 64

                    if (imagePath == null) {
                        result.error("INVALID_ARGUMENT", "imagePath is required", null)
                        return@setMethodCallHandler
                    }

                    activityScope.launch {
                        val inferenceResult = vlmService.analyzeImage(
                            imagePath = imagePath,
                            prompt = prompt,
                            maxTokens = maxTokens
                        )
                        withContext(Dispatchers.Main) {
                            result.success(inferenceResult)
                        }
                    }
                }

                "runBenchmarkX5" -> {
                    val modelKey = call.argument<String>("modelKey") ?: VlmNativeService.MODEL_KEY_SMOLVLM
                    val backend = call.argument<String>("backend") ?: "AUTO"
                    val imagePath = call.argument<String>("imagePath")
                    val prompt = call.argument<String>("prompt") ?: "Describe this image."
                    val maxTokens = call.argument<Int>("maxTokens") ?: 64

                    if (imagePath == null) {
                        result.error("INVALID_ARGUMENT", "imagePath is required", null)
                        return@setMethodCallHandler
                    }

                    activityScope.launch {
                        val benchmarkResult = vlmService.runBenchmarkX5(
                            modelKey = modelKey,
                            backendPref = backend,
                            imagePath = imagePath,
                            prompt = prompt,
                            maxTokens = maxTokens
                        )
                        withContext(Dispatchers.Main) {
                            result.success(benchmarkResult)
                        }
                    }
                }

                "disposeVlm" -> {
                    activityScope.launch {
                        vlmService.unloadModel()
                        withContext(Dispatchers.Main) {
                            result.success(true)
                        }
                    }
                }

                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}
