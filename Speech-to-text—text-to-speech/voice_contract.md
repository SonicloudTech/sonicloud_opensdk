# Voice Contract

All platforms expose the same operations:

| Operation | Input | Output |
| --- | --- | --- |
| `capabilities` | none | backend, languages, model state |
| `prepareModels` | optional language | completed when local model is ready |
| `transcribe` | 16 kHz mono WAV/PCM path, language | text, model, timestamped segments |
| `synthesize` | text, language, voice, speed | local WAV path, sample rate, duration |

The first mobile release should support file-based offline ASR and TTS. A
streaming ASR method can be added later without changing the file contract:

```text
startStreamingRecognition(language)
pushPcm(bytes)
stopStreamingRecognition()
```

Errors should be mapped to stable codes: `MODEL_NOT_INSTALLED`,
`RUNTIME_NOT_LINKED`, `INVALID_AUDIO_FORMAT`, `UNSUPPORTED_LANGUAGE`,
`INVALID_ARGUMENT`, and `CANCELLED`.
