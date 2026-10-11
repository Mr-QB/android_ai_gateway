enum SlamSensorMode {
  monocular(0),
  monoInertial(1);

  final int nativeCode;
  const SlamSensorMode(this.nativeCode);

  int get nativeValue => nativeCode;

  String get label => this == SlamSensorMode.monoInertial ? 'Mono + IMU' : 'Monocular';

  static SlamSensorMode fromCode(int code) {
    return code == 1 ? SlamSensorMode.monoInertial : SlamSensorMode.monocular;
  }

  static SlamSensorMode fromNative(int code) => fromCode(code);
}

enum SlamReplayMode {
  realtime(0),
  maximumSpeed(1);

  final int nativeCode;
  const SlamReplayMode(this.nativeCode);

  int get nativeValue => nativeCode;

  static SlamReplayMode fromNative(int code) {
    return code == 1 ? SlamReplayMode.maximumSpeed : SlamReplayMode.realtime;
  }
}

enum SlamRunState {
  uninitialized(0),
  initializing(1),
  ready(2),
  running(3),
  paused(4),
  stopped(5),
  completed(6),
  error(7),
  unknown(-1);

  final int nativeCode;
  const SlamRunState(this.nativeCode);

  int get nativeValue => nativeCode;

  static SlamRunState fromCode(int code) {
    switch (code) {
      case 0:
        return SlamRunState.uninitialized;
      case 1:
        return SlamRunState.initializing;
      case 2:
        return SlamRunState.ready;
      case 3:
        return SlamRunState.running;
      case 4:
        return SlamRunState.paused;
      case 5:
        return SlamRunState.stopped;
      case 6:
        return SlamRunState.completed;
      case 7:
        return SlamRunState.error;
      default:
        return SlamRunState.unknown;
    }
  }

  static SlamRunState fromNative(int code) => fromCode(code);
}


enum SlamTrackingState {
  systemNotReady(-1),
  noImagesYet(0),
  notInitialized(1),
  ok(2),
  recentlyLost(3),
  lost(4),
  okKlt(5),
  unknown(-99);

  final int nativeCode;
  const SlamTrackingState(this.nativeCode);

  int get nativeValue => nativeCode;

  static SlamTrackingState fromCode(int code) {
    switch (code) {
      case -1:
        return SlamTrackingState.systemNotReady;
      case 0:
        return SlamTrackingState.noImagesYet;
      case 1:
        return SlamTrackingState.notInitialized;
      case 2:
        return SlamTrackingState.ok;
      case 3:
        return SlamTrackingState.recentlyLost;
      case 4:
        return SlamTrackingState.lost;
      case 5:
        return SlamTrackingState.okKlt;
      default:
        return SlamTrackingState.systemNotReady;
    }
  }

  static SlamTrackingState fromNative(int code) => fromCode(code);

  String get label {
    switch (this) {
      case SlamTrackingState.systemNotReady:
        return 'System Not Ready';
      case SlamTrackingState.noImagesYet:
        return 'No Images Yet';
      case SlamTrackingState.notInitialized:
        return 'Not Initialized';
      case SlamTrackingState.ok:
        return 'Tracking OK';
      case SlamTrackingState.recentlyLost:
        return 'Recently Lost';
      case SlamTrackingState.lost:
        return 'Tracking Lost';
      case SlamTrackingState.okKlt:
        return 'Tracking OK (KLT)';
      case SlamTrackingState.unknown:
        return 'Unknown';
    }
  }
}

