import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'logger.dart';

/// 首页外网权限引导。
///
/// 标准 iOS/Android 没有「访问互联网」运行时权限；国内部分安卓机型会在
/// **首次真正发起网络请求**时弹出「允许使用 WLAN / 移动数据」。
/// 因此在同意后立刻探测外网，以便弹出该系统框并让后续接口可用。
class NetworkPermissionService {
  NetworkPermissionService._();

  static const _flagName = 'internet_consent.flag';

  /// 进入首页后调用：未同意则弹窗，同意后探测外网。
  static Future<void> requestOnHomeEnter(BuildContext context) async {
    // if (!await _hasConsented()) {
    //   if (!context.mounted) return;
    //   // final agreed = await _showConsentDialog(context);
    //   // if (!agreed) {
    //   //   Log.w('用户拒绝外网访问说明');
    //   //   return;
    //   // }
    //   // await _saveConsent();
    // }
    await _probeInternet();
  }

  static Future<bool> _showConsentDialog(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) {
            return AlertDialog(
              title: const Text('网络权限说明'),
              content: const Text(
                '本应用需要访问互联网，用于请求接口、拉取配置与固件升级等功能。\n\n'
                '请点击「允许」以使用无线局域网或移动数据。',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('不允许'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('允许'),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  /// 主动访问外网：触发机型「网络权限」弹窗，并验证连通性。
  static Future<void> _probeInternet() async {
    try {
      final addrs = await InternetAddress.lookup('www.baidu.com')
          .timeout(const Duration(seconds: 5));
      final ok = addrs.isNotEmpty && addrs.first.rawAddress.isNotEmpty;
      Log.i('外网 DNS 探测: $ok');

      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 5);
      try {
        final req =
            await client.getUrl(Uri.parse('https://www.baidu.com'));
        final resp = await req.close().timeout(const Duration(seconds: 5));
        await resp.drain<void>();
        Log.i('外网 HTTP 探测完成: ${resp.statusCode}');
      } finally {
        client.close(force: true);
      }
    } catch (e) {
      Log.w('外网探测失败(可能未授权或无网): $e');
    }
  }

  static Future<File> _flagFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_flagName');
  }

  static Future<bool> _hasConsented() async {
    try {
      return await (await _flagFile()).exists();
    } catch (_) {
      return false;
    }
  }

  static Future<void> _saveConsent() async {
    try {
      await (await _flagFile()).writeAsString('1');
    } catch (e) {
      Log.e('保存外网同意标记失败: $e');
    }
  }
}
