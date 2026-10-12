Pod::Spec.new do |s|
  s.name             = 'sonicloud_voice'
  s.version          = '0.1.0'
  s.summary          = 'Offline Sherpa-ONNX ASR and TTS for SoniCloud'
  s.description      = 'Isolated Flutter bridge for local SenseVoice ASR and Kokoro TTS.'
  s.homepage         = 'https://github.com/k2-fsa/sherpa-onnx'
  s.license          = { :type => 'Apache-2.0' }
  s.author           = { 'SoniCloud' => 'opensource@sonicloud.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Sources/SoniCloudVoice/**/*.{h,mm,swift}'
  s.public_header_files = 'Sources/SoniCloudVoice/*.h'
  s.vendored_frameworks = 'Native/SherpaOnnxC.xcframework', 'Native/onnxruntime.xcframework'
  s.platform         = :ios, '13.0'
  s.swift_version    = '5.0'
  s.dependency 'Flutter'
  s.frameworks       = 'Foundation'
  s.requires_arc     = true
  s.pod_target_xcconfig = {
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'HEADER_SEARCH_PATHS' => '$(inherited) "${PODS_TARGET_SRCROOT}/Native/SherpaOnnxC.xcframework/**/Headers"'
  }
end
