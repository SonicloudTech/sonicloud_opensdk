import 'package:flutter/material.dart';

abstract class IMindMapTheme {
  String getName();
  Map<String, dynamic>? getThemeByLevel(int level);
  Color getBackgroundColor();
}
