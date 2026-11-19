import 'package:flutter/material.dart';
import 'package:flutter_mind_map/mind_map.dart';
import 'package:flutter_mind_map/theme/mind_map_theme_compact.dart';

/// MindMap 实例封装：白底 + 只读 + Compact 主题（中心白底粗体胶囊 + 紫描边折线）。
class ComMindMap extends StatefulWidget {
  final GlobalKey repaintKey;
  final Map<String, dynamic> mindData;
  final MindMap mindMapInstance;

  const ComMindMap(this.mindData, this.repaintKey,
      {super.key, required this.mindMapInstance});

  @override
  State<StatefulWidget> createState() => ComMindMapState();
}

class ComMindMapState extends State<ComMindMap> {
  Future<void> init() async {
    widget.mindMapInstance.loadData(widget.mindData);
    widget.mindMapInstance.addOnChangedListeners(onChanged);
  }

  void onChanged() {
    // 只读模式下不会触发，保留空实现（对齐源项目封装）。
    widget.mindMapInstance.toJson();
  }

  @override
  void initState() {
    widget.mindMapInstance.setBackgroundColor(Colors.white);
    widget.mindMapInstance.setReadOnly(true);
    widget.mindMapInstance.setTheme(MindMapThemeCompact());
    widget.mindMapInstance.setShowZoom(false);
    super.initState();
    init();
  }

  @override
  Widget build(BuildContext context) {
    return widget.mindMapInstance;
  }
}
