import 'dart:async';

import 'package:flutter/foundation.dart';

import '../provider_record_pen.dart';
import '../test_report.dart';

typedef OtaTestDevice = ({String name, String address, int? type});
typedef OtaTestFirmware = ({String path, String version});

class OtaAutomationRunner extends ChangeNotifier {
  OtaAutomationRunner(this._provider, {
    bool Function()? canStartTest,
    void Function(String)? onReport,
  }) : _canStartTest = canStartTest,
       _onReport = onReport {
    _provider.addListener(_syncDevice);
    _syncDevice();
  }

  static const supportedDeviceType = 48;
  static const _reconnectTimeout = Duration(seconds: 30);

  final RecordPenProvider _provider;
  final bool Function()? _canStartTest;
  final void Function(String)? _onReport;
  OtaTestDevice? _connectedDevice;
  OtaTestDevice? _device;
  int _disconnectCount = 0;
  bool _isRunning = false;
  bool _stopRequested = false;
  bool _targetChanged = false;
  bool _disposed = false;
  bool _interrupted = false;
  bool _reconnecting = false;
  Completer<void>? _finished;
  void Function(Object)? _cancelPending;
  int _completed = 0;
  int _failureCount = 0;
  String _status = '等待开始';
  String? _upgradeDirection;
  String? _lastFailure;
  final Map<String, int> _failureCounts = {};

  OtaTestDevice? get device => _device;
  bool get hasSupportedDevice => _connectedDevice?.type == supportedDeviceType;
  bool get canStart => !_isRunning && hasSupportedDevice &&
      (_canStartTest?.call() ?? true);
  bool get isRunning => _isRunning;
  bool get stopRequested => _stopRequested;
  int get completed => _completed;
  int get failureCount => _failureCount;
  String get status => _status;
  String? get upgradeDirection => _upgradeDirection;
  String? get lastFailure => _lastFailure;
  Map<String, int> get failureCounts => Map.unmodifiable(_failureCounts);

  void _syncDevice() {
    final previous = _connectedDevice;
    final info = _provider.isConnected ? _provider.deviceInfo : null;
    final address = info?['address']?.toString().trim() ?? '';
    final name = info?['name']?.toString() ?? '';
    final current = address.isEmpty || address == 'null' || name.isEmpty
        ? null
        : (name: name, address: address, type: _provider.deviceType);
    if (previous == current) return;

    _connectedDevice = current;
    if (previous != null && current == null) _disconnectCount++;
    if (current != null && !_sameAddress(_device?.address, current.address)) {
      _upgradeDirection = null;
    }
    if (!_isRunning) {
      _device = current ?? _device;
    } else if (current != null &&
        !_sameAddress(current.address, _device!.address)) {
      _targetChanged = true;
      _cancelPending?.call(StateError('连接已切换到其他设备'));
    }
    notifyListeners();
  }

  bool _sameAddress(String? left, String right) =>
      left?.toLowerCase() == right.toLowerCase();

  bool _isConnectedTo(OtaTestDevice target) =>
      _sameAddress(_connectedDevice?.address, target.address);

  Future<void> start({
    required int attempts,
    required OtaTestFirmware first,
    required OtaTestFirmware second,
  }) async {
    if (!canStart) {
      throw StateError('请先在设备页连接 type $supportedDeviceType 设备');
    }
    if (attempts < 1) throw ArgumentError.value(attempts, 'attempts');
    final target = _connectedDevice!;
    _finished = Completer<void>();
    _device = target;
    _isRunning = true;
    _stopRequested = false;
    _targetChanged = false;
    _completed = 0;
    _failureCount = 0;
    _lastFailure = null;
    _failureCounts.clear();
    _interrupted = false;
    var needsFreshConnection = false;
    var initialConnection = true;
    _onReport?.call('\n\n（${formatTestTimestamp(DateTime.now())}）\n'
        '设备：${target.type} · ${target.name}\n'
        '杰理OTA自动化测试 - 重复$attempts次\n');

    try {
      while (_completed < attempts) {
        final attempt = _completed + 1;
        var round = '第 $attempt/$attempts 次';
        _upgradeDirection = null;
        final elapsed = Stopwatch()..start();
        var outcome = '成功';
        String? failure;
        String? direction;
        try {
          if (needsFreshConnection || !_isConnectedTo(target)) {
            _setStatus('$round · 恢复蓝牙连接');
            await _reconnect(target, disconnectFirst: needsFreshConnection);
            needsFreshConnection = false;
          } else if (initialConnection) {
            _setStatus('$round · 等待设备连接稳定');
            await _wait(target, const Duration(seconds: 2));
          }
          initialConnection = false;
          _setStatus('$round · 读取当前固件版本');
          final current = await _readVersion(target);
          final useFirst = current != first.version;
          final firmware = useFirst ? first : second;
          if (current == firmware.version) {
            throw StateError('当前版本 $current 与两份固件版本一致');
          }
          direction = '$current → ${firmware.version}';
          _upgradeDirection = direction;
          round = '$round · 固件 ${useFirst ? 1 : 2}';
          _setStatus('$round · 2 秒后开始 OTA');
          await _wait(target, const Duration(seconds: 2));
          final disconnectCount = _disconnectCount;
          Future<void> send() {
            _setStatus('$round · 发送固件并等待设备确认');
            return _sendFirmware(
              target,
              firmware,
              disconnectCount,
              onSend: () => needsFreshConnection = true,
            );
          }

          try {
            await send();
          } on OtaPreparationError catch (error) {
            if (error.prepareState != '2') rethrow;
            _setStatus('$round · 等待 Wi-Fi 连接');
            await _ensureWifi(target);
            await send();
          }
          _setStatus('$round · 重连设备（30 秒内）');
          await _reconnect(target, afterDisconnect: disconnectCount);
          needsFreshConnection = false;
          _setStatus('$round · 校验固件版本');
          final actual = await _readVersion(target);
          if (actual != firmware.version) {
            throw StateError('版本不一致，预期 ${firmware.version}，实际 $actual');
          }
        } catch (error) {
          outcome = _disposed || _interrupted ? '中断' : '失败';
          failure = _failureReason(error);
          if (_disposed) return;
          if (_interrupted) break;
          _failureCount++;
          final reason = _failureReason(error);
          _failureCounts.update(reason, (count) => count + 1, ifAbsent: () => 1);
          _lastFailure =
              '$round · ${error is StateError ? error.message : error}';
        } finally {
          elapsed.stop();
          _onReport?.call('$attempt/$attempts 结果：$outcome'
              '${failure == null ? "" : " 失败原因：$failure"}'
              ' 升级方向：${direction ?? "未确定"}'
              ' 总耗时：${formatTestDuration(elapsed.elapsed)}\n');
        }
        if (_disposed) return;
        _completed = attempt;
        if (_stopRequested || _targetChanged) break;
      }
    } finally {
      _isRunning = false;
      _onReport?.call('成功 ${_completed - _failureCount} 次，失败 $_failureCount 次'
          '${_completed < attempts ? "，测试已停止" : ""}\n');
      _device = _connectedDevice ?? _device;
      _setStatus(_completed == attempts ? '测试结束' : '测试已停止');
      _finished?.complete();
      _finished = null;
    }
  }

  Future<void> interrupt() async {
    if (!_isRunning) return;
    final finished = _finished;
    _interrupted = true;
    _stopRequested = true;
    _cancelPending?.call(StateError('测试已中断'));
    await _cancelCurrentOperation();
    await finished?.future;
  }

  Future<void> _cancelCurrentOperation() async {
    final reconnecting = _reconnecting;
    await _provider.cancelOtaTransfer();
    if (reconnecting) await _provider.closeConnect();
  }

  String _failureReason(Object error) {
    final message = error is StateError
        ? error.message.toString()
        : error is TimeoutException
        ? error.message ?? '等待设备回复超时'
        : error.toString();
    for (final reason in ['文件验证超时', '设备接收固件失败', '版本不一致']) {
      if (message.startsWith(reason)) return reason;
    }
    if (message.startsWith('当前版本')) return '当前版本与两份固件版本一致';
    return message;
  }

  Future<void> _wait(OtaTestDevice target, Duration duration) async {
    _requireConnection(target);
    final done = Completer<void>();
    final timer = Timer(duration, done.complete);
    _cancelPending = (error) {
      if (!done.isCompleted) done.completeError(error);
    };
    try {
      await done.future;
      _requireConnection(target);
    } finally {
      timer.cancel();
      _cancelPending = null;
    }
  }

  void stopAfterCurrentAttempt() {
    if (!_isRunning || _stopRequested) return;
    _stopRequested = true;
    notifyListeners();
  }

  void _setStatus(String status) {
    _status = status;
    if (!_disposed) notifyListeners();
  }

  Future<void> _ensureWifi(OtaTestDevice target) async {
    String? wifiState(Map<String, dynamic> event) {
      if (event['cmd']?.toString() != '12') return null;
      return _eventData(event)?['wifi_state']?.toString();
    }

    try {
      final current = await _exchange(
        action: () async {
          _requireConnection(target);
          await _provider.getDeviceWiFiState();
        },
        accepts: (event) =>
            const {'0', '1', '2', '3'}.contains(wifiState(event)),
        timeout: const Duration(seconds: 3),
        timeoutMessage: '查询 Wi-Fi 状态超时',
      );
      if (current['state']?.toString() == '0' && wifiState(current) == '2') {
        return;
      }
    } on TimeoutException {
      // 没有查询回包时，仍可由 SDK 尝试建立 Wi-Fi 和 TCP 连接。
    }

    await _exchange(
      action: () {
        _requireConnection(target);
        return _provider.quickConnectDeviceWiFi();
      },
      accepts: (event) =>
          event['state']?.toString() == '0' && wifiState(event) == '2',
      timeout: const Duration(seconds: 35),
      timeoutMessage: '连接设备 Wi-Fi 超时',
    );
  }

  Future<void> _sendFirmware(
    OtaTestDevice target,
    OtaTestFirmware firmware,
    int disconnectCount, {
    required VoidCallback onSend,
  }) async {
    _requireConnection(target);
    var active = true;
    var sendStarted = false;
    try {
      final event = await _exchange(
        action: () => _provider.requestAndSendOtaFile(
          firmware.path,
          canSend: () {
            sendStarted =
                active &&
                !_targetChanged &&
                !_disposed &&
                !_interrupted &&
                _disconnectCount == disconnectCount &&
                _isConnectedTo(target);
            if (sendStarted) onSend();
            return sendStarted;
          },
        ),
        accepts: (event) {
          if (!sendStarted) return false;
          final cmd = event['cmd']?.toString();
          return event.containsKey(RecordPenProvider.otaTransferErrorKey) ||
              cmd == '21' ||
              (cmd == '20' && event['state']?.toString() != '0');
        },
      );
      final state = event['state']?.toString();
      final received = _eventData(event)?['receiveState']?.toString();
      if (state != '0' || received != '0') {
        throw StateError('设备接收固件失败（状态 $state，接收结果 ${received ?? '未知'}）');
      }
    } finally {
      active = false;
    }
  }

  Future<void> _reconnect(
    OtaTestDevice target, {
    int? afterDisconnect,
    bool disconnectFirst = false,
  }) async {
    _checkActive();
    _reconnecting = true;
    final result = Completer<void>();
    final requiredDisconnect =
        afterDisconnect ??
        (disconnectFirst && _isConnectedTo(target) ? _disconnectCount : -1);
    var scanning = false;
    var connecting = false;
    var closed = false;
    Timer? connectTimer;

    void scan() {
      if (closed || result.isCompleted) return;
      scanning = true;
      unawaited(_provider.startSearch());
    }

    void checkConnection() {
      if (closed || result.isCompleted || _disconnectCount <= requiredDisconnect) return;
      if (_isConnectedTo(target)) {
        result.complete();
      } else if (!scanning && !connecting) {
        scan();
      }
    }

    final subscription = _provider.streamController.stream.listen((event) {
      if (closed || result.isCompleted) return;
      final cmd = event['cmd']?.toString();
      final data = _eventData(event);
      final address = data?['address']?.toString();
      final matches = _sameAddress(address, target.address);
      if (connecting &&
          cmd == '2' &&
          const {'0', 'false'}.contains(data?['connect_state']?.toString()) &&
          (matches ||
              address == null ||
              address.isEmpty ||
              address == 'null')) {
        connectTimer?.cancel();
        connecting = false;
        checkConnection();
      }
      if (!scanning ||
          cmd != '1' ||
          event['state']?.toString() != '0' ||
          !matches) {
        return;
      }
      scanning = false;
      connecting = true;
      final name = data?['name']?.toString() ?? '';
      unawaited(_provider.stopSearch());
      connectTimer = Timer(const Duration(seconds: 5), () async {
        if (closed || result.isCompleted) return;
        try {
          await _provider.stopSearch();
          _checkActive();
          if (closed || result.isCompleted) return;
          await _provider.connect({
            'name': name.isEmpty ? target.name : name,
            'address': address,
            'productType': target.type,
          });
        } catch (error) {
          if (!result.isCompleted) result.completeError(error);
        }
      });
    });
    _provider.addListener(checkConnection);
    _cancelPending = (error) {
      if (!result.isCompleted) result.completeError(error);
    };
    try {
      final wait = result.future.timeout(
        _reconnectTimeout,
        onTimeout: () => throw StateError('30 秒内未能重新连接测试设备'),
      );
      if (disconnectFirst && _disconnectCount == requiredDisconnect) {
        unawaited(_provider.closeConnect());
      }
      checkConnection();
      await wait;
    } finally {
      closed = true;
      _reconnecting = false;
      connectTimer?.cancel();
      _cancelPending = null;
      _provider.removeListener(checkConnection);
      await subscription.cancel();
      if (scanning && !_targetChanged && !_disposed) {
        await _provider.stopSearch();
      }
    }
    await _wait(target, const Duration(seconds: 2));
  }

  Future<String> _readVersion(OtaTestDevice target) async {
    final disconnectCount = _disconnectCount;
    final result = await _exchange(
      action: () async {
        _requireConnection(target);
        await _provider.getDeviceVersion();
      },
      accepts: (event) => event['cmd']?.toString() == '17',
      timeout: const Duration(seconds: 5),
      timeoutMessage: '读取固件版本超时',
    );
    final actual = _eventData(result)?['version']?.toString().trim();
    if (_disconnectCount != disconnectCount ||
        !_isConnectedTo(target) ||
        result['state']?.toString() != '0' ||
        actual == null ||
        actual.isEmpty) {
      throw StateError('读取固件版本失败');
    }
    return actual;
  }

  Future<Map<String, dynamic>> _exchange({
    required Future<void> Function() action,
    required bool Function(Map<String, dynamic>) accepts,
    Duration? timeout,
    String? timeoutMessage,
  }) async {
    _checkActive();
    final response = Completer<Map<String, dynamic>>();
    final interrupted = Completer<Never>();
    final subscription = _provider.streamController.stream.listen((event) {
      if (response.isCompleted || !accepts(event)) return;
      if (event[RecordPenProvider.otaTransferErrorKey] case final String error) {
        response.completeError(StateError(error));
      } else {
        response.complete(event);
      }
    });
    _cancelPending = (error) {
      if (!interrupted.isCompleted) interrupted.completeError(error);
    };
    try {
      final exchange = Future.any([
        Future.wait<dynamic>([
          response.future,
          Future<void>.sync(action),
        ], eagerError: true),
        interrupted.future,
      ]);
      final results = await (timeout == null
          ? exchange
          : exchange.timeout(
              timeout,
              onTimeout: () => throw TimeoutException(timeoutMessage),
            ));
      _checkActive();
      return results.first as Map<String, dynamic>;
    } finally {
      _cancelPending = null;
      await subscription.cancel();
    }
  }

  Map? _eventData(Map<String, dynamic> event) {
    final data = event['data'];
    return data is Map ? data : null;
  }

  void _checkActive() {
    if (_disposed || _targetChanged || _interrupted) {
      throw StateError('测试设备已切换、测试已中断或测试页已关闭');
    }
  }

  void _requireConnection(OtaTestDevice target) {
    _checkActive();
    if (!_isConnectedTo(target)) throw StateError('测试设备蓝牙已断开');
  }

  @override
  void dispose() {
    _disposed = true;
    _provider.removeListener(_syncDevice);
    _cancelPending?.call(StateError('测试页已关闭'));
    if (_isRunning) unawaited(_cancelCurrentOperation());
    super.dispose();
  }
}
