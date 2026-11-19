import 'dart:typed_data';

/// PCM(s16le) → WAV 文件字节（44 字节 RIFF 头 + 数据）。
Uint8List encodeWav(
  Uint8List pcm, {
  int sampleRate = 16000,
  int channels = 1,
}) {
  final dataLen = pcm.length;
  final header = ByteData(44);
  header.setUint32(0, 0x46464952, Endian.little); // 'RIFF'
  header.setUint32(4, 36 + dataLen, Endian.little);
  header.setUint32(8, 0x45564157, Endian.little); // 'WAVE'
  header.setUint32(12, 0x20746d66, Endian.little); // 'fmt '
  header.setUint32(16, 16, Endian.little); // fmt 块长度
  header.setUint16(20, 1, Endian.little); // PCM
  header.setUint16(22, channels, Endian.little);
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, sampleRate * channels * 2, Endian.little); // 字节率
  header.setUint16(32, channels * 2, Endian.little); // 块对齐
  header.setUint16(34, 16, Endian.little); // 位深
  header.setUint32(36, 0x61746164, Endian.little); // 'data'
  header.setUint32(40, dataLen, Endian.little);
  return Uint8List.fromList(
      [header.buffer.asUint8List(), pcm].expand((x) => x).toList());
}
