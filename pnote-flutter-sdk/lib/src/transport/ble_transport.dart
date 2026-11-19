/// 基于 flutter_blue_plus 的 BLE 传输实现（按 [BleTransportProfile] 配置特征集）。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../pen/commands.dart';
import 'transport.dart';

/// 把字节转为 hex 字符串便于调试，如 "5A 00 12 34 ..."。
String bytesToHex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');

/// BLE 传输配置：服务/特征 UUID。
class BleTransportProfile {
  const BleTransportProfile({
    required this.serviceUuid,
    required this.writeUuid,
    this.notifyUuids = const [],
  });

  /// 主服务 UUID（服务发现时定位）。
  final String serviceUuid;

  /// 写特征 UUID。
  final String writeUuid;

  /// 需订阅的 notify/indicate 特征（回包全部汇入统一 incoming 流）。
  final List<String> notifyUuids;

  /// 声云录音笔：0xAE20 服务，ae21 写 / ae22+ae23 订阅。
  static const BleTransportProfile pen = BleTransportProfile(
    serviceUuid: BleUuids.service,
    writeUuid: BleUuids.write,
    notifyUuids: [BleUuids.notify, BleUuids.keyNotify],
  );
}

/// 用 BLE GATT 收发字节。
///
/// - 写：[BleTransportProfile.writeUuid]；
/// - 收：订阅 [BleTransportProfile.notifyUuids]。
class BleTransport implements Transport {
  BleTransport(this.device, {this.debugLog = true, this.profile = BleTransportProfile.pen});

  /// 目标设备（由扫描结果得到）。
  final BluetoothDevice device;

  /// 传输配置（协议特征集），默认声云录音笔。
  final BleTransportProfile profile;

  /// 是否在控制台打印收发的原始字节（真机校准帧协议时用）。运行时可切换。
  @override
  bool debugLog;

  final _incomingCtrl = StreamController<Uint8List>.broadcast();
  final _stateCtrl = StreamController<TransportState>.broadcast();
  final _debugCtrl = StreamController<String>.broadcast();

  TransportState _state = TransportState.disconnected;
  BluetoothCharacteristic? _writeChar;
  final List<StreamSubscription> _subs = [];
  StreamSubscription<BluetoothConnectionState>? _connSub;

  @override
  TransportState get state => _state;

  @override
  Stream<TransportState> get stateStream => _stateCtrl.stream;

  @override
  Stream<Uint8List> get incoming => _incomingCtrl.stream;

  @override
  Stream<String> get debugLogStream => _debugCtrl.stream;

  /// 打印一条调试日志：同时输出到控制台和 [debugLogStream]（供 UI 显示）。
  void _debug(String msg) {
    debugPrint(msg);
    if (!_debugCtrl.isClosed) _debugCtrl.add(msg);
  }

  void _setState(TransportState s) {
    if (_state == s) return;
    _state = s;
    if (!_stateCtrl.isClosed) _stateCtrl.add(s);
  }

  @override
  Future<void> connect() async {
    _setState(TransportState.connecting);

    _connSub = device.connectionState.listen((s) {
      if (s == BluetoothConnectionState.disconnected) {
        _setState(TransportState.disconnected);
      }
    });

    await device.connect(timeout: const Duration(seconds: 15));

    // 提升 MTU 以减少长回包的分片数（Android 生效；iOS 忽略）。
    try {
      await device.requestMtu(247);
    } catch (_) {
      // 部分平台/设备不支持，忽略即可。
    }

    final services = await device.discoverServices();

    if (debugLog) {
      _logServices(services);
    }

    final service = services.firstWhere(
      (s) => _matchUuid(s.uuid, profile.serviceUuid),
      orElse: () => throw StateError(
          '未发现 0x${_short(profile.serviceUuid).toUpperCase()} 服务，可能不是目标设备'),
    );

    for (final c in service.characteristics) {
      if (_matchUuid(c.uuid, profile.writeUuid)) {
        _writeChar = c;
        continue;
      }
      final notify =
          profile.notifyUuids.where((u) => _matchUuid(c.uuid, u)).firstOrNull;
      if (notify != null) {
        await _subscribeChar(c, '${_short(notify)}(设备→APP)');
      }
    }

    if (_writeChar == null) {
      throw StateError('未发现写特征 0x${_short(profile.writeUuid).toUpperCase()}');
    }

    _setState(TransportState.connected);
  }

  /// 订阅某特征的 notify/indicate，把回包送入统一入站流 [incoming]。
  Future<void> _subscribeChar(BluetoothCharacteristic c, String tag) async {
    await c.setNotifyValue(true);
    final sub = c.onValueReceived.listen((value) {
      if (value.isEmpty) return;
      if (debugLog) {
        _debug('[$tag] ${bytesToHex(value)}  (${value.length}B)');
      }
      if (!_incomingCtrl.isClosed) {
        _incomingCtrl.add(Uint8List.fromList(value));
      }
    });
    _subs.add(sub);
  }

  @override
  Future<void> send(Uint8List data) async {
    if (_state != TransportState.connected) {
      throw StateError('未连接，无法发送');
    }
    final c = _writeChar;
    if (c == null) {
      throw StateError('未发现写特征 0x${_short(profile.writeUuid).toUpperCase()}');
    }
    if (debugLog) {
      _debug('[${_short(profile.writeUuid)}(APP→设备)] ${bytesToHex(data)}  (${data.length}B)');
    }
    // 写模式按特征属性选择（WRITE_NR 通常是可选项，与 WRITE 一致处理）。
    final withoutResponse = c.properties.writeWithoutResponse;
    final mtu = device.mtuNow;
    final chunkSize = (mtu - 3).clamp(20, 512).toInt();
    if (data.length <= chunkSize) {
      await c.write(data, withoutResponse: withoutResponse);
      return;
    }
    for (var offset = 0; offset < data.length; offset += chunkSize) {
      final end =
          (offset + chunkSize < data.length) ? offset + chunkSize : data.length;
      await c.write(
        Uint8List.sublistView(data, offset, end),
        withoutResponse: withoutResponse,
      );
    }
  }

  @override
  Future<void> disconnect() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    await _connSub?.cancel();
    _connSub = null;
    try {
      await device.disconnect();
    } catch (_) {}
    _setState(TransportState.disconnected);
    await _incomingCtrl.close();
    await _stateCtrl.close();
    await _debugCtrl.close();
  }

  /// 打印连接后发现的所有服务与特征（UUID + 属性）。
  void _logServices(List<BluetoothService> services) {
    final buf = StringBuffer()
      ..writeln('───── 发现 GATT 服务 (${services.length} 个) ─────');
    for (final s in services) {
      buf.writeln('  Service 0x${s.uuid.str}');
      for (final c in s.characteristics) {
        final p = c.properties;
        final props = <String>[
          if (p.read) 'READ',
          if (p.write) 'WRITE',
          if (p.writeWithoutResponse) 'WRITE_NR',
          if (p.notify) 'NOTIFY',
          if (p.indicate) 'INDICATE',
        ].join('|');
        buf.writeln('      Char 0x${c.uuid.str}  [$props]');
      }
    }
    _debug('[GATT-服务发现] $buf');
  }

  /// UUID 简写：0000ae20-0000-1000-8000-00805f9b34fb → ae20。
  static String _short(String full) => full.substring(4, 8);

  /// 比较两个 UUID 是否相同（兼容 16-bit 短形式与 128-bit 全形式）。
  static bool _matchUuid(Guid a, String full) {
    final as_ = a.str.toLowerCase();
    final fl = full.toLowerCase();
    if (as_ == fl) return true;
    // flutter_blue_plus 可能返回短 UUID（如 "ae20"）。
    final short = fl.substring(4, 8); // 0000aeXX-.... → aeXX
    return as_ == short;
  }
}
