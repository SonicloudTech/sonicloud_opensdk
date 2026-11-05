import 'package:flutter/material.dart';

/// 按钮统一沿用底部标签的圆角、配色和字重。
ThemeData createDemoTheme() {
  const primary = Color(0xFF3A7AFE);
  const surface = Color(0xFFF1F4FA);
  const disabled = Color(0xFFA5B0C1);
  const shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(12)),
  );
  final theme = ThemeData(
    colorScheme: const ColorScheme.light(primary: primary),
  );
  final textStyle = theme.textTheme.labelMedium?.copyWith(
    fontSize: 12,
    fontWeight: FontWeight.w600,
  );
  return theme.copyWith(
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: const Color(0xFFE7ECF5),
        disabledForegroundColor: disabled,
        shape: shape,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: const Size(0, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: textStyle,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        backgroundColor: surface,
        foregroundColor: primary,
        disabledForegroundColor: disabled,
        shape: shape,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: const Size(0, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: textStyle,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        backgroundColor: surface,
        foregroundColor: const Color(0xFF718096),
        shape: shape,
        padding: const EdgeInsets.all(6),
        minimumSize: const Size(36, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    ),
  );
}
