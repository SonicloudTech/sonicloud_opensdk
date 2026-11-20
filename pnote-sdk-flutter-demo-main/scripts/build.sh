#!/usr/bin/env bash
# 按 flavor 打包 Android APK / App Bundle
#
# 用法:
#   ./scripts/build.sh <flavor> [apk|appbundle] [debug|release]
#
# flavor:
#   normal  - 普通方案（无加密）
#             包名: com.soni.soni_sdk_demo
#             显示名: SoniDemo
#   bk      - AES256GCM 解密方案
#             包名: com.soni.soni_sdk_demo.bk
#             显示名: SoniDemoBK
#
# 示例:
#   ./scripts/build.sh normal
#   ./scripts/build.sh bk
#   ./scripts/build.sh bk apk release
#   ./scripts/build.sh normal appbundle

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

FLAVOR="${1:-}"
TARGET="${2:-apk}"
MODE="${3:-release}"

usage() {
  cat <<'EOF'
用法: ./scripts/build.sh <flavor> [apk|appbundle] [debug|release]

flavor:
  normal  普通方案  包名 com.soni.soni_sdk_demo / 显示名 SoniDemo
  bk      加密方案  包名 com.soni.soni_sdk_demo.bk / 显示名 SoniDemoBK
EOF
}

if [[ -z "$FLAVOR" ]]; then
  usage
  exit 1
fi

case "$FLAVOR" in
  normal)
    AES_DEFINE=false
    ;;
  bk)
    AES_DEFINE=true
    ;;
  *)
    echo "错误: 未知 flavor='$FLAVOR'，仅支持 normal | bk"
    usage
    exit 1
    ;;
esac

case "$TARGET" in
  apk|appbundle) ;;
  *)
    echo "错误: 未知产物类型='$TARGET'，仅支持 apk | appbundle"
    usage
    exit 1
    ;;
esac

case "$MODE" in
  debug|release) ;;
  *)
    echo "错误: 未知构建模式='$MODE'，仅支持 debug | release"
    usage
    exit 1
    ;;
esac

OUT_DIR="$ROOT_DIR/build/outputs/$FLAVOR"
mkdir -p "$OUT_DIR"

echo "========================================"
echo " flavor : $FLAVOR"
echo " AES    : DEVICE_AES256GCM=$AES_DEFINE"
echo " target : $TARGET ($MODE)"
if [[ "$FLAVOR" == "bk" ]]; then
  echo " 包名   : com.soni.soni_sdk_demo.bk"
  echo " 显示名 : SoniDemoBK"
else
  echo " 包名   : com.soni.soni_sdk_demo"
  echo " 显示名 : SoniDemo"
fi
echo " 输出   : $OUT_DIR"
echo "========================================"

FLUTTER_ARGS=(
  build "$TARGET"
  --flavor "$FLAVOR"
  --dart-define=DEVICE_AES256GCM="$AES_DEFINE"
  --split-per-abi
)

if [[ "$MODE" == "debug" ]]; then
  FLUTTER_ARGS+=(--debug)
else
  FLUTTER_ARGS+=(--release)
fi

"$ROOT_DIR/.fvm/flutter_sdk/bin/flutter" "${FLUTTER_ARGS[@]}"

# 拷贝产物到统一目录，便于取包
if [[ "$TARGET" == "apk" ]]; then
  SRC_DIR="$ROOT_DIR/build/app/outputs/flutter-apk"
  shopt -s nullglob
  APKS=("$SRC_DIR"/*"$FLAVOR"*.apk)
  if [[ ${#APKS[@]} -eq 0 ]]; then
    APKS=("$SRC_DIR"/*.apk)
  fi
  for apk in "${APKS[@]}"; do
    cp -f "$apk" "$OUT_DIR/"
    echo "已输出: $OUT_DIR/$(basename "$apk")"
  done
else
  if [[ "$MODE" == "debug" ]]; then
    SRC_DIR="$ROOT_DIR/build/app/outputs/bundle/${FLAVOR}Debug"
  else
    SRC_DIR="$ROOT_DIR/build/app/outputs/bundle/${FLAVOR}Release"
  fi
  shopt -s nullglob
  AABS=("$SRC_DIR"/*.aab)
  if [[ ${#AABS[@]} -eq 0 ]]; then
    echo "警告: 未在 $SRC_DIR 找到 .aab，请到 build/app/outputs/bundle/ 下手动查看"
  fi
  for aab in "${AABS[@]}"; do
    cp -f "$aab" "$OUT_DIR/"
    echo "已输出: $OUT_DIR/$(basename "$aab")"
  done
fi

echo "打包完成."
