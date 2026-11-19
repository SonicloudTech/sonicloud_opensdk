import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../asr/sinicloud_auth.dart';

/// SummaryX 会议纪要失败（msg 优先用服务端文案，code 便于日志定位）。
class SummaryException implements Exception {
  SummaryException(this.msg, [this.code = '']);

  final String msg;
  final String code;

  @override
  String toString() => code.isEmpty ? msg : '$msg（$code）';
}

/// 会议纪要服务（SummaryX）：提交转写 → 轮询 analysisDetail → 拉取 Markdown。
/// 共享分析 + 独立产物：task_id 可复用，纪要接口同任务只计费一次。
class SummaryService {
  SummaryService._();

  static final SummaryService instance = SummaryService._();

  /// ⚠️ 鉴权实测结论（openapi.sinicloud.com 网关）：
  /// 必须同时携带 `X-SC-Authorization`（访问令牌）与 `X-SC-User-Id`（自定义用户 ID）
  /// 两个 header，缺一或多带 Authorization: Bearer 都报 code=1000「header参数错误」。
  static const _base = 'https://openapi.sinicloud.com';

  /// 轮询节奏：文档提示分析通常 30~90s，5s 一次 × 40 次 ≈ 200s 上限。
  static const _pollInterval = Duration(seconds: 5);
  static const _maxPolls = 40;
  static const _timeout = Duration(seconds: 20);

  Future<Map<String, String>> _headers(String userId) async {
    final token = await SinicloudAuth.instance.fetchToken();
    if (token == null) {
      throw SummaryException('get token failed', 'token');
    }
    return {
      'X-SC-Authorization': token,
      'X-SC-User-Id': userId,
    };
  }

  Future<dynamic> _request(
    String method,
    String path, {
    required String userId,
    Map<String, String>? query,
    Map<String, dynamic>? body,
  }) async {
    final client = HttpClient();
    try {
      final headers = await _headers(userId);
      final uri = Uri.parse('$_base$path').replace(
        queryParameters: query?.map((k, v) => MapEntry(k, v)),
      );
      final req = await client.openUrl(method, uri)
        ..headers.contentType = ContentType.json;
      headers.forEach(req.headers.set);
      if (body != null) req.write(jsonEncode(body));

      // 控制台完整请求/响应（仅 debug；token 脱敏防日志外泄）。
      assert(() {
        debugPrint('[AI] → $method $uri');
        debugPrint('[AI] → headers ${headers.map(
          (k, v) => MapEntry(k, k == 'X-SC-Authorization' ? _mask(v) : v),
        )}');
        if (body != null) debugPrint('[AI] → body ${jsonEncode(body)}');
        return true;
      }());

      final resp = await req.close().timeout(_timeout);
      final text = await resp.transform(utf8.decoder).join();
      assert(() {
        debugPrint('[AI] ← ${resp.statusCode} $text');
        return true;
      }());

      final json = jsonDecode(text);
      if (json is Map && json['code'] == 0 && json['data'] is Map) {
        return json['data'];
      }
      if (json is Map && json['code'] == 0) return const {};
      throw SummaryException(
        json is Map ? (json['msg']?.toString() ?? 'unknown') : 'bad response',
        json is Map ? json['code']?.toString() ?? '' : 'parse',
      );
    } on SocketException catch (e) {
      throw SummaryException('network error: $e', 'net');
    } on TimeoutException {
      throw SummaryException('request timeout', 'timeout');
    } finally {
      client.close();
    }
  }

  /// token 脱敏：保留首尾片段，足够比对又不整串泄露到日志。
  static String _mask(String token) =>
      token.length <= 24 ? '***' : '${token.substring(0, 12)}…${token.substring(token.length - 6)}';

  /// 提交会议转写，返回 task_id（有效字符需 > 300，否则服务端拒 3101）。
  /// [language] 输出语种：界面中文（含繁中系统）传 zh，其余一律 en。
  Future<String> createAnalysis(
    String text, {
    required String userId,
    required String language,
  }) async {
    final data = await _request('POST', '/v1/meeting/createAnalysis',
        userId: userId,
        body: {
          'text': text,
          'source_type': 'transcript',
          'language': language,
        });
    final id = data is Map ? data['task_id'] : null;
    if (id is String && id.isNotEmpty) return id;
    throw SummaryException('no task_id in response', 'parse');
  }

  /// 轮询直到终态。succeeded 正常返回；failed/canceled 抛服务端错误信息。
  Future<void> pollUntilDone(String taskId, {required String userId}) async {
    for (var i = 0; i < _maxPolls; i++) {
      final data = await _request('GET', '/v1/meeting/analysisDetail',
          userId: userId, query: {'task_id': taskId});
      final status = data is Map ? data['status']?.toString() ?? '' : '';
      debugPrint('[AI] analysisDetail status=$status (${i + 1}/$_maxPolls)');
      if (status == 'succeeded') return;
      if (status == 'failed' || status == 'canceled') {
        final err = data is Map ? data['error'] : null;
        throw SummaryException(
          err is Map ? err['message']?.toString() ?? status : status,
          status,
        );
      }
      await Future.delayed(_pollInterval);
    }
    throw SummaryException('分析超时（200s）', 'poll_timeout');
  }

  /// 拉取最终纪要（Markdown）。同任务重复拉取不重复计费。
  Future<String> fetchSummary(String taskId, {required String userId}) async {
    final data = await _request('GET', '/v1/meeting/summary',
        userId: userId, query: {'task_id': taskId});
    final s = data is Map ? data['summary']?.toString() : null;
    if (s == null || s.isEmpty) throw SummaryException('empty summary', 'empty');
    return s;
  }

  /// 获取思维导图节点树（服务端原始 List 结构）。
  /// 首次请求触发按需规划，pending 期间轮询到 ready/failed。
  Future<List<dynamic>> fetchMindmap(String taskId,
      {required String userId}) async {
    for (var i = 0; i < 12; i++) {
      final data = await _request('GET', '/v1/meeting/mindmap',
          userId: userId, query: {'task_id': taskId});
      final status =
          data is Map ? data['mindmap_status']?.toString() ?? '' : '';
      debugPrint('[AI] mindmap status=$status (${i + 1}/12)');
      if (status == 'ready') {
        final nodes = data is Map ? data['MindMapSummary'] : null;
        if (nodes is List && nodes.isNotEmpty) return nodes;
        throw SummaryException('导图为空', 'empty');
      }
      if (status == 'failed') {
        throw SummaryException('导图生成失败', 'mindmap_failed');
      }
      await Future.delayed(_pollInterval);
    }
    throw SummaryException('导图生成超时', 'poll_timeout');
  }
}
