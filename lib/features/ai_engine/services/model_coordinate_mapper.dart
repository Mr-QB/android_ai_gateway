import 'dart:math' as math;
import 'dart:ui';


class ModelCoordinateMapper {
  /// Giải mã tọa độ từ 640x640 Letterbox về tọa độ khung hình camera gốc
  static Rect unletterbox({
    required double modelX,
    required double modelY,
    required double modelWidth,
    required double modelHeight,
    required int originalWidth,
    required int originalHeight,
    int targetSize = 640,
  }) {
    final scale = math.min(
      targetSize / originalWidth,
      targetSize / originalHeight,
    );

    final resizedW = (originalWidth * scale).round().clamp(1, targetSize);
    final resizedH = (originalHeight * scale).round().clamp(1, targetSize);

    final wpad = targetSize - resizedW;
    final hpad = targetSize - resizedH;
    final padX = wpad / 2.0;
    final padY = hpad / 2.0;

    final origX = (modelX - padX) / scale;
    final origY = (modelY - padY) / scale;
    final origW = modelWidth / scale;
    final origH = modelHeight / scale;

    final clampedX = origX.clamp(0.0, originalWidth.toDouble());
    final clampedY = origY.clamp(0.0, originalHeight.toDouble());
    final clampedW = origW.clamp(0.0, originalWidth.toDouble() - clampedX);
    final clampedH = origH.clamp(0.0, originalHeight.toDouble() - clampedY);

    return Rect.fromLTWH(clampedX, clampedY, clampedW, clampedH);
  }

  /// Ánh xạ tọa độ từ khung hình camera gốc sang khung nhìn Flutter CameraPreview
  static Rect cameraToPreview({
    required Rect cameraRect,
    required int cameraWidth,
    required int cameraHeight,
    required Size previewSize,
    required int sensorOrientation,
    bool isFrontCamera = false,
    bool isRotatedInNative = true,
  }) {
    // Nếu frame đã được xoay 90/270 độ trong C++ native (kanna_rotate),
    // kích thước frame đầu ra đã là Portrait (ví dụ: 480x640 thay vì 640x480)
    final double srcWidth;
    final double srcHeight;

    if (isRotatedInNative && (sensorOrientation == 90 || sensorOrientation == 270)) {
      srcWidth = math.min(cameraWidth, cameraHeight).toDouble();
      srcHeight = math.max(cameraWidth, cameraHeight).toDouble();
    } else {
      srcWidth = cameraWidth.toDouble();
      srcHeight = cameraHeight.toDouble();
    }

    // Tính tỷ lệ BoxFit.cover giữa camera frame và widget viewport
    final scaleX = previewSize.width / srcWidth;
    final scaleY = previewSize.height / srcHeight;
    final scale = math.max(scaleX, scaleY);

    final renderedWidth = srcWidth * scale;
    final renderedHeight = srcHeight * scale;

    final offsetX = (previewSize.width - renderedWidth) / 2.0;
    final offsetY = (previewSize.height - renderedHeight) / 2.0;

    double left = cameraRect.left * scale + offsetX;
    double top = cameraRect.top * scale + offsetY;
    double width = cameraRect.width * scale;
    double height = cameraRect.height * scale;

    if (isFrontCamera) {
      left = previewSize.width - (left + width);
    }

    return Rect.fromLTWH(left, top, width, height);
  }
}
