import 'dart:async';
import 'dart:typed_data';

import 'package:pnote_flutter_sdk/src/pen/frame.dart';
import 'package:pnote_flutter_sdk/src/transport/transport.dart';

/// 内存假传输：记录发出的帧，可注入设备回包。
///
/// 供 controller_test 与 ota_simulation_test 共用（BLE / TCP 各建一个实例）。
class FakeTransport implements Transport {
  final _incoming = StreamController<Uint8List>.broadcast();
  final _stateCtrl = StreamController<TransportState>.broadcast();
  final List<Uint8List> sent = [];

  @override
  TransportState state = TransportState.connected;

  @override
  bool debugLog = false;

  @override
  Stream<String> get debugLogStream => const Stream.empty();

  @override
  Stream<TransportState> get stateStream => _stateCtrl.stream;

  @override
  Stream<Uint8List> get incoming => _incoming.stream;

  @override
  Future<void> connect() async {}

  @override
  Future<void> send(Uint8List data) async => sent.add(data);

  /// 模拟设备发来一帧。
  void deviceSend(int dataType, int cmd, List<int> params) {
    _incoming.add(FrameCodec.encodeCmd(dataType, cmd, 0, params: params));
  }

  @override
  Future<void> disconnect() async {
    await _incoming.close();
    await _stateCtrl.close();
  }
}
