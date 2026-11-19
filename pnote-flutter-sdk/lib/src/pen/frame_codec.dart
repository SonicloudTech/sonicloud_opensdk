/// 流式拆包：BLE notify 可能分片或粘包，本类维护缓冲区并切出完整帧。
library;

import 'dart:typed_data';

import 'frame.dart';

/// 累积字节并按帧边界产出 [Frame]。
class FrameAssembler {
  final BytesBuilder _buffer = BytesBuilder(copy: false);

  /// 是否校验 CRC（真机调试期可临时关闭以观察原始帧）。
  final bool verifyCrc;

  FrameAssembler({this.verifyCrc = true});

  /// 喂入一段新到达的字节，返回本次能完整解析出的所有帧。
  List<Frame> addBytes(List<int> chunk) {
    _buffer.add(chunk);
    return _drain();
  }

  List<Frame> _drain() {
    final frames = <Frame>[];
    var data = _buffer.toBytes();
    var offset = 0;

    while (offset < data.length) {
      // 丢弃魔数之前的噪声字节，重新对齐到 0x5A。
      if (data[offset] != kMagic) {
        offset++;
        continue;
      }
      final remaining = Uint8List.sublistView(data, offset);
      if (remaining.length < kHeaderLength) break; // 头还没收全

      final result = FrameCodec.decode(remaining, verifyCrc: verifyCrc);
      if (result == null) {
        // 长度字段显示的整帧还没到齐 → 等更多数据；
        // 但若已够长度却 CRC 失败，跳过这个魔数字节继续找。
        final declaredLen = _peekTotalLength(remaining);
        if (declaredLen != null && remaining.length >= declaredLen) {
          offset++; // CRC 不符，错位，前移一字节重试
          continue;
        }
        break; // 数据不足，保留等待下次
      }

      frames.add(result.frame);
      offset += result.frameLength;
    }

    // 把未消费的尾部留回缓冲区。
    final rest =
        offset < data.length ? Uint8List.sublistView(data, offset) : Uint8List(0);
    _buffer.clear();
    if (rest.isNotEmpty) _buffer.add(rest);
    return frames;
  }

  /// 读出帧头声明的总长度（用于判断是否该等待更多数据）。
  int? _peekTotalLength(Uint8List bytes) {
    if (bytes.length < kHeaderLength) return null;
    // 长度字段位于 offset 4，字节序与 FrameCodec 内部一致（小端默认）。
    final len = bytes[4] | (bytes[5] << 8);
    return kHeaderLength + len;
  }

  /// 清空缓冲（断开连接时调用）。
  void reset() => _buffer.clear();
}
