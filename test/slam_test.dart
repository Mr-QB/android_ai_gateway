import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:android_ai_gateway/features/visual_slam/domain/slam_enums.dart';
import 'package:android_ai_gateway/features/visual_slam/domain/slam_pose.dart';
import 'package:android_ai_gateway/features/visual_slam/domain/slam_status.dart';

void main() {
  group('Visual SLAM Domain Enums Mapping Tests', () {
    test('SlamSensorMode mapping and native roundtrip', () {
      expect(SlamSensorMode.fromNative(0), equals(SlamSensorMode.monocular));
      expect(SlamSensorMode.fromNative(1), equals(SlamSensorMode.monoInertial));
      expect(SlamSensorMode.fromNative(99), equals(SlamSensorMode.monocular));

      expect(SlamSensorMode.monocular.nativeValue, equals(0));
      expect(SlamSensorMode.monoInertial.nativeValue, equals(1));
    });

    test('SlamReplayMode mapping and native roundtrip', () {
      expect(SlamReplayMode.fromNative(0), equals(SlamReplayMode.realtime));
      expect(SlamReplayMode.fromNative(1), equals(SlamReplayMode.maximumSpeed));
      expect(SlamReplayMode.fromNative(-1), equals(SlamReplayMode.realtime));

      expect(SlamReplayMode.realtime.nativeValue, equals(0));
      expect(SlamReplayMode.maximumSpeed.nativeValue, equals(1));
    });

    test('SlamRunState mapping from native codes', () {
      expect(SlamRunState.fromNative(0), equals(SlamRunState.uninitialized));
      expect(SlamRunState.fromNative(1), equals(SlamRunState.initializing));
      expect(SlamRunState.fromNative(2), equals(SlamRunState.ready));
      expect(SlamRunState.fromNative(3), equals(SlamRunState.running));
      expect(SlamRunState.fromNative(4), equals(SlamRunState.paused));
      expect(SlamRunState.fromNative(5), equals(SlamRunState.stopped));
      expect(SlamRunState.fromNative(6), equals(SlamRunState.completed));
      expect(SlamRunState.fromNative(7), equals(SlamRunState.error));
      expect(SlamRunState.fromNative(99), equals(SlamRunState.unknown));
    });

    test('SlamTrackingState mapping from ORB-SLAM3 tracking state', () {
      expect(SlamTrackingState.fromNative(-1), equals(SlamTrackingState.systemNotReady));
      expect(SlamTrackingState.fromNative(0), equals(SlamTrackingState.noImagesYet));
      expect(SlamTrackingState.fromNative(1), equals(SlamTrackingState.notInitialized));
      expect(SlamTrackingState.fromNative(2), equals(SlamTrackingState.ok));
      expect(SlamTrackingState.fromNative(3), equals(SlamTrackingState.recentlyLost));
      expect(SlamTrackingState.fromNative(4), equals(SlamTrackingState.lost));
      expect(SlamTrackingState.fromNative(5), equals(SlamTrackingState.okKlt));
      expect(SlamTrackingState.fromNative(-99), equals(SlamTrackingState.systemNotReady));
    });
  });

  group('SlamPose Model Tests', () {
    test('Identity pose is valid and has correct coordinates', () {
      final identity = SlamPose.identity();
      expect(identity.isValid, isTrue);
      expect(identity.tx, equals(0.0));
      expect(identity.ty, equals(0.0));
      expect(identity.tz, equals(0.0));
      expect(identity.qw, equals(1.0));
      expect(identity.qx, equals(0.0));
      expect(identity.qy, equals(0.0));
      expect(identity.qz, equals(0.0));
    });

    test('Invalid pose detection', () {
      const invalid = SlamPose(
        tx: 1.0,
        ty: 2.0,
        tz: 3.0,
        qx: 0.0,
        qy: 0.0,
        qz: 0.0,
        qw: 1.0,
        datasetTimestampS: 100.0,
        frameIndex: 5,
        isValid: false,
      );
      expect(invalid.isValid, isFalse);
    });

    test('Yaw orientation calculation from quaternion', () {
      // 90 degree rotation around Y axis: q = (x=0, y=sin(45), z=0, w=cos(45))
      final double angle = math.pi / 2; // 90 deg
      final double qy = math.sin(angle / 2);
      final double qw = math.cos(angle / 2);

      final pose = SlamPose(
        tx: 0.0,
        ty: 0.0,
        tz: 0.0,
        qx: 0.0,
        qy: qy,
        qz: 0.0,
        qw: qw,
        datasetTimestampS: 1.0,
        frameIndex: 1,
        isValid: true,
      );

      final double calculatedYaw = math.atan2(
        2.0 * (pose.qw * pose.qy + pose.qx * pose.qz),
        1.0 - 2.0 * (pose.qy * pose.qy + pose.qz * pose.qz),
      );

      expect(calculatedYaw, closeTo(angle, 1e-4));
    });
  });

  group('SlamStatus Model Tests', () {
    test('Uninitialized status defaults', () {
      final status = SlamStatus.uninitialized();
      expect(status.runState, equals(SlamRunState.uninitialized));
      expect(status.trackingState, equals(SlamTrackingState.systemNotReady));
      expect(status.currentFrame, equals(0));
      expect(status.totalFrames, equals(0));
      expect(status.hasError, isFalse);
      expect(status.effectiveFps, equals(0.0));
    });

    test('Effective FPS calculation from latency', () {
      const status = SlamStatus(
        apiVersion: 1,
        runState: SlamRunState.running,
        trackingState: SlamTrackingState.ok,
        sensorMode: SlamSensorMode.monocular,
        replayMode: SlamReplayMode.realtime,
        currentFrame: 100,
        totalFrames: 1000,
        datasetTimestampS: 1403636580.0,
        lastTrackMs: 25.0, // 40 FPS native capacity
        averageTrackMs: 30.0,
        keyframeCount: 15,
        mapPointCount: 450,
        errorCode: 0,
      );

      expect(status.effectiveFps, closeTo(40.0, 0.1));
      expect(status.hasError, isFalse);
    });

    test('Error status detection', () {
      const errorStatus = SlamStatus(
        apiVersion: 1,
        runState: SlamRunState.error,
        trackingState: SlamTrackingState.systemNotReady,
        sensorMode: SlamSensorMode.monocular,
        replayMode: SlamReplayMode.realtime,
        currentFrame: 0,
        totalFrames: 0,
        datasetTimestampS: 0.0,
        lastTrackMs: 0.0,
        averageTrackMs: 0.0,
        keyframeCount: 0,
        mapPointCount: 0,
        errorCode: -3,
      );

      expect(errorStatus.hasError, isTrue);
      expect(errorStatus.runState, equals(SlamRunState.error));
    });
  });
}
