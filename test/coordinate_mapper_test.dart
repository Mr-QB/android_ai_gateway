import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:android_ai_gateway/features/ai_engine/services/model_coordinate_mapper.dart';

void main() {
  group('ModelCoordinateMapper Tests', () {
    test('unletterbox accurately reverses padding and scaling', () {
      // 640x480 image into 640x640 letterbox:
      // scale = min(640/640, 640/480) = 1.0
      // resizedW = 640, resizedH = 480
      // wpad = 0, hpad = 160 -> padX = 0, padY = 80
      final rect = ModelCoordinateMapper.unletterbox(
        modelX: 100.0,
        modelY: 180.0, // 80 pad + 100
        modelWidth: 200.0,
        modelHeight: 150.0,
        originalWidth: 640,
        originalHeight: 480,
        targetSize: 640,
      );

      expect(rect.left, closeTo(100.0, 0.01));
      expect(rect.top, closeTo(100.0, 0.01));
      expect(rect.width, closeTo(200.0, 0.01));
      expect(rect.height, closeTo(150.0, 0.01));
    });

    test('cameraToPreview correctly maps coordinates with BoxFit.cover', () {
      final cameraRect = const Rect.fromLTWH(50, 50, 100, 100);
      final previewSize = const Size(360, 640);

      final mapped = ModelCoordinateMapper.cameraToPreview(
        cameraRect: cameraRect,
        cameraWidth: 480,
        cameraHeight: 640,
        previewSize: previewSize,
        sensorOrientation: 90,
        isFrontCamera: false,
        isRotatedInNative: true,
      );

      // Verify that mapped coordinates fall within or scale appropriately to preview
      expect(mapped.width, greaterThan(0));
      expect(mapped.height, greaterThan(0));
      expect(mapped.left.isFinite, isTrue);
      expect(mapped.top.isFinite, isTrue);
    });

    test('cameraToPreview mirrors horizontal coordinate for front camera', () {
      final cameraRect = const Rect.fromLTWH(10, 10, 100, 100);
      final previewSize = const Size(480, 640);

      final back = ModelCoordinateMapper.cameraToPreview(
        cameraRect: cameraRect,
        cameraWidth: 480,
        cameraHeight: 640,
        previewSize: previewSize,
        sensorOrientation: 90,
        isFrontCamera: false,
        isRotatedInNative: true,
      );

      final front = ModelCoordinateMapper.cameraToPreview(
        cameraRect: cameraRect,
        cameraWidth: 480,
        cameraHeight: 640,
        previewSize: previewSize,
        sensorOrientation: 90,
        isFrontCamera: true,
        isRotatedInNative: true,
      );

      expect(front.left, isNot(equals(back.left)));
      expect(front.width, equals(back.width));
    });
  });
}
