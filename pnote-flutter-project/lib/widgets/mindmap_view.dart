import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_mind_map/mind_map.dart';

import '../design/tokens.dart';
import 'com_mindmap.dart';
import 'full_screen_mindmap.dart';

/// 脑图节点：SummaryX 契约字段为大写 Title/Topic。
/// 兼容数组/单对象根、缺省 Topic、纯字符串子元素。
class MindmapNode {
  MindmapNode({this.title, this.topic});

  String? title;
  List<MindmapNode>? topic;

  factory MindmapNode.fromJson(Map<String, dynamic> json) {
    var rawList = json['Topic'];
    List<MindmapNode>? topics;

    if (rawList is List) {
      topics = rawList.map<MindmapNode>((e) {
        if (e is Map<String, dynamic>) {
          return MindmapNode.fromJson(e);
        }
        return MindmapNode(title: e?.toString() ?? '', topic: []);
      }).toList();
    }

    return MindmapNode(title: json['Title']?.toString(), topic: topics);
  }
}

/// Tab 内脑图视图：数据转换 + 缩放按钮 + 全屏入口。
/// [mindMapInstance] 必须由宿主页面级持有并传入（Tab 切换不重建实例）。
class MindMapNewView extends StatefulWidget {
  const MindMapNewView({
    super.key,
    required this.repaintKey,
    required this.mindmap,
    required this.mindMapInstance,
  });

  final GlobalKey repaintKey;
  final List<MindmapNode> mindmap;
  final MindMap mindMapInstance;

  @override
  State<MindMapNewView> createState() => _MindMapNewViewState();
}

class _MindMapNewViewState extends State<MindMapNewView> {
  /// MindmapNode(Title/Topic) → 插件数据格式 {id, content, nodes}。
  Map<String, dynamic> _rootData() {
    final root = widget.mindmap.first;
    return {
      'id': root.title ?? 'root',
      'content': root.title ?? '',
      'nodes': _getChildren(root.topic ?? []),
    };
  }

  List<Map<String, dynamic>> _getChildren(List<MindmapNode> children) {
    return [
      for (final c in children)
        {
          'id': '${c.title ?? ''}-${Random().nextInt(100000)}',
          'content': c.title ?? '',
          'nodes': _getChildren(c.topic ?? []),
        },
    ];
  }

  Future<void> _openFullscreenMindMap() async {
    if (widget.mindmap.isEmpty) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FullScreenMindMapPage(mindMapData: _rootData()),
    ));
  }

  void _setZoom(double zoom) {
    final cu = widget.mindMapInstance.getZoom();
    widget.mindMapInstance.setZoom(cu + zoom);
    widget.mindMapInstance.refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mindmap.isEmpty) return const SizedBox.shrink();
    return Stack(
      children: [
        Positioned.fill(
          child: ComMindMap(_rootData(), widget.repaintKey,
              mindMapInstance: widget.mindMapInstance),
        ),
        Positioned(
          top: 0,
          right: 0,
          child: Row(
            children: [
              IconButton(
                onPressed: _openFullscreenMindMap,
                icon: const Icon(Icons.fullscreen_rounded,
                    color: AppColors.muted),
              ),
              IconButton(
                onPressed: () => _setZoom(-0.1),
                icon: const Icon(Icons.do_not_disturb_on_outlined,
                    color: AppColors.muted),
              ),
              IconButton(
                onPressed: () => _setZoom(0.1),
                icon: const Icon(Icons.add_circle_outline_rounded,
                    color: AppColors.muted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
