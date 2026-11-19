import 'package:flutter_mind_map/theme/i_mind_map_theme.dart';

abstract class IThemeAdapter {
  String getName();
  IMindMapTheme createTheme();
}
