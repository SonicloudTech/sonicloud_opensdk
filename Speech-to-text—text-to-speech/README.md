# Speech-to-text / text-to-speech

This directory is the isolated home for SoniCloud offline voice capabilities.
It does not modify the existing Android, iOS, HarmonyOS, Flutter, or desktop
SDK implementations.

## Contents

```text
Speech-to-text—text-to-speech/
├── python/sonicloud_voice/       # Desktop Python ASR/TTS implementation
├── models/                        # Versioned manifest, not model binaries
├── scripts/                      # Download and SHA-256 verification
├── flutter/lib/                  # Cross-platform Dart contract and bridge
├── android/                      # Flutter Android native bridge
├── ios/                          # Flutter iOS bridge and C API adapter
├── native/android/               # Sherpa-ONNX 1.13.8 AAR
├── native/ios/                   # SherpaOnnxC + ONNX Runtime XCFrameworks
├── harmony/                      # HarmonyOS native adapter contract
├── tests/                        # Tests that do not download models
├── requirements-python.txt
└── voice_contract.md
```

## Desktop Python

```bash
cd Speech-to-text—text-to-speech
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements-python.txt
python scripts/fetch_voice_models.py --all
PYTHONPATH=python python -m unittest discover tests -v
```

The Python implementation uses Sherpa-ONNX SenseVoice for ASR and Kokoro for
Chinese/English TTS. Model archives are downloaded from the official release
assets and checked against the manifest SHA-256 values.

## Mobile offline recognition

Mobile apps use the Dart `VoiceService` contract and the
`MethodChannelVoiceService` bridge. The native side owns model files and
inference; no network request is needed after model installation.

The Android bridge links the checked-in Sherpa-ONNX 1.13.8 AAR and calls its
Kotlin API behind `VoiceRuntime`. The iOS bridge links
`ios/Native/SherpaOnnxC.xcframework` and calls the Sherpa-ONNX C API through an
Objective-C++ adapter. Both platforms keep model files in the app-private
`voice-models`/`VoiceModels` directory and work without network access after
installation. The existing SDK remains untouched.

The native implementation must accept 16-bit mono 16 kHz PCM and return the
same result shape defined in `voice_contract.md`. Opus decoding remains in the
existing recorder SDK and is not part of this directory's voice engine.
