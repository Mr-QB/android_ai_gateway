import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../domain/slam_pose.dart';

/// CustomPainter rendering a 2D top-down (X-Z plane) trajectory projection of ORB-SLAM3 poses.
class TrajectoryPainter extends CustomPainter {
  final List<SlamPose> trajectory;
  final SlamPose? currentPose;
  final bool autoCenter;

  const TrajectoryPainter({
    required this.trajectory,
    this.currentPose,
    this.autoCenter = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Background
    final bgPaint = Paint()..color = const Color(0xFF0F141C);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    if (size.width <= 0 || size.height <= 0) return;

    // 2. Compute bounding box in world space (X-Z)
    double minX = -1.0;
    double maxX = 1.0;
    double minZ = -1.0;
    double maxZ = 1.0;

    for (final pose in trajectory) {
      if (!pose.isValid) continue;
      if (pose.tx < minX) minX = pose.tx;
      if (pose.tx > maxX) maxX = pose.tx;
      if (pose.tz < minZ) minZ = pose.tz;
      if (pose.tz > maxZ) maxZ = pose.tz;
    }

    if (currentPose != null && currentPose!.isValid) {
      if (currentPose!.tx < minX) minX = currentPose!.tx;
      if (currentPose!.tx > maxX) maxX = currentPose!.tx;
      if (currentPose!.tz < minZ) minZ = currentPose!.tz;
      if (currentPose!.tz > maxZ) maxZ = currentPose!.tz;
    }

    // Add margin
    const double paddingFactor = 0.25;
    double spanX = (maxX - minX);
    double spanZ = (maxZ - minZ);
    if (spanX < 1.0) spanX = 1.0;
    if (spanZ < 1.0) spanZ = 1.0;

    minX -= spanX * paddingFactor;
    maxX += spanX * paddingFactor;
    minZ -= spanZ * paddingFactor;
    maxZ += spanZ * paddingFactor;

    spanX = maxX - minX;
    spanZ = maxZ - minZ;

    // Uniform aspect ratio fit
    final double scaleX = (size.width - 40) / spanX;
    final double scaleZ = (size.height - 40) / spanZ;
    final double scale = math.min(scaleX, scaleZ);

    final double centerX = (minX + maxX) / 2.0;
    final double centerZ = (minZ + maxZ) / 2.0;

    Offset worldToCanvas(double x, double z) {
      final double cx = size.width / 2.0 + (x - centerX) * scale;
      // Invert Z so forward (+Z) points upward on screen
      final double cy = size.height / 2.0 - (z - centerZ) * scale;
      return Offset(cx, cy);
    }

    // 3. Draw Grid Lines
    final gridPaint = Paint()
      ..color = const Color(0xFF1E293B)
      ..strokeWidth = 1.0;

    const double gridStep = 1.0; // 1 meter grid
    final int startGridX = (minX / gridStep).floor();
    final int endGridX = (maxX / gridStep).ceil();
    final int startGridZ = (minZ / gridStep).floor();
    final int endGridZ = (maxZ / gridStep).ceil();

    for (int gx = startGridX; gx <= endGridX; gx++) {
      final p1 = worldToCanvas(gx * gridStep, minZ);
      final p2 = worldToCanvas(gx * gridStep, maxZ);
      canvas.drawLine(p1, p2, gridPaint);
    }

    for (int gz = startGridZ; gz <= endGridZ; gz++) {
      final p1 = worldToCanvas(minX, gz * gridStep);
      final p2 = worldToCanvas(maxX, gz * gridStep);
      canvas.drawLine(p1, p2, gridPaint);
    }

    // 4. Draw World Axes at (0, 0)
    final origin = worldToCanvas(0, 0);
    final axisPaintX = Paint()
      ..color = const Color(0xFFEF4444).withValues(alpha: 0.8)
      ..strokeWidth = 2.0;
    final axisPaintZ = Paint()
      ..color = const Color(0xFF10B981).withValues(alpha: 0.8)
      ..strokeWidth = 2.0;

    // +X axis (lateral right)
    final xArrow = worldToCanvas(0.5, 0);
    canvas.drawLine(origin, xArrow, axisPaintX);

    // +Z axis (forward)
    final zArrow = worldToCanvas(0, 0.5);
    canvas.drawLine(origin, zArrow, axisPaintZ);

    final originPaint = Paint()
      ..color = Colors.white70
      ..style = PaintingStyle.fill;
    canvas.drawCircle(origin, 3.5, originPaint);

    // 5. Draw Trajectory Path
    if (trajectory.isNotEmpty) {
      final path = Path();
      bool first = true;

      for (final p in trajectory) {
        if (!p.isValid) continue;
        final pt = worldToCanvas(p.tx, p.tz);
        if (first) {
          path.moveTo(pt.dx, pt.dy);
          first = false;
        } else {
          path.lineTo(pt.dx, pt.dy);
        }
      }

      // Outer glow
      final glowPaint = Paint()
        ..color = const Color(0xFF06B6D4).withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.0;
      canvas.drawPath(path, glowPaint);

      // Core line
      final pathPaint = Paint()
        ..color = const Color(0xFF22D3EE)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(path, pathPaint);

      // Start point marker
      final startPose = trajectory.firstWhere(
        (p) => p.isValid,
        orElse: () => trajectory.first,
      );
      if (startPose.isValid) {
        final startPt = worldToCanvas(startPose.tx, startPose.tz);
        final startPaint = Paint()
          ..color = const Color(0xFF10B981)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(startPt, 5.0, startPaint);
      }
    }

    // 6. Draw Current Pose Marker
    final activePose = (currentPose != null && currentPose!.isValid)
        ? currentPose
        : (trajectory.isNotEmpty && trajectory.last.isValid
            ? trajectory.last
            : null);

    if (activePose != null && activePose.isValid) {
      final curPt = worldToCanvas(activePose.tx, activePose.tz);

      // Heading arrow from quaternion yaw
      // Euler yaw from quaternion: yaw = atan2(2*(w*y + x*z), 1 - 2*(y*y + z*z))
      final qw = activePose.qw;
      final qx = activePose.qx;
      final qy = activePose.qy;
      final qz = activePose.qz;
      final double yaw = math.atan2(
        2.0 * (qw * qy + qx * qz),
        1.0 - 2.0 * (qy * qy + qz * qz),
      );

      // Outer ripple
      final ripplePaint = Paint()
        ..color = const Color(0xFFF59E0B).withValues(alpha: 0.25)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(curPt, 12.0, ripplePaint);

      // Center point
      final curPaint = Paint()
        ..color = const Color(0xFFF59E0B)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(curPt, 6.0, curPaint);

      // Orientation vector (length: 18 px)
      const double arrowLen = 18.0;
      final double arrowDx = math.sin(yaw) * arrowLen;
      final double arrowDy = -math.cos(yaw) * arrowLen;
      final arrowTip = Offset(curPt.dx + arrowDx, curPt.dy + arrowDy);

      final arrowPaint = Paint()
        ..color = const Color(0xFFFDE047)
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(curPt, arrowTip, arrowPaint);
    }
  }

  @override
  bool shouldRepaint(covariant TrajectoryPainter oldDelegate) {
    return oldDelegate.trajectory.length != trajectory.length ||
        oldDelegate.currentPose != currentPose;
  }
}
