import 'package:flutter/material.dart';
import 'package:flutter_mind_map/link/i_link.dart';
import 'package:flutter_mind_map/mind_map.dart';

abstract class IMindMapNode {
  String getID();
  String getTitle();
  void setTitle(String value);

  String getExtended();
  void setExtended(String value);

  MindMap? getMindMap();
  void setMindMap(MindMap value);
  NodeType getNodeType();
  void setNodeType(NodeType value);

  int getLevel();

  bool getExpanded();
  void setExpanded(bool value);

  ILink getLink();
  void setLink(ILink? value);
  Color getLinkColor();
  void setLinkColor(Color? value);

  double getLinkWidth();
  void setLinkWidth(double value);

  IMindMapNode? getParentNode();
  void setParentNode(IMindMapNode parentNode);
  int getHSpace();
  int getVSpace();

  List<IMindMapNode> getLeftItems();
  void setLeftItems(List<IMindMapNode> value);
  void addLeftItem(IMindMapNode item);
  void removeLeftItem(IMindMapNode item);
  void insertLeftItem(IMindMapNode item, int index);
  List<IMindMapNode> getRightItems();
  void setRightItems(List<IMindMapNode> value);
  void addRightItem(IMindMapNode item);
  void removeRightItem(IMindMapNode item);
  void insertRightItem(IMindMapNode item, int index);

  bool getReadOnly();
  bool canExpand();

  Offset? getOffset();
  void setOffset(Offset? value);
  Offset? getOffsetByParent();
  void setOffsetByParent(Offset? value);

  double getLinkInOffset();
  double getLinkOutOffset();

  Size? getSize();
  void setSize(Size? value);

  Rect? getLeftArea();
  Rect? getRightArea();
  Rect? getNodeArea();

  Offset getDragOffset();

  RenderObject? getRenderObject();
  void refresh();

  Map<String, dynamic> toJson();
  void fromJson(Map<String, dynamic> json);

  Map<String, dynamic> getData();
  void loadData(Map<String, dynamic> json);
}

enum NodeType { root, left, right }

Color stringToColor(String value) {
  if (value.startsWith("#") && value.length >= 9) {
    int alpha = int.parse(value.substring(1, 3), radix: 16);
    int colorValue = int.parse(value.substring(3, 9), radix: 16);
    return Color.fromARGB(
      0xff,
      colorValue >> 16,
      (colorValue >> 8) & 0xFF,
      colorValue & 0xFF,
    ).withAlpha(alpha);
  }
  return Colors.black;
}

String colorToString(Color color) {
  int a = (color.a * 255).toInt();
  int r = (color.r * 255).toInt();
  int g = (color.g * 255).toInt();
  int b = (color.b * 255).toInt();
  String ax = a < 16 ? "0" : "";
  String rx = r < 16 ? "0" : "";
  String gx = g < 16 ? "0" : "";
  String bx = b < 16 ? "0" : "";

  return "#$ax${a.toRadixString(16)}$rx${r.toRadixString(16)}$gx${g.toRadixString(16)}$bx${b.toRadixString(16)}";
}
