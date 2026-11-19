import 'dart:typed_data';

import 'package:pnote_flutter_sdk/src/pen/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BatteryInfo', () {
    test('普通电量', () {
      final b = BatteryInfo.parse(Uint8List.fromList([85]));
      expect(b.percent, 85);
      expect(b.charging, false);
    });

    test('110 表示充电中', () {
      final b = BatteryInfo.parse(Uint8List.fromList([110]));
      expect(b.charging, true);
    });
  });

  group('Capacity', () {
    test('小端解析剩余/总量', () {
      // 剩余 = 0x00000100 = 256KB，总量 = 0x00010000 = 65536KB
      final params = Uint8List.fromList([
        0x00, 0x01, 0x00, 0x00, // free LE = 256
        0x00, 0x00, 0x01, 0x00, // total LE = 65536
      ]);
      final c = Capacity.parse(params);
      expect(c.freeKb, 256);
      expect(c.totalKb, 65536);
      expect(c.usedKb, 65536 - 256);
    });
  });

  group('encodeSyncTime', () {
    test('年小端，其余各 1 字节', () {
      final payload = encodeSyncTime(DateTime(2025, 12, 31, 23, 59, 58));
      expect(payload.length, 7);
      expect(payload[0], 2025 & 0xFF); // 年低字节
      expect(payload[1], (2025 >> 8) & 0xFF); // 年高字节
      expect(payload[2], 12);
      expect(payload[3], 31);
      expect(payload[4], 23);
      expect(payload[5], 59);
      expect(payload[6], 58);
    });
  });

  group('FileList', () {
    // 真机抓包校准（2026-07-03）：设备实发帧的 params，含 2 个文件。
    // file0: time=46 size=92960 name=" note 2070-00-00_00-02-08."
    // file1: time=10529 size=21058960 name="call 2028-01-27_34-01-44."
    test('真机帧：大端 + 变长名字', () {
      final params = Uint8List.fromList([
        0x00, 0x00, 0x00, 0x02, // count=2 (大端)
        // file0: time=46(BE) size=92960(BE) name
        0x00, 0x00, 0x00, 0x2E, // time=46
        0x00, 0x01, 0x6B, 0x20, // size=92960
        ...' note 2070-00-00_00-02-08.'.codeUnits,
        // file1: time=10529(BE) size=21058960(BE) name（名字以'.'结尾，无填充0）
        0x00, 0x00, 0x29, 0x21, // time=10529
        0x01, 0x41, 0x55, 0x90, // size=21058960
        ...'call 2028-01-27_34-01-44.'.codeUnits,
      ]);
      final files = FileList.parse(params);
      expect(files.length, 2);
      expect(files[0].durationSec, 46);
      expect(files[0].sizeBytes, 92960);
      expect(files[0].name, 'note 2070-00-00_00-02-08.opus');
      expect(files[0].isCall, false);
      expect(files[1].durationSec, 10529);
      expect(files[1].sizeBytes, 21058960);
      expect(files[1].name, 'call 2028-01-27_34-01-44.opus');
      expect(files[1].isCall, true);
    });

    test('个数为 0 返回空', () {
      final params = Uint8List.fromList([0, 0, 0, 0]);
      expect(FileList.parse(params), isEmpty);
    });

    // 老固件（真机抓包 2026-07-03）：文件名无空格格式 note20251020-104111.
    // 字段布局与新固件一致，仅名字字符串格式不同——解析应同样兼容。
    test('老固件帧：大端 + 无空格名字格式', () {
      // file0: time=2 size=5360 name="note20251020-104111."
      // file1: time=1023 size=2046440 name="note20251024-103505."
      final params = Uint8List.fromList([
        0x00, 0x00, 0x00, 0x02, // count=2 (大端)
        // file0: time=2 size=5360
        0x00, 0x00, 0x00, 0x02, // time=2
        0x00, 0x00, 0x14, 0xF0, // size=5360
        ...'note20251020-104111.'.codeUnits,
        // file1: time=1023 size=2046440（名字以'.'结尾，无填充0）
        0x00, 0x00, 0x03, 0xFF, // time=1023
        0x00, 0x1F, 0x39, 0xE8, // size=2046440
        ...'note20251024-103505.'.codeUnits,
      ]);
      final files = FileList.parse(params);
      expect(files.length, 2);
      expect(files[0].durationSec, 2);
      expect(files[0].sizeBytes, 5360);
      expect(files[0].name, 'note20251020-104111.opus');
      expect(files[1].durationSec, 1023);
      expect(files[1].sizeBytes, 2046440);
      expect(files[1].name, 'note20251024-103505.opus');
    });

    test('截断的数据不会越界', () {
      final params = Uint8List.fromList([0, 0, 0, 0x05, 1, 2, 3]);
      expect(FileList.parse(params), isEmpty);
    });
  });

  group('DeviceMode', () {
    test('位掩码解析', () {
      final m = DeviceMode.parse(Uint8List.fromList([0x02])); // bit1 录音
      expect(m.recording, true);
      expect(m.playing, false);
    });
  });
}
