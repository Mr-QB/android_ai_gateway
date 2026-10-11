import 'dart:ffi';
import 'package:ffi/ffi.dart';

import '../data/slam_native_bindings.dart';
import '../domain/slam_enums.dart';
import '../domain/slam_pose.dart';
import '../domain/slam_status.dart';

class SlamResult {
  final bool isSuccess;
  final String message;

  const SlamResult.success([this.message = 'Success']) : isSuccess = true;
  const SlamResult.failure(this.message) : isSuccess = false;
}

class SlamService {
  static final SlamService _instance = SlamService._internal();
  factory SlamService() => _instance;
  static SlamService get instance => _instance;

  final SlamNativeBindings _bindings = SlamNativeBindings();

  // Persistent reusable native pointers for polling
  Pointer<NativeSlamStatus>? _statusPtr;
  Pointer<NativeSlamPose>? _posePtr;
  Pointer<NativeSlamPose>? _trajectoryBuffer;
  int _trajectoryBufferCapacity = 0;

  SlamService._internal() {
    if (_bindings.isAvailable) {
      _statusPtr = calloc<NativeSlamStatus>();
      _posePtr = calloc<NativeSlamPose>();
    }
  }

  bool get isAvailable => _bindings.isAvailable;
  bool get isNativeLoaded => _bindings.isAvailable;

  int getApiVersion() {
    if (!_bindings.isAvailable) return -1;
    return _bindings.apiVersion();
  }

  Future<SlamResult> initialize({
    required String vocabularyPath,
    required String settingsPath,
    required SlamSensorMode sensorMode,
  }) async {
    if (!_bindings.isAvailable) {
      return const SlamResult.failure('Native ORB-SLAM library is not loaded.');
    }

    final vocabUtf8 = vocabularyPath.toNativeUtf8();
    final settingsUtf8 = settingsPath.toNativeUtf8();

    try {
      final code = _bindings.initialize(
        vocabUtf8,
        settingsUtf8,
        sensorMode.nativeValue,
      );

      if (code != 0) {
        final err = getLastError();
        return SlamResult.failure('SLAM initialize failed ($code): $err');
      }
      return const SlamResult.success('ORB-SLAM3 initialized');
    } catch (e) {
      return SlamResult.failure('Initialization exception: $e');
    } finally {
      calloc.free(vocabUtf8);
      calloc.free(settingsUtf8);
    }
  }

  Future<SlamResult> loadDataset({
    required String datasetPath,
    SlamSensorMode sensorMode = SlamSensorMode.monocular,
  }) async {
    if (!_bindings.isAvailable) {
      return const SlamResult.failure('Native ORB-SLAM library is not loaded.');
    }

    final pathUtf8 = datasetPath.toNativeUtf8();
    try {
      final code = _bindings.loadEurocDataset(pathUtf8);
      if (code != 0) {
        final err = getLastError();
        return SlamResult.failure('Load dataset failed ($code): $err');
      }
      return const SlamResult.success('Dataset loaded');
    } catch (e) {
      return SlamResult.failure('Load dataset exception: $e');
    } finally {
      calloc.free(pathUtf8);
    }
  }

  Future<void> loadEurocDataset(String rootPath) async {
    final res = await loadDataset(datasetPath: rootPath);
    if (!res.isSuccess) {
      throw Exception(res.message);
    }
  }

  SlamResult startReplay({
    required SlamReplayMode mode,
    double speedFactor = 1.0,
  }) {
    if (!_bindings.isAvailable) {
      return const SlamResult.failure('Native ORB-SLAM library is not loaded.');
    }

    final code = _bindings.startReplay(mode.nativeValue, speedFactor);
    if (code != 0) {
      final err = getLastError();
      return SlamResult.failure('Start replay failed ($code): $err');
    }
    return const SlamResult.success('Replay started');
  }

  Future<void> start({
    required SlamReplayMode replayMode,
    double speedFactor = 1.0,
  }) async {
    final res = startReplay(mode: replayMode, speedFactor: speedFactor);
    if (!res.isSuccess) {
      throw Exception(res.message);
    }
  }

  SlamResult pauseReplay() {
    if (!_bindings.isAvailable) {
      return const SlamResult.failure('Native library not loaded');
    }
    final code = _bindings.pauseReplay();
    return code == 0 ? const SlamResult.success() : SlamResult.failure(getLastError());
  }

  Future<void> pause() async {
    pauseReplay();
  }

  SlamResult resumeReplay() {
    if (!_bindings.isAvailable) {
      return const SlamResult.failure('Native library not loaded');
    }
    final code = _bindings.resumeReplay();
    return code == 0 ? const SlamResult.success() : SlamResult.failure(getLastError());
  }

  Future<void> resume() async {
    resumeReplay();
  }

  SlamResult stopReplay() {
    if (!_bindings.isAvailable) {
      return const SlamResult.failure('Native library not loaded');
    }
    final code = _bindings.stopReplay();
    return code == 0 ? const SlamResult.success() : SlamResult.failure(getLastError());
  }

  Future<void> stop() async {
    stopReplay();
  }

  SlamResult reset() {
    if (!_bindings.isAvailable) {
      return const SlamResult.failure('Native library not loaded');
    }
    final code = _bindings.reset();
    return code == 0 ? const SlamResult.success() : SlamResult.failure(getLastError());
  }

  Future<void> shutdown() async {
    if (!_bindings.isAvailable) return;
    _bindings.shutdown();
  }

  SlamStatus getStatus() => readStatus();

  SlamStatus readStatus() {
    if (!_bindings.isAvailable || _statusPtr == null) {
      return const SlamStatus();
    }

    final res = _bindings.getStatus(_statusPtr!);
    if (res != 0) {
      return const SlamStatus();
    }
    return _statusPtr!.ref.toModel();
  }

  SlamPose getPose() => readPose();

  SlamPose readPose() {
    if (!_bindings.isAvailable || _posePtr == null) {
      return const SlamPose.empty();
    }

    final res = _bindings.getPose(_posePtr!);
    if (res != 0) {
      return const SlamPose.empty();
    }
    return _posePtr!.ref.toModel();
  }

  List<SlamPose> getTrajectory({int maxPoints = 1000}) =>
      readTrajectory(maxPoints: maxPoints);

  List<SlamPose> readTrajectory({int maxPoints = 1000}) {
    if (!_bindings.isAvailable || maxPoints <= 0) {
      return [];
    }

    if (_trajectoryBuffer == null || _trajectoryBufferCapacity < maxPoints) {
      if (_trajectoryBuffer != null) {
        calloc.free(_trajectoryBuffer!);
      }
      _trajectoryBuffer = calloc<NativeSlamPose>(maxPoints);
      _trajectoryBufferCapacity = maxPoints;
    }

    final count = _bindings.copyTrajectory(_trajectoryBuffer!, maxPoints);
    final List<SlamPose> poses = [];
    for (int i = 0; i < count; ++i) {
      poses.add((_trajectoryBuffer! + i).ref.toModel());
    }
    return poses;
  }

  String getLastError() {
    if (!_bindings.isAvailable) return 'Native library not loaded';
    final ptr = _bindings.getLastError();
    if (ptr == nullptr) return '';
    return ptr.toDartString();
  }

  void dispose() {
    if (_statusPtr != null) {
      calloc.free(_statusPtr!);
      _statusPtr = null;
    }
    if (_posePtr != null) {
      calloc.free(_posePtr!);
      _posePtr = null;
    }
    if (_trajectoryBuffer != null) {
      calloc.free(_trajectoryBuffer!);
      _trajectoryBuffer = null;
      _trajectoryBufferCapacity = 0;
    }
  }
}
