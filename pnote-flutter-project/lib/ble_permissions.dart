import 'dart:io';

import 'package:flutter/services.dart';

/// Android 运行时蓝牙权限桥（零依赖实现，替代 permission_handler）。
///
/// Android 12+ 需要 BLUETOOTH_SCAN / BLUETOOTH_CONNECT 运行时授权，
/// Android 11 及以下需要精确定位；iOS 由系统在首次使用蓝牙时自动弹窗。
class BlePermissions {
  static const _channel = MethodChannel('pnote_demo/ble_permissions');

  /// 确保蓝牙运行时权限已授予；返回是否全部授权。
  static Future<bool> ensureGranted() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>('request') ?? false;
    } on MissingPluginException {
      return true;
    } on PlatformException {
      return false;
    }
  }

  /// 跳到本 App 的系统设置页（权限被永久拒绝时的兜底出口，仅 Android）。
  static Future<void> openAppSettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('openAppSettings');
    } catch (_) {}
  }
}
