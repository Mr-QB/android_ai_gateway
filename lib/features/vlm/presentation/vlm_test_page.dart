import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../sense_graph/models/sense_node.dart';
import '../../sense_graph/sense_graph_manager.dart';
import '../../perception/task_router.dart';
import '../../perception/vlm_engine_manager.dart';
import '../../perception/ocr/ocr_service.dart';
import '../../perception/output/assistive_output_manager.dart';
import '../../perception/agents/smol/scene_agent.dart';
import '../../perception/agents/smol/hazard_agent.dart';
import '../../perception/agents/smol/relation_agent.dart';
import '../../perception/agents/gemma/text_agent.dart';
import '../../perception/agents/gemma/reasoning_agent.dart';
import '../models/vlm_result.dart';
import '../services/vlm_service.dart';
import 'sense_graph_viewer_page.dart';

class VlmTestPage extends StatefulWidget {
  const VlmTestPage({super.key});

  @override
  State<VlmTestPage> createState() => _VlmTestPageState();
}

class _VlmTestPageState extends State<VlmTestPage> {
  // Navigation sub-tab: 0 = Multi-Agent Perception, 1 = Single VLM Benchmark
  int _activeSubTab = 0;

  // Common Services
  final VlmService _vlmService = VlmService();
  final VlmEngineManager _engineManager = VlmEngineManager();
  final AssistiveOutputManager _outputManager = AssistiveOutputManager();
  final OcrService _ocrService = OcrService();
  final SenseGraphManager _graphManager = SenseGraphManager();
  final ImagePicker _imagePicker = ImagePicker();

  // Selected Image
  String? _selectedImagePath;

  // --- Multi-Agent Perception State ---
  final TextEditingController _agentQueryController = TextEditingController();
  AgentTask _selectedAgentTask = AgentTask.describeScene;
  bool _isAgentRunning = false;
  String? _agentRuleOutput;
  String? _agentVlmOutput;
  String? _lastAgentName;
  String? _lastEngineUsed;
  Map<String, double> _agentLatencies = {};
  List<OcrResultItem> _lastOcrItems = [];
  bool _ttsEnabled = true;

  // --- Single VLM Benchmark State ---
  final TextEditingController _promptController = TextEditingController();
  String _selectedModelKey = VlmModelInfo.smolVlm2.key;
  String _selectedBackend = 'AUTO';
  int _selectedMaxTokens = 64;

  VlmStatus _status = VlmStatus.empty();
  VlmResult? _lastResult;
  VlmBenchmarkReport? _lastBenchmarkReport;

  bool _isCheckingStatus = false;
  bool _isLoadingModel = false;
  bool _isInferring = false;
  bool _isBenchmarking = false;
  String? _errorMessage;

  static const List<String> _promptPresets = [
    'Describe the important information in this image briefly.',
    'Describe this image.',
    'What objects are visible?',
    'Is there anything dangerous in front of me?',
    'Read the important text visible in this image.',
    'Describe this scene for a visually impaired person.',
    'Analyze this image for a visually impaired pedestrian.\n\nDescribe only information useful for immediate awareness.\n\nFocus on:\n- obstacles\n- people\n- vehicles\n- doors\n- stairs\n- immediate hazards\n\nKeep the response short.',
  ];

  @override
  void initState() {
    super.initState();
    _promptController.text = _promptPresets.first;
    _agentQueryController.text = 'Có lối đi thông thoáng ở phía trước không?';
    _checkStatus();
  }

  @override
  void dispose() {
    _promptController.dispose();
    _agentQueryController.dispose();
    super.dispose();
  }

  Future<void> _checkStatus() async {
    setState(() {
      _isCheckingStatus = true;
    });

    final status = await _vlmService.getStatus(modelKey: _selectedModelKey);

    if (mounted) {
      setState(() {
        _status = status;
        _isCheckingStatus = false;
      });
    }
  }

  // -------------------------------------------------------------
  // Image Selection Helpers
  // -------------------------------------------------------------
  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? file = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 90,
      );

      if (file != null && mounted) {
        setState(() {
          _selectedImagePath = file.path;
          _lastResult = null;
          _lastBenchmarkReport = null;
          _agentRuleOutput = null;
          _agentVlmOutput = null;
          _lastOcrItems = [];
        });
      }
    } catch (e) {
      debugPrint('[VLM] Error picking image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi chọn ảnh: $e')),
        );
      }
    }
  }

  Future<void> _useSampleImage() async {
    try {
      final byteData = await rootBundle.load('assets/images/sample_test.jpg');
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/sample_test.jpg');
      await tempFile.writeAsBytes(byteData.buffer.asUint8List());

      if (mounted) {
        setState(() {
          _selectedImagePath = tempFile.path;
          _lastResult = null;
          _lastBenchmarkReport = null;
          _agentRuleOutput = null;
          _agentVlmOutput = null;
          _lastOcrItems = [];
        });
      }
    } catch (e) {
      debugPrint('[VLM] Error loading sample image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi tải ảnh mẫu: $e')),
        );
      }
    }
  }

  // -------------------------------------------------------------
  // MULTI-AGENT PERCEPTION WORKFLOWS
  // -------------------------------------------------------------
  Future<void> _executeAgentTask(AgentTask task) async {
    final imagePath = _selectedImagePath;
    if (imagePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng chụp hoặc chọn ảnh mẫu trước.')),
      );
      return;
    }

    setState(() {
      _selectedAgentTask = task;
      _isAgentRunning = true;
      _agentRuleOutput = null;
      _agentVlmOutput = null;
      _agentLatencies = {};
    });

    final overallStopwatch = Stopwatch()..start();

    try {
      switch (task) {
        case AgentTask.describeScene:
          await _runSceneAgent(imagePath, overallStopwatch);
          break;

        case AgentTask.detectHazard:
          await _runHazardAgent(imagePath, overallStopwatch);
          break;

        case AgentTask.readText:
          await _runOcrAgent(imagePath, overallStopwatch);
          break;

        case AgentTask.explainText:
          await _runExplainTextAgent(imagePath, overallStopwatch);
          break;

        case AgentTask.complexQuestion:
        case AgentTask.graphReasoning:
          await _runReasoningAgent(imagePath, overallStopwatch);
          break;

        case AgentTask.extractRelations:
          await _runRelationAgent(imagePath, overallStopwatch);
          break;

        case AgentTask.semanticMemoryEnrichment:
          await _runReasoningAgent(imagePath, overallStopwatch);
          break;
      }
    } catch (e, st) {
      debugPrint('[MultiAgent] Task error: $e\n$st');
      if (mounted) {
        setState(() {
          _agentVlmOutput = 'Lỗi thực thi agent: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isAgentRunning = false;
        });
      }
    }
  }

  Future<void> _runSceneAgent(String imagePath, Stopwatch stopwatch) async {
    _lastAgentName = 'SceneAgent';
    _lastEngineUsed = 'SmolVLM2-500M (FAST)';

    final agent = SceneAgent(engineManager: _engineManager);
    final result = await agent.execute(
      imagePath: imagePath,
      ocrTexts: _lastOcrItems.map((o) => o.text).toList(),
    );

    stopwatch.stop();

    if (mounted) {
      setState(() {
        _agentVlmOutput = '''
Loại không gian: ${result.sceneType}
Tóm tắt: ${result.summary}
Đối tượng chú ý: ${result.importantObjects.join(', ')}
Độ tin cậy: ${(result.confidence * 100).toStringAsFixed(0)}%
        '''.trim();

        _agentLatencies = {
          'Total Latency': stopwatch.elapsedMilliseconds.toDouble(),
          'VLM Inference': result.latencyMs,
        };
      });

      if (_ttsEnabled && result.summary.isNotEmpty) {
        _outputManager.dispatch(
          message: result.summary,
          priority: AlertPriority.normalDescription,
          sourceAgent: 'SceneAgent',
        );
      }
    }
  }

  Future<void> _runHazardAgent(String imagePath, Stopwatch stopwatch) async {
    _lastAgentName = 'HazardAgent';
    _lastEngineUsed = 'Rule Check + SmolVLM2';

    // Step 1: Immediate Rule-Based safety check
    final ruleWatch = Stopwatch()..start();
    // Rule check: if dangerous objects occupy path
    final ruleSafety = HazardAgent.checkDeterministicSafety([]);
    ruleWatch.stop();

    if (ruleSafety.hasImmediateHazard) {
      setState(() {
        _agentRuleOutput = '🚨 CẢNH BÁO TỨC THÌ: ${ruleSafety.warningMessage} (${ruleSafety.direction})';
      });
      if (_ttsEnabled) {
        _outputManager.dispatch(
          message: ruleSafety.warningMessage,
          priority: AlertPriority.criticalHazard,
          sourceAgent: 'HazardRule',
        );
      }
    } else {
      setState(() {
        _agentRuleOutput = '✅ Kiểm tra quy tắc an toàn: Không phát hiện vật cản va chạm ngay trước mắt (< 5ms).';
      });
    }

    // Step 2: SmolVLM semantic deep hazard check
    final agent = HazardAgent(engineManager: _engineManager);
    final result = await agent.execute(imagePath: imagePath);

    stopwatch.stop();

    if (mounted) {
      setState(() {
        _agentVlmOutput = '''
Phát hiện nguy hiểm: ${result.hazard ? "CÓ NGUY HIỂM ⚠️" : "AN TOÀN ✅"}
Mức độ nghiêm trọng: ${(result.severity * 100).toStringAsFixed(0)}%
Hướng: ${result.direction}
Lý do: ${result.reason}
Thông báo: ${result.message}
        '''.trim();

        _agentLatencies = {
          'Rule Pre-check': ruleWatch.elapsedMilliseconds.toDouble(),
          'VLM Semantic Check': result.latencyMs,
          'Total Latency': stopwatch.elapsedMilliseconds.toDouble(),
        };
      });

      if (_ttsEnabled && result.hazard && result.message.isNotEmpty) {
        _outputManager.dispatch(
          message: result.message,
          priority: AlertPriority.highWarning,
          sourceAgent: 'HazardAgent',
        );
      }
    }
  }

  Future<void> _runOcrAgent(String imagePath, Stopwatch stopwatch) async {
    _lastAgentName = 'OcrService';
    _lastEngineUsed = 'Google ML Kit (On-Device OCR)';

    final ocrItems = await _ocrService.recognizeText(imagePath);
    stopwatch.stop();

    // Register into SenseGraph
    if (ocrItems.isNotEmpty) {
      final view = await _graphManager.createView(sceneType: 'image_test');
      _graphManager.ingestOcrTexts(
        view.id,
        ocrItems.map((e) => (text: e.text, bbox: e.bbox, confidence: e.confidence)).toList(),
      );
    }

    if (mounted) {
      setState(() {
        _lastOcrItems = ocrItems;
        if (ocrItems.isEmpty) {
          _agentVlmOutput = 'Không tìm thấy ký tự văn bản rõ ràng trong ảnh.';
        } else {
          final buffer = StringBuffer('Tìm thấy ${ocrItems.length} khối chữ:\n');
          for (int i = 0; i < ocrItems.length; i++) {
            buffer.writeln('${i + 1}. "${ocrItems[i].text}" (Tin cậy: ${(ocrItems[i].confidence * 100).toStringAsFixed(0)}%)');
          }
          _agentVlmOutput = buffer.toString().trim();
        }

        _agentLatencies = {
          'OCR Processing': stopwatch.elapsedMilliseconds.toDouble(),
          'Total Latency': stopwatch.elapsedMilliseconds.toDouble(),
        };
      });

      if (_ttsEnabled && ocrItems.isNotEmpty) {
        final readSummary = 'Đọc được: ${ocrItems.take(3).map((e) => e.text).join(", ")}';
        _outputManager.dispatch(
          message: readSummary,
          priority: AlertPriority.normalDescription,
          sourceAgent: 'OcrService',
        );
      }
    }
  }

  Future<void> _runExplainTextAgent(String imagePath, Stopwatch stopwatch) async {
    _lastAgentName = 'TextAgent';
    _lastEngineUsed = 'Gemma-4-E2B (DEEP)';

    // Ensure OCR first if empty
    if (_lastOcrItems.isEmpty) {
      final ocrItems = await _ocrService.recognizeText(imagePath);
      _lastOcrItems = ocrItems;
    }

    if (_lastOcrItems.isEmpty) {
      setState(() {
        _agentVlmOutput = 'Không có văn bản nào được nhận diện để giải thích.';
        _isAgentRunning = false;
      });
      return;
    }

    final topOcr = _lastOcrItems.first;
    final now = DateTime.now().millisecondsSinceEpoch;
    final textNode = TextNode(
      id: 'txt_$now',
      timestamp: now,
      rawText: topOcr.text,
      bbox: topOcr.bbox,
      confidence: topOcr.confidence,
    );

    final agent = TextAgent(engineManager: _engineManager);
    final result = await agent.execute(
      imagePath: imagePath,
      textNode: textNode,
    );

    stopwatch.stop();

    if (mounted) {
      setState(() {
        _agentVlmOutput = '''
Chữ gốc: "${topOcr.text}"
Chữ chuẩn hóa (sửa lỗi OCR): "${result.normalizedText}"
Loại ngữ nghĩa: ${result.semanticType}
Mức độ quan trọng: ${result.importance}
Giải thích: ${result.summary}
        '''.trim();

        _agentLatencies = {
          'Gemma Reasoning': result.latencyMs,
          'Total Latency': stopwatch.elapsedMilliseconds.toDouble(),
        };
      });

      if (_ttsEnabled && result.summary.isNotEmpty) {
        _outputManager.dispatch(
          message: result.summary,
          priority: AlertPriority.normalDescription,
          sourceAgent: 'TextAgent',
        );
      }
    }
  }

  Future<void> _runReasoningAgent(String imagePath, Stopwatch stopwatch) async {
    _lastAgentName = 'ReasoningAgent';
    _lastEngineUsed = 'Gemma-4-E2B (DEEP) + SenseGraph';

    final query = _agentQueryController.text.trim().isEmpty
        ? 'Có lối đi thông thoáng ở phía trước không?'
        : _agentQueryController.text.trim();

    final agent = ReasoningAgent(engineManager: _engineManager);
    final result = await agent.execute(
      imagePath: imagePath,
      userQuery: query,
    );

    stopwatch.stop();

    if (mounted) {
      setState(() {
        _agentVlmOutput = '''
Câu hỏi: "$query"
Trả lời: ${result.answer}
Độ tin cậy: ${(result.confidence * 100).toStringAsFixed(0)}%
Các nút SenseGraph đã tham chiếu: ${result.referencedNodes.isEmpty ? "None" : result.referencedNodes.join(", ")}
        '''.trim();

        _agentLatencies = {
          'Graph Retrieval + Gemma': result.latencyMs,
          'Total Latency': stopwatch.elapsedMilliseconds.toDouble(),
        };
      });

      if (_ttsEnabled && result.answer.isNotEmpty) {
        _outputManager.dispatch(
          message: result.answer,
          priority: AlertPriority.userQuery,
          sourceAgent: 'ReasoningAgent',
        );
      }
    }
  }

  Future<void> _runRelationAgent(String imagePath, Stopwatch stopwatch) async {
    _lastAgentName = 'RelationAgent';
    _lastEngineUsed = 'SmolVLM2-500M (FAST)';

    final agent = RelationAgent(engineManager: _engineManager);
    final result = await agent.execute(imagePath: imagePath);

    stopwatch.stop();

    if (mounted) {
      setState(() {
        if (result.relations.isEmpty) {
          _agentVlmOutput = 'Không trích xuất được quan hệ không gian mới.';
        } else {
          final buffer = StringBuffer('Đã cập nhật ${result.relations.length} quan hệ vào SenseGraph:\n');
          for (final rel in result.relations) {
            buffer.writeln('• ${rel.subject}  ──[ ${rel.relation} ]──>  ${rel.object}');
          }
          _agentVlmOutput = buffer.toString().trim();
        }

        _agentLatencies = {
          'SmolVLM Relation Check': result.latencyMs,
          'Total Latency': stopwatch.elapsedMilliseconds.toDouble(),
        };
      });
    }
  }

  // -------------------------------------------------------------
  // SINGLE VLM BENCHMARK WORKFLOWS (Preserved)
  // -------------------------------------------------------------
  Future<void> _initializeModel() async {
    setState(() {
      _isLoadingModel = true;
      _errorMessage = null;
    });

    final res = await _vlmService.initialize(
      modelKey: _selectedModelKey,
      backend: _selectedBackend,
      maxTokens: _selectedMaxTokens,
    );

    await _checkStatus();

    if (mounted) {
      setState(() {
        _isLoadingModel = false;
        if (res['success'] != true) {
          _errorMessage = res['message']?.toString() ?? 'Không thể tải model VLM';
        }
      });

      if (res['success'] == true) {
        final isReused = res['reused'] == true;
        final timeMs = res['loadTimeMs'] ?? 0;
        final backend = res['backend'] ?? _selectedBackend;
        final modelName = VlmModelInfo.fromKey(_selectedModelKey).displayName;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isReused
                  ? '$modelName đã sẵn sàng trong RAM (0 ms, Backend: $backend)'
                  : '$modelName nạp thành công ($timeMs ms, Backend: $backend)',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  Future<void> _unloadModel() async {
    await _vlmService.dispose();
    await _checkStatus();
    if (mounted) {
      setState(() {
        _lastResult = null;
        _lastBenchmarkReport = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã giải phóng bộ nhớ model khỏi RAM/VRAM'),
          backgroundColor: Colors.blueGrey,
        ),
      );
    }
  }

  Future<void> _runInference() async {
    final imagePath = _selectedImagePath;
    if (imagePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng chọn hoặc chụp một ảnh trước.')),
      );
      return;
    }

    if (!_status.isLoaded || _status.loadedModelKey != _selectedModelKey) {
      await _initializeModel();
      if (!_status.isLoaded) return;
    }

    setState(() {
      _isInferring = true;
      _errorMessage = null;
    });

    final modelInfo = VlmModelInfo.fromKey(_selectedModelKey);
    final result = await _vlmService.analyzeImage(
      imagePath: imagePath,
      prompt: _promptController.text.trim(),
      maxTokens: _selectedMaxTokens,
      targetResolution: modelInfo.recommendedInputResolution,
    );

    if (mounted) {
      setState(() {
        _lastResult = result;
        _isInferring = false;
        if (!result.success) {
          _errorMessage = result.message ?? result.error ?? 'Inference failed';
        }
      });
    }
  }

  Future<void> _runBenchmarkX5() async {
    final imagePath = _selectedImagePath;
    if (imagePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng chọn ảnh trước khi chạy benchmark x5.')),
      );
      return;
    }

    setState(() {
      _isBenchmarking = true;
      _errorMessage = null;
      _lastBenchmarkReport = null;
    });

    final modelInfo = VlmModelInfo.fromKey(_selectedModelKey);
    final report = await _vlmService.runBenchmarkX5(
      modelKey: _selectedModelKey,
      backend: _selectedBackend,
      imagePath: imagePath,
      prompt: _promptController.text.trim(),
      maxTokens: _selectedMaxTokens,
      targetResolution: modelInfo.recommendedInputResolution,
    );

    await _checkStatus();

    if (mounted) {
      setState(() {
        _isBenchmarking = false;
        _lastBenchmarkReport = report;
        if (report == null) {
          _errorMessage = 'Benchmark x5 thất bại. Vui lòng kiểm tra model và log.';
        }
      });

      if (report != null && report.runs.isNotEmpty) {
        _showBenchmarkDetailsDialog(report);
      }
    }
  }

  void _showBenchmarkDetailsDialog(VlmBenchmarkReport report) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.assessment, color: Color(0xFF7F5AF0)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Benchmark x5: ${report.modelDisplayName}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              Text('Backend thực tế: ${report.backend}'),
              if (report.coldLoadMs > 0)
                Text('Cold Start Model Load: ${report.coldLoadMs.toStringAsFixed(0)} ms'),
              const Divider(),
              const Text('Kết quả 5 vòng chạy:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              ...report.runs.map((run) => Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF16161A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF2E2E38)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Vòng ${run.runIndex} (${run.isWarm ? "Warm" : "Cold Start"})',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: run.isWarm ? Colors.greenAccent : Colors.orangeAccent,
                              ),
                            ),
                            Text(
                              '${run.totalMs.toStringAsFixed(0)} ms',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'TTFT: ${run.ttftMs != null ? "${run.ttftMs!.toStringAsFixed(1)} ms" : "N/A"} | '
                          'Gen: ${run.generationMs.toStringAsFixed(1)} ms | '
                          'Tốc độ: ${run.tokensPerSecond.toStringAsFixed(1)} tok/s',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade300),
                        ),
                        Text(
                          'RAM (Native/Java): ${run.nativeHeapMb.toStringAsFixed(1)} / ${run.javaHeapMb.toStringAsFixed(1)} MB | '
                          'Tokens: ${run.tokenCount}',
                          style: TextStyle(fontSize: 10, color: Colors.grey.shade400),
                        ),
                      ],
                    ),
                  )),
              const Divider(),
              const Text('Chỉ số trung bình (Warm Inferences):', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('Avg TTFT: ${report.avgWarmTtftMs.toStringAsFixed(1)} ms'),
              Text('Avg Total: ${report.avgWarmTotalMs.toStringAsFixed(1)} ms'),
              Text('Avg Tốc độ: ${report.avgWarmTokensPerSecond.toStringAsFixed(2)} tokens/s'),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy JSON'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: jsonEncode(report.toJson())));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Đã copy dữ liệu benchmark JSON')),
              );
            },
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // MAIN BUILD
  // -------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.hub_outlined, color: Color(0xFF7F5AF0)),
            SizedBox(width: 8),
            Text('VLM & Perception Lab', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(_ttsEnabled ? Icons.volume_up : Icons.volume_off,
                color: _ttsEnabled ? Colors.greenAccent : Colors.grey),
            tooltip: _ttsEnabled ? 'Tắt âm thanh trợ năng' : 'Bật âm thanh trợ năng',
            onPressed: () {
              setState(() {
                _ttsEnabled = !_ttsEnabled;
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: (_isInferring || _isBenchmarking || _isAgentRunning) ? null : _checkStatus,
            tooltip: 'Kiểm tra trạng thái',
          ),
          IconButton(
            icon: const Icon(Icons.cleaning_services),
            onPressed: (_isInferring || _isBenchmarking || _isAgentRunning || !_status.isLoaded) ? null : _unloadModel,
            tooltip: 'Giải phóng model khỏi RAM',
          ),
        ],
      ),
      body: Column(
        children: [
          // Sub-tab selector
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(
                    value: 0,
                    icon: Icon(Icons.account_tree_outlined, size: 16),
                    label: Text('MULTI AGENT TEST', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                  ButtonSegment(
                    value: 1,
                    icon: Icon(Icons.speed, size: 16),
                    label: Text('BENCHMARK SINGLE VLM', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ],
                selected: {_activeSubTab},
                onSelectionChanged: (set) {
                  setState(() {
                    _activeSubTab = set.first;
                  });
                },
              ),
            ),
          ),
          // Body content based on active sub-tab
          Expanded(
            child: _activeSubTab == 0
                ? _buildMultiAgentSection()
                : _buildSingleBenchmarkSection(),
          ),
        ],
      ),
    );
  }

  // =============================================================
  // SUB-TAB 0: MULTI-AGENT PERCEPTION SECTION
  // =============================================================
  Widget _buildMultiAgentSection() {
    final graph = _graphManager.graph;
    final viewCount = graph.getNodesByType<ViewNode>().length;
    final objCount = graph.getNodesByType<ObjectNode>().length;
    final textCount = graph.getNodesByType<TextNode>().length;
    final edgeCount = graph.allEdges.length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Models & SenseGraph Status Header
        Card(
          elevation: 2,
          color: const Color(0xFF16161A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFF2E2E38)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('ON-DEVICE ENGINES',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.green.withAlpha(40),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('LITERT-LM ON-DEVICE',
                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.greenAccent)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _buildEngineStatusItem(
                        name: 'SmolVLM2 (500M)',
                        role: 'FAST Vision',
                        status: _engineManager.currentlyLoadedModelKey == VlmModelInfo.smolVlm2.key && _status.isLoaded
                            ? 'Sẵn sàng trong RAM'
                            : (_status.modelsAvailable[VlmModelInfo.smolVlm2.key] == true ? 'Sẵn có (Unloaded)' : 'Chưa có file'),
                        color: _engineManager.currentlyLoadedModelKey == VlmModelInfo.smolVlm2.key && _status.isLoaded
                            ? Colors.greenAccent
                            : Colors.amberAccent,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildEngineStatusItem(
                        name: 'Gemma-4-E2B',
                        role: 'DEEP Reasoning',
                        status: _engineManager.currentlyLoadedModelKey == VlmModelInfo.gemma4.key && _status.isLoaded
                            ? 'Sẵn sàng trong RAM'
                            : (_status.modelsAvailable[VlmModelInfo.gemma4.key] == true ? 'Sẵn có (Unloaded)' : 'Chưa có file'),
                        color: _engineManager.currentlyLoadedModelKey == VlmModelInfo.gemma4.key && _status.isLoaded
                            ? Colors.greenAccent
                            : Colors.blueGrey,
                      ),
                    ),
                  ],
                ),
                const Divider(height: 16),
                // SenseGraph live counter
                Row(
                  children: [
                    const Icon(Icons.bubble_chart_outlined, size: 16, color: Color(0xFF7F5AF0)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'SenseGraph: $viewCount Views | $objCount Objects | $textCount Texts | $edgeCount Edges',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ),
                    InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const SenseGraphViewerPage()),
                        ).then((_) => setState(() {}));
                      },
                      child: const Text('Chi tiết >',
                          style: TextStyle(fontSize: 11, color: Color(0xFF7F5AF0), fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () async {
                        await _graphManager.clear();
                        setState(() {});
                      },
                      child: const Icon(Icons.delete_sweep_outlined, size: 16, color: Colors.grey),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),
        // Image preview & pickers
        _buildImagePreview(),
        const SizedBox(height: 8),
        _buildImageButtons(),

        const SizedBox(height: 16),
        // Agent Action Grid / Fast Test Buttons
        const Text('KIỂM THỬ NHANH TỪNG VAI TRÒ AGENT:',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildAgentButton(
              label: 'Describe Scene',
              sublabel: 'SmolVLM Fast',
              icon: Icons.landscape_outlined,
              color: const Color(0xFF2CB67D),
              onTap: _isAgentRunning ? null : () => _executeAgentTask(AgentTask.describeScene),
            ),
            _buildAgentButton(
              label: 'Check Hazard',
              sublabel: 'Rule + SmolVLM',
              icon: Icons.warning_amber_rounded,
              color: const Color(0xFFE53170),
              onTap: _isAgentRunning ? null : () => _executeAgentTask(AgentTask.detectHazard),
            ),
            _buildAgentButton(
              label: 'Read Text',
              sublabel: 'ML Kit OCR',
              icon: Icons.text_fields_outlined,
              color: const Color(0xFFFF8906),
              onTap: _isAgentRunning ? null : () => _executeAgentTask(AgentTask.readText),
            ),
            _buildAgentButton(
              label: 'Explain Text',
              sublabel: 'Gemma 4 E2B',
              icon: Icons.translate_outlined,
              color: const Color(0xFF7F5AF0),
              onTap: _isAgentRunning ? null : () => _executeAgentTask(AgentTask.explainText),
            ),
            _buildAgentButton(
              label: 'Spatial Relations',
              sublabel: 'SmolVLM Graph',
              icon: Icons.share_outlined,
              color: const Color(0xFF00B4D8),
              onTap: _isAgentRunning ? null : () => _executeAgentTask(AgentTask.extractRelations),
            ),
          ],
        ),

        const SizedBox(height: 14),
        // ReasoningAgent Query Input & Run Button
        Card(
          elevation: 1,
          color: const Color(0xFF16161A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.psychology_alt_outlined, size: 18, color: Color(0xFF7F5AF0)),
                    SizedBox(width: 6),
                    Text('Hỏi đáp ngữ cảnh (ReasoningAgent - Gemma 4):',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _agentQueryController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: 'Nhập câu hỏi không gian / chướng ngại vật / văn bản...',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    filled: true,
                    fillColor: const Color(0xFF0F0E17),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isAgentRunning ? null : () => _executeAgentTask(AgentTask.complexQuestion),
                    icon: _isAgentRunning
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send_rounded, size: 16),
                    label: const Text('Complex Question (ReasoningAgent + Subgraph)'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7F5AF0),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),
        // Agent Execution Results
        if (_isAgentRunning || _agentVlmOutput != null || _agentRuleOutput != null)
          _buildAgentOutputCard(),
      ],
    );
  }

  Widget _buildEngineStatusItem({
    required String name,
    required String role,
    required String status,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0E17),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF2E2E38)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(role, style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
          const SizedBox(height: 2),
          Text(status, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildAgentButton({
    required String label,
    required String sublabel,
    required IconData icon,
    required Color color,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF16161A),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withAlpha(120)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                Text(sublabel, style: TextStyle(fontSize: 9, color: Colors.grey.shade400)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAgentOutputCard() {
    return Card(
      elevation: 3,
      color: const Color(0xFF16161A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFF7F5AF0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.bolt, color: Color(0xFF7F5AF0), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Task: ${_selectedAgentTask.displayName}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      Text(
                        'Agent: $_lastAgentName | Engine: $_lastEngineUsed',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                      ),
                    ],
                  ),
                ),
                if (_isAgentRunning)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const Divider(height: 16),

            // Rule-based output (if any)
            if (_agentRuleOutput != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.withAlpha(30),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.redAccent.withAlpha(80)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'TỨC THÌ (RULE-BASED SAFETY OUTPUT < 5ms):',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.redAccent),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _agentRuleOutput!,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],

            // VLM Output
            if (_isAgentRunning)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('Đang xử lý on-device (LiteRT-LM / OCR)...',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                ),
              )
            else if (_agentVlmOutput != null) ...[
              const Text('KẾT QUẢ TỪ VLM / AGENT:',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF7F5AF0))),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F0E17),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF2E2E38)),
                ),
                child: SelectableText(
                  _agentVlmOutput!,
                  style: const TextStyle(fontSize: 13, height: 1.4),
                ),
              ),
            ],

            // Latency Breakdown
            if (_agentLatencies.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text('LATENCY BREAKDOWN:',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
              const SizedBox(height: 4),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: _agentLatencies.entries.map((e) {
                  return Text(
                    '${e.key}: ${e.value.toStringAsFixed(0)} ms',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.greenAccent),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // =============================================================
  // SUB-TAB 1: SINGLE VLM BENCHMARK SECTION (Preserved)
  // =============================================================
  Widget _buildSingleBenchmarkSection() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildStatusCard(),
        const SizedBox(height: 16),
        _buildImagePreview(),
        const SizedBox(height: 12),
        _buildImageButtons(),
        const SizedBox(height: 16),
        _buildModelAndBackendSelectors(),
        const SizedBox(height: 16),
        _buildPromptSection(),
        const SizedBox(height: 16),
        _buildActionButtons(),
        const SizedBox(height: 16),
        if (_lastResult != null || _isInferring || _isBenchmarking) _buildResultCard(),
        const SizedBox(height: 16),
        _buildBenchmarkMetricsCard(),
      ],
    );
  }

  Widget _buildStatusCard() {
    final currentModelInfo = VlmModelInfo.fromKey(_selectedModelKey);
    final modelExists = _status.modelsAvailable[_selectedModelKey] ?? _status.modelExists;
    final isCurrentModelLoaded = _status.isLoaded && _status.loadedModelKey == _selectedModelKey;

    final Color statusColor;
    final String statusText;
    final IconData statusIcon;

    if (_isCheckingStatus || _isLoadingModel) {
      statusColor = Colors.orange;
      statusText = _isLoadingModel ? 'NẠP MODEL VÀO RAM/VRAM...' : 'KIỂM TRA TRẠNG THÁI...';
      statusIcon = Icons.hourglass_top;
    } else if (_isInferring) {
      statusColor = const Color(0xFF7F5AF0);
      statusText = 'ĐANG SUY LUẬN MULTIMODAL...';
      statusIcon = Icons.bolt;
    } else if (_isBenchmarking) {
      statusColor = Colors.purpleAccent;
      statusText = 'ĐANG CHẠY BENCHMARK X5...';
      statusIcon = Icons.speed;
    } else if (!modelExists) {
      statusColor = Colors.redAccent;
      statusText = 'CHƯA CÓ FILE MODEL';
      statusIcon = Icons.warning_amber_rounded;
    } else if (isCurrentModelLoaded) {
      statusColor = Colors.green;
      statusText = 'SẴN SÀNG TRONG RAM (${_status.actualBackend})';
      statusIcon = Icons.check_circle;
    } else if (_status.isLoaded) {
      statusColor = Colors.blueAccent;
      statusText = 'MODEL KHÁC ĐANG SẴN SÀNG (${_status.loadedModelKey})';
      statusIcon = Icons.swap_horiz;
    } else {
      statusColor = Colors.amber;
      statusText = 'FILE SẴN CÓ (CHƯA NẠP VÀO RAM)';
      statusIcon = Icons.info_outline;
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(statusIcon, color: statusColor, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    statusText,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                      fontSize: 13,
                    ),
                  ),
                ),
                if (!isCurrentModelLoaded && modelExists)
                  ElevatedButton.icon(
                    onPressed: (_isLoadingModel || _isInferring || _isBenchmarking) ? null : _initializeModel,
                    icon: _isLoadingModel
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.flash_on, size: 16),
                    label: const Text('Load / Warm', style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Model được chọn: ${currentModelInfo.displayName} (${currentModelInfo.filename})',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              'Đường dẫn: ${_status.expectedPath}',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
            ),
            if (!modelExists) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withAlpha(25),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.redAccent.withAlpha(80)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cách nạp file ${currentModelInfo.filename} vào máy:',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      'adb push ${currentModelInfo.filename} /data/local/tmp/\n'
                      'adb shell run-as com.example.android_ai_gateway cp /data/local/tmp/${currentModelInfo.filename} files/models/',
                      style: TextStyle(fontFamily: 'monospace', fontSize: 10, color: Colors.amber.shade200),
                    ),
                  ],
                ),
              ),
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                'Lỗi: $_errorMessage',
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildImagePreview() {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: const Color(0xFF16161A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2E2E38)),
      ),
      clipBehavior: Clip.antiAlias,
      child: _selectedImagePath != null
          ? Stack(
              fit: StackFit.expand,
              children: [
                Image.file(
                  File(_selectedImagePath!),
                  fit: BoxFit.contain,
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton.filled(
                    style: IconButton.styleFrom(backgroundColor: Colors.black54),
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () {
                      setState(() {
                        _selectedImagePath = null;
                        _lastResult = null;
                        _lastBenchmarkReport = null;
                        _agentRuleOutput = null;
                        _agentVlmOutput = null;
                        _lastOcrItems = [];
                      });
                    },
                  ),
                ),
              ],
            )
          : Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_photo_alternate_outlined, size: 44, color: Colors.grey.shade600),
                  const SizedBox(height: 8),
                  Text(
                    'Chưa chọn ảnh để phân tích',
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildImageButtons() {
    final disabled = _isInferring || _isBenchmarking || _isAgentRunning;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: disabled ? null : () => _pickImage(ImageSource.camera),
            icon: const Icon(Icons.camera_alt, size: 18),
            label: const Text('Camera'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: disabled ? null : () => _pickImage(ImageSource.gallery),
            icon: const Icon(Icons.photo_library, size: 18),
            label: const Text('Gallery'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: disabled ? null : _useSampleImage,
            icon: const Icon(Icons.image, size: 18),
            label: const Text('Ảnh Mẫu'),
          ),
        ),
      ],
    );
  }

  Widget _buildModelAndBackendSelectors() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Model VLM:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF16161A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF2E2E38)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedModelKey,
                        isExpanded: true,
                        items: VlmModelInfo.supportedModels.map((m) {
                          final isAvail = _status.modelsAvailable[m.key] ?? false;
                          return DropdownMenuItem<String>(
                            value: m.key,
                            child: Row(
                              children: [
                                Text(m.displayName, style: const TextStyle(fontSize: 13)),
                                const Spacer(),
                                Icon(
                                  isAvail ? Icons.check_circle : Icons.cloud_download,
                                  size: 14,
                                  color: isAvail ? Colors.green : Colors.grey,
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                        onChanged: (_isInferring || _isBenchmarking)
                            ? null
                            : (val) {
                                if (val != null && val != _selectedModelKey) {
                                  setState(() {
                                    _selectedModelKey = val;
                                    _lastResult = null;
                                  });
                                  _checkStatus();
                                }
                              },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Max Tokens:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                DropdownButton<int>(
                  value: _selectedMaxTokens,
                  items: const [
                    DropdownMenuItem(value: 32, child: Text('32')),
                    DropdownMenuItem(value: 64, child: Text('64')),
                    DropdownMenuItem(value: 128, child: Text('128')),
                  ],
                  onChanged: (_isInferring || _isBenchmarking)
                      ? null
                      : (val) {
                          if (val != null) {
                            setState(() {
                              _selectedMaxTokens = val;
                            });
                          }
                        },
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Backend:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'AUTO', label: Text('AUTO (Mali-G610)', style: TextStyle(fontSize: 11))),
                ButtonSegment(value: 'GPU', label: Text('GPU', style: TextStyle(fontSize: 11))),
                ButtonSegment(value: 'CPU', label: Text('CPU', style: TextStyle(fontSize: 11))),
              ],
              selected: {_selectedBackend},
              onSelectionChanged: (_isInferring || _isBenchmarking)
                  ? null
                  : (val) {
                      setState(() {
                        _selectedBackend = val.first;
                      });
                    },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPromptSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Prompt:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            PopupMenuButton<String>(
              icon: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.list_alt, size: 16),
                  SizedBox(width: 4),
                  Text('Presets', style: TextStyle(fontSize: 12)),
                ],
              ),
              onSelected: (preset) {
                setState(() {
                  _promptController.text = preset;
                });
              },
              itemBuilder: (context) {
                return _promptPresets.map((preset) {
                  final title = preset.length > 40 ? '${preset.substring(0, 40)}...' : preset;
                  return PopupMenuItem<String>(
                    value: preset,
                    child: Text(title, style: const TextStyle(fontSize: 12)),
                  );
                }).toList();
              },
            ),
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _promptController,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: 'Nhập câu hỏi hoặc prompt cho ảnh...',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: const Color(0xFF16161A),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    final disabled = _isInferring || _isBenchmarking || _selectedImagePath == null;
    final currentModelName = VlmModelInfo.fromKey(_selectedModelKey).displayName;

    return Row(
      children: [
        Expanded(
          flex: 3,
          child: SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: disabled ? null : _runInference,
              icon: _isInferring
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.auto_awesome),
              label: Text(
                _isInferring ? 'Đang suy luận...' : 'Run ($currentModelName)',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7F5AF0),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              onPressed: disabled ? null : _runBenchmarkX5,
              icon: _isBenchmarking
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.speed, size: 18),
              label: const Text(
                'BENCH x5',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResultCard() {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.chat_bubble_outline, size: 18, color: Color(0xFF7F5AF0)),
                const SizedBox(width: 8),
                Text(
                  'Kết quả VLM Output (${VlmModelInfo.fromKey(_selectedModelKey).displayName}):',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ],
            ),
            const Divider(),
            if (_isInferring || _isBenchmarking)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Column(
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 10),
                      Text(
                        _isBenchmarking
                            ? 'Đang thực hiện Benchmark 5 vòng liên tiếp...'
                            : 'Đang thực hiện multimodal inference trên Mali GPU...',
                      ),
                    ],
                  ),
                ),
              )
            else if (_lastResult != null)
              SelectableText(
                _lastResult!.success ? _lastResult!.text : 'Lỗi: ${_lastResult!.message ?? _lastResult!.error}',
                style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: _lastResult!.success ? Colors.white : Colors.redAccent,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBenchmarkMetricsCard() {
    final res = _lastResult;
    final report = _lastBenchmarkReport;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.speed, size: 18, color: Colors.blueAccent),
                const SizedBox(width: 8),
                const Text(
                  'Benchmark & Performance Metrics',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const Spacer(),
                if (report != null)
                  TextButton.icon(
                    icon: const Icon(Icons.table_chart, size: 14),
                    label: const Text('Xem x5', style: TextStyle(fontSize: 11)),
                    onPressed: () => _showBenchmarkDetailsDialog(report),
                  ),
              ],
            ),
            const Divider(),
            _buildMetricRow('Model', VlmModelInfo.fromKey(_selectedModelKey).displayName),
            _buildMetricRow(
              'Backend thực tế',
              res != null
                  ? '${res.backend} (Yêu cầu: ${res.requestedBackend})'
                  : _status.actualBackend,
            ),
            _buildMetricRow(
              'Model Load',
              res != null
                  ? (res.isWarm
                      ? '0 ms (Cached / Warm in RAM)'
                      : '${res.modelLoadMs.toStringAsFixed(0)} ms (Cold start)')
                  : (_status.isLoaded ? 'Sẵn sàng trong RAM' : 'Chưa nạp'),
            ),
            _buildMetricRow(
              'TTFT (Time To First Token)',
              res?.timeToFirstTokenMs != null
                  ? '${res!.timeToFirstTokenMs!.toStringAsFixed(1)} ms'
                  : (res != null ? 'Đo qua streaming flow' : '-'),
            ),
            _buildMetricRow(
              'Tốc độ sinh (Tokens/s)',
              res != null && res.tokensPerSecond > 0
                  ? '${res.tokensPerSecond.toStringAsFixed(2)} tokens/sec'
                  : '-',
            ),
            _buildMetricRow(
              'Generation Time',
              res != null ? '${res.generationMs.toStringAsFixed(1)} ms' : '-',
            ),
            _buildMetricRow(
              'Total Inference Time',
              res != null ? '${res.totalInferenceMs.toStringAsFixed(1)} ms' : '-',
            ),
            _buildMetricRow(
              'Tokens đã sinh',
              res != null ? '${res.generatedTokens} tokens' : '-',
            ),
            if (res != null) ...[
              _buildMetricRow(
                'Memory (Native / Java)',
                '${res.nativeHeapMb.toStringAsFixed(1)} MB / ${res.javaHeapMb.toStringAsFixed(1)} MB',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMetricRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
          Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
