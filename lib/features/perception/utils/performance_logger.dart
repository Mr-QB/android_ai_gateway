import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class PerformanceLogger {
  static const String _fileName = 'agent_benchmark.jsonl';

  static Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// Appends a benchmark entry to agent_benchmark.jsonl
  static Future<void> logRecord({
    required String agent,
    required String model,
    required String backend,
    String? imageSize,
    int? promptTokens,
    int? outputTokens,
    double? ttftMs,
    double? generationMs,
    double? totalMs,
    double? nativeHeapMb,
    double? javaHeapMb,
    String? triggerReason,
  }) async {
    final entry = {
      'timestamp': DateTime.now().toIso8601String(),
      'agent': agent,
      'model': model,
      'backend': backend,
      'imageSize': imageSize ?? '512x512',
      'promptTokens': promptTokens ?? 0,
      'outputTokens': outputTokens ?? 0,
      'ttftMs': ttftMs,
      'generationMs': generationMs,
      'totalMs': totalMs,
      'memory': {
        'nativeHeapMb': nativeHeapMb,
        'javaHeapMb': javaHeapMb,
      },
      'triggerReason': triggerReason ?? 'manual_query',
    };

    try {
      final file = await _getFile();
      final line = '${jsonEncode(entry)}\n';
      await file.writeAsString(line, mode: FileMode.append, flush: true);
      debugPrint('[PerformanceLogger] Logged entry for $agent ($model, $totalMs ms)');
    } catch (e) {
      debugPrint('[PerformanceLogger] Error logging benchmark: $e');
    }
  }

  /// Returns the path to agent_benchmark.jsonl
  static Future<String> getLogPath() async {
    final file = await _getFile();
    return file.path;
  }
}
