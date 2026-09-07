import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../graph_serializer.dart';
import '../sense_graph.dart';

abstract class ISenseGraphStorage {
  Future<void> saveGraph(SenseGraph graph);
  Future<SenseGraph> loadGraph();
  Future<void> clear();
}

class JsonFileGraphStorage implements ISenseGraphStorage {
  static const String _fileName = 'sense_graph.json';

  Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  @override
  Future<void> saveGraph(SenseGraph graph) async {
    try {
      final file = await _getFile();
      final data = GraphSerializer.toJson(graph);
      await file.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint('[SenseGraph Storage] Error saving graph: $e');
    }
  }

  @override
  Future<SenseGraph> loadGraph() async {
    try {
      final file = await _getFile();
      if (!await file.exists()) {
        return SenseGraph();
      }
      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      return GraphSerializer.fromJson(json);
    } catch (e) {
      debugPrint('[SenseGraph Storage] Error loading graph: $e');
      return SenseGraph();
    }
  }

  @override
  Future<void> clear() async {
    try {
      final file = await _getFile();
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('[SenseGraph Storage] Error clearing graph file: $e');
    }
  }
}
