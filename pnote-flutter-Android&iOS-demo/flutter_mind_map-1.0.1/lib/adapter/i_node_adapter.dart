import 'package:flutter_mind_map/i_mind_map_node.dart';

abstract class INodeAdapter {
  String getName();
  IMindMapNode createNode();
}
