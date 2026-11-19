/// 帧的编码与解码。
///
/// 帧格式：`魔数(0x5A,1B) | 包序号(1B) | CRC16(2B) | 数据长度(2B) | 数据(nB)`
/// - CRC 对「数据长度(2B) + 数据」参与计算（CRC-16/XMODEM）。
/// - 收到设备包后需回 ACK：数据类型=3，包序号与收到的相同。
library;

import 'dart:typed_data';

import 'commands.dart';
import '../protocol/crc16_xmodem.dart';

/// 帧起始魔数。
const int kMagic = 0x5A;

/// 帧头固定长度：魔数 + 包序号 + CRC(2) + 长度(2) = 6 字节。
const int kHeaderLength = 6;

/// CRC 字段字节序：真机校准结论为**小端**（设备回包 CRC 算出 0x890c，
/// 帧内存放为 `0c 89`，低字节在前）。
const bool _crcBigEndian = false;

/// 长度字段字节序：小端（真机校准：len=3 存放为 `03 00`）。
const bool _lenBigEndian = false;

/// 一个已解析的帧。
class Frame {
  Frame({required this.seq, required this.dataType, required this.payload});

  /// 包序号（0..255 循环）。
  final int seq;

  /// 数据体首字节：数据类型（[DataType]）。
  final int dataType;

  /// 数据体（含 dataType 之后的全部字节，即 `cmd | 参数...`，
  /// ACK 帧此处为空）。
  final Uint8List payload;

  /// 数据体内的命令字（payload 的第 0 字节）；ACK 帧无 cmd 返回 -1。
  int get cmd => payload.isEmpty ? -1 : payload[0];

  /// cmd 之后的参数部分。
  Uint8List get params =>
      payload.length > 1 ? Uint8List.sublistView(payload, 1) : Uint8List(0);

  @override
  String toString() =>
      'Frame(seq=$seq, type=$dataType, cmd=$cmd, params=${params.length}B)';
}

/// 帧编解码工具。
class FrameCodec {
  FrameCodec._();

  /// 编码一帧。
  ///
  /// [dataType] 数据类型；[body] 为「cmd | 参数...」的数据体内容；
  /// [seq] 包序号。
  static Uint8List encode(int dataType, List<int> body, int seq) {
    // 数据 = 数据类型(1B) + body
    final data = Uint8List(1 + body.length);
    data[0] = dataType & 0xFF;
    data.setRange(1, data.length, body);

    final dataLen = data.length;
    // CRC 输入 = 长度(2B) + 数据
    final crcInput = Uint8List(2 + dataLen);
    _writeUint16(crcInput, 0, dataLen, _lenBigEndian);
    crcInput.setRange(2, crcInput.length, data);
    final crc = crc16Xmodem(crcInput);

    final frame = Uint8List(kHeaderLength + dataLen);
    frame[0] = kMagic;
    frame[1] = seq & 0xFF;
    _writeUint16(frame, 2, crc, _crcBigEndian);
    _writeUint16(frame, 4, dataLen, _lenBigEndian);
    frame.setRange(kHeaderLength, frame.length, data);
    return frame;
  }

  /// 便捷编码：数据类型 + cmd + 参数。
  static Uint8List encodeCmd(
    int dataType,
    int cmd,
    int seq, {
    List<int> params = const [],
  }) {
    return encode(dataType, [cmd & 0xFF, ...params], seq);
  }

  /// 构造一个 ACK 帧（数据类型=3，数据体仅类型字节，无 cmd）。
  static Uint8List ack(int seq) => encode(DataType.ack, const [], seq);

  /// 解码单帧（[bytes] 必须正好是一帧或以一帧起始）。
  ///
  /// 返回解析结果与该帧总长度；魔数/CRC/长度任一不符返回 null。
  static FrameDecodeResult? decode(Uint8List bytes, {bool verifyCrc = true}) {
    if (bytes.length < kHeaderLength) return null;
    if (bytes[0] != kMagic) return null;

    final seq = bytes[1];
    final crc = _readUint16(bytes, 2, _crcBigEndian);
    final dataLen = _readUint16(bytes, 4, _lenBigEndian);
    final total = kHeaderLength + dataLen;
    if (bytes.length < total) return null;

    final data = Uint8List.sublistView(bytes, kHeaderLength, total);

    if (verifyCrc && crc != 0) {
      // 仅当设备填写了 CRC（非 0）才校验。部分老固件帧的 CRC 字段恒为 0
      // （未计算），此时跳过校验以免误判为损坏帧而丢弃。
      final crcInput = Uint8List(2 + dataLen);
      _writeUint16(crcInput, 0, dataLen, _lenBigEndian);
      crcInput.setRange(2, crcInput.length, data);
      if (crc16Xmodem(crcInput) != crc) return null;
    }

    final dataType = dataLen > 0 ? data[0] : -1;
    final payload =
        dataLen > 1 ? Uint8List.sublistView(data, 1) : Uint8List(0);

    return FrameDecodeResult(
      frame: Frame(seq: seq, dataType: dataType, payload: payload),
      frameLength: total,
    );
  }

  static void _writeUint16(Uint8List buf, int offset, int value, bool bigEndian) {
    if (bigEndian) {
      buf[offset] = (value >> 8) & 0xFF;
      buf[offset + 1] = value & 0xFF;
    } else {
      buf[offset] = value & 0xFF;
      buf[offset + 1] = (value >> 8) & 0xFF;
    }
  }

  static int _readUint16(Uint8List buf, int offset, bool bigEndian) {
    return bigEndian
        ? (buf[offset] << 8) | buf[offset + 1]
        : buf[offset] | (buf[offset + 1] << 8);
  }
}

/// [FrameCodec.decode] 的返回值。
class FrameDecodeResult {
  FrameDecodeResult({required this.frame, required this.frameLength});

  final Frame frame;

  /// 该帧在原始字节流中占用的总长度（用于流式拆包推进游标）。
  final int frameLength;
}
