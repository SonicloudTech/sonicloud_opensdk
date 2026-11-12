import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:soni_sdk_demo/service_bk_http.dart';
import 'package:soni_sdk_demo/service_bluetooth.dart';
import 'package:soni_sdk_demo/service_record.dart';
import 'package:soni_sdk_demo/service_system_ability.dart';
import 'package:wifi_iot/wifi_iot.dart';

import 'logger.dart';

///
/// @author 杰森明
/// @fileName provider_record_pen.dart
/// @date 2025/12/10 11:21
/// @description [RecordPenProvider]
/// 录音笔接口
/// @description [flutter与生层通信协议]
///

/// Opus 音频数据来源：实时录音 / 文件传输
class AudioDataType {
  static const record = 'record';
  static const file = 'file';
}

class RecordFileInfo {
  final String name;
  final int sizeBytes;
  final int durationSec;

  RecordFileInfo({
    required this.name,
    required this.sizeBytes,
    required this.durationSec,
  });

  String get sizeKbLabel => '${(sizeBytes / 1024).toStringAsFixed(1)}kb';

  String get durationMinLabel => '${(durationSec / 60).toStringAsFixed(1)}min';

  String get displayLabel => '$name  $sizeKbLabel  $durationMinLabel';
}

class _AudioRateStats {
  double? _currentBytesPerSecond;
  double? _minBytesPerSecond;
  double? _maxBytesPerSecond;
  int _windowBytes = 0;
  DateTime? _windowStartedAt;
  DateTime? _lastDataAt;
  int _totalBytes = 0;
  DateTime? _startedAt;

  void reset() {
    _totalBytes = 0;
    _startedAt = null;
    _resetWindow();
  }

  void _resetWindow() {
    _currentBytesPerSecond = null;
    _minBytesPerSecond = null;
    _maxBytesPerSecond = null;
    _windowBytes = 0;
    _windowStartedAt = null;
    _lastDataAt = null;
  }

  bool record(int bytes) {
    if (bytes <= 0) return false;

    final now = DateTime.now();
    var didReset = false;
    if (_lastDataAt != null &&
        now.difference(_lastDataAt!) > const Duration(seconds: 2)) {
      _resetWindow();
      didReset = true;
    }
    _lastDataAt = now;
    _startedAt ??= now;
    _totalBytes += bytes;

    _windowStartedAt ??= now;
    _windowBytes += bytes;
    final elapsedMs = now.difference(_windowStartedAt!).inMilliseconds;
    if (elapsedMs < 1000) return didReset;

    final rate = _windowBytes * 1000 / elapsedMs;
    _currentBytesPerSecond = rate;
    _minBytesPerSecond = _minBytesPerSecond == null
        ? rate
        : math.min(_minBytesPerSecond!, rate);
    _maxBytesPerSecond = _maxBytesPerSecond == null
        ? rate
        : math.max(_maxBytesPerSecond!, rate);
    _windowBytes = 0;
    _windowStartedAt = now;
    return true;
  }

  String _formatRate(double? bytesPerSecond) {
    if (bytesPerSecond == null) return '--';
    return '${(bytesPerSecond / 1024).toStringAsFixed(1)}KB/s';
  }

  String get currentLabel => _formatRate(_currentBytesPerSecond);
  String get minLabel => _formatRate(_minBytesPerSecond);
  String get maxLabel => _formatRate(_maxBytesPerSecond);
  String get averageLabel {
    if (_startedAt == null || _lastDataAt == null) return '--';
    final elapsedUs = _lastDataAt!.difference(_startedAt!).inMicroseconds;
    if (elapsedUs <= 0) return '--';
    return _formatRate(_totalBytes * Duration.microsecondsPerSecond / elapsedUs);
  }

  String get summary => '当前 $currentLabel，最低 $minLabel，最高 $maxLabel';
}

class OtaPreparationError extends StateError {
  OtaPreparationError(this.prepareState, String message) : super(message);

  final String? prepareState;
}

class RecordPenProvider extends ChangeNotifier with WidgetsBindingObserver {
  static const _allowedOtaPrepareStates = {'0', '3'};
  static const otaResultTimeout = Duration(minutes: 5);
  static const _otaVerificationTimeout = Duration(seconds: 20);
  static const otaTransferErrorKey = 'otaTransferError';
  bool _otaRequestPending = false;
  Completer<Never>? _otaRequestCancellation;
  Timer? _otaTransferTimer;
  bool _otaAwaitingVerification = false;

  // 🔧 服务实例（抱歐）
  final _bluetoothService = RecordPenBluetoothService();
  final _recordService = RecordPenRecordService();

  String _transFileName = '';

  String get transFileName => _transFileName;

  final List<RecordFileInfo> _recordFiles = [];

  List<RecordFileInfo> get recordFiles => List.unmodifiable(_recordFiles);

  List<String> get recordFileNames =>
      _recordFiles.map((e) => e.name).toList(growable: false);

  final Map<String, _AudioRateStats> _audioRateStats = {
    AudioDataType.record: _AudioRateStats(),
    AudioDataType.file: _AudioRateStats(),
  };
  int _transferPacketNumber = 0;

  bool _audioDecodeAndStoreEnabled = true;

  bool get audioDecodeAndStoreEnabled => _audioDecodeAndStoreEnabled;

  // 连接成功后是否自动传输
  final bool _isAutoTransfer = false;

  setTransFileName(String fileName) {
    if (_transFileName == fileName) return;
    _transFileName = fileName;
    notifyListeners();
  }

  void setAudioDecodeAndStoreEnabled(bool enabled) {
    if (_audioDecodeAndStoreEnabled == enabled) return;
    _audioDecodeAndStoreEnabled = enabled;
    notifyListeners();
  }

  void _clearRecordFileList() {
    if (_recordFiles.isEmpty && _transFileName.isEmpty) return;
    _recordFiles.clear();
    _transFileName = '';
    notifyListeners();
  }

  // 前后台状态
  bool _isAppForeground = true;

  bool get isAppForeground => _isAppForeground;

  /// 待跳转标记
  bool _pendingGotoRealTimePen = false;

  bool get pendingGotoRealTimePen => _pendingGotoRealTimePen;

  final MethodChannel _methodChannel = const MethodChannel(
    'com.soni.soni_sdk_demo/recordPen',
  );
  final EventChannel _eventChannel = const EventChannel(
    'com.soni.soni_sdk_demo/eventChannel',
  );
  StreamController<Map<String, dynamic>> streamController =
      StreamController.broadcast();

  bool _isConnected = false;
  String? _connectedDeviceKey;
  bool _heartbeatReplyEnabled = true;
  bool _deviceHeartbeatEnabled = true;
  ({bool enabled, Timer timeout})? _heartbeatSetting;

  bool get heartbeatReplyEnabled => _heartbeatReplyEnabled;

  set heartbeatReplyEnabled(bool enabled) {
    if (_heartbeatReplyEnabled == enabled) return;
    _heartbeatReplyEnabled = enabled;
    notifyListeners();
  }

  bool get deviceHeartbeatEnabled => _deviceHeartbeatEnabled;

  bool get isHeartbeatSettingPending => _heartbeatSetting != null;

  //是否正在录音
  bool _isRecording = false;
  bool _isFileTransferring = false;

  bool get isFileTransferring => _isFileTransferring;

  //启动录音当时的时间
  int? _pendingRecordStartTimestamp;

  int? get pendingRecordStartTimestamp => _pendingRecordStartTimestamp;

  bool get isConnected => _isConnected;

  bool get isRecording => _isRecording;
  String _cbc = "-1";

  String get cbc => _cbc;
  String _sn = "00000000";

  String get sn => _sn;

  /// 设备信息（统一管理）
  Map<String, dynamic>? _deviceInfo;

  Map<String, dynamic>? get deviceInfo => _deviceInfo;

  int? get deviceType => int.tryParse(
    '${_deviceInfo?['productType'] ?? _deviceInfo?['type'] ?? ''}',
  );

  String deviceName = "";
  String deviceAddress = "";

  final List<Map<String, String>> _discoveredDevices = [];

  List<Map<String, String>> get discoveredDevices =>
      List.unmodifiable(_discoveredDevices);

  /// WiFi 状态：0表示打开，1表示关闭或失败，2表示连接成功，3表示断开
  String _wifiState = "";

  String get wifiState => _wifiState;
  String _wifiName = "";

  String get wifiName => _wifiName;

  /// 设备固件版本
  String _deviceVersion = "";

  String get deviceVersion => _deviceVersion;

  /// 设备固件版本 Code（数字格式）
  int _deviceVersionCode = 0;

  int get deviceVersionCode => _deviceVersionCode;

  void clearPendingJump() {
    _pendingGotoRealTimePen = false;
    _pendingRecordStartTimestamp = null;
  }

  void triggerPendingJump() {
    if (_pendingGotoRealTimePen && onGotoRealTimePen != null) {
      _pendingGotoRealTimePen = false;
      onGotoRealTimePen!();
    }
  }

  //连接成功后判断是否跳转到录音页的回调，isRecording表示跳转前是否已经开始录音了
  void Function(bool isRecording)? connectGotoRealTimePen;

  void Function()? onGotoRealTimePen;

  //通知是否传输完成
  void Function(int state, String? progress)? onTransferComplete;

  //所有文件下载完成回调（触发云端列表刷新）
  void Function()? onAllTransferComplete;

  ///  构造函数
  RecordPenProvider() {
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _clearHeartbeatSetting();
    _clearOtaTransfer();
    super.dispose();
  }

  ///  全局只初始化一次
  ///  确保有权限
  init() async {
    Log.d("录音笔初始化");
    try {
      if (Platform.isAndroid) {
        await _methodChannel.invokeMethod('init');
      }
    } catch (e) {}

    _eventChannel.receiveBroadcastStream().listen(
      (event) async {
        await _handleBluetoothEvent(event);
      },
      onError: (err) {
        Log.e("$err");
      },
    );
  }

  bool _isAudioBytes(dynamic data) =>
      data is List || data is Uint8List || data is TypedData;

  List<int> _toIntList(dynamic data) {
    if (data is Uint8List) return data.toList();
    if (data is List) return List<int>.from(data);
    return List<int>.from((data as TypedData).buffer.asUint8List());
  }

  /// 发送音频帧的方法
  ///
  /// 该方法将音频数据分割并添加到流控制器中，以便后续处理或传输
  ///
  /// @param audioType 音频类型，用于标识音频数据的格式或编码方式
  /// @param data 音频数据，以字节列表形式提供
  void _emitAudioFrames(String audioType, List<int> data) {
    /// A 款：80ms/160字节，一包 4 帧，每帧 40 字节（20ms）
    /// B 款：解密后 400 字节，一包 5 帧，每帧 80 字节
    if (audioType == AudioDataType.file) {
      // Log.d(
      //   '[蓝牙调试][文件传输] 接收包编号: $_transferPacketNumber, 数据包长度: ${data.length} 字节',
      // );
      _transferPacketNumber++;
    }
    final updated = _audioRateStats
        .putIfAbsent(audioType, _AudioRateStats.new)
        .record(data.length);
    if (updated) notifyListeners();
    if (!_audioDecodeAndStoreEnabled) return;
    for (final item in _splitData(data)) {
      streamController.add({"audioType": audioType, "audio": item});
    }
  }

  void resetAudioRate(String audioType) {
    _audioRateStats.putIfAbsent(audioType, _AudioRateStats.new).reset();
    notifyListeners();
  }

  String audioRateSummary(String audioType) =>
      _audioRateStats.putIfAbsent(audioType, _AudioRateStats.new).summary;

  String audioAverageRateLabel(String audioType) =>
      _audioRateStats.putIfAbsent(audioType, _AudioRateStats.new).averageLabel;

  ({double? minimum, double? maximum}) audioRateBounds(String audioType) {
    final stats = _audioRateStats.putIfAbsent(audioType, _AudioRateStats.new);
    return (minimum: stats._minBytesPerSecond, maximum: stats._maxBytesPerSecond);
  }

  int audioReceivedBytes(String audioType) =>
      _audioRateStats.putIfAbsent(audioType, _AudioRateStats.new)._totalBytes;

  List<List<int>> _splitData(List<int> data) {
    final blockSize = 40;
    final result = <List<int>>[];

    int index = 0;
    while (index + blockSize <= data.length) {
      final block = data.sublist(index, index + blockSize);
      result.add(block);
      index += blockSize;
    }

    return result;
  }

  /// 处理蓝牙事件的主方法
  Future<void> _handleBluetoothEvent(dynamic event) async {
    try {
      // 预处理事件数据（修复Android/iOS平台差异 + 修复JSON格式）
      // String processedEvent = RecordPenUtils.preprocessBluetoothEvent(
      //   event.toString(),
      // );

      if (event is Map) {
        final audioType = event['audioType']?.toString();
        final audioData = event['audio'];
        if (audioType != null && _isAudioBytes(audioData)) {
          _emitAudioFrames(audioType, _toIntList(audioData));
          return;
        }
        if (event.containsKey('sdkLog')) {
          streamController.add({'SDK': event['sdkLog']});
          return;
        }
        print("sdklog=>$event");
        return;
      } else if (event is List<int>) {
        /// 兼容旧版原生：未带类型时按实时录音处理
        _emitAudioFrames(AudioDataType.record, event);
        return;
      } else if (event is Uint8List) {
        _emitAudioFrames(AudioDataType.record, event.toList());
        return;
      } else if (event is String &&
          (event.startsWith('send:') || event.startsWith('rev:'))) {
        streamController.add({'SDK': event});
        return;
      } else {
        print("录音笔数据源${event.runtimeType}:$event");
      }

      // 解析 JSON
      Map<String, dynamic> map = jsonDecode(event as String);
      streamController.add(map);
      // 根据 cmd 分发到不同的处理方法
      final String cmd = map['cmd'].toString();
      switch (cmd) {
        case "1":
          _handleDeviceSearchEvent(map);
          break;
        case "2":
          await _handleDeviceConnectionEvent(map);
          break;
        case "3":
          _handleRecordStateEvent(map);
          break;
        case "4":
          await _handleFileListEvent(map);
          break;
        case "5":
          await _handleTransferProgressEvent(map);
          break;
        case "6":
          _handleBatteryEvent(map);
          break;
        case "7":
          _handleDeviceSNEvent(map);
          break;
        case "8":
          _handleDeviceButtonEvent(map);
          break;
        case "9":
          _handleRecordingStateEvent(map);
          break;
        case "10":
          _handleRecordTimeEvent(map);
          break;
        case "11":
          _handleRecordFileNameEvent(map);
          break;
        case "12":
          _handleDeviceWiFiStateEvent(map);
          break;
        case "13":
        case "14":
        case "15":
        case "16":
          if (cmd == "14") {
            _handleDeleteEvent(map);
          } else {
            _handleAdditionalCommandEvent(cmd, map);
          }
          break;
        case "17":
          _handleDeviceFirewareVersion(map);
          break;
        case "18":
          _handleDeviceWiFiCode(map);
          break;
        case "19":
          //返回状态，0 和 3 表示可以进入升级状态，
          //     1 表示不能进入升级状态，主要原因是可能是SD卡或者内存不足；
          //     2 表示WiFi的TCP/IP未连接，升级模式需要在WiFi连接的状态下才能进行升级；
          final otaData = map['data'];
          final canUpgrade =
              map['state']?.toString() == '0' &&
              otaData is Map &&
              _allowedOtaPrepareStates.contains(
                otaData['prepareState']?.toString(),
              );
          streamController.add({"是否可以升级": canUpgrade ? "可以" : "不可以"});
          break;
        case "20":
          _handleOtaProgress(map);
          break;
        case "21":
          //state    标记：0 表示正常，非0表示异常
          //     receiveState  0：文件接收完成，准备重启
          _clearOtaTransfer();
          break;
        case "22":
          //state    标记：0 表示正常，非0表示异常
          //     low_power_state    0 不是  1是
          break;
        case "23":

          /// 设置低功耗录音模式状态返回
          /// low_power_state=0 表示成功，=1 表示失败
          final data = map['data'] as Map<String, dynamic>? ?? {};
          final lowPowerState = data['low_power_state']?.toString() ?? "0";
          break;
        case "31":
        case "32":
        case "33":
        case "34":
          // AuthKey 和热点密码操作结果已通过 streamController 转发到页面日志。
          break;
        case "24":
        case "25":
        case "26":
        case "27":
        case "28":
        case "29":
        case "30":
        case "35":
        case "40":
        case "100":
        case "102":
          _handleAdditionalCommandEvent(cmd, map);
          break;
        case "101":
          final shouldReply = heartbeatReplyEnabled;
          _logHeartbeat(
            shouldReply ? '收到设备心跳（0x32）' : '收到设备心跳（0x32），自动回复已关闭',
          );
          if (shouldReply) await sendBackHeartbeatData();
          break;
        default:
          Log.w("未知的 cmd: $cmd");
      }
    } catch (e, t) {
      Log.e("$e $t \n ${event.runtimeType}");
    }
  }

  void _handleAdditionalCommandEvent(String cmd, Map<String, dynamic> map) {
    final rawData = map['data'];
    final data = rawData is Map
        ? Map<String, dynamic>.from(rawData)
        : <String, dynamic>{};

    switch (cmd) {
      case "13":
        streamController.add({
          "设备容量": "剩余${data['residueSpace']}，总计${data['totalSpace']}",
        });
        break;
      case "15":
        streamController.add({"设备增益": data['gain']?.toString() ?? "未知"});
        break;
      case "16":
        streamController.add({
          "设置设备增益": _commandResultText(data['gain_state']),
        });
        break;
      case "24":
        streamController.add({"重点标记": data['key_point']?.toString() ?? "未知"});
        break;
      case "25":
      case "26":
        final operation = cmd == "25" ? "设置设备名称" : "复位设备名称";
        streamController.add({
          "设备名称": "$operation${_commandResultText(data['device_name_state'])}",
        });
        break;
      case "27":
      case "28":
        final operation = cmd == "27" ? "设置直连Wi-Fi" : "设置上传URL";
        streamController.add({
          "直连Wi-Fi": "$operation${_commandResultText(data['wifi_direct_state'])}",
        });
        break;
      case "29":
        streamController.add({"直连Wi-Fi": "复位参数已收到设备回复"});
        break;
      case "30":
        streamController.add({
          "直连Wi-Fi":
              "SSID=${data['ssid'] ?? ''}，连接${_commandResultText(data['status'])}",
        });
        break;
      case "35":
        streamController.add({
          "重置设备": _commandResultText(data['reset_device_state']),
        });
        break;
      case "40":
        streamController.add({
          "BK OTA": "${data['type']?.toString() ?? ""} - ${data['value']?.toString() ?? ""}"
        });
        break;
      case "100":
        streamController.add({
          '设置传输间隔': _commandResultText(data['offline_transfer_interval_state']),
        });
        break;
      case "102":
        const reply = '收到设备心跳开关应答（0x35）';
        final requested = _heartbeatSetting?.enabled;
        final hasReportedState = data.containsKey('heartbeat_state');
        final state = data['heartbeat_state']?.toString();
        final enabled = hasReportedState
            ? switch (int.tryParse(state ?? '', radix: 10)) {
                0 => true,
                1 => false,
                _ => null,
              }
            : requested;
        if (map['state']?.toString() != '0') {
          _logHeartbeat('$reply，设置失败');
        } else if (enabled != null) {
          _deviceHeartbeatEnabled = enabled;
          final actual = enabled ? '开启' : '关闭';
          final mismatch = requested != null && requested != enabled;
          _logHeartbeat('$reply，${mismatch ? '设置失败，' : ''}设备当前为$actual');
        } else if (hasReportedState) {
          _logHeartbeat('$reply，状态异常（heartbeat_state=$state）');
        } else {
          _logHeartbeat(reply);
        }
        _clearHeartbeatSetting();
        notifyListeners();
        break;
    }
  }

  String _commandResultText(dynamic value) {
    final result = value?.toString();
    if (result == "0") return "成功";
    if (result == "1") return "失败";
    return "结果未知($result)";
  }

  /// 处理设备搜索 (cmd=1)
  void _handleDeviceSearchEvent(Map<String, dynamic> map) {
    if (map['state']?.toString() != "0") return;

    final name = map['data']['name']?.toString() ?? '';
    final address = map['data']['address']?.toString() ?? '';
    final productType = map['data']['productType'] ?? map['data']['type'];
    deviceName = name;
    deviceAddress = address;

    if (address.isNotEmpty && address != 'null') {
      final index = _discoveredDevices.indexWhere((d) => d['address'] == address);
      final device = {
        if (index >= 0) ..._discoveredDevices[index],
        'name': name,
        'address': address,
        if (productType != null) 'productType': productType.toString(),
      };
      if (index < 0) {
        _discoveredDevices.add(device);
        notifyListeners();
      } else if (_discoveredDevices[index]['name'] != name ||
          _discoveredDevices[index]['productType'] != device['productType']) {
        _discoveredDevices[index] = device;
        notifyListeners();
      }
    }

    // 如果自动连接未开启，直接返回
    if (!_isAutoConnecting || deviceMap == null) return;

    final savedAddress = (deviceMap?["address"] ?? "").toString();
    final savedName = (deviceMap?["name"] ?? "").toString();

    final bool isMatch;

    // 如果保存的设备有 address → 必须用 address 匹配
    if (savedAddress.isNotEmpty) {
      // 扫描到的设备如果没有 address，直接跳过
      if (deviceAddress.isEmpty || deviceAddress == "null") {
        isMatch = false;
      } else {
        isMatch = (deviceAddress == savedAddress && deviceName == savedName);
      }
    } else {
      // 保存的设备没有 address → 老设备逻辑
      // 如果扫描到的设备存在 address（非空且不为 "null"），直接跳过
      if (deviceAddress.isNotEmpty && deviceAddress != "null") {
        isMatch = false;
      } else {
        // 扫描到的设备也没有 address，按名字匹配
        isMatch = (deviceName == savedName);
      }
    }

    // if (isMatch) {
    //   Log.d("找到匹配设备，开始自动连接name: $deviceName, address: $deviceAddress");
    //   connect({'name': deviceName, 'address': deviceAddress});
    // }
  }

  /// 处理连接状态变化 (cmd=2)
  Future<void> _handleDeviceConnectionEvent(Map<String, dynamic> map) async {
    //安卓是true,false,ios 是 1，0
    final connectState = map['data']['connect_state']?.toString();
    if (connectState == '0' || connectState == 'false') {
      _isFileTransferring = false;
    }
    if (connectState == "true" || connectState == "1") {
      String? deviceName = map['data']["name"]?.toString();
      if (deviceName != null && !deviceName.contains("null")) {
        var address = map['data']['address']?.toString().trim();
        if (address == null || address.isEmpty || address == 'null') {
          final selectedAddress = deviceMap?['name'] == deviceName
              ? (deviceMap?['address']?.toString().trim())
              : null;
          final matches = _discoveredDevices
              .where((device) => device['name'] == deviceName)
              .toList();
          if (selectedAddress != null &&
              selectedAddress.isNotEmpty && selectedAddress != 'null') {
            address = selectedAddress;
          } else {
            address = matches.length == 1 ? matches.single['address'] : null;
          }
        }
        final deviceKey = address != null && address.isNotEmpty && address != 'null'
            ? 'address:${address.toLowerCase()}'
            : 'name:$deviceName';
        final scanned = _discoveredDevices.firstWhere(
          (device) => address != null && address.isNotEmpty && address != 'null'
              ? device['address']?.toLowerCase() == address.toLowerCase()
              : device['name'] == deviceName,
          orElse: () => const {},
        );
        final saved = deviceKey ==
                'address:${deviceMap?['address']?.toString().toLowerCase()}' ||
            (deviceKey == 'name:${deviceMap?['name']}');
        final savedDevice = saved ? deviceMap : null;
        final previous = _connectedDeviceKey == deviceKey ? _deviceInfo : null;
        final data = Map<String, dynamic>.from(map['data'] as Map);
        // 连接回调的名称可能与扫描名称不同，外贸版暂按类型 40 处理。
        final scannedName = scanned['name'] ?? savedDevice?['name']?.toString();
        final isExportDevice =
            deviceName.contains('外贸') || scannedName?.contains('外贸') == true;
        _deviceInfo = {
          ...?previous,
          ...?savedDevice,
          ...scanned,
          ...data,
          'address': address,
          'productType': isExportDevice
              ? 40
              : data['productType'] ??
                    data['type'] ??
                    scanned['productType'] ??
                    savedDevice?['productType'] ??
                    savedDevice?['type'] ??
                    previous?['productType'],
        };
        // 同一连接的重复成功通知不重复初始化，也不清空文件列表。
        if (_isConnected && _connectedDeviceKey == deviceKey) {
          notifyListeners();
          return;
        }
        _resetDeviceHeartbeat();
        _isFileTransferring = false;
        _connectedDeviceKey = deviceKey;
        _isConnected = true;

        _isAutoConnecting = true;
        stopSearch();
        _clearRecordFileList();
        notifyListeners();

        // 连接成功后
        await ServiceSystemAbility.sleep(2000);
        asyncNowTime();
        await ServiceSystemAbility.sleep(50);
        getCBC();
        await ServiceSystemAbility.sleep(50);
        getSN();
        // // ⚠️⚠️⚠️⚠️⚠️紧接着开始获取传输文件，传输蓝牙大概率断，所以需要延时3秒才可以
        // await ServiceSystemAbility.sleep(3000);
        // getRecordFileList();
      }
    } else if (map['data']['address'] == "null") {
      _resetDeviceHeartbeat();
      _isConnected = false;
      _connectedDeviceKey = null;
      _deviceInfo = null;
    } else {
      closeSuccess();
    }
    notifyListeners();
  }

  /// 处理录音状态 (cmd=3)
  void _handleRecordStateEvent(Map<String, dynamic> map) {
    int recordState =
        int.tryParse(map['data']['record_state']?.toString() ?? '0') ?? 0;
    if (recordState == 1) {
      //设备正在录音
      print("record_state=1开始录音");
      _isRecording = true;
    } else if (recordState == 2) {
      //设备暂停录音
    } else if (recordState == 0) {
      //设备停止录音
      print("record_state=0停止录音");
      _isRecording = false;
      // deleteFile(map['data']["fileName"]);
    }
    notifyListeners();
  }

  /// 处理文件列表 (cmd=4)
  Future<void> _handleFileListEvent(Map<String, dynamic> map) async {
    final raw = map['data'];
    final dataList = raw is List ? raw : const [];
    final isFinish = map['finish'] == '1' || map['finish'] == 1;

    for (final item in dataList) {
      if (item is! Map) continue;
      final name = item['name']?.toString() ?? '';
      if (name.isEmpty || _recordFiles.any((e) => e.name == name)) continue;
      _recordFiles.add(
        RecordFileInfo(
          name: name,
          sizeBytes: _toInt(item['size']),
          durationSec: _toInt(item['time']),
        ),
      );
    }

    if (isFinish) {
      if (_transFileName.isEmpty ||
          !_recordFiles.any((e) => e.name == _transFileName)) {
        _transFileName = _recordFiles.isEmpty ? '' : _recordFiles.last.name;
      }
      Log.d('📋 文件列表接收完成，共 ${_recordFiles.length} 个文件');
    }

    notifyListeners();

    if (isFinish && _isAutoTransfer && _transFileName.isNotEmpty) {
      sendFileFromPenToPhoneWithOffset(transFileName, 0);
    }
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  /// 处理传输进度 (cmd=5)
  Future<void> _handleTransferProgressEvent(Map<String, dynamic> map) async {
    /// 0完成，4传输中，1文件不在，2offset过大（预留），3其他停止
    final String fileState = map['data']['record_file_state'].toString();
    if (const {'0', '1', '2', '3'}.contains(fileState) ||
        (map['state'] != null && map['state']?.toString() != '0')) {
      _isFileTransferring = false;
      notifyListeners();
    }
    switch (fileState) {
      case '0':
        await _handleTransferComplete(map['data']);
        break;
      case '4':
        await _handleTransferInProgress(map['data']);
        break;
      case '1':
        await _handleFileNotFound();
        break;
      case '2':
        Log.e('❌ offset过大');
        onTransferComplete?.call(2, null);
        break;
    }
  }

  /// 处理文件传输完成 (cmd=5, state=0)
  Future<void> _handleTransferComplete(Map<String, dynamic> data) async {
    Log.d('📋 文件传输完成');
    notifyListeners();
  }

  /// 处理文件传输中 (cmd=5, state=4)
  Future<void> _handleTransferInProgress(Map<String, dynamic> data) async {}

  /// 处理文件不存在 (cmd=5, state=1)
  Future<void> _handleFileNotFound() async {
    Log.e('❌ 文件不存在');
  }

  /// 处理电量 (cmd=6)
  void _handleBatteryEvent(Map<String, dynamic> map) {
    _cbc = map['data']['cbc']?.toString() ?? '-1';
    _isConnected = true;
    notifyListeners();
  }

  /// 处理设备SN (cmd=7)
  void _handleDeviceSNEvent(Map<String, dynamic> map) {
    _sn = map['data']['sn']?.toString() ?? '00000000';
    notifyListeners();
  }

  /// 处理设备按键事件 (cmd=8)
  void _handleDeviceButtonEvent(Map<String, dynamic> map) {
    String event = map['data']['event']?.toString() ?? '';
    switch (event) {
      case "1": // 开始录音
        startBtnBackRecord();
        _pendingRecordStartTimestamp = DateTime.now().millisecondsSinceEpoch;
        if (_isAppForeground) {
          onGotoRealTimePen?.call();
        } else {
          _pendingGotoRealTimePen = true;
          print("后台开始录音，保存待跳转标记");
        }
        break;

      case "3": // 停止录音
        _stopBtnBackRecord();

        if (!_isAppForeground) {
          print("后台停止录音，取消待跳转");
          clearPendingJump();
        }
        break;

      default:
    }
  }

  /// 处理录音状态 (cmd=9)
  void _handleRecordingStateEvent(Map<String, dynamic> map) {
    bool isRecording = map['data']['recordState'] == "1";
    if (isRecording) {
      print("小机在录音状态");
      _isRecording = true;
      connectGotoRealTimePen?.call(true);
    } else {
      _isRecording = false;
    }
    notifyListeners();
  }

  /// 处理录音时间 (cmd=10)
  void _handleRecordTimeEvent(Map<String, dynamic> map) {
    // _getFileName();
    notifyListeners();
  }

  /// 处理录音文件名 (cmd=11)
  void _handleRecordFileNameEvent(Map<String, dynamic> map) {
    String fileName = map['data']['recordName']?.toString() ?? '';
    print("启动获取录音名称$fileName");
  }

  _handleDeleteEvent(Map<String, dynamic> map) {
    bool isDelete = map['data']['delete_state'] == "0";
    if (isDelete) {
      print("删除成功");
    } else {
      print("删除失败");
    }
  }

  /// 前后台切换监听
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    bool wasForeground = _isAppForeground;

    if (state == AppLifecycleState.resumed) {
      _isAppForeground = true;
      print("RecordPenProvider监听到前台");
      if (wasForeground != _isAppForeground) {
        notifyListeners();
      }
      // App 前台时触发待跳转
      triggerPendingJump();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _isAppForeground = false;
      print("RecordPenProvider监听到后台");
      if (wasForeground != _isAppForeground) {
        notifyListeners();
      }
    }
  }

  /// 设备信息
  @Deprecated("抛弃，原生未实现")
  getDeviceInfo() async {
    await _methodChannel.invokeMethod('getDeviceInfo');
  }

  /// 搜索
  startSearch() async {
    _discoveredDevices.clear();
    deviceName = '';
    deviceAddress = '';
    notifyListeners();
    await _bluetoothService.startSearch();
  }

  /// 连接
  connect(Map<String, dynamic> device) async {
    print("链接设备name=${device["name"]} address=${device["address"]}");
    deviceMap = device;
    await _bluetoothService.connect(device);
  }

  /// 蓝牙连接后进行 AuthKey 认证，结果通过 cmd=31 返回。
  Future<void> authkeyConnect(String authkey) async {
    await _bluetoothService.authkeyConnect(authkey);
  }

  Future<void> resetAuthkey(String authkey) async {
    await _bluetoothService.resetAuthkey(authkey);
  }

  Future<void> unbondAuthkey() async {
    await _bluetoothService.unbondAuthkey();
  }

  Future<void> setWifiPassword(String password) async {
    await _bluetoothService.setWifiPassword(password);
  }

  // 用于自动连接的设备名称和地址
  Map<String, dynamic>? deviceMap;
  bool _isAutoConnecting = false;

  /// 停止自动连接状态
  void stopAutoConnect() {
    _isAutoConnecting = false;
    _deviceInfo = null;
  }

  /// 断开连接成功
  closeSuccess() async {
    Log.d("☹️断开了");
    _resetDeviceHeartbeat();
    _isConnected = false;
    _connectedDeviceKey = null;
    _deviceInfo = null;
    _isRecording = false;
    _cbc = "-1";
    _isFileTransferring = false;
    _sn = "00000000";
    _clearRecordFileList();

    notifyListeners();
    Future.delayed(const Duration(seconds: 5), () {
      if (!_isAutoConnecting) return;
      startSearch();
    });
  }

  //准备断开连接
  closeConnect() async {
    Log.d("准备断开连接");
    await _bluetoothService.disconnect();
  }

  /// 录音
  startRecord() async {
    if (_isRecording) {
      // UIUtil.showToast("已经录音，不启动startRecord()");
      return;
    }
    resetAudioRate(AudioDataType.record);
    await _recordService.startRecord();
  }

  /// L09 选择麦克风并启动录音
  Future<void> startRecordWithBoneMic(bool enabled) async {
    if (_isRecording) return;
    resetAudioRate(AudioDataType.record);
    await _recordService.startRecordWithBoneMic(enabled);
  }

  /// 暂停录音
  pauseRecord() async {
    await _recordService.pauseRecord();
    Log.d("暂停结果");
  }

  /// 恢复录音
  continueRecord() async {
    await _recordService.continueRecord();
  }

  /// 停止录音
  stopRecord() async {
    print("停止录音");
    await _recordService.stopRecord();
    if (!_isRecording) {
      // UIUtil.showToast("已经停止，不启动stopRecord()");

      return;
    }
    _pendingRecordStartTimestamp = null;
    if (_isRecording != false) {
      _isRecording = false;
      await _recordService.stopRecord();
    }
  }

  /// 停止扫描
  stopSearch() async {
    await _bluetoothService.stopSearch();
  }

  // ================== 私有辅助方法 ==================

  /// 获取文件列表
  Future<void> getRecordFileList() async {
    _clearRecordFileList();
    await _bluetoothService.getRecordFileList();
  }

  /// 获取设备电量
  Future<void> getCBC() async {
    await _bluetoothService.getCBC();
  }

  /// 获取sn
  Future<void> getSN() async {
    await _bluetoothService.getSN();
  }

  /// 给设备下发当前时间
  Future<void> asyncNowTime() async {
    await _bluetoothService.syncTime();
  }

  /// 获取录音笔正在录音中时候的录音文件名称
  Future<void> getFileName() async {
    await _bluetoothService.getFileNameOnlyRecording();
  }

  /// 传输文件到手机（支持断点续传）
  Future<void> sendFileFromPenToPhoneWithOffset(
    String fileName,
    int offset,
  ) async {
    _transferPacketNumber = 0;
    resetAudioRate(AudioDataType.file);
    _isFileTransferring = true;
    notifyListeners();
    try {
      await _recordService.sendFileFromPenToPhoneWithOffset(fileName, offset);
    } catch (_) {
      _isFileTransferring = false;
      notifyListeners();
      rethrow;
    }
  }

  /// 停止传输文件
  Future<void> stopTransferFile(String fileName) async {
    await _recordService.stopTransferFile(fileName);
    notifyListeners();
  }

  ///返回按键开始录音
  void startBtnBackRecord() {
    _recordService.startBtnBackRecord();
  }

  ///返回按键停止录音
  void _stopBtnBackRecord() {
    _isRecording = false;
    _pendingRecordStartTimestamp = null;
    _recordService.stopBtnBackRecord();
  }

  /// 是否已连接
  isDeviceConnected() {
    return _bluetoothService.isDeviceConnected();
  }

  /// 获取设备容量
  getDeviceCapacity() {
    return _bluetoothService.getDeviceCapacity();
  }

  /// 获取获取录音笔录音状态
  getRecordState() {
    return _bluetoothService.getRecordState();
  }

  ///获取当前录音时长，当录音笔设备是在录音状态的时候
  getTimeOnlyRecording() {
    return _bluetoothService.getTimeOnlyRecording();
  }

  /// 删除文件
  deleteFile(String fileName) async {
    await _bluetoothService.deleteFile(fileName);
  }

  /// 删除所有文件
  deleteAllFile() async {
    await _bluetoothService.deleteAllFiles();
  }

  /// 获取当前增益
  getDeviceGain() {
    return _bluetoothService.getDeviceGain();
  }

  /// 设置当前增益  参数：gain 值：1：低   2：中   3：高
  setDeviceGain(int gain) {
    return _bluetoothService.setDeviceGain(gain);
  }

  /// 发送sendAppShowState
  sendAppShowState(int state) {
    return _bluetoothService.sendAppShowState(state);
  }

  /// 获取设备固件版本
  getDeviceVersion() {
    return _bluetoothService.getDeviceVersion();
  }

  ///搜索 wifi
  openWiFi() async {
    _methodChannel.invokeMethod('openWiFi');

    if (!Platform.isAndroid) return;
    await WiFiForIoTPlugin.setEnabled(true, shouldOpenSettings: false);
    await WiFiForIoTPlugin.forceWifiUsage(true);
    streamController.add({"wifi": "Wi-Fi 已尝试打开"});
  }

  ///关闭搜索 Wi-Fi
  closeWiFi() async {
    _methodChannel.invokeMethod('closeWiFi');
    if (!Platform.isAndroid) return;
    await WiFiForIoTPlugin.forceWifiUsage(false);
    await WiFiForIoTPlugin.setEnabled(false, shouldOpenSettings: false);
    streamController.add({"wifi": "Wi-Fi 已尝试关闭"});
  }

  ///连接wifi
  connectDeviceWiFi({String? password}) async {
    if (_wifiName.isEmpty) {
      streamController.add({"wifi": "wifiName 为空，无法匹配并连接"});
      return;
    }

    if (Platform.isAndroid) {
      await WiFiForIoTPlugin.setEnabled(true, shouldOpenSettings: false);
    }

    final bool connected = await WiFiForIoTPlugin.connect(
      _wifiName.trim(),
      password: password,
      joinOnce: true,
      withInternet: false,
      security: password == null ? NetworkSecurity.NONE : NetworkSecurity.WPA,
    );
    if (Platform.isAndroid) {
      streamController.add({
        "wifi": connected ? "已发起直连: $_wifiName" : "直连失败: $_wifiName",
      });
      if (!connected) return;
    }
    if (Platform.isAndroid) {
      await WiFiForIoTPlugin.forceWifiUsage(true);
    }
    // connect() 返回 true 后，系统可能仍在完成关联流程，先确认 SSID 再发起 TCP。
    bool ssidMatched = false;
    if (Platform.isAndroid) {
      for (int i = 0; i < 12; i++) {
        await Future.delayed(const Duration(seconds: 1));
        final String? currentSsid = await WiFiForIoTPlugin.getSSID();
        final String normalized = (currentSsid ?? '')
            .replaceAll('"', '')
            .trim()
            .toLowerCase();
        final String target = _wifiName.trim().toLowerCase();
        if (normalized == target) {
          ssidMatched = true;
          break;
        }
      }
    } else {
      ssidMatched = true;
    }

    if (!ssidMatched) {
      streamController.add({"wifi": "Wi-Fi 尚未稳定连接到 $_wifiName，取消建立 TCP"});
      return;
    }
    if (Platform.isIOS) {
      await ServiceSystemAbility.sleep(8000);
    }
    streamController.add({"wifi": "建立TCP/IP"});
    await _methodChannel.invokeMethod('connectDeviceWiFi');
  }

  ///断开 Wi-Fi
  disconnectDeviceWiFi() async {
    await WiFiForIoTPlugin.disconnect();
    await WiFiForIoTPlugin.forceWifiUsage(false);
    streamController.add({"wifi": "已断开当前 Wi-Fi"});
    _methodChannel.invokeMethod('disconnectDeviceWiFi');
  }

  /// 一键连接设备 Wi-Fi
  Future<void> quickConnectDeviceWiFi({String password = ''}) async {
    await _methodChannel.invokeMethod('quickConnectDeviceWiFi', {
      'password': password,
    });
  }

  ///获取设备 Wi-Fi 状态
  /// 返回 WiFi 状态字符串，如果超时则返回当前缓存的状态
  /// 0表示打开，1表示关闭或失败，2表示连接成功，3表示断开
  getDeviceWiFiState() async {
    await _methodChannel.invokeMethod('getDeviceWiFiState');
  }

  ///获取设备版本 Code
  getDeviceVersionCode({Duration timeout = const Duration(seconds: 5)}) async {
    // 发送获取版本 Code 命令
    await _methodChannel.invokeMethod('getDeviceVersionCode');
  }

  /// 获取手机热点状态
  /// 返回热点状态字符串，如果超时则返回当前缓存的状态
  /// 4 有手机连接设备WiFi热点   5当前没有手机连接设备WiFi热点
  getWiFiHotspotState() async {
    await _methodChannel.invokeMethod('getWiFiHotspotState');
  }

  /// 设置设备名称，仅支持 2-16 位英文或数字。
  Future<void> setDeviceName(String name) async {
    await _methodChannel.invokeMethod('setDeviceName', {'name': name});
  }

  /// 重置设备，执行结果通过 cmd=35 返回。
  Future<void> resetDevice() async {
    await _methodChannel.invokeMethod('resetDevice');
  }

  /// 将设备名称复位为出厂默认值。
  Future<void> resetDeviceName() async {
    await _methodChannel.invokeMethod('resetDeviceName');
  }

  /// 设置直连 Wi-Fi 的 SSID 和密码。
  Future<void> setWifiDirect(String ssid, String password) async {
    await _methodChannel.invokeMethod('setWifiDirect', {
      'ssid': ssid,
      'password': password,
    });
  }

  /// 设置音频直传服务器上传 URL。
  Future<void> setRemoteUrl(String url) async {
    await _methodChannel.invokeMethod('setRemoteUrl', {'url': url});
  }

  /// 将直连 Wi-Fi 参数复位为出厂默认值。
  Future<void> resetWifiDirect() async {
    await _methodChannel.invokeMethod('resetWifiDirect');
  }

  /// 获取当前直连 Wi-Fi 的 SSID 和连接状态。
  Future<void> getWifiDirect() async {
    await _methodChannel.invokeMethod('getWifiDirect');
  }

  /// 请求设备进入 OTA 升级模式
  /// 结果通过 EventChannel (cmd=19) 返回
  Future<void> requestDeviceGotoOtaMode() async {
    await _methodChannel.invokeMethod('requestDeviceGotoOtaMode');
  }

  Future<void> cancelOtaTransfer() async {
    final active = _otaRequestPending || _otaTransferTimer != null;
    final cancellation = _otaRequestCancellation;
    if (cancellation != null && !cancellation.isCompleted) {
      cancellation.completeError(StateError('OTA 已中断'));
    }
    _clearOtaTransfer();
    if (active && isConnected) await closeConnect();
  }

  void _clearOtaTransfer() {
    _otaTransferTimer?.cancel();
    _otaTransferTimer = null;
    _otaAwaitingVerification = false;
  }

  void _startOtaTransferTimeout(Duration timeout, String message) {
    _otaTransferTimer?.cancel();
    _otaTransferTimer = Timer(timeout, () {
      _clearOtaTransfer();
      streamController.add({otaTransferErrorKey: message});
    });
  }

  void _handleOtaProgress(Map<String, dynamic> event) {
    if (event['state']?.toString() != '0') {
      _clearOtaTransfer();
      return;
    }
    if (_otaTransferTimer == null || _otaAwaitingVerification) return;
    final data = event['data'];
    if (data is! Map) return;
    final progress = int.tryParse('${data['progress']}');
    final total = int.tryParse('${data['total']}');
    if (progress == null || total == null || total <= 0 || progress < total) {
      return;
    }

    _otaAwaitingVerification = true;
    _startOtaTransferTimeout(
      _otaVerificationTimeout,
      '文件验证超时（${_otaVerificationTimeout.inSeconds} 秒内未收到校验结果）',
    );
  }

  /// 收到设备进入升级模式的成功回复后，再发送固件。
  Future<void> requestAndSendOtaFile(
    String filePath, {
    Duration timeout = const Duration(seconds: 10),
    bool Function()? canSend,
  }) async {
    if (_otaRequestPending || _otaTransferTimer != null) {
      throw StateError('OTA 正在进行，请等待当前操作结束');
    }
    _otaRequestPending = true;
    final cancellation = Completer<Never>();
    _otaRequestCancellation = cancellation;
    final prepared = Completer<Map<String, dynamic>>();
    // 先监听，避免遗漏请求调用期间立即到达的设备回复。
    final subscription = streamController.stream.listen((event) {
      if (event['cmd']?.toString() == '19' && !prepared.isCompleted) {
        prepared.complete(event);
      }
    });
    try {
      final results = await Future.any([
        Future.wait<dynamic>([
          prepared.future,
          requestDeviceGotoOtaMode(),
        ], eagerError: true),
        cancellation.future,
      ]).timeout(
        timeout,
        onTimeout: () => throw TimeoutException('请求升级超时，未发送固件', timeout),
      );
      final response = results.first as Map<String, dynamic>;
      if (response['state']?.toString() != '0') {
        throw StateError('请求升级失败（state=${response['state']}）');
      }
      final data = response['data'];
      final prepareState = data is Map ? data['prepareState']?.toString() : null;
      if (!_allowedOtaPrepareStates.contains(prepareState)) {
        final reason = switch (prepareState) {
          '1' => '不能进入升级状态，请检查 SD 卡或内存空间',
          '2' => 'WiFi 的 TCP/IP 未连接，请先连接设备 WiFi',
          _ => '未知升级准备状态：$prepareState',
        };
        throw OtaPreparationError(prepareState, reason);
      }
      if (canSend?.call() == false) {
        throw StateError('设备连接已变化，取消发送固件');
      }
      _startOtaTransferTimeout(otaResultTimeout, '等待固件发送完成超时');
      try {
        await sendOtaFile(filePath);
      } catch (_) {
        _clearOtaTransfer();
        rethrow;
      }
    } finally {
      _otaRequestPending = false;
      _otaRequestCancellation = null;
      await subscription.cancel();
    }
  }

  /// 发送 OTA 固件文件
  /// [filePath] 固件文件路径
  /// 进度通过 EventChannel (cmd=20) 返回
  Future<void> sendOtaFile(String filePath) async {
    await _methodChannel.invokeMethod('sendOtaFile', {'filePath': filePath});
  }

  /// cmd 12
  /// WiFi 状态返回
  /// 0表示打开状态，1表示关闭或打开失败，2表示连接成功，3表示断开连接状态
  void _handleDeviceWiFiStateEvent(Map<String, dynamic> map) {
    final data = map['data'] as Map<String, dynamic>? ?? {};
    _wifiState = data['wifi_state']?.toString() ?? "";
    if (data['wifiName'] != "" && data['wifiName'] != null) {
      _wifiName = data['wifiName']?.toString() ?? "";
    }
    const wifiStateTextMap = <String, String>{
      "0": "WiFi热点打开",
      "1": "WiFi热点关闭",
      "2": "WiFi连接成功",
      "3": "WiFi断开连接",
      "4": "有手机WiFi连接",
      "5": "当前没有手机连接设备WiFi热点",
    };
    streamController.add({
      "wifi": wifiStateTextMap[_wifiState] ?? "未知WiFi状态($_wifiState)",
    });
    notifyListeners();
  }

  /// cmd 17
  /// 获取设备固件版本
  void _handleDeviceFirewareVersion(Map<String, dynamic> map) {
    _deviceVersion = map['data']['version'];
  }

  /// cmd 18
  /// 获取设备固件版本 Code
  void _handleDeviceWiFiCode(Map<String, dynamic> map) {
    final versionCodeData = map['data']['versionCode'];
    // 处理字符串或整数类型
    if (versionCodeData is int) {
      _deviceVersionCode = versionCodeData;
    } else if (versionCodeData is String) {
      _deviceVersionCode = int.tryParse(versionCodeData) ?? 0;
    } else {
      _deviceVersionCode = 0;
    }
  }

  /// 获取低功耗录音模式状态
  getDeviceLowPowerRecordMode({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    await _methodChannel.invokeMethod('getDeviceLowPowerRecordMode');
  }

  /// 设置低功耗录音模式状态
  /// state: 0 表示关闭，1 表示开启
  Future<void> setDeviceLowPowerRecordMode(bool enabled) async {
    await _methodChannel.invokeMethod('setDeviceLowPowerRecordMode', {
      'state': enabled ? 1 : 0,
    });
  }

  /// 设置离线文件传输间隔（毫秒）。
  Future<void> setSendFileTimeInterval(int interval) async {
    if (interval < 13 || interval > 255) {
      throw const FormatException('传输间隔须为 13–255 毫秒');
    }
    await _methodChannel.invokeMethod('sendFileTimeInterval', {
      'interval': interval,
    });
  }

  Future<void> setHeartbeatDataState(bool enabled) async {
    if (isHeartbeatSettingPending) return;
    final action = enabled ? '开启' : '关闭';
    final timeout = Timer(const Duration(seconds: 5), () {
      _clearHeartbeatSetting();
      _logHeartbeat('设置$action设备心跳超时，未收到设备应答');
      notifyListeners();
    });
    _heartbeatSetting = (enabled: enabled, timeout: timeout);
    _logHeartbeat('设置$action设备心跳（0x34）');
    notifyListeners();
    try {
      await _methodChannel.invokeMethod('setHeartbeatDataState', {
        'state': enabled ? 1 : 0,
      });
    } catch (error) {
      if (_heartbeatSetting?.timeout == timeout) {
        _clearHeartbeatSetting();
        _logHeartbeat('设置$action设备心跳发送失败 $error');
        notifyListeners();
      }
      rethrow;
    }
  }

  Future<void> sendBackHeartbeatData() async {
    try {
      await _methodChannel.invokeMethod('sendBackHeartbeatData');
    } catch (error) {
      _logHeartbeat('发送心跳回复失败 $error');
      rethrow;
    }
    _logHeartbeat('已发送心跳回复（0x33）');
  }

  void _logHeartbeat(String message) {
    streamController.add({'heartbeatLog': message});
  }

  void _clearHeartbeatSetting() {
    _heartbeatSetting?.timeout.cancel();
    _heartbeatSetting = null;
  }

  void _resetDeviceHeartbeat() {
    _clearHeartbeatSetting();
    _deviceHeartbeatEnabled = true;
  }

  /// 获取 BK 版本号
  Future<void> getBKHDVersion() {
    return _bluetoothService.getBKHDVersion();
  }

  /// 发送 BK 升级 URL
  Future<void> setBKUpgradeHd(String url) {
    return _bluetoothService.setBKUpgradeHd(url);
  }

  /// 启动本地 HTTP，[firmwareFile] 为文件管理器选出的固件。
  Future<String> startBkUpgradeHttpServer({required File firmwareFile}) async {
    final url = await BkUpgradeHttpServer.instance.start(
      firmwareFile: firmwareFile,
    );
    streamController.add({'BK': 'HTTP已启动 $url'});
    return url;
  }

  Future<void> stopBkUpgradeHttpServer() async {
    await BkUpgradeHttpServer.instance.stop();
    streamController.add({'BK': 'HTTP已停止'});
  }
}
