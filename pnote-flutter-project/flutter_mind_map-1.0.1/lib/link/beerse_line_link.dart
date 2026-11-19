import 'dart:ui';

import 'package:flutter/src/rendering/custom_paint.dart';
import 'package:flutter_mind_map/adapter/i_link_adapter.dart';
import 'package:flutter_mind_map/i_mind_map_node.dart';
import 'package:flutter_mind_map/link/i_link.dart';

class BeerseLineLink implements ILink {
  @override
  String getName() {
    return "BeerseLineLink";
  }

  @override
  CustomPainter getPainter(IMindMapNode node) {
    return BeerseLineLinkPainter(node: node);
  }
}

class BeerseLineLinkPainter extends CustomPainter {
  BeerseLineLinkPainter({required this.node});
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
              ..style = PaintingStyle.stroke
              ..strokeWidth = item.getLinkWidth();
            Offset? itemOffset = item.getOffsetByParent();
            Size? itemSize = item.getSize();
            if (itemOffset != null && itemSize != null) {
              Path path = Path();
              path.moveTo(
                itemOffset.dx + itemSize.width,
                itemOffset.dy + itemSize.height / 2 + item.getLinkInOffset(),
              );
              path.cubicTo(
                itemOffset.dx + itemSize.width + node.getHSpace() / 2,
                itemOffset.dy + itemSize.height / 2 + item.getLinkInOffset(),
                offset.dx - node.getHSpace() / 2,
                offset.dy + s.height / 2 + node.getLinkOutOffset(),
                offset.dx,
                offset.dy + s.height / 2 + node.getLinkOutOffset(),
              );
              canvas.drawPath(path, paint);
            }
          }
        }
        if (node.getNodeType() != NodeType.left) {
          for (IMindMapNode item in node.getRightItems()) {
            Paint paint = Paint()
              ..color = item.getLinkColor()
              ..style = PaintingStyle.stroke
              ..strokeWidth = item.getLinkWidth();

            Offset? itemOffset = item.getOffsetByParent();
            Size? itemSize = item.getSize();
            if (itemOffset != null && itemSize != null) {
              Path path = Path();
              path.moveTo(
                itemOffset.dx,
                itemOffset.dy + itemSize.height / 2 + item.getLinkInOffset(),
              );
              path.cubicTo(
                itemOffset.dx - (node.getHSpace() / 2),
                itemOffset.dy + itemSize.height / 2 + item.getLinkInOffset(),
                offset.dx + s.width + (node.getHSpace() / 2),
                offset.dy + s.height / 2 + node.getLinkOutOffset(),
                offset.dx + s.width,
                offset.dy + s.height / 2 + node.getLinkOutOffset(),
              );
              canvas.drawPath(path, paint);
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

class BeerseLinkLinkAdapter implements ILinkAdapter {
  @override
  ILink createLink() {
    return BeerseLineLink();
  }

  @override
  String getName() {
    return "BeerseLineLink";
  }
}
