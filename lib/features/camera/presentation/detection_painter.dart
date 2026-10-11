import 'package:flutter/material.dart';

import '../../ai_engine/domain/detection.dart';
import '../../ai_engine/services/model_coordinate_mapper.dart';
import '../data/coco_labels.dart';

class DetectionPainter extends CustomPainter {
  final List<Detection> detections;
  final int imageWidth;
  final int imageHeight;
  final int sensorOrientation;
  final bool isFrontCamera;

  const DetectionPainter({
    required this.detections,
    required this.imageWidth,
    required this.imageHeight,
    this.sensorOrientation = 90,
    this.isFrontCamera = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (imageWidth <= 0 || imageHeight <= 0 || detections.isEmpty) return;

    for (final detection in detections) {
      final color = Colors.primaries[detection.classId.abs() % Colors.primaries.length];

      // Ánh xạ tọa độ chính xác qua ModelCoordinateMapper
      final rect = ModelCoordinateMapper.cameraToPreview(
        cameraRect: Rect.fromLTWH(
          detection.x,
          detection.y,
          detection.width,
          detection.height,
        ),
        cameraWidth: imageWidth,
        cameraHeight: imageHeight,
        previewSize: size,
        sensorOrientation: sensorOrientation,
        isFrontCamera: isFrontCamera,
        isRotatedInNative: true,
      );

      final boxPaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0;
      canvas.drawRect(rect, boxPaint);

      final className = detection.classId >= 0 && detection.classId < cocoLabels.length
          ? cocoLabels[detection.classId]
          : 'class ${detection.classId}';
      final label = '$className ${(detection.confidence * 100).toStringAsFixed(1)}%';

      final textPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width);

      final labelLeft = rect.left.clamp(0.0, size.width - textPainter.width).toDouble();
      final preferredTop = rect.top - textPainter.height - 4;
      final labelTop = preferredTop >= 0 ? preferredTop : rect.top;

      final background = Rect.fromLTWH(
        labelLeft - 2,
        labelTop - 2,
        textPainter.width + 4,
        textPainter.height + 4,
      );

      canvas.drawRect(background, Paint()..color = color.withAlpha(220));
      textPainter.paint(canvas, Offset(labelLeft, labelTop));
    }
  }

  @override
  bool shouldRepaint(covariant DetectionPainter oldDelegate) {
    return oldDelegate.detections != detections ||
        oldDelegate.imageWidth != imageWidth ||
        oldDelegate.imageHeight != imageHeight ||
        oldDelegate.sensorOrientation != sensorOrientation;
  }
}
