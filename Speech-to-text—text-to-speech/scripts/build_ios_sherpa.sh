#!/usr/bin/env bash
set -euo pipefail

# Builds the same C API used by SoniCloudSherpaVoiceRuntime.mm. The generated
# XCFramework is intentionally copied into ios/Native by this script so a
# Flutter host can link it through sonicloud_voice.podspec.
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${SHERPA_ONNX_VERSION:-v1.13.8}"
WORK_DIR="${SHERPA_ONNX_BUILD_DIR:-${TMPDIR:-/tmp}/sonicloud-sherpa-onnx-${VERSION}}"
SOURCE_DIR="$WORK_DIR/sherpa-onnx-${VERSION#v}"
ORT_VERSION="${SHERPA_ONNX_ONNXRUNTIME_VERSION:-1.28.2}"

if [[ ! -f "$SOURCE_DIR/CMakeLists.txt" ]]; then
  mkdir -p "$WORK_DIR"
  archive="$WORK_DIR/sherpa-onnx.tar.gz"
  wget -q --show-progress --timeout=30 --tries=3 -O "$archive" \
    "https://codeload.github.com/k2-fsa/sherpa-onnx/tar.gz/refs/tags/${VERSION}"
  tar -xzf "$archive" -C "$WORK_DIR"
fi

cd "$SOURCE_DIR"
if [[ ! -f "$SOURCE_DIR/build-ios-shared.sh" ]]; then
  echo "Sherpa-ONNX ${VERSION} does not contain build-ios-shared.sh" >&2
  exit 1
fi

# The upstream script downloads ONNX Runtime and builds device/simulator
# slices, then creates sherpa-onnx.xcframework.
SHERPA_ONNX_ONNXRUNTIME_VERSION="$ORT_VERSION" bash ./build-ios-shared.sh

mkdir -p "$ROOT_DIR/ios/Native"
rm -rf "$ROOT_DIR/ios/Native/SherpaOnnxC.xcframework"
cp -R "$SOURCE_DIR/build-ios-shared/sherpa-onnx.xcframework" \
  "$ROOT_DIR/ios/Native/SherpaOnnxC.xcframework"
rm -rf "$ROOT_DIR/ios/Native/onnxruntime.xcframework"
cp -R "$SOURCE_DIR/build-ios-shared/ios-onnxruntime/onnxruntime.xcframework" \
  "$ROOT_DIR/ios/Native/onnxruntime.xcframework"

shasum -a 256 "$ROOT_DIR/ios/Native/SherpaOnnxC.xcframework"/*/* 2>/dev/null || true
echo "Built SherpaOnnxC and ONNX Runtime XCFrameworks under $ROOT_DIR/ios/Native"
