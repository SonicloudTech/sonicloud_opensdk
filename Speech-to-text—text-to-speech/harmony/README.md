# HarmonyOS native runtime

The existing HarmonyOS SDK remains unchanged. A future HarmonyOS adapter
should expose the same `VoiceRuntime` contract through ArkTS/NAPI and link a
HarmonyOS-compatible Sherpa-ONNX C/C++ build. Model installation, language
selection, PCM format, result fields, and error codes must match
`voice_contract.md`.
