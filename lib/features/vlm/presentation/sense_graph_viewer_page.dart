import 'package:flutter/material.dart';
import '../../sense_graph/models/sense_node.dart';
import '../../sense_graph/sense_graph_manager.dart';

class SenseGraphViewerPage extends StatefulWidget {
  const SenseGraphViewerPage({super.key});

  @override
  State<SenseGraphViewerPage> createState() => _SenseGraphViewerPageState();
}

class _SenseGraphViewerPageState extends State<SenseGraphViewerPage> {
  final SenseGraphManager _graphManager = SenseGraphManager();

  @override
  Widget build(BuildContext context) {
    final graph = _graphManager.graph;
    final views = graph.getNodesByType<ViewNode>()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final edges = graph.allEdges;
    final events = graph.getNodesByType<EventNode>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('SenseGraph World State', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() {}),
            tooltip: 'Tải lại',
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              await _graphManager.clear();
              setState(() {});
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Đã xóa sạch SenseGraph')),
                );
              }
            },
            tooltip: 'Xóa Graph',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header summary card
          Card(
            color: const Color(0xFF16161A),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0xFF2E2E38)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStat('Views', '${views.length}', Icons.visibility),
                  _buildStat('Objects', '${graph.getNodesByType<ObjectNode>().length}', Icons.category),
                  _buildStat('Texts', '${graph.getNodesByType<TextNode>().length}', Icons.text_fields),
                  _buildStat('Edges', '${edges.length}', Icons.linear_scale),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Events section if any
          if (events.isNotEmpty) ...[
            const Text(
              'Ghi nhận sự kiện (Events):',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 8),
            ...events.map((ev) => Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: ev.severity > 0.7 ? Colors.red.withAlpha(30) : const Color(0xFF1E1E26),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: ev.severity > 0.7 ? Colors.redAccent : const Color(0xFF2E2E38),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        ev.severity > 0.7 ? Icons.warning_amber : Icons.info_outline,
                        color: ev.severity > 0.7 ? Colors.redAccent : Colors.blueAccent,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '[${ev.type}] ${ev.description}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                )),
            const SizedBox(height: 16),
          ],

          // Views Tree Section
          const Text(
            'Cây cấu trúc không gian (Views & Entities):',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 8),
          if (views.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Text(
                  'Chưa có ViewNode nào trong SenseGraph.\nHãy chạy các agent ở tab VLM hoặc Camera để nạp.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                ),
              ),
            )
          else
            ...views.map((view) {
              final objects = graph.getObjectsForView(view.id);
              final texts = graph.getTextsForView(view.id);

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ExpansionTile(
                  initiallyExpanded: true,
                  leading: const Icon(Icons.remove_red_eye, color: Color(0xFF7F5AF0)),
                  title: Text(
                    '${view.id} (${view.sceneType ?? "Chưa phân loại"})',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  subtitle: Text(
                    '${objects.length} vật thể • ${texts.length} khối chữ',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (objects.isNotEmpty) ...[
                            const Text('├── Vật thể (Objects):', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                            ...objects.map((o) => Padding(
                                  padding: const EdgeInsets.only(left: 16, top: 3),
                                  child: Text(
                                    '• [${o.id}] ${o.className} (${(o.confidence * 100).toStringAsFixed(0)}%)',
                                    style: TextStyle(fontSize: 12, color: Colors.amber.shade200),
                                  ),
                                )),
                            const SizedBox(height: 6),
                          ],
                          if (texts.isNotEmpty) ...[
                            const Text('├── Chữ / Biển báo (Texts):', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                            ...texts.map((t) => Padding(
                                  padding: const EdgeInsets.only(left: 16, top: 3),
                                  child: Text(
                                    '• [${t.id}] "${t.normalizedText ?? t.rawText}" (${t.semanticType ?? "raw"})',
                                    style: TextStyle(fontSize: 12, color: Colors.greenAccent.shade200),
                                  ),
                                )),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),

          const SizedBox(height: 16),
          // Relations / Edges Section
          const Text(
            'Quan hệ ngữ nghĩa không gian (Spatial Edges):',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 8),
          if (edges.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Chưa có quan hệ không gian nào.',
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                ),
              ),
            )
          else
            ...edges.map((e) => Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF16161A),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF2E2E38)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.arrow_right_alt, size: 16, color: Color(0xFF7F5AF0)),
                      const SizedBox(width: 6),
                      Text(e.sourceId, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF7F5AF0).withAlpha(40),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          e.relation.name,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF7F5AF0),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(e.targetId, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    ],
                  ),
                )),
        ],
      ),
    );
  }

  Widget _buildStat(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 20, color: const Color(0xFF7F5AF0)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        Text(label, style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
      ],
    );
  }
}
