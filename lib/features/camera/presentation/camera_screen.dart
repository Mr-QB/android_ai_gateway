import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../../ai_engine/domain/ai_inference_result.dart';
import '../../ai_engine/services/ai_engine_service.dart';

class CameraScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const CameraScreen({super.key, required this.cameras});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  final AIEngineService _aiEngineService = AIEngineService();

  bool _isInitialized = false;
  int _selectedCameraIndex = 0;
  String? _errorMessage;
  int _engineVersion = -1;
  AIInferenceResultModel? lastResult;

  @override
  void initState() {
    super.initState();
    _engineVersion = _aiEngineService.getVersion();
    if (widget.cameras.isNotEmpty) {
      _initCamera(_selectedCameraIndex);
    } else {
      setState(() {
        _errorMessage = 'Không tìm thấy camera nào trên thiết bị.';
      });
    }
  }

  Future<void> _initCamera(int cameraIndex) async {
    if (widget.cameras.isEmpty) return;

    setState(() {
      _isInitialized = false;
      _errorMessage = null;
    });

    final camera = widget.cameras[cameraIndex];
    final controller = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: false,
    );

    try {
      await controller.initialize();
      if (!mounted) return;

      setState(() {
        _controller = controller;
        _isInitialized = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Lỗi khởi tạo Camera: $e';
      });
    }
  }

  void _switchCamera() {
    if (widget.cameras.length < 2) return;
    _selectedCameraIndex = (_selectedCameraIndex + 1) % widget.cameras.length;
    _controller?.dispose();
    _initCamera(_selectedCameraIndex);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.memory, color: Color(0xFF7F5AF0)),
            SizedBox(width: 8),
            Text('Android AI Gateway'),
          ],
        ),
        actions: [
          if (widget.cameras.length > 1)
            IconButton(
              icon: const Icon(Icons.switch_camera),
              onPressed: _switchCamera,
              tooltip: 'Đổi Camera',
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
          padding: const EdgeInsets.all(16.0),
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
            Text('Đang kết nối Camera & AI Engine...'),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Camera Viewport
        Expanded(
          child: Stack(
            children: [
              Container(
                margin: const EdgeInsets.all(12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Center(
                    child: CameraPreview(_controller!),
                  ),
                ),
              ),
              // AI Native Status Overlay Banner
              Positioned(
                top: 24,
                left: 24,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(190),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _aiEngineService.isNativeLoaded
                          ? const Color(0xFF2CB67D)
                          : const Color(0xFFFF5470),
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _aiEngineService.isNativeLoaded
                            ? Icons.check_circle
                            : Icons.warning,
                        size: 16,
                        color: _aiEngineService.isNativeLoaded
                            ? const Color(0xFF2CB67D)
                            : const Color(0xFFFF5470),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _aiEngineService.isNativeLoaded
                            ? 'C++ Engine v$_engineVersion (Loaded)'
                            : 'C++ Engine (Not Loaded)',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // AI Control & Diagnostic Bar
        Container(
          padding: const EdgeInsets.all(16),
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Chip(
                avatar: const Icon(Icons.videocam, size: 16),
                label: Text(widget.cameras[_selectedCameraIndex].name),
              ),
              ElevatedButton.icon(
                onPressed: _aiEngineService.isNativeLoaded
                    ? () {
                        // Demo trigger C++ process frame
                        final dummyBytes = Uint8List(640 * 480 * 3);
                        final result = _aiEngineService.processFrame(
                          bytes: dummyBytes,
                          width: 640,
                          height: 480,
                          format: 0,
                        );
                        setState(() {
                          lastResult = result;
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'C++ Inference: ${result.inferenceTimeMs.toStringAsFixed(2)}ms | Conf: ${(result.confidence * 100).toStringAsFixed(0)}%',
                            ),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      }
                    : null,
                icon: const Icon(Icons.bolt),
                label: const Text('Test C++ AI'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7F5AF0),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
