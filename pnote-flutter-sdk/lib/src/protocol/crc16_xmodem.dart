/// CRC-16/XMODEM 实现。
///
/// 参数（标准 CRC-16/XMODEM）：
/// - 多项式 poly = 0x1021
/// - 初始值 init  = 0x0000
/// - 输入/输出不反转，结果不异或
///
/// 协议规定：CRC 对「数据长度(2B) + 数据」参与计算。
library;

import 'dart:typed_data';

/// 预计算的 CRC 表，加速逐字节计算。
final Uint16List _table = _buildTable();

Uint16List _buildTable() {
  final table = Uint16List(256);
  for (var i = 0; i < 256; i++) {
    var crc = i << 8;
    for (var bit = 0; bit < 8; bit++) {
      if ((crc & 0x8000) != 0) {
        crc = (crc << 1) ^ 0x1021;
      } else {
        crc = crc << 1;
      }
      crc &= 0xFFFF;
    }
    table[i] = crc;
  }
  return table;
}

/// 计算 [data]（可选区间 [start, end)）的 CRC-16/XMODEM 值。
int crc16Xmodem(List<int> data, {int start = 0, int? end}) {
  end ??= data.length;
  var crc = 0x0000;
  for (var i = start; i < end; i++) {
    final index = ((crc >> 8) ^ data[i]) & 0xFF;
    crc = ((crc << 8) ^ _table[index]) & 0xFFFF;
  }
  return crc;
}
