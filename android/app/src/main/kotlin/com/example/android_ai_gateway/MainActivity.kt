package com.example.android_ai_gateway

import android.os.Bundle
import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.content.Intent
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.media.AudioManager
import android.os.Build
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.example.android_ai_gateway/vlm"
    private val REMINDER_CHANNEL = "com.example.android_ai_gateway/reminders"
    private val ASR_CHANNEL = "com.example.android_ai_gateway/asr"
    private val DEVICE_CHANNEL = "com.example.android_ai_gateway/device_commands"
    private val activityJob = SupervisorJob()
    private val activityScope = CoroutineScope(Dispatchers.Default + activityJob)
    private lateinit var vlmService: VlmNativeService
    private var streamSink: EventChannel.EventSink? = null
    private var inferenceStreamJob: Job? = null
    private var asrRecognizer: SpeechRecognizer? = null
    private var asrEventSink: EventChannel.EventSink? = null
    private var pendingAsrPermissionResult: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        vlmService = VlmNativeService.getInstance(applicationContext)
    }

    override fun onDestroy() {
        vlmService.cancelInference()
        stopAsr()
        activityJob.cancel()
        super.onDestroy()
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
                    val structuredOutputFormat = call.argument<String>("structuredOutputFormat")

                    if (imagePath == null) {
                        result.error("INVALID_ARGUMENT", "imagePath is required", null)
                        return@setMethodCallHandler
                    }

                    activityScope.launch {
                        try {
                            val inferenceResult = vlmService.analyzeImage(
                                imagePath = imagePath,
                                prompt = prompt,
                                maxTokens = maxTokens,
                                structuredOutputFormat = structuredOutputFormat,
                            )
                            withContext(Dispatchers.Main) {
                                result.success(inferenceResult)
                            }
                        } catch (_: CancellationException) {
                            withContext(Dispatchers.Main) {
                                result.success(
                                    mapOf(
                                        "success" to false,
                                        "error" to "CANCELLED",
                                        "message" to "Inference cancelled"
                                    )
                                )
                            }
                        } catch (error: Throwable) {
                            withContext(Dispatchers.Main) {
                                result.error(
                                    "INFERENCE_EXCEPTION",
                                    error.message ?: "VLM inference failed",
                                    null
                                )
                            }
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

                "cancelInference" -> {
                    vlmService.cancelInference()
                    result.success(true)
                }

                else -> {
                    result.notImplemented()
                }
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, REMINDER_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "createReminder" -> {
                        val message = call.argument<String>("message")
                        val delayMinutes = call.argument<Int>("delayMinutes")
                        if (message.isNullOrBlank() || delayMinutes == null) {
                            result.error("INVALID_ARGUMENT", "message and delayMinutes are required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val reminder = ReminderScheduler.create(applicationContext, message, delayMinutes)
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                                checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                                PackageManager.PERMISSION_GRANTED
                            ) {
                                requestPermissions(
                                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                                    REQUEST_NOTIFICATIONS_PERMISSION,
                                )
                            }
                            result.success(reminder)
                        } catch (error: IllegalArgumentException) {
                            result.error("INVALID_ARGUMENT", error.message, null)
                        } catch (error: Throwable) {
                            result.error("REMINDER_CREATE_FAILED", error.message, null)
                        }
                    }

                    "cancelReminder" -> {
                        val id = call.argument<String>("id")
                        if (id.isNullOrBlank()) {
                            result.error("INVALID_ARGUMENT", "id is required", null)
                        } else {
                            result.success(ReminderScheduler.cancel(applicationContext, id))
                        }
                    }

                    "listReminders" -> result.success(ReminderScheduler.list(applicationContext))
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ASR_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startListening" -> startAsr(result)
                    "stopListening" -> {
                        stopAsr()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "$ASR_CHANNEL/events")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    asrEventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    asrEventSink = null
                    stopAsr()
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DEVICE_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method != "executeDeviceCommand") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                when (call.argument<String>("action")) {
                    "volume_up", "volume_down" -> {
                        val direction = if (call.argument<String>("action") == "volume_up")
                            AudioManager.ADJUST_RAISE else AudioManager.ADJUST_LOWER
                        val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                        audio.adjustStreamVolume(
                            AudioManager.STREAM_MUSIC,
                            direction,
                            AudioManager.FLAG_SHOW_UI,
                        )
                        result.success(mapOf("success" to true, "action" to call.argument<String>("action")))
                    }
                    "flashlight_on", "flashlight_off" -> try {
                        val cameraManager = getSystemService(Context.CAMERA_SERVICE) as CameraManager
                        val cameraId = cameraManager.cameraIdList.firstOrNull { id ->
                            cameraManager.getCameraCharacteristics(id)
                                .get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
                        } ?: error("No flashlight is available")
                        cameraManager.setTorchMode(
                            cameraId,
                            call.argument<String>("action") == "flashlight_on",
                        )
                        result.success(mapOf("success" to true, "action" to call.argument<String>("action")))
                    } catch (error: Throwable) {
                        result.error("DEVICE_COMMAND_FAILED", error.message, null)
                    }
                    else -> result.error(
                        "UNSUPPORTED_DEVICE_COMMAND",
                        "This device command is not implemented yet",
                        null,
                    )
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "$CHANNEL/stream")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    val request = arguments as? Map<*, *>
                    val imagePath = request?.get("imagePath") as? String
                    if (imagePath.isNullOrBlank()) {
                        events.error("INVALID_ARGUMENT", "imagePath is required", null)
                        return
                    }
                    if (inferenceStreamJob?.isActive == true) {
                        events.error("BUSY", "Another inference stream is active", null)
                        return
                    }

                    streamSink = events
                    val prompt = request["prompt"] as? String ?: "Describe this image."
                    val maxTokens = (request["maxTokens"] as? Number)?.toInt() ?: 64
                    val preprocessMs = (request["preprocessMs"] as? Number)?.toLong() ?: 0L
                    val structuredOutputFormat = request["structuredOutputFormat"] as? String

                    inferenceStreamJob = activityScope.launch {
                        try {
                            val result = vlmService.analyzeImage(
                                imagePath = imagePath,
                                prompt = prompt,
                                maxTokens = maxTokens,
                                structuredOutputFormat = structuredOutputFormat,
                                externalPreprocessMs = preprocessMs,
                                onTextChunk = { text ->
                                    withContext(Dispatchers.Main) {
                                        streamSink?.success(mapOf("type" to "token", "text" to text))
                                    }
                                }
                            )
                            withContext(Dispatchers.Main) {
                                streamSink?.success(mapOf("type" to "completed", "result" to result))
                                streamSink?.endOfStream()
                            }
                        } catch (_: CancellationException) {
                            withContext(Dispatchers.Main) {
                                streamSink?.success(mapOf("type" to "cancelled"))
                                streamSink?.endOfStream()
                            }
                        } catch (e: Throwable) {
                            withContext(Dispatchers.Main) {
                                streamSink?.success(mapOf(
                                    "type" to "failed",
                                    "error" to "INFERENCE_EXCEPTION",
                                    "message" to (e.message ?: "VLM inference failed")
                                ))
                                streamSink?.endOfStream()
                            }
                        } finally {
                            withContext(Dispatchers.Main) {
                                if (streamSink === events) {
                                    streamSink = null
                                    inferenceStreamJob = null
                                }
                            }
                        }
                    }
                }

                override fun onCancel(arguments: Any?) {
                    vlmService.cancelInference()
                    inferenceStreamJob?.cancel()
                    inferenceStreamJob = null
                    streamSink = null
                }
            })
    }

    companion object {
        private const val REQUEST_NOTIFICATIONS_PERMISSION = 4102
        private const val REQUEST_RECORD_AUDIO_PERMISSION = 4103
    }

    private fun startAsr(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            !SpeechRecognizer.isOnDeviceRecognitionAvailable(this)
        ) {
            result.error("ON_DEVICE_ASR_UNAVAILABLE", "On-device speech recognition is unavailable", null)
            return
        }
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            pendingAsrPermissionResult = result
            requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), REQUEST_RECORD_AUDIO_PERMISSION)
            return
        }
        createAsrRecognizer(result)
    }

    private fun createAsrRecognizer(result: MethodChannel.Result) {
        try {
            stopAsr()
            asrRecognizer = SpeechRecognizer.createOnDeviceSpeechRecognizer(this).apply {
                setRecognitionListener(object : RecognitionListener {
                    override fun onReadyForSpeech(params: Bundle?) {
                        asrEventSink?.success(mapOf("type" to "ready"))
                    }
                    override fun onBeginningOfSpeech() = Unit
                    override fun onRmsChanged(rmsdB: Float) = Unit
                    override fun onBufferReceived(buffer: ByteArray?) = Unit
                    override fun onEndOfSpeech() = Unit
                    override fun onEvent(eventType: Int, params: Bundle?) = Unit
                    override fun onPartialResults(partialResults: Bundle?) {
                        val text = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()
                        if (!text.isNullOrBlank()) asrEventSink?.success(mapOf("type" to "partial", "text" to text))
                    }
                    override fun onResults(results: Bundle?) {
                        val text = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()
                        if (text.isNullOrBlank()) {
                            asrEventSink?.error("ASR_EMPTY", "No speech recognized", null)
                            asrEventSink?.endOfStream()
                        } else {
                            asrEventSink?.success(mapOf("type" to "final", "text" to text))
                            asrEventSink?.endOfStream()
                        }
                        asrEventSink = null
                        stopAsr()
                    }
                    override fun onError(error: Int) {
                        asrEventSink?.error("ASR_$error", "Speech recognition failed", null)
                        asrEventSink?.endOfStream()
                        asrEventSink = null
                        stopAsr()
                    }
                })
                val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE, "vi-VN")
                    putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                    putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
                    putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
                }
                startListening(intent)
            }
            result.success(true)
        } catch (error: Throwable) {
            stopAsr()
            result.error("ASR_START_FAILED", error.message, null)
        }
    }

    private fun stopAsr() {
        val pendingPermission = pendingAsrPermissionResult
        pendingAsrPermissionResult = null
        pendingPermission?.error("ASR_CANCELLED", "Speech recognition cancelled", null)
        val recognizer = asrRecognizer
        asrRecognizer = null
        if (recognizer != null) {
            try { recognizer.cancel() } catch (_: Throwable) { }
            recognizer.destroy()
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_RECORD_AUDIO_PERMISSION) {
            val pending = pendingAsrPermissionResult ?: return
            pendingAsrPermissionResult = null
            if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
                createAsrRecognizer(pending)
            } else {
                pending.error("MICROPHONE_PERMISSION_DENIED", "Microphone permission is required", null)
            }
        }
    }
}
