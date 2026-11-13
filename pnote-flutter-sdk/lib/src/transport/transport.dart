/// 传输层抽象：屏蔽 BLE / WiFi(TCP) 差异。
///
/// 核心层（帧/CRC/指令）只依赖本接口，后续加 WiFi 传输只需新增一个实现。
library;

import 'dart:typed_data';

/// 传输连接状态。
enum TransportState { disconnected, connecting, connected }

/// 字节收发通道抽象。
abstract class Transport {
  /// 当前状态。
  TransportState get state;

  /// 是否打印收发的原始字节（调试用，运行时可切换）。
  abstract bool debugLog;

  /// 调试日志行流（与 `debugPrint` 同源：原始字节、GATT 发现等）。
  /// 仅在 [debugLog] 为 true 时产出，便于上层把日志显示在 UI 控制台。
  Stream<String> get debugLogStream;

  /// 状态变化流。
  Stream<TransportState> get stateStream;

  /// 收到的原始字节流（未拆帧）。
  Stream<Uint8List> get incoming;

  /// 建立连接（扫描/连接由具体实现或调用方完成，本方法负责打通收发通道）。
  Future<void> connect();

  /// 发送原始字节（已是完整帧）。
  Future<void> send(Uint8List data);

  /// 断开并释放资源。
  Future<void> disconnect();
}
