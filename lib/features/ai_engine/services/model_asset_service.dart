import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class Yolo26ModelFiles {
  final String paramPath;
  final String binPath;

  const Yolo26ModelFiles({required this.paramPath, required this.binPath});
}

// Backward compatibility alias
typedef NanoDetModelFiles = Yolo26ModelFiles;

/// Chuẩn bị model NCNN thành các file thật trên bộ nhớ riêng của ứng dụng.
///
/// Flutter assets nằm bên trong APK nên C++ không thể dùng trực tiếp như một
/// đường dẫn thông thường. Service này copy model sang Application Support.
class ModelAssetService {
  static const String _paramAsset = 'assets/models/yolo26n.param';

  static const String _binAsset = 'assets/models/yolo26n.bin';

  Future<Yolo26ModelFiles> prepareYolo26Model() async {
    final Directory supportDirectory = await getApplicationSupportDirectory();

    final Directory modelDirectory = Directory(
      '${supportDirectory.path}/models',
    );

    await modelDirectory.create(recursive: true);

    final File paramFile = File('${modelDirectory.path}/yolo26n.param');

    final File binFile = File('${modelDirectory.path}/yolo26n.bin');

    await _copyAssetIfNeeded(assetPath: _paramAsset, destination: paramFile);

    await _copyAssetIfNeeded(assetPath: _binAsset, destination: binFile);

    return Yolo26ModelFiles(paramPath: paramFile.path, binPath: binFile.path);
  }

  // Alias for backward compatibility
  Future<Yolo26ModelFiles> prepareNanoDetModel() => prepareYolo26Model();

  Future<void> _copyAssetIfNeeded({
    required String assetPath,
    required File destination,
  }) async {
    final ByteData data = await rootBundle.load(assetPath);

    final Uint8List bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );

    // Tránh ghi lại model trong mỗi lần ứng dụng khởi động.
    if (await destination.exists()) {
      final int currentLength = await destination.length();

      if (currentLength == bytes.length) {
        return;
      }
    }

    await destination.writeAsBytes(bytes, flush: true);
  }
}
