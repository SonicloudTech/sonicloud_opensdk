import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:opus_codec_dart/opus_codec_dart.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'sinicloud_auth.dart';
import '../audio/opus_bootstrap.dart';

/// 转写 socket 三态（驱动 UI 指示：绿点 / 转圈 / 红点）。
enum PenAsrSocketState { disconnected, connecting, connected }

/// 录音笔实时转写服务（开放平台 talentStreamAsr 线路，单例）。
///
/// 数据源直接取 SDK 的 `recordDataStream`（opus 原始字节流，纯 Dart，无原生通道）：
/// 1. 按 40B 一帧解码为 PCM（s16le / 16kHz / 单声道）；
/// 2. 累积切 3200B（100ms）片发转写 WebSocket；
/// 3. 识别结果进 [results]，统一归一化 errCode：'3'=中间滚动结果 / '0'=完整句。
///
/// 协议要点（https://open.sinicloud.com/documents/webapi/stream-asr）：
/// - 连接 `wss://openapi.sinicloud.com/talentStreamAsr`，鉴权走 get_token 的
///   访问令牌（token 含 `+`/`/`，进 query 必须 URL 编码）；
/// - 连接成功服务端推 errCode=1000，之后才开始上行音频；
/// - 结束发文本帧 "end"，服务端补推最后一句（End>0）后 errCode=10 并关闭；
/// - 文档未定义静音保活——不发心跳（静音帧会产生识别记录计入计费）；
/// - onError（网络异常）才重连；onDone（服务端关闭）不重连——重连会被当新会话，
///   时间戳从 0 重计打乱字幕时间轴；
/// - 断线期间待发切片上限 20 片（约 2 秒）丢最旧，防时间轴错乱。
class PenAsrService {
  PenAsrService._();

  static final PenAsrService instance = PenAsrService._();

  /// 单个 opus 帧的字节数（录音笔固件约定：20ms/帧 @16kbps）。
  static const int _frameSize = kOpusFrameSize;

  /// socket 发送切片大小：100ms 的 s16le/16k/单声道 PCM。
  static const int _sliceSize = 3200;

  /// 断线期间待发切片的保留上限（约 2 秒），超出丢弃最旧的。
  static const int _maxPendingSlices = 20;

  /// 连续解码失败告警阈值。
  static const int _decodeFailThreshold = 50;

  /// 重连退避序列（秒）：指数递增封顶 15s，连接成功后从头计数。
  static const List<int> _reconnectDelays = [3, 6, 12, 15];

  /// 识别结果流（归一化 Map：errCode '0'=定稿 / '3'=临时，一次一条）。
  final StreamController<Map<String, dynamic>> _resultsController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get results => _resultsController.stream;

  /// socket 三态。
  final ValueNotifier<PenAsrSocketState> socketState =
      ValueNotifier(PenAsrSocketState.disconnected);

  // ---- 事件回调（由 Session 接线，输出到 Activity 控制台） ----
  VoidCallback? onConnecting;
  VoidCallback? onConnected;
  VoidCallback? onDisconnected;
  VoidCallback? onDecodeWarn;
  void Function(String error)? onConnectFailed;
  void Function(int attempt, int delaySeconds)? onReconnectScheduled;

  /// 余额低于 1000 秒警告（连接保持，errCode=1001）。
  void Function(int balanceSeconds)? onLowBalance;

  /// 服务端错误码（4xxx 参数/鉴权、5xxx 运行时，随后连接会被关闭）。
  void Function(String code, String msg)? onServerError;

  bool _sessionActive = false;
  bool isConnected = false;
  SimpleOpusDecoder? _decoder;
  WebSocketChannel? _channel;
  StreamSubscription<Uint8List>? _audioSub;

  /// 当前未凑满一个切片的 PCM 累积。
  final BytesBuilder _acc = BytesBuilder();

  /// socket 未就绪期间缓存的待发切片。
  final List<Uint8List> _pendingSlices = [];

  String? _currentUserId;
  String? _currentToken;
  bool _connecting = false;
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;

  /// 发送 "end" 后等待服务端补推最后一句的兜底收尾定时器。
  Timer? _endGraceTimer;
  int _consecutiveDecodeFails = 0;
  bool _decodeFailWarned = false;

  bool get sessionActive => _sessionActive;

  static Uri _buildUrl(String token, String userId) => Uri(
        scheme: 'wss',
        host: 'openapi.sinicloud.com',
        path: '/talentStreamAsr',
        // Uri.queryParameters 自动做 URL 编码（token 含 + / = 等，必须编码）。
        // role=1：区分发言人，结果帧携带 spkid（"1"=说话人1）。
        queryParameters: {
          'X-SC-Authorization': token,
          'X-SC-User-Id': userId,
          'lanid': '0',
          'role': '1',
        },
      );

  /// 开始一个转写会话（幂等）。[opusStream] 为设备实时 opus 字节流，
  /// [userId] 为客户自定义用户标识。连接前先取平台访问令牌。
  Future<void> start(Stream<Uint8List> opusStream, String userId) async {
    if (_sessionActive) return;
    _sessionActive = true;
    _currentUserId = userId;
    _reconnectAttempts = 0;
    _consecutiveDecodeFails = 0;
    _decodeFailWarned = false;

    final token = await SinicloudAuth.instance.fetchToken();
    if (token == null) {
      _sessionActive = false;
      socketState.value = PenAsrSocketState.disconnected;
      onConnectFailed?.call('get token failed');
      return;
    }
    _currentToken = token;

    await ensureOpusInitialized();
    _decoder ??= createPenDecoder();
    unawaited(_connectSocket(token));

    _audioSub?.cancel();
    _audioSub = opusStream.listen(
      _onAudioPacket,
      onError: (e) => debugPrint('[ASR] audio stream error: $e'),
      cancelOnError: false,
    );
  }

  /// 结束会话（幂等）：停音频订阅，发文本帧 "end" 让服务端补推最后一句，
  /// 服务端回 errCode=10 后关闭连接；3s 兜底强收。
  Future<void> finishSession() async {
    if (!_sessionActive) return;
    _sessionActive = false;
    socketState.value = PenAsrSocketState.disconnected;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _audioSub?.cancel();
    _audioSub = null;

    final channel = _channel;
    if (channel != null && isConnected) {
      try {
        channel.sink.add('end');
      } catch (_) {}
      _endGraceTimer?.cancel();
      _endGraceTimer = Timer(const Duration(seconds: 3), _fullTeardown);
    } else {
      _fullTeardown();
    }
  }

  /// 彻底释放：关 socket、销毁解码器、清缓冲。
  void _fullTeardown() {
    _endGraceTimer?.cancel();
    _endGraceTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    final channel = _channel;
    _channel = null;
    if (channel != null) {
      try {
        channel.sink.close();
      } catch (_) {}
    }
    _decoder?.destroy();
    _decoder = null;
    _acc.clear();
    _pendingSlices.clear();
    isConnected = false;
  }

  // ==================== 音频接收与解码 ====================

  void _onAudioPacket(Uint8List packet) {
    if (!_sessionActive || packet.isEmpty) return;

    final pcm = BytesBuilder();
    // 按 40B 切帧逐帧解码；尾包不足一整帧的丢弃（固件帧定长）。
    for (var i = 0; i + _frameSize <= packet.length; i += _frameSize) {
      final frame = Uint8List.sublistView(packet, i, i + _frameSize);
      final out = decodePenFrame(_decoder!, frame);
      if (out != null) {
        pcm.add(out);
        _consecutiveDecodeFails = 0;
      } else {
        _consecutiveDecodeFails++;
        if (_consecutiveDecodeFails >= _decodeFailThreshold &&
            !_decodeFailWarned) {
          _decodeFailWarned = true;
          debugPrint('[ASR] opus 连续解码失败 $_consecutiveDecodeFails 次');
          onDecodeWarn?.call();
        }
      }
    }

    final bytes = pcm.takeBytes();
    if (bytes.isEmpty) return;
    _feedPcm(bytes);
  }

  void _feedPcm(Uint8List bytes) {
    _acc.add(bytes);
    while (_acc.length >= _sliceSize) {
      final all = _acc.takeBytes();
      var offset = 0;
      while (offset + _sliceSize <= all.length) {
        _enqueueSlice(Uint8List.sublistView(all, offset, offset + _sliceSize));
        offset += _sliceSize;
      }
      if (offset < all.length) {
        _acc.add(Uint8List.sublistView(all, offset));
      }
    }
  }

  void _enqueueSlice(Uint8List slice) {
    final channel = _channel;
    if (isConnected && channel != null) {
      try {
        channel.sink.add(slice);
      } catch (e) {
        debugPrint('[ASR] 切片发送失败，转入待发队列: $e');
        _pendingSlices.add(Uint8List.fromList(slice));
      }
    } else {
      // socket 未就绪：缓存待连接成功后冲刷（超出上限丢最旧）。
      _pendingSlices.add(Uint8List.fromList(slice));
      if (_pendingSlices.length > _maxPendingSlices) {
        _pendingSlices.removeRange(0, _pendingSlices.length - _maxPendingSlices);
      }
    }
  }

  // ==================== WebSocket 连接 ====================

  Future<void> _connectSocket(String token) async {
    if (_connecting || !_sessionActive) return;
    _connecting = true;
    socketState.value = PenAsrSocketState.connecting;
    onConnecting?.call();
    try {
      final userId = _currentUserId;
      if (userId == null) return;
      final channel = WebSocketChannel.connect(_buildUrl(token, userId));
      // 连接超时：路由不通时 OS 级 TCP 超时可拖到 75s，主动 15s 截断。
      await channel.ready.timeout(const Duration(seconds: 15));
      if (!_sessionActive) {
        await channel.sink.close();
        return;
      }
      try {
        _channel?.sink.close();
      } catch (_) {}
      _channel = channel;
      _reconnectAttempts = 0; // 连上即复位
      isConnected = false; // 开放平台：等 errCode=1000 确认
      channel.stream.listen(_onData,
          onError: _onSocketError, onDone: _onSocketDone, cancelOnError: true);
    } catch (e) {
      debugPrint('[ASR] socket 连接失败: $e');
      onConnectFailed?.call('$e');
      _scheduleReconnect();
    } finally {
      _connecting = false;
    }
  }

  void _flushPending() {
    if (_pendingSlices.isEmpty) return;
    if (_pendingSlices.length > _maxPendingSlices) {
      _pendingSlices.removeRange(0, _pendingSlices.length - _maxPendingSlices);
    }
    final channel = _channel;
    if (channel == null) return;
    for (final s in _pendingSlices) {
      try {
        channel.sink.add(s);
      } catch (_) {}
    }
    _pendingSlices.clear();
  }

  /// 服务端推送：裸换行剥离 + 多条拼接拆分 + errCode 分流
  /// （1000 确认 / 1001 低余额 / 0 结果按 End 归一化为 '0'定稿/'3'临时 /
  /// 10 流结束 / 其余错误码上抛回调）。
  ///
  /// 注意：开放平台会把裸换行混进报文（1000 消息的 result 值即换行符，
  /// 部分报文尾部还追加换行），严格 jsonDecode 必失败——先整体剥离换行。
  void _onData(dynamic event) {
    final text =
        event.toString().replaceAll('\n', '').replaceAll('\r', '');
    final parts = text.split(RegExp(r'}\s*{'));
    for (var item in parts) {
      if (!item.startsWith('{')) item = '{$item';
      if (!item.endsWith('}')) item = '$item}';
      try {
        final json = jsonDecode(item);
        if (json is! Map<String, dynamic>) continue;
        final code = json['errCode']?.toString() ?? '';
        switch (code) {
          case '1000':
            // 开放平台连接确认，可开始上行。
            isConnected = true;
            _flushPending();
            socketState.value = PenAsrSocketState.connected;
            onConnected?.call();
          case '1001':
            final balance = (json['balance'] as num?)?.toInt() ?? 0;
            debugPrint('[ASR] 余额不足警告：剩 $balance 秒');
            onLowBalance?.call(balance);
          case '0':
            final text = json['result']?.toString() ?? '';
            if (text.isEmpty) break;
            // End>0 = 完整句（定稿），End==0 = 中间滚动结果（临时）。
            final end = (json['End'] as num?)?.toInt() ?? 0;
            debugPrint('[ASR] ${end > 0 ? '定稿' : '滚动'}: $text');
            if (!_resultsController.isClosed) {
              _resultsController.add({
                'errCode': end > 0 ? '0' : '3',
                'result': text,
                if (json['spkid'] != null)
                  'spkid': json['spkid']?.toString() ?? '',
              });
            }
          case '3':
            // 错误码表：3 = 流识别未结束，即中间滚动结果（实测流走此码）。
            final text = json['result']?.toString() ?? '';
            debugPrint('[ASR] 滚动: $text');
            if (text.isNotEmpty && !_resultsController.isClosed) {
              _resultsController.add({
                'errCode': '3',
                'result': text,
                if (json['spkid'] != null)
                  'spkid': json['spkid']?.toString() ?? '',
              });
            }
          case '10':
            debugPrint('[ASR] 整个流结束（errCode=10）');
          default:
            debugPrint('[ASR] 服务端错误码 $code: ${json['result']}');
            onServerError?.call(code, json['result']?.toString() ?? '');
        }
      } catch (err) {
        debugPrint('[ASR] 消息解析失败: $err');
      }
    }
  }

  void _onSocketError(Object err) {
    // onError = 真正的网络异常（TCP 重置/超时等）→ 走重连。
    debugPrint('[ASR] socket 网络异常: $err');
    if (!_sessionActive) {
      _fullTeardown();
      return;
    }
    isConnected = false;
    socketState.value = PenAsrSocketState.connecting;
    onDisconnected?.call();
    _scheduleReconnect();
  }

  void _onSocketDone() {
    if (!_sessionActive) {
      // finishSession 发 "end" 后服务端正常关闭，或主动 close。
      _fullTeardown();
      return;
    }
    // onDone 不重连：重连后服务端按新会话处理，时间戳从头计会打乱字幕；
    // 接受转写缺口，只有网络异常（onError）才重连。
    debugPrint('[ASR] socket 被动断开: closeCode=${_channel?.closeCode}');
    isConnected = false;
    socketState.value = PenAsrSocketState.disconnected;
    onDisconnected?.call();
    _fullTeardown();
  }

  void _scheduleReconnect() {
    if (!_sessionActive || _reconnectTimer != null) return;
    final token = _currentToken;
    if (token == null) return;
    final delay = _reconnectDelays[
        _reconnectAttempts.clamp(0, _reconnectDelays.length - 1)];
    _reconnectAttempts++;
    onReconnectScheduled?.call(_reconnectAttempts, delay);
    _reconnectTimer = Timer(Duration(seconds: delay), () {
      _reconnectTimer = null;
      if (_sessionActive) {
        unawaited(_connectSocket(token));
      }
    });
  }
}
