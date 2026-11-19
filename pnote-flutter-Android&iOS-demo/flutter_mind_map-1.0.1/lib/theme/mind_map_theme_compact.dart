import 'package:flutter/material.dart';
import 'package:flutter_mind_map/adapter/i_theme_adapter.dart';
import 'package:flutter_mind_map/link/beerse_line_link.dart';
import 'package:flutter_mind_map/theme/i_mind_map_theme.dart';
import 'package:flutter_mind_map/link/poly_line_link.dart';
class MindMapThemeCompact implements IMindMapTheme {
  @override
  String getName() {
    return "Compact";
  }

  @override
  Map<String, dynamic>? getThemeByLevel(int level) {
    switch (level) {
      case 0:
        return {
          "BackgroundColor": Colors.white,
          "TextColor": Colors.black,
          "FontSize": 16.0,
          "Bold": true,
          "LinkColor": Colors.deepPurpleAccent,
          "LinkWidth": 3.5,
          "HSpace": 40,
          "VSpace": 10,
          "Border": Border.all(
            color: Colors.deepPurpleAccent,
            width: 2,
            style: BorderStyle.solid,
            strokeAlign: BorderSide.strokeAlignOutside,
          ),
          "BorderRadius": BorderRadius.circular(100),
          "Padding": EdgeInsets.fromLTRB(18, 9, 18, 9),
          "Link": PolyLineLink(),
        };
      case 1:
        return {
          "BackgroundColor": Colors.transparent,
          "TextColor": Colors.black,
          "FontSize": 12.0,
          "HSpace": 40,
          "VSpace": 10,
          "Border": Border.all(color: Colors.transparent, width: 0),
          "BorderRadius": BorderRadius.circular(0),
          "Padding": EdgeInsets.fromLTRB(6, 0, 6, 0),
          "LinkWidth": 3.5,
          "LinkColors": [
            Colors.deepPurpleAccent,
            Colors.blueAccent,
            Colors.green,
            Colors.deepOrangeAccent,
            Colors.cyan,
            Colors.redAccent,
            Colors.brown,
          ],
        };
    }
    return null;
  }

  @override
  Color getBackgroundColor() {
    return Colors.white;
  }
}

class MindMapThemeCompactAdapter implements IThemeAdapter {
  @override
  IMindMapTheme createTheme() {
    return MindMapThemeCompact();
  }

  @override
  String getName() {
    return "Compact";
  }
}
