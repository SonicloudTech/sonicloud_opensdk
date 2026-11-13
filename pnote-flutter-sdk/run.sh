#!/usr/bin/env bash
# 一键运行 pnote_flutter_sdk 的示例 App
# 插件本身不能直接运行，必须进入 example 目录运行示例工程
set -e

# 切换到脚本所在目录下的 example，无论从哪里调用都不会出错
cd "$(dirname "$0")/example"



echo "==> flutter run $*"
# 把脚本后面带的参数透传给 flutter run，例如 ./run.sh -d <设备id>
fvm flutter run "$@"
