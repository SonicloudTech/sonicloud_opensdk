import 'package:flutter/services.dart';

import 'voice_service.dart';

/// Mobile implementation boundary. The native side owns Sherpa-ONNX and the
/// model files; Flutter only passes paths, text, and typed result metadata.
class MethodChannelVoiceService implements VoiceService {
  MethodChannelVoiceService({String channelName = 'com.sonicloud.voice'})
      : _channel = MethodChannel(channelName);

  final MethodChannel _channel;

  @override
  Future<void> prepareModels({String? language}) async {
    await _channel.invokeMethod<void>('prepareModels', {
      if (language != null) 'language': language,
    });
  }

  @override
  Future<VoiceCapabilities> capabilities() async {
    final result = Map<Object?, Object?>.from(
      await _channel.invokeMethod<Map<Object?, Object?>>('capabilities') ?? {},
    );
    final asr = _map(result['asr']);
    final tts = _map(result['tts']);
    return VoiceCapabilities(
      backend: result['backend']?.toString() ?? 'sherpa-onnx',
      asrAvailable: asr['available'] == true,
      asrLanguages: _strings(asr['languages']),
      ttsAvailable: tts['available'] == true,
      ttsLanguages: _strings(tts['languages']),
    );
  }

  @override
  Future<TranscriptResult> transcribe(String audioPath, {String language = 'auto'}) async {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>('transcribe', {
      'path': audioPath,
      'language': language,
    });
    final result = Map<Object?, Object?>.from(raw ?? {});
    return TranscriptResult(
      text: result['text']?.toString() ?? '',
      language: result['language']?.toString() ?? language,
      model: result['model']?.toString() ?? '',
      segments: _segments(result['segments']),
    );
  }

  @override
  Future<SynthesisResult> synthesize(String text, {String language = 'zh', String voice = 'default', double speed = 1.0}) async {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>('synthesize', {
      'text': text,
      'language': language,
      'voice': voice,
      'speed': speed,
    });
    final result = Map<Object?, Object?>.from(raw ?? {});
    return SynthesisResult(
      path: result['path']?.toString() ?? '',
      sampleRate: (result['sampleRate'] as num?)?.toInt() ?? 0,
      duration: (result['duration'] as num?)?.toDouble() ?? 0,
      model: result['model']?.toString() ?? '',
      voice: result['voice']?.toString() ?? voice,
    );
  }

  static Map<Object?, Object?> _map(Object? value) => value is Map ? Map<Object?, Object?>.from(value) : {};
  static List<String> _strings(Object? value) => value is List ? value.map((item) => item.toString()).toList() : const [];
  static List<TranscriptSegment> _segments(Object? value) => value is List
      ? value.map((item) {
          final map = _map(item);
          return TranscriptSegment(start: (map['start'] as num?)?.toDouble() ?? 0, end: (map['end'] as num?)?.toDouble() ?? 0, text: map['text']?.toString() ?? '');
        }).toList()
      : const [];
}
