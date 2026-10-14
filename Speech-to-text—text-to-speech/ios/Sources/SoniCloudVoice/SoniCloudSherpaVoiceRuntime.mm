#import "SoniCloudSherpaVoiceRuntime.h"

#include <cmath>
#include <cstring>
#include <string>

#include "sherpa-onnx/c-api/c-api.h"

namespace {
NSString *const kRuntimeErrorDomain = @"SoniCloudSherpaVoiceRuntime";

NSError *RuntimeError(NSInteger code, NSString *message) {
  return [NSError errorWithDomain:kRuntimeErrorDomain
                              code:code
                          userInfo:@{NSLocalizedDescriptionKey: message}];
}

std::string Path(NSString *root, NSString *child) {
  return [[root stringByAppendingPathComponent:child] UTF8String];
}

bool FileExists(NSString *path) {
  return [[NSFileManager defaultManager] fileExistsAtPath:path];
}
}

@implementation SoniCloudSherpaVoiceRuntime {
  NSString *_modelRoot;
}

- (instancetype)initWithModelRoot:(NSString *)modelRoot {
  self = [super init];
  if (self) {
    _modelRoot = [modelRoot copy];
  }
  return self;
}

- (NSString *)asrRoot {
  return [_modelRoot stringByAppendingPathComponent:@"sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2025-09-09"];
}

- (NSString *)ttsRoot {
  return [_modelRoot stringByAppendingPathComponent:@"kokoro-int8-multi-lang-v1_0"];
}

- (BOOL)asrReady {
  NSString *root = [self asrRoot];
  return FileExists([root stringByAppendingPathComponent:@"model.int8.onnx"]) &&
         FileExists([root stringByAppendingPathComponent:@"tokens.txt"]);
}

- (BOOL)ttsReady {
  NSString *root = [self ttsRoot];
  return FileExists([root stringByAppendingPathComponent:@"model.onnx"]) &&
         FileExists([root stringByAppendingPathComponent:@"voices.bin"]) &&
         FileExists([root stringByAppendingPathComponent:@"tokens.txt"]);
}

- (NSDictionary<NSString *, id> *)capabilities {
  return @{
    @"backend": @"sherpa-onnx-c-api",
    @"asr": @{
      @"available": @([self asrReady]),
      @"languages": @[ @"auto", @"zh", @"en", @"yue", @"ja", @"ko" ]
    },
    @"tts": @{
      @"available": @([self ttsReady]),
      @"languages": @[ @"zh", @"en" ]
    }
  };
}

- (BOOL)prepareModelsWithLanguage:(NSString *)language error:(NSError **)error {
  if (![self asrReady] && ![self ttsReady]) {
    if (error) *error = RuntimeError(2, [NSString stringWithFormat:@"Voice models are not installed under %@", _modelRoot]);
    return NO;
  }
  return YES;
}

- (NSDictionary<NSString *, id> *)transcribeWithPath:(NSString *)path
                                              language:(NSString *)language
                                                 error:(NSError **)error {
  if (![self asrReady]) {
    if (error) *error = RuntimeError(3, [NSString stringWithFormat:@"ASR model is not installed under %@", [self asrRoot]]);
    return nil;
  }

  std::string model = Path([self asrRoot], @"model.int8.onnx");
  std::string tokens = Path([self asrRoot], @"tokens.txt");
  std::string input = [path UTF8String];
  std::string lang = [language UTF8String];

  SherpaOnnxOfflineRecognizerConfig config;
  std::memset(&config, 0, sizeof(config));
  config.feat_config.sample_rate = 16000;
  config.feat_config.feature_dim = 80;
  config.model_config.tokens = tokens.c_str();
  config.model_config.num_threads = 2;
  config.model_config.provider = "cpu";
  config.model_config.sense_voice.model = model.c_str();
  config.model_config.sense_voice.language = lang.c_str();
  config.model_config.sense_voice.use_itn = 1;
  config.decoding_method = "greedy_search";

  const SherpaOnnxOfflineRecognizer *recognizer = SherpaOnnxCreateOfflineRecognizer(&config);
  if (!recognizer) {
    if (error) *error = RuntimeError(4, @"Unable to create Sherpa-ONNX ASR recognizer");
    return nil;
  }
  const SherpaOnnxWave *wave = SherpaOnnxReadWave(input.c_str());
  if (!wave) {
    SherpaOnnxDestroyOfflineRecognizer(recognizer);
    if (error) *error = RuntimeError(5, [NSString stringWithFormat:@"Unable to read WAV file: %@", path]);
    return nil;
  }
  if (wave->sample_rate != 16000) {
    SherpaOnnxFreeWave(wave);
    SherpaOnnxDestroyOfflineRecognizer(recognizer);
    if (error) *error = RuntimeError(6, @"ASR requires a 16 kHz WAV file");
    return nil;
  }

  const SherpaOnnxOfflineStream *stream = SherpaOnnxCreateOfflineStream(recognizer);
  if (!stream) {
    SherpaOnnxFreeWave(wave);
    SherpaOnnxDestroyOfflineRecognizer(recognizer);
    if (error) *error = RuntimeError(14, @"Unable to create Sherpa-ONNX ASR stream");
    return nil;
  }
  SherpaOnnxAcceptWaveformOffline(stream, wave->sample_rate, wave->samples, wave->num_samples);
  SherpaOnnxDecodeOfflineStream(recognizer, stream);
  const SherpaOnnxOfflineRecognizerResult *result = SherpaOnnxGetOfflineStreamResult(stream);
  NSString *text = result && result->text ? [NSString stringWithUTF8String:result->text] : @"";
  NSString *resultLanguage = result && result->lang ? [NSString stringWithUTF8String:result->lang] : language;
  if (result) SherpaOnnxDestroyOfflineRecognizerResult(result);
  SherpaOnnxDestroyOfflineStream(stream);
  SherpaOnnxFreeWave(wave);
  SherpaOnnxDestroyOfflineRecognizer(recognizer);

  return @{
    @"text": text,
    @"language": resultLanguage.length ? resultLanguage : language,
    @"model": @"sensevoice-2025-09-09",
    @"segments": @[]
  };
}

- (NSDictionary<NSString *, id> *)synthesizeWithText:(NSString *)text
                                             language:(NSString *)language
                                                voice:(NSString *)voice
                                                speed:(double)speed
                                                error:(NSError **)error {
  if (![self ttsReady]) {
    if (error) *error = RuntimeError(7, [NSString stringWithFormat:@"TTS model is not installed under %@", [self ttsRoot]]);
    return nil;
  }
  if (!text.length) {
    if (error) *error = RuntimeError(8, @"text must not be empty");
    return nil;
  }
  if (![language isEqualToString:@"zh"] && ![language isEqualToString:@"en"]) {
    if (error) *error = RuntimeError(9, @"Kokoro TTS supports zh and en");
    return nil;
  }
  if (!(speed > 0.0) || !std::isfinite(speed)) {
    if (error) *error = RuntimeError(10, @"speed must be greater than zero");
    return nil;
  }

  NSString *root = [self ttsRoot];
  std::string model = Path(root, @"model.onnx");
  std::string voices = Path(root, @"voices.bin");
  std::string tokens = Path(root, @"tokens.txt");
  std::string dataDir = Path(root, @"espeak-ng-data");
  std::string lexicon = Path(root, @"lexicon-us-en.txt") + "," + Path(root, @"lexicon-zh.txt");

  SherpaOnnxOfflineTtsConfig config;
  std::memset(&config, 0, sizeof(config));
  config.model.num_threads = 2;
  config.model.provider = "cpu";
  config.model.kokoro.model = model.c_str();
  config.model.kokoro.voices = voices.c_str();
  config.model.kokoro.tokens = tokens.c_str();
  config.model.kokoro.data_dir = dataDir.c_str();
  config.model.kokoro.lexicon = lexicon.c_str();
  config.model.kokoro.lang = [language UTF8String];
  config.max_num_sentences = 1;

  const SherpaOnnxOfflineTts *tts = SherpaOnnxCreateOfflineTts(&config);
  if (!tts) {
    if (error) *error = RuntimeError(11, @"Unable to create Sherpa-ONNX TTS engine");
    return nil;
  }
  SherpaOnnxGenerationConfig generation;
  std::memset(&generation, 0, sizeof(generation));
  generation.sid = 0;
  generation.speed = static_cast<float>(speed);
  generation.silence_scale = 0.2f;
  const SherpaOnnxGeneratedAudio *audio = SherpaOnnxOfflineTtsGenerateWithConfig(
      tts, [text UTF8String], &generation, nullptr, nullptr);
  if (!audio) {
    SherpaOnnxDestroyOfflineTts(tts);
    if (error) *error = RuntimeError(12, @"Unable to generate speech");
    return nil;
  }
  NSString *filename = [NSString stringWithFormat:@"tts-%lu-%@.wav", (unsigned long)text.hash, language];
  NSString *output = [NSTemporaryDirectory() stringByAppendingPathComponent:filename];
  const int32_t sampleRate = audio->sample_rate;
  const int32_t sampleCount = audio->n;
  int32_t ok = SherpaOnnxWriteWave(audio->samples, sampleCount, sampleRate, [output UTF8String]);
  double duration = sampleRate > 0 ? static_cast<double>(sampleCount) / sampleRate : 0.0;
  SherpaOnnxDestroyOfflineTtsGeneratedAudio(audio);
  SherpaOnnxDestroyOfflineTts(tts);
  if (!ok) {
    if (error) *error = RuntimeError(13, [NSString stringWithFormat:@"Unable to save generated speech: %@", output]);
    return nil;
  }

  return @{
    @"path": output,
    @"sampleRate": @(sampleRate),
    @"duration": @(duration),
    @"model": @"kokoro-1.0",
    @"voice": voice
  };
}

@end
