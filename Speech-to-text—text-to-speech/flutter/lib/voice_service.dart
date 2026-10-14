/// Cross-platform contract for the project's offline ASR/TTS capability.
///
/// Platform implementations can use a native sherpa-onnx binding or call the
/// project's local service. BLE transport remains independent from this API.
abstract class VoiceService {
  Future<void> prepareModels({String? language});

  Future<VoiceCapabilities> capabilities();

  Future<TranscriptResult> transcribe(
    String audioPath, {
    String language = 'auto',
  });

  Future<SynthesisResult> synthesize(
    String text, {
    String language = 'zh',
    String voice = 'default',
    double speed = 1.0,
  });
}

class VoiceCapabilities {
  const VoiceCapabilities({
    required this.backend,
    required this.asrAvailable,
    required this.asrLanguages,
    required this.ttsAvailable,
    required this.ttsLanguages,
  });

  final String backend;
  final bool asrAvailable;
  final List<String> asrLanguages;
  final bool ttsAvailable;
  final List<String> ttsLanguages;
}

class TranscriptResult {
  const TranscriptResult({
    required this.text,
    required this.language,
    required this.model,
    required this.segments,
  });

  final String text;
  final String language;
  final String model;
  final List<TranscriptSegment> segments;
}

class TranscriptSegment {
  const TranscriptSegment({
    required this.start,
    required this.end,
    required this.text,
  });

  final double start;
  final double end;
  final String text;
}

class SynthesisResult {
  const SynthesisResult({
    required this.path,
    required this.sampleRate,
    required this.duration,
    required this.model,
    required this.voice,
  });

  final String path;
  final int sampleRate;
  final double duration;
  final String model;
  final String voice;
}
