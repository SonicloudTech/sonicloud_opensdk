import 'dart:async';

import 'package:flutter/foundation.dart';

import '../provider_record_pen.dart';
import '../test_report.dart';

class BluetoothConnectionTestRunner extends ChangeNotifier {
  BluetoothConnectionTestRunner(
    this._provider, {
    bool Function()? canStartTest,
    void Function(String)? onReport,
  }) : _canStartTest = canStartTest,
       _onReport = onReport {
    _provider.addListener(_sync);
  }

  final RecordPenProvider _provider;
  final bool Function()? _canStartTest;
  final void Function(String)? _onReport;
  Map<String, dynamic>? _device;
  bool _isRunning = false;
  bool _interrupted = false;
  bool _targetChanged = false;
  bool _closeUnconfirmed = false;
  bool _disposed = false;
  int _total = 0;
  int _successes = 0;
  int _failureCount = 0;
  String _status = '等待开始';
  Completer<void>? _finished;
  void Function(Object)? _cancelPending;

  bool get isRunning => _isRunning;
  bool get canStart =>
      !_disposed &&
      !_isRunning &&
      _connectedDevice != null &&
      !_provider.isRecording &&
      !_provider.isFileTransferring &&
      (_canStartTest?.call() ?? true);
  Map<String, dynamic>? get device =>
      _device == null ? null : Map.unmodifiable(_device!);
  int get total => _total;
  int get completed => _successes + _failureCount;
  int get successes => _successes;
  int get failureCount => _failureCount;
  String get status => _status;

  String _value(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text == 'null' ? '' : text;
  }

  Map<String, dynamic>? get _connectedDevice {
    if (!_provider.isConnected) return null;
    final info = _provider.deviceInfo;
    if (info == null || _value(info['name']).isEmpty) return null;
    return {
      ...info,
      'name': _value(info['name']),
      'address': _value(info['address']),
      'productType': _provider.deviceType,
    };
  }

  bool _matches(Map data) {
    final address = _value(_device?['address']);
    return address.isNotEmpty
        ? _value(data['address']).toLowerCase() == address.toLowerCase()
        : _value(data['name']) == _value(_device?['name']);
  }

  void _sync() {
    final current = _connectedDevice;
    if (_isRunning && current != null && !_matches(current)) {
      _targetChanged = true;
      _cancelPending?.call(StateError('连接已切换到其他设备'));
    }
    if (!_disposed) notifyListeners();
  }

  void clearResults() {
    if (_isRunning) throw StateError('请先结束蓝牙连接测试');
    _total = 0;
    _successes = 0;
    _failureCount = 0;
    _setStatus('等待开始');
  }

  void _checkActive() {
    if (_disposed || _interrupted) throw StateError('测试已中断');
    if (_targetChanged) throw StateError('连接已切换到其他设备');
  }

  void _setStatus(String status) {
    _status = status;
    if (!_disposed) notifyListeners();
  }

  Future<void> start({
    required int attempts,
    required Duration reconnectInterval,
    Duration disconnectDelay = Duration.zero,
  }) async {
    if (!canStart) throw StateError('请先连接设备并停止录音或文件传输');
    if (attempts < 1) throw ArgumentError.value(attempts, 'attempts');
    if (reconnectInterval.isNegative) {
      throw ArgumentError.value(reconnectInterval, 'reconnectInterval');
    }
    if (disconnectDelay.isNegative) {
      throw ArgumentError.value(disconnectDelay, 'disconnectDelay');
    }
    _device = _connectedDevice!;
    _total = attempts;
    _successes = 0;
    _failureCount = 0;
    _interrupted = false;
    _targetChanged = false;
    _closeUnconfirmed = false;
    _isRunning = true;
    _finished = Completer<void>();
    _setStatus('准备开始');
    try {
      final header = await formatTestStartHeader(DateTime.now());
      _onReport?.call(
        '$header'
        '设备：${_device!['productType'] ?? "--"} · ${_device!['name']}\n'
        '设备蓝牙连接测试 - 重复$attempts次'
        ' - 断链延迟${disconnectDelay.inMilliseconds / 1000}秒'
        ' - 重连间隔${reconnectInterval.inMilliseconds / 1000}秒\n',
      );
      var initialConnection = true;
      while (completed < attempts) {
        try {
          _checkActive();
          if (initialConnection) {
            initialConnection = false;
            await _waitBeforeDisconnect(disconnectDelay);
          }
          _setStatus('第 ${completed + 1}/$attempts 次 · 断开设备');
          if (_provider.isConnected) {
            try {
              await _waitFor(
                ready: () => !_provider.isConnected,
                action: () async => _provider.closeConnect(),
                timeout: const Duration(seconds: 10),
                timeoutMessage: '等待设备断开超时',
              );
            } on TimeoutException {
              _closeUnconfirmed = true;
              rethrow;
            }
          }
          _setStatus('第 ${completed + 1}/$attempts 次 · 等待重连间隔');
          await _waitInterval(reconnectInterval);
          _checkActive();
          await _reconnect();
          await _waitBeforeDisconnect(disconnectDelay);
          _checkActive();
          _successes++;
        } catch (_) {
          if (_interrupted || _disposed) break;
          _failureCount++;
        }
        if (_targetChanged || _closeUnconfirmed) break;
      }
    } finally {
      _onReport?.call(
        '成功 $_successes 次，失败 $_failureCount 次'
        '${_interrupted || _disposed
            ? "，测试已中断"
            : completed < attempts
            ? "，测试已停止"
            : ""}\n',
      );
      _isRunning = false;
      _setStatus(
        _interrupted || _disposed
            ? '测试已中断'
            : _closeUnconfirmed
            ? '断开连接未确认，测试已停止'
            : _targetChanged
            ? '设备已切换，测试已停止'
            : '测试结束',
      );
      _finished?.complete();
      _finished = null;
    }
  }

  Future<void> _waitBeforeDisconnect(Duration delay) async {
    if (delay == Duration.zero) return;
    _setStatus('第 ${completed + 1}/$_total 次 · 保持连接，等待断链延迟');
    await _waitInterval(delay, requireConnection: true);
    _checkActive();
  }

  Future<void> _waitInterval(
    Duration interval, {
    bool requireConnection = false,
  }) async {
    _checkActive();
    if (interval == Duration.zero) return;
    final result = Completer<void>();
    final timer = Timer(interval, result.complete);
    void checkDisconnected() {
      if (!_provider.isConnected && !result.isCompleted) {
        result.completeError(StateError('设备在自动断开前主动断连'));
      }
    }

    if (requireConnection) {
      _provider.addListener(checkDisconnected);
      checkDisconnected();
    }
    _cancelPending = (error) {
      if (!result.isCompleted) result.completeError(error);
    };
    try {
      await result.future;
    } finally {
      timer.cancel();
      if (requireConnection) _provider.removeListener(checkDisconnected);
      _cancelPending = null;
    }
  }

  Future<void> _waitFor({
    required bool Function() ready,
    required Future<void> Function() action,
    required Duration timeout,
    required String timeoutMessage,
    void Function(Map<String, dynamic>, void Function(Object))? onEvent,
  }) async {
    _checkActive();
    final result = Completer<void>();
    void fail(Object error) {
      if (!result.isCompleted) result.completeError(error);
    }

    void check() {
      if (!result.isCompleted && ready()) result.complete();
    }

    final timer = Timer(timeout, () => fail(TimeoutException(timeoutMessage)));
    final subscription = _provider.streamController.stream.listen((event) {
      if (!result.isCompleted) {
        onEvent?.call(event, fail);
        check();
      }
    });
    _provider.addListener(check);
    _cancelPending = fail;
    try {
      // Platform calls only submit requests; completion comes from SDK state.
      unawaited(Future<void>.sync(action).then((_) => check(), onError: fail));
      await result.future;
      _checkActive();
    } finally {
      timer.cancel();
      _cancelPending = null;
      _provider.removeListener(check);
      await subscription.cancel();
    }
  }

  Future<void> _reconnect() async {
    var connecting = false;
    var connectionRequested = false;
    var connectionFailed = false;
    var closed = false;
    var succeeded = false;
    _setStatus('第 ${completed + 1}/$_total 次 · 扫描并重连设备');
    try {
      await _waitFor(
        ready: () =>
            connectionRequested &&
            _connectedDevice != null &&
            _matches(_connectedDevice!),
        action: () async => _provider.startSearch(),
        timeout: const Duration(seconds: 30),
        timeoutMessage: '重新连接设备超时',
        onEvent: (event, fail) {
          final data = event['data'];
          if (data is! Map) return;
          final cmd = event['cmd']?.toString();
          if (connectionRequested &&
              cmd == '2' &&
              const {
                '0',
                'false',
              }.contains(data['connect_state']?.toString()) &&
              (_value(data['address']).isEmpty || _matches(data))) {
            connectionFailed = true;
            fail(StateError('设备连接失败'));
          }
          if (connecting ||
              cmd != '1' ||
              event['state']?.toString() != '0' ||
              !_matches(data)) {
            return;
          }
          connecting = true;
          unawaited(() async {
            try {
              await _provider.stopSearch();
              if (closed) return;
              _checkActive();
              connectionRequested = true;
              await _provider.connect({
                ..._device!,
                'name': _value(data['name']).isEmpty
                    ? _device!['name']
                    : _value(data['name']),
              });
            } catch (error) {
              fail(error);
            }
          }());
        },
      );
      succeeded = true;
    } finally {
      closed = true;
      if (!_targetChanged) {
        await _provider.stopSearch();
        if (!succeeded && connectionRequested && !connectionFailed) {
          await _cancelConnection();
        }
      }
    }
  }

  Future<void> _cancelConnection() async {
    if (_interrupted || _disposed) {
      await _provider.closeConnect();
      return;
    }
    // A pending connection already reports isConnected=false. Require a new
    // SDK disconnect callback before another round can reuse that state.
    var confirmed = false;
    try {
      await _waitFor(
        ready: () => confirmed && !_provider.isConnected,
        action: () async => _provider.closeConnect(),
        timeout: const Duration(seconds: 10),
        timeoutMessage: '取消连接超时',
        onEvent: (event, _) {
          final data = event['data'];
          if (event['cmd']?.toString() == '2' &&
              data is Map &&
              const {
                '0',
                'false',
              }.contains(data['connect_state']?.toString()) &&
              (_value(data['address']).isEmpty || _matches(data))) {
            confirmed = true;
          }
        },
      );
    } catch (_) {
      _closeUnconfirmed = true;
    }
  }

  Future<void> interrupt() async {
    if (!_isRunning) return;
    final finished = _finished;
    _interrupted = true;
    _cancelPending?.call(StateError('测试已中断'));
    await finished?.future;
  }

  @override
  void dispose() {
    _disposed = true;
    _interrupted = true;
    _provider.removeListener(_sync);
    _cancelPending?.call(StateError('测试页已关闭'));
    super.dispose();
  }
}
