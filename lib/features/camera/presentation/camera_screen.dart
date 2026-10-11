import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import '../../ai_engine/domain/detection.dart';
import '../../ai_engine/domain/inference_backend.dart';
import '../../ai_engine/domain/inference_metrics.dart';
import '../../ai_engine/services/ai_engine_service.dart';
import '../../ai_engine/services/frame_hub.dart';
import '../../camera/data/coco_labels.dart';
import '../../assistant/device_command_service.dart';
import '../../assistant/intent_router.dart';
import '../../assistant/reminder_parser.dart';
import '../../assistant/reminder_service.dart';
import '../../assistant/vietnamese_asr_service.dart';
import '../../assistant/vietnamese_text.dart';
import '../../perception/agents/smol/hazard_agent.dart';
import '../../perception/agents/smol/scene_agent.dart';
import '../../perception/ocr/ocr_service.dart';
import '../../perception/output/assistive_output_manager.dart';
import '../../perception/vlm_engine_manager.dart';
import '../../vlm/models/vlm_stream_event.dart';
import '../../vlm/services/vlm_service.dart';
import 'detection_painter.dart';

class CameraScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const CameraScreen({super.key, required this.cameras});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  final AIEngineService _aiEngineService = AIEngineService();
  final FrameHub _frameHub = FrameHub();
  final VlmEngineManager _vlmEngineManager = VlmEngineManager();
  final VlmService _vlmService = VlmService();
  final OcrService _ocrService = OcrService();
  final ReminderService _reminderService = NativeReminderService();
  final DeviceCommandService _deviceCommandService = DeviceCommandService();
  final VietnameseAsrService _asrService = VietnameseAsrService();
  final AssistiveOutputManager _outputManager = AssistiveOutputManager();

  bool _isInitialized = false;
  int _selectedCameraIndex = 0;
  String? _errorMessage;
  bool _hasVulkan = false;

  bool _isModelLoading = false;
  bool _isModelLoaded = false;
  bool _isStreaming = false;
  bool _isListening = false;
  bool _isAssistantRunning = false;
  StreamSubscription<VietnameseAsrEvent>? _asrSubscription;

  InferenceBackend _selectedBackend = InferenceBackend.auto;
  int _selectedThreads = 0; // 0 = AUTO

  List<Detection> _currentDetections = [];
  InferenceMetrics _currentMetrics = const InferenceMetrics();
  Timer? _metricsTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    debugPrint('Native AI Engine version: ${_aiEngineService.getVersion()}');
    _hasVulkan = _aiEngineService.hasVulkanGPU();

    if (widget.cameras.isNotEmpty) {
      _initCamera(_selectedCameraIndex);
    } else {
      _errorMessage = 'Không tìm thấy camera nào trên thiết bị.';
    }

    // Tự động load model với Backend AUTO (ưu tiên Vulkan GPU)
    _loadModel();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null || !_controller!.value.isInitialized) return;

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _stopStreaming();
    } else if (state == AppLifecycleState.resumed) {
      if (_isModelLoaded && !_isStreaming) {
        _startStreaming();
      }
    }
  }

  @override
  void didHaveMemoryPressure() {
    unawaited(_vlmEngineManager.handleMemoryPressure());
  }

  Future<void> _initCamera(int cameraIndex) async {
    if (widget.cameras.isEmpty) return;

    await _stopStreaming();

    setState(() {
      _isInitialized = false;
      _errorMessage = null;
    });

    final previousController = _controller;
    _controller = null;
    await previousController?.dispose();

    final camera = widget.cameras[cameraIndex];
    // ResolutionPreset.medium (thường là 720x480 hoặc 640x480) giúp tiết kiệm băng thông
    // và cho tốc độ xử lý nhanh nhất cho model 640x640
    final controller = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _controller = controller;
        _isInitialized = true;
      });

      if (_isModelLoaded) {
        _startStreaming();
      }
    } catch (error) {
      await controller.dispose();
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Lỗi khởi tạo camera: $error';
      });
    }
  }

  Future<void> _switchCamera() async {
    if (widget.cameras.length < 2) return;
    _selectedCameraIndex = (_selectedCameraIndex + 1) % widget.cameras.length;
    await _initCamera(_selectedCameraIndex);
  }

  Future<void> _loadModel() async {
    if (_isModelLoading || !_aiEngineService.isNativeLoaded) return;

    setState(() {
      _isModelLoading = true;
    });

    await _stopStreaming();

    final loaded = await _aiEngineService.initializeModel(
      backend: _selectedBackend,
      threads: _selectedThreads,
    );

    if (!mounted) return;

    setState(() {
      _isModelLoading = false;
      _isModelLoaded = loaded;
    });

    if (loaded) {
      _showMessage(
        'YOLO26n (640x640) đã sẵn sàng • ${_aiEngineService.modelBackendName} '
        '(${_aiEngineService.threadCount} threads)',
      );
      _startStreaming();
    } else {
      _showMessage(
        'Lỗi load YOLO26n (mã: ${_aiEngineService.lastModelLoadCode})',
      );
    }
  }

  void _startStreaming() {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        !_isModelLoaded ||
        _isStreaming) {
      return;
    }

    final camera = widget.cameras[_selectedCameraIndex];
    final sensorOrientation = camera.sensorOrientation;

    // 1. Khởi động C++ background FrameWorker
    _aiEngineService.startRealtimeWorker();

    // 2. Đăng ký FrameHub consumer đẩy thẳng frame vào C++ worker
    _frameHub.resetStats();
    _frameHub.subscribeRealtimeConsumer((frame) async {
      _aiEngineService.pushCameraFrame(frame);
    });

    // 3. Khởi động Camera Image Stream (nhận buffer YUV420 trực tiếp)
    controller.startImageStream((CameraImage image) {
      _frameHub.onCameraImage(image, sensorOrientation);
    });

    // 4. Timer định kỳ 50ms đọc kết quả mới nhất từ Native worker và cập nhật HUD
    _metricsTimer?.cancel();
    _metricsTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (!mounted) return;

      final latestBatch = _aiEngineService.getLatestWorkerDetections();
      final hubStats = _frameHub.getStats();

      if (latestBatch != null) {
        final m = latestBatch.metrics;
        final updatedMetrics = InferenceMetrics(
          preprocessMs: m?.preprocessMs ?? 0.0,
          inferenceMs: m?.inferenceMs ?? latestBatch.inferenceTimeMs,
          postprocessMs: m?.postprocessMs ?? 0.0,
          totalNativeMs: m?.totalNativeMs ?? 0.0,
          cameraFps: hubStats.cameraFps,
          processedFps: hubStats.processedFps,
          receivedFrames: hubStats.receivedFrames,
          processedFrames: hubStats.processedFrames,
          droppedFrames: hubStats.droppedFrames,
          backendName: _aiEngineService.modelBackendName,
          threadCount: _aiEngineService.threadCount,
        );

        setState(() {
          _currentDetections = latestBatch.detections;
          _currentMetrics = updatedMetrics;
        });
      } else {
        final metrics = _currentMetrics;
        if (metrics.cameraFps != hubStats.cameraFps ||
            metrics.processedFps != hubStats.processedFps ||
            metrics.receivedFrames != hubStats.receivedFrames ||
            metrics.processedFrames != hubStats.processedFrames ||
            metrics.droppedFrames != hubStats.droppedFrames) {
          setState(() {
            _currentMetrics = metrics.copyWith(
              cameraFps: hubStats.cameraFps,
              processedFps: hubStats.processedFps,
              receivedFrames: hubStats.receivedFrames,
              processedFrames: hubStats.processedFrames,
              droppedFrames: hubStats.droppedFrames,
            );
          });
        }
      }
    });

    setState(() {
      _isStreaming = true;
    });
  }

  Future<void> _stopStreaming({bool updateState = true}) async {
    _metricsTimer?.cancel();
    _metricsTimer = null;

    if (_isStreaming &&
        _controller != null &&
        _controller!.value.isInitialized) {
      try {
        await _controller!.stopImageStream();
      } catch (_) {}
    }

    _frameHub.unsubscribeRealtimeConsumer();
    _aiEngineService.stopRealtimeWorker();

    _isStreaming = false;
    _currentDetections = [];

    if (updateState && mounted) {
      setState(() {});
    }
  }

  /// Chụp snapshot on-demand qua FrameHub mà không tắt stream
  Future<void> _toggleVoiceAssistant() async {
    if (_isAssistantRunning) {
      await _vlmService.cancel();
      await _outputManager.interrupt();
      return;
    }
    if (_isListening) {
      await _asrService.stop();
      await _asrSubscription?.cancel();
      if (mounted) setState(() => _isListening = false);
      return;
    }
    await _outputManager.interrupt();
    if (!mounted) return;
    setState(() => _isListening = true);
    _asrSubscription = _asrService.listen().listen(
      (event) {
        if (event.type == 'final' && event.text.trim().isNotEmpty) {
          if (mounted) setState(() => _isListening = false);
          unawaited(_routeVoiceQuery(event.text));
        }
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() => _isListening = false);
        _showMessage('Nhận dạng giọng nói thất bại: $error');
      },
      onDone: () {
        if (mounted && _isListening) setState(() => _isListening = false);
      },
    );
  }

  Future<void> _routeVoiceQuery(String query) async {
    final result = IntentRouter.route(query);
    debugPrint(
      '[INTENT] intent=${result.type.wireName} slotKeys=${result.slots.keys.join(',')}',
    );
    switch (result.type) {
      case IntentType.reminderCreate:
        final parsed = ReminderParser.parseCreate(query);
        if (parsed == null) {
          _speakAssistant('Tôi chưa hiểu thời gian nhắc.');
          return;
        }
        try {
          final reminder = await _reminderService.create(parsed);
          final note = reminder.notificationsEnabled
              ? ''
              : ' Hãy cấp quyền thông báo.';
          _speakAssistant(
            'Tôi sẽ nhắc bạn ${reminder.message} sau ${parsed.delayMinutes} phút.$note',
          );
        } catch (error) {
          debugPrint('[REMINDER] create failed: $error');
          _speakAssistant('Không đặt được lời nhắc.');
        }
      case IntentType.reminderCancel:
        try {
          final reminders = await _reminderService.list();
          final target = result.slots['target']?.toString();
          final matches = reminders
              .where(
                (item) =>
                    target == null ||
                    target.isEmpty ||
                    VietnameseText.normalize(item.message).contains(target),
              )
              .toList();
          if (matches.length == 1) {
            await _reminderService.cancel(matches.single.id);
            _speakAssistant('Đã hủy lời nhắc ${matches.single.message}.');
          } else if (matches.isEmpty) {
            _speakAssistant('Không tìm thấy lời nhắc phù hợp.');
          } else {
            _speakAssistant('Có nhiều lời nhắc. Hãy nêu rõ nội dung cần hủy.');
          }
        } catch (error) {
          debugPrint('[REMINDER] cancel failed: $error');
          _speakAssistant('Không hủy được lời nhắc.');
        }
      case IntentType.reminderList:
        try {
          final reminders = await _reminderService.list();
          _speakAssistant(
            reminders.isEmpty
                ? 'Bạn chưa có lời nhắc nào đang chờ.'
                : reminders
                      .map(
                        (item) =>
                            '${item.message}, lúc ${item.scheduledAt.toLocal().hour} giờ ${item.scheduledAt.toLocal().minute} phút',
                      )
                      .join('. '),
          );
        } catch (error) {
          debugPrint('[REMINDER] list failed: $error');
          _speakAssistant('Không tải được danh sách lời nhắc.');
        }
      case IntentType.deviceCommand:
        final action = result.slots['action']?.toString();
        if (!const {
          'volume_up',
          'volume_down',
          'flashlight_on',
          'flashlight_off',
        }.contains(action)) {
          _speakAssistant('Lệnh thiết bị này chưa được hỗ trợ.');
          return;
        }
        try {
          await _deviceCommandService.execute(action!);
          _speakAssistant(switch (action) {
            'volume_up' => 'Đã tăng âm lượng.',
            'volume_down' => 'Đã giảm âm lượng.',
            'flashlight_on' => 'Đã bật đèn pin.',
            _ => 'Đã tắt đèn pin.',
          });
        } catch (error) {
          debugPrint('[DEVICE_COMMAND] failed action=$action error=$error');
          _speakAssistant('Không thực hiện được lệnh thiết bị.');
        }
      case IntentType.visionQuery:
      case IntentType.sceneDescription:
      case IntentType.safetyAlert:
      case IntentType.ocrQuery:
        await _runVoiceVisionTask(result.type, query);
      case IntentType.unknown:
        _speakAssistant('Tôi chưa hiểu yêu cầu.');
    }
  }

  void _speakAssistant(
    String text, {
    AlertPriority priority = AlertPriority.userQuery,
  }) {
    _showMessage(text);
    unawaited(
      _outputManager.dispatch(
        message: text,
        priority: priority,
        sourceAgent: 'VoiceAssistant',
      ),
    );
  }

  Future<void> _runVoiceVisionTask(IntentType intent, String query) async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        _isAssistantRunning) {
      _speakAssistant('Camera chưa sẵn sàng.');
      return;
    }
    final restoreYolo = _isModelLoaded && _isStreaming;
    final wasStreaming = _isStreaming;
    final detections = List<Detection>.of(_currentDetections);
    XFile? image;
    setState(() => _isAssistantRunning = true);
    try {
      await _stopStreaming();
      image = await controller.takePicture();
      if (restoreYolo && _aiEngineService.isModelLoaded) {
        _aiEngineService.unloadModel();
        _isModelLoaded = false;
      }
      switch (intent) {
        case IntentType.visionQuery:
        case IntentType.sceneDescription:
          final result = await SceneAgent(engineManager: _vlmEngineManager)
              .execute(
                imagePath: image.path,
                userQuery: query,
                detectedObjects: detections
                    .map(
                      (item) =>
                          item.classId >= 0 && item.classId < cocoLabels.length
                          ? cocoLabels[item.classId]
                          : 'other',
                    )
                    .toList(),
                speakStreaming: true,
              );
          _showMessage(result.summary);
        case IntentType.safetyAlert:
          final result = await HazardAgent(
            engineManager: _vlmEngineManager,
          ).execute(imagePath: image.path, detections: detections);
          if (result.hazard && result.message.isNotEmpty) {
            _showMessage(result.message);
          } else if (!result.analysisSucceeded) {
            _speakAssistant(
              'Tôi không kiểm tra được đường đi. Hãy dừng lại và thận trọng.',
              priority: AlertPriority.highWarning,
            );
          } else {
            _speakAssistant('Không thấy nguy hiểm rõ ràng phía trước.');
          }
        case IntentType.ocrQuery:
          final items = await _ocrService.recognizeText(image.path);
          final text = items.map((item) => item.text).join('. ');
          _speakAssistant(
            text.isEmpty ? 'Không đọc được chữ trong ảnh.' : text,
          );
        case IntentType.reminderCreate:
        case IntentType.reminderCancel:
        case IntentType.reminderList:
        case IntentType.deviceCommand:
        case IntentType.unknown:
          break;
      }
    } on VlmInferenceCancelled {
      debugPrint('[VOICE_VISION] inference cancelled by user');
    } catch (error, stack) {
      debugPrint('[VOICE_VISION] failed: $error\n$stack');
      _speakAssistant('Không phân tích được hình ảnh lúc này.');
    } finally {
      if (image != null) {
        try {
          await File(image.path).delete();
        } catch (_) {}
      }
      if (mounted && restoreYolo) {
        await _loadModel();
      } else if (mounted && wasStreaming) {
        _startStreaming();
      }
      if (mounted) setState(() => _isAssistantRunning = false);
    }
  }

  Future<void> _captureSnapshotForVlm() async {
    if (!_isStreaming) {
      _showMessage('Camera chưa stream để lấy snapshot.');
      return;
    }

    try {
      final snapshot = await _frameHub.requestSnapshot();
      if (!mounted) return;

      _showMessage(
        'Đã chụp snapshot VLM: ${snapshot.width}x${snapshot.height} '
        '(${snapshot.yuvBytes.length ~/ 1024} KB)',
      );
    } catch (e) {
      _showMessage('Lỗi lấy snapshot: $e');
    }
  }

  /// Nhận diện ảnh mẫu qua FFI đồng bộ (tương thích ngược)
  Future<void> _detectSampleImage() async {
    if (!_aiEngineService.isModelLoaded) {
      _showMessage('Đang nạp model YOLO26n...');
      await _loadModel();
      if (!_isModelLoaded) return;
    }

    try {
      final byteData = await rootBundle.load('assets/images/sample_test.jpg');
      final jpegBytes = byteData.buffer.asUint8List();
      final decoded = img.decodeImage(jpegBytes);
      if (decoded == null) throw StateError('Không giải mã được ảnh mẫu.');

      final oriented = img.bakeOrientation(decoded);
      final rgbBytes = oriented.getBytes(order: img.ChannelOrder.rgb);

      final batch = _aiEngineService.detectRgb(
        rgbBytes: rgbBytes,
        width: oriented.width,
        height: oriented.height,
        probabilityThreshold: 0.35,
        nmsThreshold: 0.50,
      );

      _showMessage(
        'Ảnh mẫu: Tìm thấy ${batch.detections.length} vật thể trong '
        '${batch.inferenceTimeMs.toStringAsFixed(1)} ms (${batch.metrics?.backendName ?? ''})',
      );
    } catch (error) {
      _showMessage('Nhận diện ảnh mẫu thất bại: $error');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
      );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_asrSubscription?.cancel());
    if (_isListening) unawaited(_asrService.stop());
    if (_isAssistantRunning) {
      unawaited(_vlmService.cancel());
      unawaited(_outputManager.stop());
    }
    _stopStreaming(updateState: false);
    _frameHub.dispose();
    _aiEngineService.dispose();
    _ocrService.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bolt, color: Color(0xFF2CB67D)),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'YOLO26n Realtime (${_aiEngineService.modelBackendName})',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.camera_alt),
            onPressed: _captureSnapshotForVlm,
            tooltip: 'Lấy snapshot cho VLM',
          ),
          IconButton(
            icon: const Icon(Icons.image_search),
            onPressed: _detectSampleImage,
            tooltip: 'Thử ảnh mẫu assets',
          ),
          if (widget.cameras.length > 1)
            IconButton(
              icon: const Icon(Icons.switch_camera),
              onPressed: _switchCamera,
              tooltip: 'Đổi camera',
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            _errorMessage!,
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      );
    }

    if (!_isInitialized || _controller == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Đang khởi động camera stream và NCNN Engine...'),
          ],
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: Container(
            margin: const EdgeInsets.all(12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildCameraViewport(),
                  Positioned(
                    top: 12,
                    left: 12,
                    right: 12,
                    child: _buildRealtimeHudBanner(),
                  ),
                  Positioned(
                    right: 16,
                    bottom: 16,
                    child: FloatingActionButton.small(
                      heroTag: 'camera_voice_assistant',
                      tooltip: _isAssistantRunning
                          ? 'Dừng trợ lý'
                          : _isListening
                          ? 'Dừng nghe'
                          : 'Hỏi bằng tiếng Việt',
                      onPressed: _toggleVoiceAssistant,
                      backgroundColor: _isListening
                          ? Colors.redAccent
                          : const Color(0xFF7F5AF0),
                      child: Icon(
                        _isAssistantRunning
                            ? Icons.stop_rounded
                            : _isListening
                            ? Icons.mic
                            : Icons.mic_none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        _buildControlPanel(),
      ],
    );
  }

  Widget _buildCameraViewport() {
    final controller = _controller!;
    final camera = widget.cameras[_selectedCameraIndex];
    final previewSize = controller.value.previewSize ?? const Size(640, 480);

    // Kích thước khung hình đã nắn theo chiều xoay Portrait
    final rotatedWidth = math
        .min(previewSize.width, previewSize.height)
        .toInt();
    final rotatedHeight = math
        .max(previewSize.width, previewSize.height)
        .toInt();

    return Center(
      child: AspectRatio(
        aspectRatio: controller.value.aspectRatio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Preview trực tiếp từ camera phần cứng, KHÔNG encode/decode JPEG!
            CameraPreview(controller),
            // CustomPaint vẽ bounding boxes overlay
            CustomPaint(
              painter: DetectionPainter(
                detections: _currentDetections,
                imageWidth: rotatedWidth,
                imageHeight: rotatedHeight,
                sensorOrientation: camera.sensorOrientation,
                isFrontCamera:
                    camera.lensDirection == CameraLensDirection.front,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRealtimeHudBanner() {
    final m = _currentMetrics;
    final isGpu =
        m.backendName.contains('Vulkan') || m.backendName.contains('GPU');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(200),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isGpu ? const Color(0xFF2CB67D) : const Color(0xFFFF8E3C),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Camera: ${m.cameraFps.toStringAsFixed(1)} FPS • YOLO: ${m.processedFps.toStringAsFixed(1)} FPS',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Drop: ${m.dropRatePercent.toStringAsFixed(0)}%',
                style: TextStyle(
                  color: m.dropRatePercent > 35
                      ? Colors.orangeAccent
                      : Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Native: ${m.totalNativeMs.toStringAsFixed(1)} ms (Inf: ${m.inferenceMs.toStringAsFixed(1)} | Pre: ${m.preprocessMs.toStringAsFixed(1)} | Post: ${m.postprocessMs.toStringAsFixed(1)})',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${m.backendName} (${m.threadCount}T)',
                style: TextStyle(
                  color: isGpu
                      ? const Color(0xFF2CB67D)
                      : const Color(0xFFFF8E3C),
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildControlPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Row 1: Backend & Thread Selector
          Row(
            children: [
              // Backend selector
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<InferenceBackend>(
                      value: _selectedBackend,
                      isExpanded: true,
                      items: [
                        DropdownMenuItem(
                          value: InferenceBackend.auto,
                          child: Text(
                            _hasVulkan ? 'AUTO (Vulkan)' : 'AUTO (CPU)',
                          ),
                        ),
                        const DropdownMenuItem(
                          value: InferenceBackend.vulkan,
                          child: Text('Vulkan GPU'),
                        ),
                        const DropdownMenuItem(
                          value: InferenceBackend.cpu,
                          child: Text('CPU Pure'),
                        ),
                      ],
                      onChanged: _isModelLoading
                          ? null
                          : (newBackend) {
                              if (newBackend != null &&
                                  newBackend != _selectedBackend) {
                                setState(() {
                                  _selectedBackend = newBackend;
                                });
                                _loadModel();
                              }
                            },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Threads selector
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _selectedThreads,
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('Threads: AUTO')),
                      DropdownMenuItem(value: 2, child: Text('Threads: 2')),
                      DropdownMenuItem(value: 3, child: Text('Threads: 3')),
                      DropdownMenuItem(value: 4, child: Text('Threads: 4')),
                    ],
                    onChanged: _isModelLoading
                        ? null
                        : (threads) {
                            if (threads != null &&
                                threads != _selectedThreads) {
                              setState(() {
                                _selectedThreads = threads;
                              });
                              _loadModel();
                            }
                          },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Row 2: Stream Toggle & Action Buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isModelLoading
                      ? null
                      : () {
                          if (_isStreaming) {
                            _stopStreaming();
                          } else {
                            _startStreaming();
                          }
                        },
                  icon: Icon(_isStreaming ? Icons.pause : Icons.play_arrow),
                  label: Text(
                    _isStreaming ? 'Tạm dừng Stream' : 'Bật Realtime Stream',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isStreaming
                        ? Colors.blueGrey
                        : const Color(0xFF2CB67D),
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _captureSnapshotForVlm,
                icon: const Icon(Icons.center_focus_strong, size: 18),
                label: const Text('Snapshot VLM'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7F5AF0),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
