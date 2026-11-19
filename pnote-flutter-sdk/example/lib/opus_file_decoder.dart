import 'dart:io';
import 'dart:typed_data';

import 'package:opus_codec/opus_codec.dart' as opus_codec;
import 'package:opus_codec_dart/opus_codec_dart.dart';

/// opus 文件解码参数（硬件确认：16k / 单声道 / 20ms 帧）。
const _kSampleRate = 16000;
const _kChannels = 1;
const _kOpusFrameBytes = 40; // 16k/单声道/20ms → 每帧 40B

bool _opusInited = false;

/// 一次性初始化原生 opus 库（幂等）。
Future<void> _ensureOpus() async {
  if (_opusInited) return;
  initOpus(await opus_codec.load());
  _opusInited = true;
}

/// 把一个**裸 opus 流文件**（设备下载的，每帧 40B）解码成 PCM，并包成 WAV 文件。
///
/// 按 [_kOpusFrameBytes] 切分逐帧 decode（整包直接解码会得到杂音）。
/// 返回 WAV 文件路径。
Future<String> opusFileToWav(String opusPath, String wavPath) async {
  await _ensureOpus(); // 幂等初始化 libopus

  final bytes = await File(opusPath).readAsBytes();
  final decoder = SimpleOpusDecoder(
    sampleRate: _kSampleRate,
    channels: _kChannels,
  );

  final pcm = <int>[]; // 小端 16-bit PCM 字节
  for (var off = 0; off < bytes.length; off += _kOpusFrameBytes) {
    final end = off + _kOpusFrameBytes <= bytes.length
        ? off + _kOpusFrameBytes
        : bytes.length;
    final frame = Uint8List.sublistView(bytes, off, end);
    try {
      final samples = decoder.decode(input: frame);
      for (final s in samples) {
        pcm.add(s & 0xFF);
        pcm.add((s >> 8) & 0xFF);
      }
    } catch (_) {
      // 单帧解码失败跳过，不影响整体。
    }
  }
  decoder.destroy();

  // 写 WAV：44B 头 + PCM 数据。
  final dataLen = pcm.length;
  final totalLen = 36 + dataLen;
  final out = BytesBuilder();
  out.add(utf8Bytes('RIFF'));
  out.add(u32Le(totalLen));
  out.add(utf8Bytes('WAVE'));
  out.add(utf8Bytes('fmt '));
  out.add(u32Le(16)); // PCM fmt chunk size
  out.add(u16Le(1)); // PCM
  out.add(u16Le(_kChannels));
  out.add(u32Le(_kSampleRate));
  out.add(u32Le(_kSampleRate * _kChannels * 2)); // byte rate
  out.add(u16Le(_kChannels * 2)); // block align
  out.add(u16Le(16)); // bits per sample
  out.add(utf8Bytes('data'));
  out.add(u32Le(dataLen));
  out.add(pcm);

  final wavFile = File(wavPath);
  await wavFile.writeAsBytes(out.toBytes(), flush: true);
  return wavFile.path;
}

List<int> utf8Bytes(String s) => s.codeUnits;

List<int> u32Le(int v) => [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF];

List<int> u16Le(int v) => [v & 0xFF, (v >> 8) & 0xFF];
