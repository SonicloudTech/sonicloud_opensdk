import 'dart:io';
import 'dart:typed_data';

class AudioFileExporter {
  static const _oggSignature = 0x4f676753; // OggS

  static Future<bool> isSaved(File source) async {
    if (!await source.exists()) return false;
    final reader = await source.open();
    try {
      final length = await reader.length();
      final header = await reader.read(44);
      if (header.length < 44) return false;
      final bytes = ByteData.sublistView(header);
      if (source.path.endsWith('.wav')) {
        return length > 44 &&
            bytes.getUint32(0) == 0x52494646 && // RIFF
            bytes.getUint32(8) == 0x57415645 && // WAVE
            bytes.getUint32(36) == 0x64617461 && // data
            bytes.getUint32(40, Endian.little) == length - 44;
      }
      if (bytes.getUint32(0) != _oggSignature) return false;
      return await _hasOggEndPage(reader, length);
    } finally {
      await reader.close();
    }
  }

  static Future<bool> _hasOggEndPage(
    RandomAccessFile reader,
    int length,
  ) async {
    // Only the last page is needed to reject partial files from earlier demos.
    const pageHeaderSize = 27;
    const maxPageSize = pageHeaderSize + 255 + 255 * 255;
    final tailStart = length > maxPageSize ? length - maxPageSize : 0;
    await reader.setPosition(tailStart);
    final tail = await reader.read(length - tailStart);
    final bytes = ByteData.sublistView(tail);
    for (var offset = tail.length - pageHeaderSize; offset >= 0; offset--) {
      if (bytes.getUint32(offset) != _oggSignature) continue;
      final isEnd = tail[offset + 5] & 4 != 0;
      final samples = bytes.getInt64(offset + 6, Endian.little);
      final segmentStart = offset + pageHeaderSize;
      final bodyStart = segmentStart + tail[offset + 26];
      if (!isEnd || samples <= 0 || bodyStart >= tail.length) continue;

      var end = bodyStart;
      for (var index = segmentStart; index < bodyStart; index++) {
        end += tail[index];
      }
      if (end == tail.length) return true;
    }
    return false;
  }

}
