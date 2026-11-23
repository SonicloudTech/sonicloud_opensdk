# Soni SDK Demo（Flutter）

[English](README.en.md)

Soni 录音笔的 Flutter 演示工程，用于联调 Android 和 iOS 原生 SDK。Flutter 通过 `MethodChannel` 发送命令，通过 `EventChannel` 接收设备状态、音频数据和 SDK 日志。

## 主要功能

- **设备页**支持蓝牙扫描、连接、自动同步时间、设备信息查询，以及按型号显示 AuthKey 认证、心跳、Wi-Fi 直传等功能。点击顶部「切换英文」可切换设备页文案。
- **录音与文件**支持开始、暂停、继续和停止录音，查询、下载和删除录音文件。Android 将 Opus 封装为 Ogg，iOS 将 Opus 解码为 PCM 并写入 WAV。两端均可导出原始 Opus 数据供分析。
- **Wi-Fi 与 OTA**支持设备热点管理、一键连接，以及适用设备的 UFW 或 BK 固件升级。
- **测试页**提供蓝牙连接、文件传输、OTA 和 BK OTA 自动化测试，并可分享测试报告。

## 环境要求

- FVM，按 [`.fvmrc`](.fvmrc) 使用 Flutter 3.41.9（Dart 3.11.5）。IDE 的 Flutter SDK 路径可设置为 `.fvm/flutter_sdk`。
- Android Studio 和 Android SDK，或 macOS、Xcode 和 CocoaPods。iOS Demo 的部署目标为 iOS 15.0。
- 支持的录音笔和 Android 或 iOS 真机，用于验证蓝牙、Wi-Fi、录音和升级。

## 快速开始

安装 FVM 后，在项目根目录执行。 [FVM 安装说明](https://fvm.app/documentation/getting-started/installation)

```bash
fvm install
fvm use 3.41.9
fvm flutter pub get
fvm flutter devices
```

### Android

选择与录音笔匹配的构建变体。两条运行命令任选其一，将 `<device-id>` 替换为 `fvm flutter devices` 列出的真机 ID。

| Flavor | 应用名 | 音频处理 |
| --- | --- | --- |
| `normal` | SoniDemo | 使用未加密的音频数据 |
| `bk` | SoniDemoBK | 启用 AES-256-GCM 实时音频解密 |

```bash
fvm flutter run -d <device-id> --flavor normal --dart-define=DEVICE_AES256GCM=false
fvm flutter run -d <device-id> --flavor bk --dart-define=DEVICE_AES256GCM=true
```

按系统提示授予蓝牙、定位和附近 Wi-Fi 设备等权限，具体提示取决于 Android 版本和操作。打包 APK 可运行 `./scripts/build.sh normal` 或 `./scripts/build.sh bk`，产物位于 `build/outputs/<flavor>/`。

### iOS

打开 [`ios/Runner.xcworkspace`](ios/Runner.xcworkspace)，为 Runner 配置开发团队和真机签名。可直接在 Xcode 运行，也可在项目根目录运行以下命令。

```bash
fvm flutter run -d <device-id>
```

按系统提示授予蓝牙、定位和本地网络权限。使用一键连接设备热点时，Runner 的签名配置和供应描述文件需支持 Hotspot Configuration。

## iOS 打包与版本号

[`pubspec.yaml`](pubspec.yaml) 中的 `version: 4.0.3+17` 对应 App 显示版本 `4.0.3` 和构建号 `17`，Demo 页面显示 `V4.0.3（17）`。修改版本号或升级 Flutter SDK 后，在 Xcode Run 或 Archive 前从项目根目录刷新生成配置。 [Flutter iOS 版本号说明](https://docs.flutter.dev/deployment/ios#update-the-apps-build-and-version-numbers)

```bash
fvm flutter build ios --config-only --no-codesign
```

Flutter 会生成 `ios/Flutter/Generated.xcconfig`，其中的 `FLUTTER_BUILD_NAME` 和 `FLUTTER_BUILD_NUMBER` 分别用于 `CFBundleShortVersionString` 和 `CFBundleVersion`。如果重新安装后仍显示旧版本，执行以下命令，再在 Xcode 中选择 **Product → Clean Build Folder**（`Shift + Command + K`）并重新 Run 或 Archive。 [package_info_plus 版本读取说明](https://pub.dev/packages/package_info_plus/versions/9.0.1#i-have-changed-version-in-pubspecyaml-and-plugin-returns-wrong-info)

```bash
fvm flutter clean
fvm flutter pub get
fvm flutter build ios --config-only --no-codesign
```

iOS 使用 `FlutterSceneDelegate` 启动，原生通道和 Flutter 插件在 `didInitializeImplicitFlutterEngine` 中注册，以适配 iOS 27 SDK 的 UIScene 生命周期。

## SDK 文档与代码入口

| 平台 | 中文开发文档 | English SDK guide |
| --- | --- | --- |
| Android | [Android SDK 开发文档](<android SDK开发文档.md>) | [Android SDK Development Guide](Android-SDK-Guide.en.md) |
| iOS | [iOS SDK 开发文档](<iOS SDK开发文档.md>) | [iOS SDK Development Guide](iOS-SDK-Guide.en.md) |

- [`lib/main.dart`](lib/main.dart) 和 [`lib/demo_function_panel.dart`](lib/demo_function_panel.dart) 提供设备页与按型号显示的操作入口。 [Demo 功能列表](<Demo功能列表.md>)
- [`lib/provider_record_pen.dart`](lib/provider_record_pen.dart) 负责命令发送、事件分发和设备状态管理。
- [`lib/demo_test_page.dart`](lib/demo_test_page.dart) 提供自动化测试入口和报告操作。
- [Android MainActivity](android/app/src/main/kotlin/com/soni/soni_sdk_demo/MainActivity.kt) 和 [iOS AppDelegate](ios/Runner/AppDelegate.swift) 实现 Flutter 与原生 SDK 的桥接。
- [`assets/`](assets/) 包含演示资源和示例 OTA 固件。

主要 Flutter 依赖包括 `provider`（状态管理）、`permission_handler`（权限）、`wifi_iot`（Wi-Fi）、`opus_flutter` 和 `opus_dart`（Opus 解码）、`logger`（日志）及 `path_provider`（文件路径）。 [完整依赖列表](pubspec.yaml)

## Wi-Fi 状态码

设备通过 `cmd=12` 回调上报 `data.wifi_state`。使用 Wi-Fi 传输文件或 UFW 升级前，等待 `wifi_state=2` 确认 TCP 已连接。

| 状态码 | 含义 |
| --- | --- |
| `0` | 设备热点已打开 |
| `1` | 设备热点已关闭 |
| `2` | 与设备的 TCP 连接已建立 |
| `3` | 与设备的 TCP 连接已断开 |
| `4` | 有手机已加入设备热点 |
| `5` | 当前没有手机加入设备热点 |

## 常见问题

- **蓝牙找不到设备。** 确认录音笔已开机并可以连接，检查手机蓝牙和相关权限。
- **手机已加入热点，仍出现 `ENONET` 或传输失败。** 检查附近 Wi-Fi 或本地网络权限、热点密码和系统入网提示，并在日志中确认收到 `wifi_state=2`。
- **OTA 失败。** 确认固件与设备型号和升级方式匹配。UFW 升级需确认设备已进入升级模式。BK OTA 需确认设备能访问固件 URL。设备重启后，重新读取版本以确认结果。
