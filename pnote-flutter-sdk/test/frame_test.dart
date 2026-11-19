import 'dart:typed_data';

import 'package:pnote_flutter_sdk/src/pen/commands.dart';
import 'package:pnote_flutter_sdk/src/pen/frame.dart';
import 'package:pnote_flutter_sdk/src/pen/frame_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Frame 编解码', () {
    test('encode/decode 往返', () {
      final encoded = FrameCodec.encodeCmd(
        DataType.control,
        ControlCmd.getBattery,
        7,
      );
      expect(encoded[0], kMagic);
      expect(encoded[1], 7); // seq

      final result = FrameCodec.decode(encoded);
      expect(result, isNotNull);
      expect(result!.frame.seq, 7);
      expect(result.frame.dataType, DataType.control);
      expect(result.frame.cmd, ControlCmd.getBattery);
      expect(result.frameLength, encoded.length);
    });

    test('带参数的数据体解析', () {
      final encoded = FrameCodec.encodeCmd(
        DataType.control,
        ControlCmd.syncTime,
        0,
        params: [0xE9, 0x07, 12, 31, 23, 59, 58],
      );
      final frame = FrameCodec.decode(encoded)!.frame;
      expect(frame.cmd, ControlCmd.syncTime);
      expect(frame.params, [0xE9, 0x07, 12, 31, 23, 59, 58]);
    });

    test('ACK 帧无 cmd', () {
      final ack = FrameCodec.ack(42);
      final frame = FrameCodec.decode(ack)!.frame;
      expect(frame.seq, 42);
      expect(frame.dataType, DataType.ack);
      expect(frame.payload, isEmpty);
      expect(frame.cmd, -1);
    });

    test('CRC 损坏时解码失败', () {
      final encoded = FrameCodec.encodeCmd(DataType.control, 4, 1);
      encoded[encoded.length - 1] ^= 0xFF; // 破坏数据
      expect(FrameCodec.decode(encoded), isNull);
    });

    test('CRC 字段为 0 时仍可解码（兼容老固件未填 CRC）', () {
      final encoded = FrameCodec.encodeCmd(DataType.control, 4, 1);
      encoded[2] = 0; // 清零 CRC 字段（小端 2B）
      encoded[3] = 0;
      final r = FrameCodec.decode(encoded); // verifyCrc 默认 true
      expect(r, isNotNull); // CRC=0 视为设备未填，跳过校验
    });

    test('魔数错误返回 null', () {
      final encoded = FrameCodec.encodeCmd(DataType.control, 4, 1);
      encoded[0] = 0x00;
      expect(FrameCodec.decode(encoded), isNull);
    });
  });

  group('FrameAssembler 流式拆包', () {
    test('粘包：一次喂入两帧', () {
      final f1 = FrameCodec.encodeCmd(DataType.control, ControlCmd.getBattery, 1);
      final f2 = FrameCodec.encodeCmd(DataType.file, FileCmd.getFileList, 2);
      final combined = Uint8List.fromList([...f1, ...f2]);

      final asm = FrameAssembler();
      final frames = asm.addBytes(combined);
      expect(frames.length, 2);
      expect(frames[0].cmd, ControlCmd.getBattery);
      expect(frames[1].cmd, FileCmd.getFileList);
    });

    test('分片：帧被拆成多段到达', () {
      final f = FrameCodec.encodeCmd(
        DataType.control,
        ControlCmd.getCapacity,
        3,
        params: List.filled(8, 0xAB),
      );
      final asm = FrameAssembler();
      // 先喂前 4 字节，不应产出
      expect(asm.addBytes(f.sublist(0, 4)), isEmpty);
      // 再喂剩余，应产出完整一帧
      final frames = asm.addBytes(f.sublist(4));
      expect(frames.length, 1);
      expect(frames[0].cmd, ControlCmd.getCapacity);
      expect(frames[0].params.length, 8);
    });

    test('丢弃前导噪声字节', () {
      final f = FrameCodec.encodeCmd(DataType.control, 4, 5);
      final noisy = Uint8List.fromList([0x00, 0x11, 0x22, ...f]);
      final asm = FrameAssembler();
      final frames = asm.addBytes(noisy);
      expect(frames.length, 1);
      expect(frames[0].seq, 5);
    });
  });
}
