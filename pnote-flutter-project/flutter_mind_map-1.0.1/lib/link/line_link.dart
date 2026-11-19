import 'dart:ui';

import 'package:flutter/src/rendering/custom_paint.dart';
import 'package:flutter_mind_map/adapter/i_link_adapter.dart';
import 'package:flutter_mind_map/i_mind_map_node.dart';
import 'package:flutter_mind_map/link/i_link.dart';

class LineLink implements ILink {
  @override
  String getName() {
    return "LineLink";
  }

  @override
  CustomPainter getPainter(IMindMapNode node) {
    return LineLinkPainter(node: node);
  }
}

class LineLinkPainter extends CustomPainter {
  LineLinkPainter({required this.node});
  IMindMapNode node;
  @override
  void paint(Canvas canvas, Size size) {
    if (node.getExpanded()) {
      Offset? offset = node.getOffset();
      Size? s = node.getSize();
      if (offset != null && s != null) {
        if (node.getNodeType() != NodeType.right) {
          for (IMindMapNode item in node.getLeftItems()) {
            Paint paint = Paint()
              ..color = item.getLinkColor()
              ..strokeWidth = item.getLinkWidth();
            Offset? itemOffset = item.getOffsetByParent();
            Size? itemSize = item.getSize();
            if (itemOffset != null && itemSize != null) {
              canvas.drawLine(
                Offset(
                  itemOffset.dx + itemSize.width,
                  itemOffset.dy + itemSize.height / 2 + item.getLinkInOffset(),
                ),
                Offset(
                  offset.dx,
                  offset.dy + s.height / 2 + node.getLinkOutOffset(),
                ),
                paint,
              );
            }
          }
        }
        if (node.getNodeType() != NodeType.left) {
          for (IMindMapNode item in node.getRightItems()) {
            Paint paint = Paint()
              ..color = item.getLinkColor()
              ..strokeWidth = item.getLinkWidth();
            Offset? itemOffset = item.getOffsetByParent();
            Size? itemSize = item.getSize();
            if (itemOffset != null && itemSize != null) {
              canvas.drawLine(
                Offset(
                  itemOffset.dx,
                  itemOffset.dy + itemSize.height / 2 + item.getLinkInOffset(),
                ),
                Offset(
                  offset.dx + s.width,
                  offset.dy + s.height / 2 + node.getLinkOutOffset(),
                ),
                paint,
              );
            }
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}

class LineLinkAdapter implements ILinkAdapter {
  @override
  ILink createLink() {
    return LineLink();
  }

  @override
  String getName() {
    return "LineLink";
  }
}
