import 'dart:typed_data';

import 'package:opus_codec/opus_codec.dart' as opus_codec;
import 'package:opus_codec_dart/opus_codec_dart.dart';

/// libopus 是否已初始化（进程内一次）。
bool _opusInited = false;

/// 一次性初始化原生 opus 库（幂等）。未初始化直接建解码器会抛
/// LateInitializationError: Field 'opus' has not been initialized。
Future<void> ensureOpusInitialized() async {
  if (_opusInited) return;
  initOpus(await opus_codec.load());
  _opusInited = true;
}

/// 录音笔固件音频参数：20ms/帧、40B/帧、16kbps、s16le/16k/单声道。
const int kOpusFrameSize = 40;
const int kOpusSampleRate = 16000;
const int kOpusChannels = 1;

/// 创建一个录音笔参数的解码器（用完必须 destroy）。
SimpleOpusDecoder createPenDecoder() =>
    SimpleOpusDecoder(sampleRate: kOpusSampleRate, channels: kOpusChannels);

/// 单帧 opus → PCM 字节（s16le 小端）；坏帧返回 null。
Uint8List? decodePenFrame(SimpleOpusDecoder decoder, Uint8List frame) {
  try {
    final samples = decoder.decode(input: frame);
    return samples.buffer
        .asUint8List(samples.offsetInBytes, samples.lengthInBytes);
  } catch (_) {
    return null;
  }
}
