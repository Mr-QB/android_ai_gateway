import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/slam_enums.dart';
import '../domain/slam_pose.dart';
import '../domain/slam_status.dart';
import '../services/slam_service.dart';
import 'widgets/slam_status_panel.dart';
import 'widgets/trajectory_painter.dart';

class VisualSlamScreen extends StatefulWidget {
  const VisualSlamScreen({super.key});

  @override
  State<VisualSlamScreen> createState() => _VisualSlamScreenState();
}

class _VisualSlamScreenState extends State<VisualSlamScreen> {
  final SlamService _slam = SlamService.instance;
  Timer? _pollTimer;

  // Configuration controllers
  late final TextEditingController _vocabPathCtrl;
  late final TextEditingController _settingsPathCtrl;
  late final TextEditingController _datasetPathCtrl;

  SlamSensorMode _sensorMode = SlamSensorMode.monocular;
  SlamReplayMode _replayMode = SlamReplayMode.realtime;
  double _speedFactor = 1.0;

  SlamStatus _status = SlamStatus.uninitialized();
  SlamPose? _currentPose;
  List<SlamPose> _trajectory = [];

  bool _isBusy = false;
  String? _bannerMessage;
  bool _bannerIsError = false;
  bool _pathsExpanded = false;

  @override
  void initState() {
    super.initState();
    _vocabPathCtrl = TextEditingController();
    _settingsPathCtrl = TextEditingController();
    _datasetPathCtrl = TextEditingController();

    _initDefaultPaths();
    _startPolling();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _vocabPathCtrl.dispose();
    _settingsPathCtrl.dispose();
    _datasetPathCtrl.dispose();
    super.dispose();
  }

  Future<void> _initDefaultPaths() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final baseDir = appDir.path;

      // Extract bundled configs if not present
      final monoYamlPath = '$baseDir/euroc_monocular.yaml';
      final monoImuYamlPath = '$baseDir/euroc_mono_inertial.yaml';

      await _extractAssetIfMissing('assets/slam/euroc_monocular.yaml', monoYamlPath);
      await _extractAssetIfMissing('assets/slam/euroc_mono_inertial.yaml', monoImuYamlPath);

      if (mounted) {
        setState(() {
          _vocabPathCtrl.text = '$baseDir/ORBvoc.txt';
          _settingsPathCtrl.text = (_sensorMode == SlamSensorMode.monoInertial)
              ? monoImuYamlPath
              : monoYamlPath;
          _datasetPathCtrl.text = '$baseDir/MH_01_easy/mav0';
        });
      }
    } catch (e) {
      debugPrint('[VisualSlamScreen] Path init error: $e');
    }
  }

  Future<void> _extractAssetIfMissing(String assetPath, String targetPath) async {
    final file = File(targetPath);
    if (!await file.exists()) {
      try {
        final data = await rootBundle.load(assetPath);
        final bytes = data.buffer.asUint8List();
        await file.writeAsBytes(bytes, flush: true);
      } catch (e) {
        debugPrint('[VisualSlamScreen] Could not extract $assetPath: $e');
      }
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 66), (_) {
      if (!mounted) return;
      if (!_slam.isNativeLoaded) return;

      final currentStatus = _slam.getStatus();
      final currentPose = _slam.getPose();

      // Only fetch trajectory when running or completed
      List<SlamPose> traj = _trajectory;
      if (currentStatus.runState == SlamRunState.running ||
          currentStatus.runState == SlamRunState.paused ||
          currentStatus.runState == SlamRunState.completed) {
        traj = _slam.getTrajectory(maxPoints: 2000);
      }

      setState(() {
        _status = currentStatus;
        _currentPose = currentPose;
        _trajectory = traj;
      });
    });
  }

  void _showMessage(String msg, {bool isError = false}) {
    setState(() {
      _bannerMessage = msg;
      _bannerIsError = isError;
    });
  }

  Future<void> _handleInitialize() async {
    if (_isBusy) return;
    setState(() => _isBusy = true);
    _showMessage('Initializing ORB-SLAM3 native engine...');

    final res = await _slam.initialize(
      vocabularyPath: _vocabPathCtrl.text.trim(),
      settingsPath: _settingsPathCtrl.text.trim(),
      sensorMode: _sensorMode,
    );

    setState(() => _isBusy = false);
    if (res.isSuccess) {
      _showMessage('ORB-SLAM3 initialized successfully!');
    } else {
      _showMessage('Initialization failed: ${res.message}', isError: true);
    }
  }

  Future<void> _handleLoadDataset() async {
    if (_isBusy) return;
    setState(() => _isBusy = true);
    _showMessage('Parsing EuRoC dataset files...');

    final res = await _slam.loadDataset(
      datasetPath: _datasetPathCtrl.text.trim(),
      sensorMode: _sensorMode,
    );

    setState(() => _isBusy = false);
    if (res.isSuccess) {
      _showMessage('Dataset loaded: ${_status.totalFrames} camera frames parsed');
    } else {
      _showMessage('Dataset load failed: ${res.message}', isError: true);
    }
  }

  void _handleStartReplay() {
    final res = _slam.startReplay(
      mode: _replayMode,
      speedFactor: _speedFactor,
    );
    if (res.isSuccess) {
      _showMessage('Replay started (${_replayMode.name} ${_speedFactor}x)');
    } else {
      _showMessage('Start failed: ${res.message}', isError: true);
    }
  }

  void _handlePauseResume() {
    if (_status.runState == SlamRunState.paused) {
      final res = _slam.resumeReplay();
      if (res.isSuccess) _showMessage('Replay resumed');
    } else if (_status.runState == SlamRunState.running) {
      final res = _slam.pauseReplay();
      if (res.isSuccess) _showMessage('Replay paused');
    }
  }

  void _handleStop() {
    final res = _slam.stopReplay();
    if (res.isSuccess) _showMessage('Replay stopped');
  }

  void _handleReset() {
    final res = _slam.reset();
    if (res.isSuccess) {
      setState(() {
        _trajectory = [];
        _currentPose = null;
      });
      _showMessage('SLAM system reset cleanly');
    } else {
      _showMessage('Reset failed: ${res.message}', isError: true);
    }
  }

  void _onSensorModeChanged(SlamSensorMode mode) {
    if (_status.runState == SlamRunState.running) return;
    setState(() {
      _sensorMode = mode;
      // Auto switch default yaml
      final current = _settingsPathCtrl.text;
      if (mode == SlamSensorMode.monoInertial) {
        _settingsPathCtrl.text = current.replaceAll('euroc_monocular.yaml', 'euroc_mono_inertial.yaml');
      } else {
        _settingsPathCtrl.text = current.replaceAll('euroc_mono_inertial.yaml', 'euroc_monocular.yaml');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isRunning = _status.runState == SlamRunState.running;
    final isPaused = _status.runState == SlamRunState.paused;
    final isReady = _status.runState == SlamRunState.ready;
    final isStopped = _status.runState == SlamRunState.stopped;
    final isCompleted = _status.runState == SlamRunState.completed;
    final canStart = (isReady || isStopped || isCompleted) && !_isBusy;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E17),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1522),
        elevation: 0,
        title: Row(
          children: [
            const Icon(Icons.hub_outlined, color: Color(0xFF38BDF8), size: 22),
            const SizedBox(width: 8),
            const Text(
              'Visual SLAM',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _slam.isNativeLoaded
                    ? const Color(0xFF10B981).withValues(alpha: 0.15)
                    : const Color(0xFFEF4444).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                _slam.isNativeLoaded ? 'liborbslam: OK' : 'liborbslam: Missing',
                style: TextStyle(
                  color: _slam.isNativeLoaded ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Top: Trajectory Viewport (Fixed aspect ratio 16:10)
            Expanded(
              flex: 5,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: TrajectoryPainter(
                        trajectory: _trajectory,
                        currentPose: _currentPose,
                      ),
                    ),
                  ),
                  // Overlay: Viewport Info Legend
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Row(
                        children: [
                          const Text(
                            'Top-Down X-Z',
                            style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Points: ${_trajectory.length}',
                            style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Banner notification
                  if (_bannerMessage != null)
                    Positioned(
                      bottom: 8,
                      left: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: _bannerIsError
                              ? const Color(0xFF991B1B).withValues(alpha: 0.9)
                              : const Color(0xFF1E293B).withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: _bannerIsError ? const Color(0xFFEF4444) : const Color(0xFF38BDF8),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _bannerIsError ? Icons.error_outline : Icons.info_outline,
                              size: 14,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _bannerMessage!,
                                style: const TextStyle(color: Colors.white, fontSize: 11),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            GestureDetector(
                              onTap: () => setState(() => _bannerMessage = null),
                              child: const Icon(Icons.close, size: 14, color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Bottom: Scrollable Dashboard & Controls
            Expanded(
              flex: 6,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                children: [
                  // Status panel
                  SlamStatusPanel(
                    status: _status,
                    pose: _currentPose,
                  ),
                  const SizedBox(height: 12),

                  // Mode Selectors (Sensor mode & Replay mode)
                  _buildModeSelectors(isRunning),
                  const SizedBox(height: 12),

                  // Control Action Buttons
                  _buildActionControls(isRunning, isPaused, canStart),
                  const SizedBox(height: 10),

                  // Paths Collapsible Card
                  _buildPathSettingsCard(isRunning),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeSelectors(bool isRunning) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF131A26),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sensor Mode Chips
          Row(
            children: [
              const Text('Sensor: ', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              _buildSensorChip('Monocular', SlamSensorMode.monocular, isRunning),
              const SizedBox(width: 8),
              _buildSensorChip('Mono + IMU', SlamSensorMode.monoInertial, isRunning),
            ],
          ),
          const SizedBox(height: 10),

          // Replay Speed Chips
          Row(
            children: [
              const Text('Speed: ', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              _buildSpeedChip('0.5x', SlamReplayMode.realtime, 0.5, isRunning),
              const SizedBox(width: 6),
              _buildSpeedChip('1.0x', SlamReplayMode.realtime, 1.0, isRunning),
              const SizedBox(width: 6),
              _buildSpeedChip('2.0x', SlamReplayMode.realtime, 2.0, isRunning),
              const SizedBox(width: 6),
              _buildSpeedChip('Max FPS', SlamReplayMode.maximumSpeed, 1.0, isRunning),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSensorChip(String label, SlamSensorMode mode, bool isRunning) {
    final selected = _sensorMode == mode;
    return GestureDetector(
      onTap: isRunning ? null : () => _onSensorModeChanged(mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF0284C7) : const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? const Color(0xFF38BDF8) : const Color(0xFF334155),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : const Color(0xFF94A3B8),
            fontSize: 11,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildSpeedChip(String label, SlamReplayMode mode, double factor, bool isRunning) {
    final selected = _replayMode == mode && (mode == SlamReplayMode.maximumSpeed || _speedFactor == factor);
    return GestureDetector(
      onTap: isRunning
          ? null
          : () {
              setState(() {
                _replayMode = mode;
                _speedFactor = factor;
              });
            },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF8B5CF6) : const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? const Color(0xFFA78BFA) : const Color(0xFF334155),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : const Color(0xFF94A3B8),
            fontSize: 11,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildActionControls(bool isRunning, bool isPaused, bool canStart) {
    return Row(
      children: [
        // Init Button
        Expanded(
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: isRunning || _isBusy ? null : _handleInitialize,
            icon: _isBusy
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.settings_suggest, size: 16),
            label: const Text('Init', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(width: 8),

        // Load Dataset Button
        Expanded(
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0D9488),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: isRunning || _isBusy ? null : _handleLoadDataset,
            icon: const Icon(Icons.folder_open, size: 16),
            label: const Text('Load', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(width: 8),

        // Start / Pause / Resume Button
        if (canStart)
          Expanded(
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF16A34A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: _handleStartReplay,
              icon: const Icon(Icons.play_arrow, size: 16),
              label: const Text('Start', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          )
        else
          Expanded(
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: isPaused ? const Color(0xFF16A34A) : const Color(0xFFD97706),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: (isRunning || isPaused) ? _handlePauseResume : null,
              icon: Icon(isPaused ? Icons.play_arrow : Icons.pause, size: 16),
              label: Text(isPaused ? 'Resume' : 'Pause', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ),
        const SizedBox(width: 8),

        // Stop Button
        IconButton.filled(
          style: IconButton.styleFrom(
            backgroundColor: (isRunning || isPaused) ? const Color(0xFFDC2626) : const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: (isRunning || isPaused) ? _handleStop : null,
          icon: const Icon(Icons.stop, size: 18, color: Colors.white),
          tooltip: 'Stop',
        ),
        const SizedBox(width: 4),

        // Reset Button
        IconButton.filled(
          style: IconButton.styleFrom(
            backgroundColor: const Color(0xFF334155),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: isRunning ? null : _handleReset,
          icon: const Icon(Icons.restart_alt, size: 18, color: Colors.white),
          tooltip: 'Reset',
        ),
      ],
    );
  }

  Widget _buildPathSettingsCard(bool isRunning) {
    return Material(
      color: const Color(0xFF131A26),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Color(0xFF1E293B)),
      ),
      child: ExpansionTile(
        initiallyExpanded: _pathsExpanded,
        onExpansionChanged: (exp) => setState(() => _pathsExpanded = exp),
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
        title: const Text(
          'Dataset & Calibration Paths',
          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.bold),
        ),
        iconColor: const Color(0xFF38BDF8),
        collapsedIconColor: const Color(0xFF64748B),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              children: [
                _buildPathInput('ORBvoc.txt Path', _vocabPathCtrl, isRunning),
                const SizedBox(height: 8),
                _buildPathInput('Settings YAML Path', _settingsPathCtrl, isRunning),
                const SizedBox(height: 8),
                _buildPathInput('Dataset Dir (mav0)', _datasetPathCtrl, isRunning),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPathInput(String label, TextEditingController ctrl, bool disabled) {
    return TextField(
      controller: ctrl,
      enabled: !disabled,
      style: const TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'monospace'),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        filled: true,
        fillColor: const Color(0xFF0B101B),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF1E293B))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF1E293B))),
      ),
    );
  }
}
