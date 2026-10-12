# Android native runtime

`SoniCloudVoicePlugin.kt` defines the Flutter MethodChannel and the stable
`VoiceRuntime` boundary. The module's `build.gradle` links the checked-in
`native/android/sherpa-onnx-1.13.8.aar`, which contains arm64-v8a,
armeabi-v7a, x86, and x86_64 native C/C++ runtime libraries plus the Sherpa
Kotlin API. The Kotlin API is the official JNI facade over those native
libraries, so the Flutter boundary does not depend on a second Android JNI
implementation.

The implementation keeps models under the app's private files directory and
exposes 16 kHz mono PCM/WAV ASR plus WAV TTS without network access after
installation. Copy the model directories from the shared manifest into
`filesDir/voice-models/` before calling `prepareModels`.

The AAR SHA-256 is:

```text
633c24321e06b1fe79feafa03ea16cbc0f8a286641e2da3559bac91bdb13bd96
```
