import 'package:flutter/material.dart';
import '../../domain/slam_enums.dart';
import '../../domain/slam_pose.dart';
import '../../domain/slam_status.dart';

/// Clean, responsive dashboard status panel displaying real-time metrics for ORB-SLAM3.
class SlamStatusPanel extends StatelessWidget {
  final SlamStatus status;
  final SlamPose? pose;

  const SlamStatusPanel({
    super.key,
    required this.status,
    this.pose,
  });

  Color _trackingColor(SlamTrackingState state) {
    switch (state) {
      case SlamTrackingState.ok:
      case SlamTrackingState.okKlt:
        return const Color(0xFF10B981);
      case SlamTrackingState.recentlyLost:
        return const Color(0xFFF59E0B);
      case SlamTrackingState.lost:
        return const Color(0xFFEF4444);
      case SlamTrackingState.notInitialized:
        return const Color(0xFF6366F1);
      case SlamTrackingState.noImagesYet:
      case SlamTrackingState.systemNotReady:
      case SlamTrackingState.unknown:
        return const Color(0xFF64748B);
    }
  }

  Color _runStateColor(SlamRunState state) {
    switch (state) {
      case SlamRunState.running:
        return const Color(0xFF06B6D4);
      case SlamRunState.ready:
      case SlamRunState.completed:
        return const Color(0xFF10B981);
      case SlamRunState.paused:
        return const Color(0xFFF59E0B);
      case SlamRunState.error:
        return const Color(0xFFEF4444);
      case SlamRunState.uninitialized:
      case SlamRunState.initializing:
      case SlamRunState.stopped:
      case SlamRunState.unknown:
        return const Color(0xFF64748B);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final double progress = (status.totalFrames > 0)
        ? (status.currentFrame / status.totalFrames).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      padding: const EdgeInsets.all(14.0),
      decoration: BoxDecoration(
        color: const Color(0xFF131A26),
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(color: const Color(0xFF22304A), width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: State Chips
          Row(
            children: [
              _buildBadge(
                label: status.sensorMode.label,
                color: status.sensorMode == SlamSensorMode.monoInertial
                    ? const Color(0xFF8B5CF6)
                    : const Color(0xFF3B82F6),
              ),
              const SizedBox(width: 8),
              _buildBadge(
                label: status.runState.name.toUpperCase(),
                color: _runStateColor(status.runState),
              ),
              const Spacer(),
              _buildBadge(
                label: status.trackingState.label,
                color: _trackingColor(status.trackingState),
                icon: Icons.lens,
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Row 2: Progress bar
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Replay Progress: ${status.currentFrame} / ${status.totalFrames}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF94A3B8),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '${(progress * 100).toStringAsFixed(1)}%',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF38BDF8),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: const Color(0xFF1E293B),
                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF0EA5E9)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Row 3: Performance & Feature Metrics
          Row(
            children: [
              Expanded(
                child: _buildMetricTile(
                  label: 'Latency',
                  value: '${status.lastTrackMs.toStringAsFixed(1)} ms',
                  sub: 'Avg: ${status.averageTrackMs.toStringAsFixed(1)} ms',
                ),
              ),
              Expanded(
                child: _buildMetricTile(
                  label: 'Frame Rate',
                  value: '${status.effectiveFps.toStringAsFixed(1)} FPS',
                  sub: 'Target: 20 FPS',
                ),
              ),
              Expanded(
                child: _buildMetricTile(
                  label: 'Features',
                  value: '${status.mapPointCount} pts',
                  sub: status.keyframeCount >= 0
                      ? '${status.keyframeCount} KFs'
                      : 'KFs: N/A',
                ),
              ),
            ],
          ),

          // Row 4: Current World Coordinates
          if (pose != null && pose!.isValid) ...[
            const Divider(color: Color(0xFF22304A), height: 20),
            Row(
              children: [
                const Icon(Icons.my_location, size: 14, color: Color(0xFF38BDF8)),
                const SizedBox(width: 6),
                Text(
                  'Pose (Twc): ',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF94A3B8),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Expanded(
                  child: Text(
                    'X: ${pose!.tx.toStringAsFixed(3)}  Y: ${pose!.ty.toStringAsFixed(3)}  Z: ${pose!.tz.toStringAsFixed(3)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: const Color(0xFFF1F5F9),
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBadge({
    required String label,
    required Color color,
    IconData? icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6.0),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1.0),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 8, color: color),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTile({
    required String label,
    required String value,
    required String sub,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 3.0),
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1520),
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFFF1F5F9),
              fontSize: 13,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 2),
          Text(
            sub,
            style: const TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 9.5,
            ),
          ),
        ],
      ),
    );
  }
}
