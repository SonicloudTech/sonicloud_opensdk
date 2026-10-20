import 'dart:io';
import 'dart:typed_data';

class WavWriter {
  static Future<void> writeWavFile({
    required String filePath,
    required File pcmFile,
    int sampleRate = 16000,
    int channels = 1,
  }) async {
    final byteRate = sampleRate * channels * 2; // 16bit = 2字节
    final blockAlign = channels * 2;
    final subchunk2Size = await pcmFile.length();
    final chunkSize = 36 + subchunk2Size;

    final header = BytesBuilder();

    // ---- RIFF chunk ----
    header.add(ascii('RIFF'));
    header.add(_uint32LE(chunkSize));
    header.add(ascii('WAVE'));

    // ---- fmt subchunk ----
    header.add(ascii('fmt '));
    header.add(_uint32LE(16)); // Subchunk1Size
    header.add(_uint16LE(1));  // PCM format
    header.add(_uint16LE(channels));
    header.add(_uint32LE(sampleRate));
    header.add(_uint32LE(byteRate));
    header.add(_uint16LE(blockAlign));
    header.add(_uint16LE(16)); // Bits per sample

    // ---- data subchunk ----
    header.add(ascii('data'));
    header.add(_uint32LE(subchunk2Size));

    // ---- write to file ----
    final wavFile = File(filePath);
    final sink = wavFile.openWrite();
    try {
      sink.add(header.toBytes());
      await sink.addStream(pcmFile.openRead());
      await sink.flush();
    } finally {
      await sink.close();
    }
  }

  static List<int> ascii(String s) => s.codeUnits;

  static List<int> _uint16LE(int value) => [value & 0xFF, (value >> 8) & 0xFF];

  static List<int> _uint32LE(int value) => [
    value & 0xFF,
    (value >> 8) & 0xFF,
    (value >> 16) & 0xFF,
    (value >> 24) & 0xFF,
  ];
}
///
/// @author 杰森明
/// @fileName wave_write.dart
/// @date 2025/8/4 11:53
/// @description [在此处添加文件描述]
///
