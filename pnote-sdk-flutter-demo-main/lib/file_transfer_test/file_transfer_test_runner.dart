import 'dart:async';

import 'package:flutter/foundation.dart';

import '../provider_record_pen.dart';
import '../test_report.dart';

class FileTransferTestRunner extends ChangeNotifier {
  FileTransferTestRunner(
    this._provider, {
    Future<void> Function(String, bool Function())? startTransfer,
    Future<void> Function(bool)? setStorage,
    bool Function()? canStartTest,
    void Function(String)? onReport,
  }) : _startTransfer =
           startTransfer ??
           ((name, canSend) async {
             if (canSend())
               await _provider.sendFileFromPenToPhoneWithOffset(name, 0);
           }),
       _setStorage =
           setStorage ??
           ((enabled) async =>
               _provider.setAudioDecodeAndStoreEnabled(enabled)),
       _canStartTest = canStartTest,
       _onReport = onReport {
    _provider.addListener(_sync);
    _sync();
  }

  final RecordPenProvider _provider;
  final Future<void> Function(String, bool Function()) _startTransfer;
  final Future<void> Function(bool) _setStorage;
  final bool Function()? _canStartTest;
  final void Function(String)? _onReport;
  final Map<String, int> _failures = {};
  List<RecordFileInfo> _files = [];
  String? _deviceAddress;
  String? _target;
  String? _activeFile;
  bool _isRunning = false;
  bool _refreshing = false;
  bool _interrupted = false;
  bool _connectionLost = false;
  bool _disposed = false;
  bool? _previousStorage;
  int _completed = 0;
  int _total = 0;
  int _successes = 0;
  int _lastBytes = 0;
  String _status = '等待开始';
  String _speedSummary = '当前 --，最低 --，最高 --';
  String _averageRate = '--';
  Completer<void>? _finished;
  void Function(Object)? _cancelPending;
  VoidCallback? _activity;

  bool get isRunning => _isRunning;
  bool get isBusy => _isRunning || _refreshing;
  bool get canStart =>
      !isBusy &&
      _address != null &&
      !_provider.isRecording &&
      !_provider.isFileTransferring &&
      (_canStartTest?.call() ?? true);
  List<RecordFileInfo> get files => List.unmodifiable(_files);
  Map<String, int> get failureCounts => Map.unmodifiable(_failures);
  int get completed => _completed;
  int get total => _total;
  int get successes => _successes;
  int get failureCount => _failures.values.fold(0, (sum, count) => sum + count);
  String get status => _status;
  String get speedSummary => _speedSummary;
  String get averageRate => _averageRate;

  String? get _address {
    if (!_provider.isConnected) return null;
    final address = _provider.deviceInfo?['address']?.toString();
    if (address != null && address.isNotEmpty && address != 'null') {
      return 'address:${address.toLowerCase()}';
    }
    final name = _provider.deviceInfo?['name']?.toString();
    return name == null || name.isEmpty || name == 'null' ? null : 'name:$name';
  }

  void _sync() {
    final address = _address;
    if (isBusy && address != _target) {
      _connectionLost = true;
      _cancelPending?.call(StateError('设备已断开或已切换'));
    }
    if (!isBusy && address != null && address != _deviceAddress) {
      _files = [];
      _deviceAddress = address;
    }
    if (address == _deviceAddress && _provider.recordFiles.isNotEmpty) {
      _files = _provider.recordFiles;
    }
    final bytes = _provider.audioReceivedBytes(AudioDataType.file);
    if (_activeFile != null && bytes > _lastBytes) _activity?.call();
    if (_activeFile != null) {
      _speedSummary = _provider.audioRateSummary(AudioDataType.file);
      _averageRate = _provider.audioAverageRateLabel(AudioDataType.file);
    }
    _lastBytes = bytes;
    if (!_disposed) notifyListeners();
  }

  void _requireConnection() {
    if (_interrupted || _disposed) throw StateError('测试已中断');
    if (_connectionLost || _address != _target) {
      throw StateError('设备已断开或已切换');
    }
  }

  Future<void> refreshFiles() async {
    if (!canStart) throw StateError('请先连接设备并停止录音');
    _refreshing = true;
    _target = _address;
    _connectionLost = false;
    _interrupted = false;
    notifyListeners();
    try {
      await _loadFiles();
      _status = '已获取 ${_files.length} 个文件';
    } finally {
      _refreshing = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _loadFiles() async {
    _status = '读取文件列表';
    final event = await _exchange(
      action: _provider.getRecordFileList,
      accepts: (event) =>
          event['cmd']?.toString() == '4' &&
          (event['finish']?.toString() == '1' ||
              (event['state'] != null && event['state']?.toString() != '0')),
      timeout: const Duration(seconds: 20),
      timeoutMessage: '获取文件列表超时',
    );
    if (event['state'] != null && event['state']?.toString() != '0') {
      throw StateError('获取文件列表失败');
    }
    _files = _provider.recordFiles;
    _deviceAddress = _target;
  }

  Future<void> start({String? fileName, int repetitions = 1}) async {
    if (!canStart) throw StateError('请先连接设备并停止录音');
    if (repetitions < 1) throw ArgumentError.value(repetitions, 'repetitions');
    _isRunning = true;
    _interrupted = false;
    _connectionLost = false;
    _target = _address;
    _completed = 0;
    _total = 0;
    _successes = 0;
    _speedSummary = '当前 --，最低 --，最高 --';
    _averageRate = '--';
    _failures.clear();
    _finished = Completer<void>();
    final previousStorage = _provider.audioDecodeAndStoreEnabled;
    _previousStorage = previousStorage;
    final startedAt = DateTime.now();
    final totalElapsed = Stopwatch()..start();
    var receivedBytes = 0;
    var headerWritten = false;
    final device = _provider.deviceInfo;
    final deviceLabel = '${_provider.deviceType ?? "--"} · ${device?['name'] ?? "--"}';
    void writeHeader() {
      if (headerWritten) return;
      headerWritten = true;
      final selected = _files.where((file) => file.name == fileName);
      final size = selected.isEmpty
          ? '--'
          : '${(selected.first.sizeBytes / 1024).toStringAsFixed(1)}KB';
      final title = fileName == null
          ? '全部文件传输测试'
          : '单次传输测试 - 重复$repetitions次 - $fileName - $size';
      _onReport?.call('\n\n（${formatTestTimestamp(startedAt)}）\n'
          '设备：$deviceLabel\n$title\n');
    }
    notifyListeners();
    try {
      await _setStorage(false);
      _requireConnection();
      await _loadFiles();
      writeHeader();
      if (_files.isEmpty) throw StateError('设备没有可传输的文件');
      if (fileName != null && !_files.any((file) => file.name == fileName)) {
        throw StateError('所选文件已不存在');
      }
      final names = fileName == null
          ? _files.map((file) => file.name).toList()
          : [fileName];
      _total = fileName == null ? names.length : repetitions;
      if (fileName == null) {
        final size = _files.fold<int>(0, (sum, file) => sum + file.sizeBytes);
        _onReport?.call('文件总大小：${(size / 1024).toStringAsFixed(1)}KB\n');
      }
      for (var index = 0; index < _total; index++) {
        _requireConnection();
        final name = fileName == null ? names[index] : fileName;
        _activeFile = name;
        _lastBytes = 0;
        _status = '第 ${index + 1}/$_total 次 · $name';
        notifyListeners();
        var terminal = false;
        var active = true;
        Future<void>? starting;
        final elapsed = Stopwatch()..start();
        var outcome = '成功';
        String? failure;
        try {
          final event = await _exchange(
            action: () {
              starting = _startTransfer(
                name,
                () =>
                    active &&
                    !_interrupted &&
                    !_disposed &&
                    !_connectionLost &&
                    _address == _target,
              );
              return starting!;
            },
            accepts: (event) {
              if (event['cmd']?.toString() != '5') return false;
              final data = event['data'];
              if (data is! Map) return false;
              final reportedName = data['name']?.toString();
              if (reportedName != null &&
                  reportedName.isNotEmpty &&
                  reportedName != name) {
                return false;
              }
              if (event['state'] != null && event['state']?.toString() != '0') {
                return true;
              }
              if (data['record_file_state']?.toString() == '4') {
                _activity?.call();
                return false;
              }
              return true;
            },
            timeout: const Duration(seconds: 60),
            timeoutMessage: '文件传输超时（60 秒未收到数据或进度）',
            watchActivity: true,
          );
          elapsed.stop();
          final state = (event['data'] as Map)['record_file_state']?.toString();
          final validEnvelope =
              event['state'] == null || event['state']?.toString() == '0';
          terminal =
              validEnvelope && const {'0', '1', '2', '3'}.contains(state);
          if (!validEnvelope) {
            throw StateError('文件传输失败');
          }
          if (state != '0') {
            throw StateError(switch (state) {
              '1' => '文件不存在',
              '2' => '传输偏移错误',
              '3' => '设备停止传输',
              _ => '文件传输回包异常',
            });
          }
          _successes++;
        } catch (error) {
          elapsed.stop();
          outcome = _interrupted || _disposed ? '中断' : '失败';
          failure = _failureReason(error);
          active = false;
          try {
            await starting?.timeout(const Duration(seconds: 5));
          } catch (_) {
            // The original transfer failure is recorded below.
          }
          if (!terminal) await _stopTransfer(name);
          if (_interrupted || _disposed) break;
          _recordFailure(error);
          if (!terminal || _connectionLost) break;
        } finally {
          active = false;
          elapsed.stop();
          _speedSummary = _provider.audioRateSummary(AudioDataType.file);
          final bytes = _provider.audioReceivedBytes(AudioDataType.file);
          receivedBytes += bytes;
          if (elapsed.elapsedMicroseconds > 0) {
            final rate =
                bytes *
                Duration.microsecondsPerSecond /
                elapsed.elapsedMicroseconds /
                1024;
            _averageRate = '${rate.toStringAsFixed(1)}KB/s';
          }
          final bounds = _provider.audioRateBounds(AudioDataType.file);
          String speed(double? value) => value == null
              ? _averageRate
              : '${(value / 1024).toStringAsFixed(1)}KB/s';
          _onReport?.call('${index + 1}/$_total 结果：$outcome'
              '${failure == null ? "" : " 失败原因：$failure"}'
              ' ，文件：$name ，耗时：${formatTestDuration(elapsed.elapsed)}'
              '  平均速度：$_averageRate'
              ' ，最高速度：${speed(bounds.maximum)}'
              ' ，最低速度：${speed(bounds.minimum)}\n');
          _activeFile = null;
          if ((terminal || !_interrupted) && !_disposed) _completed = index + 1;
        }
        notifyListeners();
      }
      _status = _interrupted ? '测试已中断' : '测试结束';
    } catch (error) {
      writeHeader();
      _onReport?.call('结果：${_interrupted || _disposed ? "中断" : "失败"}'
          ' 失败原因：${_failureReason(error)}\n');
      if (!_interrupted && !_disposed) _recordFailure(error);
      _status = _interrupted ? '测试已中断' : '测试结束';
    } finally {
      totalElapsed.stop();
      _onReport?.call('总耗时：${formatTestDuration(totalElapsed.elapsed)}\n'
          '累计接收：${(receivedBytes / 1024).toStringAsFixed(1)}KB\n'
          '平均速度：${formatTestRate(receivedBytes, totalElapsed.elapsed)}\n'
          '成功 $_successes 次，失败 $failureCount 次'
          '${_interrupted || _disposed ? "，测试已中断" : ""}\n');
      try {
        if (!_disposed) await _setStorage(previousStorage);
      } finally {
        _previousStorage = null;
        _isRunning = false;
        _finished?.complete();
        _finished = null;
        if (!_disposed) notifyListeners();
      }
    }
  }

  void _recordFailure(Object error) {
    final reason = _failureReason(error);
    _failures.update(reason, (count) => count + 1, ifAbsent: () => 1);
  }

  String _failureReason(Object error) => error is StateError
        ? error.message.toString()
        : error is TimeoutException
        ? error.message ?? '传输超时'
        : error.toString();

  Future<Map<String, dynamic>> _exchange({
    required Future<void> Function() action,
    required bool Function(Map<String, dynamic>) accepts,
    required Duration timeout,
    required String timeoutMessage,
    bool watchActivity = false,
  }) async {
    _requireConnection();
    final reply = Completer<Map<String, dynamic>>();
    Timer? timer;
    void resetTimeout() {
      timer?.cancel();
      timer = Timer(timeout, () {
        if (!reply.isCompleted)
          reply.completeError(TimeoutException(timeoutMessage));
      });
    }

    final subscription = _provider.streamController.stream.listen((event) {
      if (!reply.isCompleted && accepts(event)) reply.complete(event);
    });
    _cancelPending = (error) {
      if (!reply.isCompleted) reply.completeError(error);
    };
    if (watchActivity) _activity = resetTimeout;
    resetTimeout();
    try {
      final values = await Future.wait<dynamic>([
        reply.future,
        Future<void>.sync(action),
      ], eagerError: true);
      _requireConnection();
      return values.first as Map<String, dynamic>;
    } finally {
      timer?.cancel();
      _activity = null;
      _cancelPending = null;
      await subscription.cancel();
    }
  }

  Future<void> _stopTransfer(String name) async {
    if (_disposed || _address != _target || !_provider.isFileTransferring)
      return;
    final stopped = Completer<void>();
    final subscription = _provider.streamController.stream.listen((event) {
      final data = event['data'];
      if (!stopped.isCompleted &&
          event['cmd']?.toString() == '5' &&
          data is Map &&
          (data['name'] == null || data['name']?.toString() == name) &&
          const {
            '0',
            '1',
            '2',
            '3',
          }.contains(data['record_file_state']?.toString())) {
        if (event['state'] != null && event['state']?.toString() != '0') {
          stopped.completeError(StateError('停止传输失败'));
        } else {
          stopped.complete();
        }
      }
    });
    try {
      await Future.wait<dynamic>([
        stopped.future,
        _provider.stopTransferFile(name),
      ], eagerError: true).timeout(const Duration(seconds: 5));
    } catch (_) {
      if (_address == _target) await _provider.closeConnect();
    } finally {
      await subscription.cancel();
    }
  }

  Future<void> interrupt() async {
    if (!isBusy) return;
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
    final previousStorage = _previousStorage;
    if (previousStorage != null) {
      _provider.setAudioDecodeAndStoreEnabled(previousStorage);
    }
    if (_activeFile != null && _address == _target) {
      unawaited(_provider.closeConnect());
    }
    super.dispose();
  }
}
