import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// Sonicloud开放平台访问令牌（打开页面先获取，2 小时有效，自动提前刷新）。
///
/// 作用对齐源项目的"登录 token"：
/// 1. 作为实时转写的连接门槛（无 token 不连）；
/// 2. 无用户体系时，userid = "sn" + token（源项目 `userInfo?.user?.id ?? token` 同款兜底）。
///
/// ⚠️ apiSecret 硬编码在客户端可被逆向提取，demo 可接受；
/// 正式产品应由自家后端中转签发。
class SinicloudAuth {
  SinicloudAuth._();

  static final SinicloudAuth instance = SinicloudAuth._();

  static const _appId = 'YOUR_APP_ID';
  static const _apiKey = 'YOUR_API_KEY';
  static const _apiSecret = 'YOUR_API_SECRET';
  static const _base = 'https://openapi.sinicloud.com';

  /// 非 license 方案：sign = md5(appId + apiKey + timeStamp + apiSecret)。
  static const _validity = Duration(hours: 2);

  String? _token;
  DateTime? _tokenAt;
  bool _fetching = false;

  /// 未过期的 token；过期/未获取返回 null。
  String? get token {
    final at = _tokenAt;
    if (_token == null || at == null) return null;
    // 提前 5 分钟视为过期，避免边界失效。
    if (DateTime.now()
        .isBefore(at.add(_validity - const Duration(minutes: 5)))) {
      return _token;
    }
    return null;
  }

  /// 获取（或刷新）token；失败返回 null（不抛异常，调用方按"无 token"处理）。
  Future<String?> fetchToken() async {
    final cached = token;
    if (cached != null) return cached;
    if (_fetching) return null;
    _fetching = true;
    try {
      final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final sign =
          md5.convert(utf8.encode('$_appId$_apiKey$ts$_apiSecret')).toString();
      final body = jsonEncode({
        'appId': _appId,
        'apiKey': _apiKey,
        'timeStamp': ts,
        'sign': sign,
      });
      final req = await HttpClient()
          .postUrl(Uri.parse('$_base/api/auth/get_token'))
        ..headers.contentType = ContentType.json;
      req.write(body);
      final resp = await req.close().timeout(const Duration(seconds: 15));
      final text = await resp.transform(utf8.decoder).join();
      final data = jsonDecode(text);
      if (data is Map && data['code'] == 0) {
        final t = data['data']?['token'];
        if (t is String && t.isNotEmpty) {
          _token = t;
          _tokenAt = DateTime.now();
          return t;
        }
      }
      debugPrint('[AUTH] get_token 失败: $text');
      return null;
    } catch (e) {
      debugPrint('[AUTH] get_token 异常: $e');
      return null;
    } finally {
      _fetching = false;
    }
  }
}
