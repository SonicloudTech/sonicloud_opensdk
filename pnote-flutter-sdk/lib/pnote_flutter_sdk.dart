/// 声云录音笔 SDK 对外入口（AudioPenSdk）。
///
/// 方法名对齐 iOS 端（便于跨端同事按 iOS 习惯查找）：
/// `startSearch` / `connectDevice` / `getCBC` / `getDeviceCapacity` /
/// `getDeviceVersion` / `getSn` / `getRecordFileList` / `startGetFile` /
/// `stopGetFile` 等。
///
/// 典型用法：
/// ```dart
/// final sdk = AudioPenSdk();
/// sdk.startSearch().listen((results) { /* 显示设备列表 */ });
/// final device = await sdk.connectDevice(scanResult.device);
/// await device.syncTime();
/// final battery = await device.getCBC();
/// final files = await device.getRecordFileList();
/// ```
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'src/pen/app_protocol.dart';
import 'src/pen/audio_pen_controller.dart';
import 'src/pen/commands.dart';
import 'src/pen/frame.dart';
import 'src/pen/models.dart';
import 'src/transport/ble_transport.dart';
import 'src/transport/transport.dart';

export 'src/pen/app_protocol.dart' show AppCmd, AppCodec;
export 'src/pen/commands.dart' show BleUuids, DataType, ControlCmd, KeyCmd, FileCmd;
export 'src/pen/frame.dart' show Frame;
export 'src/pen/models.dart'
    show BatteryInfo, Capacity, DeviceMode, PenFile, RecordState, FileList,
        FileEndCode, FileDownloadResult;
export 'src/transport/transport.dart' show TransportState;

/// SDK 顶层入口：负责扫描与建立连接。
class AudioPenSdk {
  AudioPenSdk({this.debugLog = true});

  /// 是否在控制台打印扫描/连接的设备底层信息。
  final bool debugLog;

  /// 已打印过的设备 id（扫描日志去重，避免刷屏）。
  final Set<String> _loggedScan = {};

  /// 扫描结果缓存（地址小写 → 结果），供 [connectDeviceAndAddress] 按名址重连。
  final Map<String, ScanResult> _scanCache = {};

  /// 是否蓝牙可用且已开启。
  Future<bool> get isBluetoothOn async {
    if (!await FlutterBluePlus.isSupported) return false;
    return FlutterBluePlus.adapterStateNow == BluetoothAdapterState.on;
  }

  /// 蓝牙适配器状态流。
  Stream<BluetoothAdapterState> get adapterState =>
      FlutterBluePlus.adapterState;

  /// 开始搜索（对齐 iOS 端 `startSearch`）。
  ///
  /// 返回扫描结果流（按 0xAE20 服务过滤）；[timeout] 到后自动停止扫描。
  Stream<List<ScanResult>> startSearch({
    Duration timeout = const Duration(seconds: 15),
  }) {
    _loggedScan.clear();
    _scanCache.clear();
    FlutterBluePlus.startScan(
      withServices: [Guid(BleUuids.service)],
      timeout: timeout,
    );
    return FlutterBluePlus.scanResults.map(_cacheAndLog);
  }

  /// 不带服务过滤的扫描（调试用）：当按 0xAE20 过滤扫不到设备时，
  /// 用本方法看到周围所有 BLE 设备的广播，确认录音笔到底广播了什么。
  Stream<List<ScanResult>> scanAll({
    Duration timeout = const Duration(seconds: 15),
  }) {
    _loggedScan.clear();
    _scanCache.clear();
    FlutterBluePlus.startScan(timeout: timeout);
    return FlutterBluePlus.scanResults.map(_cacheAndLog);
  }

  /// 更新扫描缓存 +（可选）打印，返回原结果列表。
  List<ScanResult> _cacheAndLog(List<ScanResult> results) {
    for (final r in results) {
      _scanCache[r.device.remoteId.str.toLowerCase()] = r;
    }
    if (debugLog) {
      for (final r in results) {
        _logScanResult(r);
      }
    }
    return results;
  }

  /// 打印单个扫描结果的底层信息（按 id 去重）。
  void _logScanResult(ScanResult r) {
    final id = r.device.remoteId.str;
    if (!_loggedScan.add(id)) return; // 已打印过

    final adv = r.advertisementData;
    final buf = StringBuffer()
      ..writeln('───── 扫描到设备 ─────')
      ..writeln('  名称(platformName) : ${r.device.platformName}')
      ..writeln('  广播名(advName)    : ${adv.advName}')
      ..writeln('  设备ID/MAC         : $id')
      ..writeln('  RSSI               : ${r.rssi} dBm')
      ..writeln('  可连接             : ${adv.connectable}')
      ..writeln('  TxPower            : ${adv.txPowerLevel}')
      ..writeln('  Service UUIDs      : '
          '${adv.serviceUuids.isEmpty ? '(无)' : adv.serviceUuids.map((g) => '0x${g.str}').join(', ')}');

    // 广播里的 Service Data（key=UUID, value=字节）
    if (adv.serviceData.isNotEmpty) {
      buf.writeln('  Service Data:');
      adv.serviceData.forEach((uuid, bytes) {
        buf.writeln('    0x${uuid.str} -> ${_hex(bytes)}');
      });
    }

    // 制造商自定义数据（key=公司ID, value=字节）—— 协议里 mac/类别就藏这里
    if (adv.manufacturerData.isNotEmpty) {
      buf.writeln('  Manufacturer Data:');
      adv.manufacturerData.forEach((companyId, bytes) {
        final raw = _hex(bytes);
        // 协议：制造商数据 = 类别(1B)+mac，整体与 0x35 异或加密
        final dec = _hex(bytes.map((b) => b ^ 0x35).toList());
        buf.writeln('    companyId=0x${companyId.toRadixString(16)} '
            'raw=$raw');
        buf.writeln('      ^0x35解密=$dec');
        if (bytes.isNotEmpty) {
          final category = bytes[0] ^ 0x35;
          final macBytes = bytes.skip(1).map((b) => b ^ 0x35).toList();
          final mac = macBytes
              .map((b) => b.toRadixString(16).padLeft(2, '0'))
              .join(':');
          buf.writeln('      => 类别=0x${category.toRadixString(16)} '
              '(0x03=WiFi卡片机), MAC=$mac');
        }
      });
    }

    debugPrint('[BLE-SCAN] $buf');
  }

  static String _hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');

  /// 停止搜索（对齐 iOS 端 `stopSearch`）。
  Future<void> stopSearch() => FlutterBluePlus.stopScan();

  /// 连接设备并返回会话对象（对齐 iOS 端 `connectDevice:`）。
  Future<AudioPenDevice> connectDevice(BluetoothDevice device) async {
    await stopSearch();
    final transport = BleTransport(device, debugLog: debugLog);
    final controller = AudioPenController(transport);
    await transport.connect();
    controller.start();
    return AudioPenDevice._(device, transport, controller);
  }

  /// 按名字+地址连接（对齐 iOS 端 `connectDeviceAndAddress::`，用于重连）。
  ///
  /// iOS 端实现是从扫描缓存 peripherals 里按名/址匹配后连接；这里等价：
  /// 先按 [address]（唯一，大小写不敏感）命中本次 [startSearch]/[scanAll]
  /// 的扫描缓存，未命中再按 [name] 兜底匹配；仍未命中则按地址直接构造
  /// [BluetoothDevice] 发起连接（上次会话记录的地址重连，无需设备正在广播）。
  Future<AudioPenDevice> connectDeviceAndAddress(
    String name,
    String address,
  ) async {
    ScanResult? cached = _scanCache[address.toLowerCase()];
    if (cached == null && name.isNotEmpty) {
      for (final r in _scanCache.values) {
        if (r.device.platformName == name) {
          cached = r;
          break;
        }
      }
    }
    final device = cached?.device ?? BluetoothDevice.fromId(address);
    return connectDevice(device);
  }
}

/// 一个已连接的录音笔会话。
class AudioPenDevice {
  AudioPenDevice._(this._device, this._transport, this._controller);

  final BluetoothDevice _device;
  final Transport _transport;
  final AudioPenController _controller;

  /// 设备名称。
  String get name => _device.platformName;

  /// 设备 id。
  String get id => _device.remoteId.str;

  /// 连接状态流。
  Stream<TransportState> get connectionState => _transport.stateStream;

  /// 是否已连接（对齐 iOS 端 `isDeviceConnected`）。
  bool get isDeviceConnected => _transport.state == TransportState.connected;

  /// 是否显示日志（对齐 iOS 端 `setShowLog:`）。等价于 [debugLog] 赋值。
  void setShowLog(bool showLog) => debugLog = showLog;

  /// 设备模式状态流（录音/播放等）。
  Stream<DeviceMode> get statusStream => _controller.statusStream;

  /// 按键事件流。
  Stream<Frame> get keyEventStream => _controller.keyEventStream;

  /// 设备端暂停/继续/停止录音事件流（用户在机身上物理操作，audio `0x04`）。
  /// 值：0 停止 / 2 暂停 / 3 继续（对齐 iOS 映射）。
  Stream<int> get deviceRecordStream => _controller.deviceRecordStream;

  /// 原始帧流（调试用）。
  Stream<Frame> get rawFrameStream => _controller.rawFrameStream;

  /// 实时录音音频流（opus 原始字节，对齐 iOS `deviceRecordData:`）。
  /// [startRecord] 后设备自动持续下发，[stopRecord] 即停。
  Stream<Uint8List> get recordDataStream => _controller.recordDataStream;

  /// 底层调试日志行流（原始字节 `[BLE…]`、GATT 发现等），供上层显示到 UI 控制台。
  /// 仅在 [debugLog] 为 true 时产出。
  Stream<String> get debugLogStream => _transport.debugLogStream;

  /// 调试日志开关（运行时可切换）。
  ///
  /// 控制传输层是否打印**原始字节**。解码后的**原始帧调试流** [rawFrameStream]
  /// 是否消费由上层自行决定；设为 false 时建议上层一并停止监听 [rawFrameStream]。
  bool get debugLog => _transport.debugLog;
  set debugLog(bool v) => _transport.debugLog = v;

  /// **App 侧统一事件流**（下发给上层 app 的 JSON 字符串）。
  ///
  /// 把设备主动上报的事件按《录音笔接口信息说明文档》格式输出，
  /// 上层 app 可直接消费（等价于 iOS 端的 `onDeviceStateEvent(String)`）。
  /// 当前覆盖：
  /// - 物理按键（cmd=8）：用户在录音笔上按开始(1)/保存(3)/暂停(5)/继续(7)。
  /// - 录音模式变化（cmd=9）：设备模式状态流里录音位变化时上报。
  /// - 设备端暂停/继续/停止（cmd=3）：用户在录音笔上物理操作，对齐 iOS
  ///   `AUDIO_PAUSE_PLAY_BY_DEVICE`（record_state：0 停止/2 暂停/3 继续）。
  Stream<String> get appEventStream {
    final keyEvents = _controller.keyEventStream
        .where((f) => f.cmd > 0 && f.cmd.isOdd) // 1/3/5/7 物理按键
        .map((f) => AppCodec.encode(AppCodec.keyEvent(f.cmd)));
    final recordEvents = _controller.statusStream.map((m) =>
        AppCodec.encode(AppCodec.recordStateReply(
            m.recording ? RecordState.recording : RecordState.idle)));
    final deviceRecordEvents = _controller.deviceRecordStream.map(
        (state) => AppCodec.encode(AppCodec.record(recordState: state)));
    return _mergeStreams([keyEvents, recordEvents, deviceRecordEvents]);
  }

  /// 同步时间到设备。
  Future<void> syncTime([DateTime? time]) => _controller.syncTime(time);

  /// 获取电量（对齐 iOS 端 `getCBC`）。
  Future<BatteryInfo> getCBC() => _controller.getBattery();

  /// 获取容量（对齐 iOS 端 `getDeviceCapacity`）。
  Future<Capacity> getDeviceCapacity() => _controller.getCapacity();

  /// 获取固件版本（对齐 iOS 端 `getDeviceVersion`）。
  Future<String> getDeviceVersion() => _controller.getVersion();

  /// 获取 SN（对齐 iOS 端 `getSn`）。协议无独立 SN 指令，底层用 MAC 代替。
  Future<String> getSn() => _controller.getMac();

  /// 开始录音。
  Future<bool> startRecord() => _controller.startRecord();

  /// 停止（保存）录音。
  Future<bool> stopRecord() => _controller.stopRecord();

  /// 暂停录音。
  Future<bool> pauseRecord() => _controller.pauseRecord();

  /// 继续录音（对齐 iOS 端 `continueRecord`）。
  Future<bool> continueRecord() => _controller.resumeRecord();

  /// 获取录音状态。
  Future<RecordState> getRecordState() => _controller.getRecordState();

  /// 获取文件列表（对齐 iOS 端 `getRecordFileList`）。
  Future<List<PenFile>> getRecordFileList() => _controller.getFileList();

  /// 下载录音文件（对齐 iOS 端 `startGetFile:fileName:offset`）。
  /// [fileName] 取自 [PenFile.name]；[offset] 续传起点（0=从头）。
  /// 期间数据块经 [fileDataStream]、进度（已收字节）经 [downloadProgressStream]。
  Future<FileDownloadResult> startGetFile(String fileName, {int offset = 0}) =>
      _controller.downloadFile(fileName, offset: offset);

  /// 分段下载录音文件（对齐 iOS 端 `startGetFileByFromToEnd:::`）。
  /// 下载 [offset, end) 字节区间；期间数据块经 [fileDataStream]、进度经 [downloadProgressStream]。
  Future<FileDownloadResult> startGetFileByFromToEnd(
          String fileName, {required int offset, required int end}) =>
      _controller.downloadFile(fileName, offset: offset, end: end);

  /// 终止当前下载（对齐 iOS 端 `stopGetFile:`）。设备停止推流。
  /// [fileName] 仅为对齐 iOS 端签名保留，底层终止指令无需文件名。
  Future<void> stopGetFile([String? fileName]) => _controller.abortDownload();

  /// 删除一个录音文件（对齐 iOS 端 `delFileData:`）。返回是否删除成功。
  Future<bool> delFileData(String fileName) => _controller.delFileData(fileName);

  /// 删除全部录音文件（对齐 iOS 端 `delAllFileData`）。
  /// 返回是否成功（设备回 0 成功 / 1 失败）。
  Future<bool> delAllFileData() => _controller.deleteAllFiles();

  /// 文件下载数据流（设备 cmd=4 推送的每一块字节）。
  Stream<Uint8List> get fileDataStream => _controller.fileDataStream;

  /// 文件下载进度流（已收字节数）。
  Stream<int> get downloadProgressStream => _controller.downloadProgressStream;

  // ---- App 侧 JSON 便捷方法（请求 + 转 app 格式，返回可下发字符串） ----

  /// 获取电量并返回 app JSON（cmd=6）：`{"cmd":"6","state":"0","data":{"cbc":"95"}}`。
  Future<String> getCBCAppJson() async =>
      AppCodec.encode(AppCodec.battery(await getCBC()));

  /// 获取容量并返回 app JSON（cmd=13）。
  Future<String> getDeviceCapacityAppJson() async =>
      AppCodec.encode(AppCodec.capacity(await getDeviceCapacity()));

  /// 获取版本并返回 app JSON（cmd=17）。
  Future<String> getDeviceVersionAppJson() async =>
      AppCodec.encode(AppCodec.version(await getDeviceVersion()));

  /// 获取 SN（底层用 MAC 代替）并返回 app JSON（cmd=7）。
  Future<String> getSnAppJson() async =>
      AppCodec.encode(AppCodec.sn(await getSn()));

  /// 获取录音状态并返回 app JSON（cmd=9）。
  Future<String> getRecordStateAppJson() async =>
      AppCodec.encode(AppCodec.recordStateReply(await getRecordState()));

  /// 开始录音并返回 app JSON（cmd=3，record_state=1），对齐 iOS 端。
  Future<String> startRecordAppJson() async {
    await startRecord();
    return AppCodec.encode(AppCodec.record(recordState: 1));
  }

  /// 停止录音并返回 app JSON（cmd=3，record_state=0），对齐 iOS 端。
  Future<String> stopRecordAppJson() async {
    await stopRecord();
    return AppCodec.encode(AppCodec.record(recordState: 0));
  }

  /// 暂停录音并返回 app JSON（cmd=3，record_state=2）。
  Future<String> pauseRecordAppJson() async {
    await pauseRecord();
    return AppCodec.encode(AppCodec.record(recordState: 2));
  }

  /// 继续录音并返回 app JSON（cmd=3，record_state=1）。
  Future<String> continueRecordAppJson() async {
    await continueRecord();
    return AppCodec.encode(AppCodec.record(recordState: 1));
  }

  /// 获取文件列表并返回 app JSON（cmd=4）。
  Future<String> getRecordFileListAppJson() async =>
      AppCodec.encode(AppCodec.fileList(await getRecordFileList()));

  /// 删除全部录音文件并返回 app JSON（cmd=14，delete_state：0 成功/1 失败）。
  Future<String> delAllFileDataAppJson() async =>
      AppCodec.encode(AppCodec.deleteFile((await delAllFileData()) ? 0 : 1));

  /// 断开连接（对齐 iOS 端 `closeConnect`）并释放资源。
  Future<void> closeConnect() async {
    await _controller.dispose();
    await _transport.disconnect();
  }
}

/// 合并多条同类型流为一条广播流（避免引入 package:async）。
Stream<T> _mergeStreams<T>(List<Stream<T>> streams) {
  late StreamController<T> controller;
  final subs = <StreamSubscription<T>>[];
  controller = StreamController<T>.broadcast(
    onListen: () {
      for (final s in streams) {
        subs.add(s.listen(controller.add, onError: controller.addError));
      }
    },
    onCancel: () async {
      for (final sub in subs) {
        await sub.cancel();
      }
      subs.clear();
    },
  );
  return controller.stream;
}
