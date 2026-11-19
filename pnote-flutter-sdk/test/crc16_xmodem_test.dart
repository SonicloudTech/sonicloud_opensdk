import 'dart:typed_data';

import 'package:pnote_flutter_sdk/src/protocol/crc16_xmodem.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CRC-16/XMODEM', () {
    test('已知向量 "123456789" = 0x31C3', () {
      final data = '123456789'.codeUnits;
      expect(crc16Xmodem(data), 0x31C3);
    });

    test('空数据 = 0x0000', () {
      expect(crc16Xmodem(const []), 0x0000);
    });

    test('支持区间计算', () {
      final data = Uint8List.fromList([0xFF, ...'123456789'.codeUnits, 0xFF]);
      expect(crc16Xmodem(data, start: 1, end: data.length - 1), 0x31C3);
    });
  });
}
