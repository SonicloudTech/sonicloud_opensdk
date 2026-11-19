import 'dart:math';
import 'dart:ui';
import 'package:flutter/src/rendering/custom_paint.dart';
import 'package:flutter_mind_map/adapter/i_link_adapter.dart';
import 'package:flutter_mind_map/i_mind_map_node.dart';
import 'package:flutter_mind_map/link/i_link.dart';

class PolyLineLink implements ILink {
  @override
  String getName() {
    return "PolyLineLink";
  }

  double radius = 10;
  double getRadius() {
    return radius;
  }

  void setRadius(double value) {
    radius = value;
  }

  @override
  CustomPainter getPainter(IMindMapNode node) {
    return PolyLineLinkPainter(node: node, radius: radius);
  }
}

class PolyLineLinkPainter extends CustomPainter {
  PolyLineLinkPainter({required this.node, required this.radius});

  IMindMapNode node;
  double radius;

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
              ..strokeCap = StrokeCap.round
              ..strokeWidth = item.getLinkWidth();

            Offset? itemOffset = item.getOffsetByParent();
            Size? itemSize = item.getSize();
            if (itemOffset != null && itemSize != null) {
              double w = (offset.dx - itemOffset.dx - itemSize.width) / 2;
              double h =
                  ((offset.dy + s.height / 2 + node.getLinkOutOffset()) -
                      (itemOffset.dy +
                          itemSize.height / 2 +
                          item.getLinkInOffset())) /
                  2;

              if (w > radius) {
                double r = radius;
                if (h.abs() < r) {
                  r = h.abs();
                }
                //Left HLine
                canvas.drawLine(
                  Offset(
                    itemOffset.dx + itemSize.width,
                    itemOffset.dy +
                        itemSize.height / 2 +
                        item.getLinkInOffset(),
                  ),
                  Offset(
                    itemOffset.dx + itemSize.width + w - r,
                    itemOffset.dy +
                        itemSize.height / 2 +
                        item.getLinkInOffset(),
                  ),
                  paint,
                );
                if (r > 0) {
                  //Left Arc
                  canvas.drawArc(
                    Rect.fromCenter(
                      center: Offset(
                        itemOffset.dx + itemSize.width + w - r,
                        itemOffset.dy +
                            itemSize.height / 2 +
                            item.getLinkInOffset() +
                            r *
                                ((offset.dy +
                                            s.height / 2 +
                                            node.getLinkOutOffset()) >
                                        (itemOffset.dy +
                                            itemSize.height / 2 +
                                            item.getLinkInOffset())
                                    ? 1
                                    : -1),
                      ),
                      width: r * 2,
                      height: r * 2,
                    ),
                    (offset.dy + s.height / 2 + node.getLinkOutOffset()) >
                            (itemOffset.dy +
                                itemSize.height / 2 +
                                item.getLinkInOffset())
                        ? pi * 3 / 2
                        : 0,
                    pi / 2,
                    false,
                    paint,
                  );
                  if (r >= radius) {
                    //Center VLine
                    canvas.drawLine(
                      Offset(
                        itemOffset.dx + itemSize.width + w,
                        itemOffset.dy +
                            itemSize.height / 2 +
                            item.getLinkInOffset() +
                            r *
                                ((offset.dy +
                                            s.height / 2 +
                                            node.getLinkOutOffset()) >
                                        (itemOffset.dy +
                                            itemSize.height / 2 +
                                            item.getLinkInOffset())
                                    ? 1
                                    : -1),
                      ),
                      Offset(
                        itemOffset.dx + itemSize.width + w,
                        offset.dy +
                            s.height / 2 +
                            node.getLinkOutOffset() -
                            r *
                                ((offset.dy +
                                            s.height / 2 +
                                            node.getLinkOutOffset()) >
                                        (itemOffset.dy +
                                            itemSize.height / 2 +
                                            item.getLinkInOffset())
                                    ? 1
                                    : -1),
                      ),
                      paint,
                    );
                  }
                  //Right Arc
                  canvas.drawArc(
                    Rect.fromCenter(
                      center: Offset(
                        itemOffset.dx + itemSize.width + w + r,
                        offset.dy +
                            s.height / 2 +
                            node.getLinkOutOffset() -
                            r *
                                ((offset.dy +
                                            s.height / 2 +
                                            node.getLinkOutOffset()) >
                                        (itemOffset.dy +
                                            itemSize.height / 2 +
                                            item.getLinkInOffset())
                                    ? 1
                                    : -1),
                      ),
                      width: r * 2,
                      height: r * 2,
                    ),
                    (offset.dy + s.height / 2 + node.getLinkOutOffset()) >
                            (itemOffset.dy +
                                itemSize.height / 2 +
                                item.getLinkInOffset())
                        ? pi / 2
                        : pi,
                    pi / 2,
                    false,
                    paint,
                  );
                }
                //Right HLine
                canvas.drawLine(
                  Offset(
                    itemOffset.dx + itemSize.width + w + r,
                    offset.dy + s.height / 2 + node.getLinkOutOffset(),
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
        }
        if (node.getNodeType() != NodeType.left) {
          for (IMindMapNode item in node.getRightItems()) {
            Paint paint = Paint()
              ..color = item.getLinkColor()
              ..style = PaintingStyle.stroke
              ..strokeCap = StrokeCap.round
              ..strokeWidth = item.getLinkWidth();

            Offset? itemOffset = item.getOffsetByParent();
            Size? itemSize = item.getSize();
            if (itemOffset != null && itemSize != null) {
              double w = (itemOffset.dx - offset.dx - s.width) / 2;
              double h =
                  ((offset.dy + s.height / 2 + node.getLinkOutOffset()) -
                      (itemOffset.dy +
                          itemSize.height / 2 +
                          item.getLinkInOffset())) /
                  2;

              if (w > radius) {
                double r = radius;
                if (h.abs() < r) {
                  r = h.abs();
                }
                //Right HLine
                canvas.drawLine(
                  Offset(
                    itemOffset.dx,
                    itemOffset.dy +
                        itemSize.height / 2 +
                        item.getLinkInOffset(),
                  ),
                  Offset(
                    itemOffset.dx - w + r,
                    itemOffset.dy +
                        itemSize.height / 2 +
                        item.getLinkInOffset(),
                  ),
                  paint,
                );
                if (r > 0) {
                  //Right Arc
                  canvas.drawArc(
                    Rect.fromCenter(
                      center: Offset(
                        itemOffset.dx - w + r,
                        itemOffset.dy +
                            itemSize.height / 2 +
                            item.getLinkInOffset() +
                            r *
                                ((offset.dy +
                                            s.height / 2 +
                                            node.getLinkOutOffset()) >
                                        (itemOffset.dy +
                                            itemSize.height / 2 +
                                            item.getLinkInOffset())
                                    ? 1
                                    : -1),
                      ),
                      width: r * 2,
                      height: r * 2,
                    ),
                    (offset.dy + s.height / 2 + node.getLinkOutOffset()) >
                            (itemOffset.dy +
                                itemSize.height / 2 +
                                item.getLinkInOffset())
                        ? pi
                        : pi / 2,
                    pi / 2,
                    false,
                    paint,
                  );
                  if (r >= radius) {
                    //Center VLine
                    canvas.drawLine(
                      Offset(
                        itemOffset.dx - w,
                        itemOffset.dy +
                            itemSize.height / 2 +
                            item.getLinkInOffset() +
                            r *
                                ((offset.dy +
                                            s.height / 2 +
                                            node.getLinkOutOffset()) >
                                        (itemOffset.dy +
                                            itemSize.height / 2 +
                                            item.getLinkInOffset())
                                    ? 1
                                    : -1),
                      ),
                      Offset(
                        itemOffset.dx - w,
                        offset.dy +
                            s.height / 2 +
                            node.getLinkOutOffset() -
                            r *
                                ((offset.dy +
                                            s.height / 2 +
                                            node.getLinkOutOffset()) >
                                        (itemOffset.dy +
                                            itemSize.height / 2 +
                                            item.getLinkInOffset())
                                    ? 1
                                    : -1),
                      ),
                      paint,
                    );
                  }
                  //Left Arc
                  canvas.drawArc(
                    Rect.fromCenter(
                      center: Offset(
                        itemOffset.dx - w - r,
                        offset.dy +
                            s.height / 2 +
                            node.getLinkOutOffset() -
                            r *
                                ((offset.dy +
                                            s.height / 2 +
                                            node.getLinkOutOffset()) >
                                        (itemOffset.dy +
                                            itemSize.height / 2 +
                                            item.getLinkInOffset())
                                    ? 1
                                    : -1),
                      ),
                      width: r * 2,
                      height: r * 2,
                    ),
                    (offset.dy + s.height / 2 + node.getLinkOutOffset()) >
                            (itemOffset.dy +
                                itemSize.height / 2 +
                                item.getLinkInOffset())
                        ? 0
                        : pi * 3 / 2,
                    pi / 2,
                    false,
                    paint,
                  );
                }
                //left HLine
                canvas.drawLine(
                  Offset(
                    itemOffset.dx - w - r,
                    offset.dy + s.height / 2 + node.getLinkOutOffset(),
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
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}

class PolyLineLinkAdapter implements ILinkAdapter {
  @override
  ILink createLink() {
    return PolyLineLink();
  }

  @override
  String getName() {
    return "PolyLineLink";
  }
}
