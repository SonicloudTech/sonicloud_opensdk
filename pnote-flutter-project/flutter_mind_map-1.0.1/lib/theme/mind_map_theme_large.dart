import 'package:flutter/material.dart';
import 'package:flutter_mind_map/adapter/i_theme_adapter.dart';
import 'package:flutter_mind_map/link/beerse_line_link.dart';
import 'package:flutter_mind_map/theme/i_mind_map_theme.dart';

class MindMapThemeLarge implements IMindMapTheme {
  @override
  String getName() {
    return "Large";
  }

  @override
  Map<String, dynamic>? getThemeByLevel(int level) {
    switch (level) {
      case 0:
        return {
          "BackgroundColor": Colors.white,
          "TextColor": Colors.black,
          "FontSize": 20.0,
          "Bold": true,
          "LinkColor": Colors.deepPurpleAccent,
          "LinkWidth": 1.5,
          "HSpace": 60,
          "VSpace": 20,
          "Border": Border.all(
            color: Colors.deepPurpleAccent,
            width: 2,
            style: BorderStyle.solid,
            strokeAlign: BorderSide.strokeAlignOutside,
          ),
          "BorderRadius": BorderRadius.circular(100),
          "Padding": EdgeInsets.fromLTRB(24, 12, 24, 12),
          "Link": BeerseLineLink(),
        };
      case 1:
        return {
          "BackgroundColor": Colors.transparent,
          "TextColor": Colors.black,
          "FontSize": 15.0,
          "HSpace": 60,
          "VSpace": 20,
          "Border": Border.all(color: Colors.transparent, width: 0),
          "BorderRadius": BorderRadius.circular(100),
          "Padding": EdgeInsets.fromLTRB(12, 0, 12, 0),
          "LinkWidth": 1.5,
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

class MindMapThemeLargeAdapter implements IThemeAdapter {
  @override
  IMindMapTheme createTheme() {
    return MindMapThemeLarge();
  }

  @override
  String getName() {
    return "Large";
  }
}
