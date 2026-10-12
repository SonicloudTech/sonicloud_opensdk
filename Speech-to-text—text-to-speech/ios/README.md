# iOS native runtime

`SoniCloudVoicePlugin.swift` defines the Flutter MethodChannel and the stable
`VoiceRuntime` boundary. `SoniCloudSherpaVoiceRuntime.mm` implements that
boundary with Sherpa-ONNX's C API; it is linked through
`Native/SherpaOnnxC.xcframework` and its required
`Native/onnxruntime.xcframework` dependency.

Build the framework from the pinned upstream source with:

```bash
cd Speech-to-text—text-to-speech
bash scripts/build_ios_sherpa.sh
```

The script builds arm64 device plus arm64/x86_64 simulator slices using
Sherpa-ONNX `v1.13.8` and ONNX Runtime `1.28.2`. It requires Xcode, CMake,
`wget`, and an Apple SDK. The generated framework is ignored at the individual
binary-file level so large artifacts are not accidentally committed; release
packaging should publish its SHA-256 alongside the framework.

The checked-in slice hashes for the generated `v1.13.8` framework are:

```text
ios-arm64/SherpaOnnxC.framework/SherpaOnnxC
67f4c2c82768700122287b88f749817151a6269ab62ebd89b041c133e883a2d9
ios-arm64_x86_64-simulator/SherpaOnnxC.framework/SherpaOnnxC
b1880f561f36e2d73e24895b0c566f4df46130d0182bc6e6d0feaff4ad00aad3
onnxruntime.xcframework/ios-arm64/onnxruntime.framework/onnxruntime
f5862fa8ec2dce3e8ceafb897a970b2ebbeafbe6e810a84b5588989aa5903ab9
onnxruntime.xcframework/ios-arm64_x86_64-simulator/onnxruntime.framework/onnxruntime
199fb19a655df9e163b405fa5092d4896308f5660bab075915ec68b323f43fac
```

ONNX Runtime `1.28.2` is included because the Sherpa dynamic framework links
`@rpath/onnxruntime.framework/onnxruntime`. CocoaPods embeds both frameworks
through the podspec.

Store models in `Application Support/VoiceModels`, validate the shared
manifest SHA-256, and use file input to provide 16 kHz mono PCM/WAV ASR and
local WAV TTS without network access after installation. The included adapter
uses SenseVoice for `auto/zh/en/yue/ja/ko` and Kokoro for `zh/en`.
