import 'package:flutter/material.dart';
import 'package:flutter_mind_map/i_mind_map_node.dart';

abstract class ILink {
  String getName();
  CustomPainter getPainter(IMindMapNode node);
}
