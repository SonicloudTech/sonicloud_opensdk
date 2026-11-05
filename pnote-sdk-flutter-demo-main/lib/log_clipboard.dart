import 'package:flutter/services.dart';

class LogClipboard {
  // 保守的单次复制预算，并非所有设备统一的系统上限。
  static const maxBytes = 256 * 1024;

  static List<String> split(
    String text, {
    int maxBytes = LogClipboard.maxBytes,
  }) {
    if (maxBytes < 4) {
      throw ArgumentError.value(maxBytes, 'maxBytes', '至少容纳一个 Unicode 字符');
    }
    final parts = <String>[];
    var buffer = StringBuffer();
    var bytes = 0;
    for (final rune in text.runes) {
      final size = rune <= 0x7F
          ? 1
          : (rune <= 0x7FF ? 2 : (rune <= 0xFFFF ? 3 : 4));
      if (bytes + size > maxBytes) {
        parts.add(buffer.toString());
        buffer = StringBuffer();
        bytes = 0;
      }
      buffer.writeCharCode(rune);
      bytes += size;
    }
    if (buffer.isNotEmpty) parts.add(buffer.toString());
    return parts;
  }

  static Future<bool> copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    final copied = await Clipboard.getData(Clipboard.kTextPlain);
    return copied?.text == text;
  }
}
