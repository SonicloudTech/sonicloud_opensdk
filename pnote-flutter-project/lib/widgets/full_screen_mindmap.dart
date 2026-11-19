import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mind_map/mind_map.dart';
import 'package:flutter_mind_map/theme/mind_map_theme_compact.dart';

/// 脑图全屏页：横屏沉浸展示，右上退出并恢复竖屏。
class FullScreenMindMapPage extends StatefulWidget {
  final Map<String, dynamic> mindMapData;

  const FullScreenMindMapPage({super.key, required this.mindMapData});

  @override
  State<FullScreenMindMapPage> createState() => _FullScreenMindMapPageState();
}

class _FullScreenMindMapPageState extends State<FullScreenMindMapPage> {
  final GlobalKey _repaintKey = GlobalKey();
  late final MindMap _mindMap;

  @override
  void initState() {
    super.initState();
    _mindMap = MindMap(repaintKey: _repaintKey)
      ..setBackgroundColor(Colors.white)
      ..setReadOnly(true)
      ..setTheme(MindMapThemeCompact())
      ..setShowZoom(false)
      ..loadData(widget.mindMapData);

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  void dispose() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(child: _mindMap),
            Positioned(
              top: 8,
              left: 8,
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.fullscreen_exit_rounded, size: 30),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
