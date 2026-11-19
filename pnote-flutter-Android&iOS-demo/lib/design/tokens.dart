import 'package:flutter/material.dart';

/// 设计令牌 — 主色指定蓝 #3D9AFF。
abstract final class AppColors {
  // 主色
  static const primary = Color(0xFF3D9AFF);
  static const primaryLight = Color(0xFF7FBEFF);
  static const primaryDark = Color(0xFF1F7AE6);
  static const primaryFaint = Color(0xFFEAF4FF);
  static const primaryInk = Color(0xFF0B57A4);

  // 次色
  static const secondary = Color(0xFF0EA5E9);

  // 中性 zinc
  static const bg = Color(0xFFFAFAFA);
  static const surface = Colors.white;
  static const border = Color(0xFFE4E4E7);
  static const borderStrong = Color(0xFFD4D4D8);
  static const fill = Color(0xFFF4F4F5);
  static const ink = Color(0xFF18181B);
  static const inkSoft = Color(0xFF3F3F46);
  static const muted = Color(0xFF71717A);
  static const mutedFaint = Color(0xFFA1A1AA);

  // 语义色（克制使用，不做大面积）
  static const success = Color(0xFF16A34A);
  static const successFaint = Color(0xFFE7F6EC);
  static const warning = Color(0xFFD97706);
  static const danger = Color(0xFFDC2626);
}

abstract final class AppRadius {
  static const sm = 6.0;
  static const md = 8.0;
  static const lg = 12.0;
  static const xl = 16.0;
}
