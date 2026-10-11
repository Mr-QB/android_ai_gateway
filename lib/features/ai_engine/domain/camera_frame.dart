import 'dart:typed_data' as typed;
import 'package:camera/camera.dart';

class PlaneData {
  final typed.Uint8List bytes;
  final int bytesPerRow;
  final int bytesPerPixel;

  const PlaneData({
    required this.bytes,
    required this.bytesPerRow,
    required this.bytesPerPixel,
  });
}

class CameraFrame {
  final int width;
  final int height;
  final int rotationDegrees;
  final int timestampUs;
  final bool isNv12;
  final typed.Uint8List yuvBytes;

  const CameraFrame({
    required this.width,
    required this.height,
    required this.rotationDegrees,
    required this.timestampUs,
    required this.isNv12,
    required this.yuvBytes,
  });

  /// Chuyển đổi siêu nhanh từ CameraImage YUV_420_888 sang buffer NV21 liên tục.
  /// Tuyệt đối KHÔNG encode JPEG hay dùng package:image!
  static int packCameraImageToNv21(CameraImage image, typed.Uint8List outBuffer) {
    final width = image.width;
    final height = image.height;
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    final ySize = width * height;
    final uvSize = width * (height ~/ 2);
    final totalSize = ySize + uvSize;

    if (outBuffer.length < totalSize) {
      throw ArgumentError('outBuffer size ${outBuffer.length} < required $totalSize');
    }

    // 1. Copy Y Plane (loại bỏ stride padding nếu bytesPerRow != width)
    final yRowStride = yPlane.bytesPerRow;
    if (yRowStride == width) {
      outBuffer.setRange(0, ySize, yPlane.bytes);
    } else {
      for (int row = 0; row < height; row++) {
        final srcOffset = row * yRowStride;
        final dstOffset = row * width;
        outBuffer.setRange(
          dstOffset,
          dstOffset + width,
          yPlane.bytes,
          srcOffset,
        );
      }
    }

    // 2. Copy UV Plane thành chuẩn NV21 (V, U, V, U...)
    // Trên Android Camera2 thông dụng, pixelStride của U/V thường = 2 (interleaved).
    final vBytes = vPlane.bytes;
    final uBytes = uPlane.bytes;
    final uvRowStride = vPlane.bytesPerRow;
    final uvPixelStride = vPlane.bytesPerPixel ?? 1;

    int uvDest = ySize;

    if (uvPixelStride == 2) {
      // Buffer đã xen kẽ V và U: Plane V bắt đầu bằng V, Plane U bắt đầu bằng U
      for (int row = 0; row < height ~/ 2; row++) {
        final rowOffset = row * uvRowStride;
        for (int col = 0; col < width ~/ 2; col++) {
          final srcIndex = rowOffset + (col * 2);
          if (srcIndex < vBytes.length) {
            outBuffer[uvDest++] = vBytes[srcIndex]; // V
          }
          if (srcIndex < uBytes.length) {
            outBuffer[uvDest++] = uBytes[srcIndex]; // U
          }
        }
      }
    } else {
      // Planar I420 (U riêng, V riêng) -> xen kẽ V và U thành NV21
      final halfWidth = width ~/ 2;
      final halfHeight = height ~/ 2;
      for (int row = 0; row < halfHeight; row++) {
        final uRowOffset = row * uPlane.bytesPerRow;
        final vRowOffset = row * vPlane.bytesPerRow;
        for (int col = 0; col < halfWidth; col++) {
          outBuffer[uvDest++] = vBytes[vRowOffset + col]; // V
          outBuffer[uvDest++] = uBytes[uRowOffset + col]; // U
        }
      }
    }

    return totalSize;
  }
}
