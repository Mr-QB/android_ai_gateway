import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

import '../domain/slam_enums.dart';
import '../domain/slam_pose.dart';
import '../domain/slam_status.dart';

final class NativeSlamPose extends Struct {
  @Double()
  external double timestampSeconds;

  @Float()
  external double tx;
  @Float()
  external double ty;
  @Float()
  external double tz;

  @Float()
  external double qx;
  @Float()
  external double qy;
  @Float()
  external double qz;
  @Float()
  external double qw;

  @Int32()
  external int valid;

  SlamPose toModel() {
    return SlamPose(
      timestampSeconds: timestampSeconds,
      x: tx,
      y: ty,
      z: tz,
      qx: qx,
      qy: qy,
      qz: qz,
      qw: qw,
      valid: valid != 0,
    );
  }
}

final class NativeSlamStatus extends Struct {
  @Int32()
  external int apiVersion;

  @Int32()
  external int runState;
  @Int32()
  external int trackingState;
  @Int32()
  external int sensorMode;

  @Int32()
  external int currentFrame;
  @Int32()
  external int totalFrames;

  @Int32()
  external int keyframeCount;
  @Int32()
  external int mapPointCount;

  @Double()
  external double datasetTimestampSeconds;

  @Double()
  external double lastTrackMs;
  @Double()
  external double averageTrackMs;
  @Double()
  external double replayElapsedSeconds;

  @Int32()
  external int finished;
  @Int32()
  external int errorCode;

  SlamStatus toModel() {
    return SlamStatus(
      apiVersion: apiVersion,
      runState: SlamRunState.fromCode(runState),
      trackingState: SlamTrackingState.fromCode(trackingState),
      sensorMode: SlamSensorMode.fromCode(sensorMode),
      currentFrame: currentFrame,
      totalFrames: totalFrames,
      keyframeCount: keyframeCount,
      mapPointCount: mapPointCount,
      datasetTimestampSeconds: datasetTimestampSeconds,
      lastTrackMs: lastTrackMs,
      averageTrackMs: averageTrackMs,
      replayElapsedSeconds: replayElapsedSeconds,
      finished: finished != 0,
      errorCode: errorCode,
    );
  }
}

typedef SlamApiVersionC = Int32 Function();
typedef SlamApiVersionDart = int Function();

typedef SlamInitializeC = Int32 Function(
    Pointer<Utf8> vocabPath, Pointer<Utf8> settingsPath, Int32 sensorMode);
typedef SlamInitializeDart = int Function(
    Pointer<Utf8> vocabPath, Pointer<Utf8> settingsPath, int sensorMode);

typedef SlamLoadDatasetC = Int32 Function(Pointer<Utf8> sequenceRoot);
typedef SlamLoadDatasetDart = int Function(Pointer<Utf8> sequenceRoot);

typedef SlamStartReplayC = Int32 Function(Int32 replayMode, Double speedFactor);
typedef SlamStartReplayDart = int Function(int replayMode, double speedFactor);

typedef SlamControlC = Int32 Function();
typedef SlamControlDart = int Function();

typedef SlamGetStatusC = Int32 Function(Pointer<NativeSlamStatus> outStatus);
typedef SlamGetStatusDart = int Function(Pointer<NativeSlamStatus> outStatus);

typedef SlamGetPoseC = Int32 Function(Pointer<NativeSlamPose> outPose);
typedef SlamGetPoseDart = int Function(Pointer<NativeSlamPose> outPose);

typedef SlamCopyTrajectoryC = Int32 Function(
    Pointer<NativeSlamPose> outPoses, Int32 maxCount);
typedef SlamCopyTrajectoryDart = int Function(
    Pointer<NativeSlamPose> outPoses, int maxCount);

typedef SlamGetLastErrorC = Pointer<Utf8> Function();
typedef SlamGetLastErrorDart = Pointer<Utf8> Function();

typedef SlamShutdownC = Void Function();
typedef SlamShutdownDart = void Function();

class SlamNativeBindings {
  static final SlamNativeBindings _instance = SlamNativeBindings._internal();
  factory SlamNativeBindings() => _instance;

  late final DynamicLibrary _lib;
  bool _isAvailable = false;

  late final SlamApiVersionDart apiVersion;
  late final SlamInitializeDart initialize;
  late final SlamLoadDatasetDart loadEurocDataset;
  late final SlamStartReplayDart startReplay;
  late final SlamControlDart pauseReplay;
  late final SlamControlDart resumeReplay;
  late final SlamControlDart stopReplay;
  late final SlamControlDart reset;
  late final SlamGetStatusDart getStatus;
  late final SlamGetPoseDart getPose;
  late final SlamCopyTrajectoryDart copyTrajectory;
  late final SlamGetLastErrorDart getLastError;
  late final SlamShutdownDart shutdown;

  bool get isAvailable => _isAvailable;

  SlamNativeBindings._internal() {
    try {
      if (Platform.isAndroid) {
        _lib = DynamicLibrary.open('liborbslam_native.so');
        _bindFunctions();
        _isAvailable = true;
      }
    } catch (e) {
      _isAvailable = false;
    }
  }

  void _bindFunctions() {
    apiVersion = _lib
        .lookup<NativeFunction<SlamApiVersionC>>('slam_api_version')
        .asFunction<SlamApiVersionDart>();

    initialize = _lib
        .lookup<NativeFunction<SlamInitializeC>>('slam_initialize')
        .asFunction<SlamInitializeDart>();

    loadEurocDataset = _lib
        .lookup<NativeFunction<SlamLoadDatasetC>>('slam_load_euroc_dataset')
        .asFunction<SlamLoadDatasetDart>();

    startReplay = _lib
        .lookup<NativeFunction<SlamStartReplayC>>('slam_start_replay')
        .asFunction<SlamStartReplayDart>();

    pauseReplay = _lib
        .lookup<NativeFunction<SlamControlC>>('slam_pause_replay')
        .asFunction<SlamControlDart>();

    resumeReplay = _lib
        .lookup<NativeFunction<SlamControlC>>('slam_resume_replay')
        .asFunction<SlamControlDart>();

    stopReplay = _lib
        .lookup<NativeFunction<SlamControlC>>('slam_stop_replay')
        .asFunction<SlamControlDart>();

    reset = _lib
        .lookup<NativeFunction<SlamControlC>>('slam_reset')
        .asFunction<SlamControlDart>();

    getStatus = _lib
        .lookup<NativeFunction<SlamGetStatusC>>('slam_get_status')
        .asFunction<SlamGetStatusDart>();

    getPose = _lib
        .lookup<NativeFunction<SlamGetPoseC>>('slam_get_pose')
        .asFunction<SlamGetPoseDart>();

    copyTrajectory = _lib
        .lookup<NativeFunction<SlamCopyTrajectoryC>>('slam_copy_trajectory')
        .asFunction<SlamCopyTrajectoryDart>();

    getLastError = _lib
        .lookup<NativeFunction<SlamGetLastErrorC>>('slam_get_last_error')
        .asFunction<SlamGetLastErrorDart>();

    shutdown = _lib
        .lookup<NativeFunction<SlamShutdownC>>('slam_shutdown')
        .asFunction<SlamShutdownDart>();
  }
}
