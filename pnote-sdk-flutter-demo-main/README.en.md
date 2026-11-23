# Soni SDK Demo (Flutter)

[简体中文](README.md)

A Flutter demo for integrating and testing the Soni recorder SDK on Android and iOS. Flutter sends commands over a `MethodChannel` and receives device events, audio data, and SDK logs over an `EventChannel`.

## Features

- **Device tab.** Scan for and connect to recorders over Bluetooth, sync the clock automatically, and read device information. Controls such as AuthKey authentication, heartbeat, and Wi-Fi Direct vary by model. Select **切换英文** in the app bar to switch the Device tab to English.
- **Recording and files.** Start, pause, resume, and stop recordings. List, download, and delete files. Android wraps Opus in an Ogg container, and iOS decodes Opus to PCM and writes WAV files. Both platforms can export raw Opus for analysis.
- **Wi-Fi and OTA.** Manage the device hotspot, use one-tap connection, and run UFW or BK firmware updates on supported models.
- **Test tab (测试).** Run automated Bluetooth connection, file transfer, OTA, and BK OTA tests, and share test reports.

## Requirements

- FVM with Flutter 3.41.9 (Dart 3.11.5), as pinned in [`.fvmrc`](.fvmrc). Set your IDE's Flutter SDK path to `.fvm/flutter_sdk`.
- Android Studio and the Android SDK for Android, or macOS, Xcode, and CocoaPods for iOS. The iOS demo targets iOS 15.0 or later.
- A supported recorder and a physical Android or iOS device for Bluetooth, Wi-Fi, recording, and OTA testing.

## Quick start

Install FVM, then run these commands in the repository root. [FVM installation](https://fvm.app/documentation/getting-started/installation)

```bash
fvm install
fvm use 3.41.9
fvm flutter pub get
fvm flutter devices
```

### Android

Choose the flavor that matches your recorder. Run one of the following commands, replacing `<device-id>` with the ID reported by `fvm flutter devices`.

| Flavor | App name | Audio handling |
| --- | --- | --- |
| `normal` | SoniDemo | Uses unencrypted audio |
| `bk` | SoniDemoBK | Enables AES-256-GCM decryption for live audio |

```bash
fvm flutter run -d <device-id> --flavor normal --dart-define=DEVICE_AES256GCM=false
fvm flutter run -d <device-id> --flavor bk --dart-define=DEVICE_AES256GCM=true
```

Grant Bluetooth, location, and nearby Wi-Fi device permissions when prompted. The prompts depend on the Android version and the operation. To build APKs, run `./scripts/build.sh normal` or `./scripts/build.sh bk`. APKs are copied to `build/outputs/<flavor>/`.

### iOS

Open [`ios/Runner.xcworkspace`](ios/Runner.xcworkspace) and configure a development team and device signing for Runner. Run from Xcode or use this command from the repository root.

```bash
fvm flutter run -d <device-id>
```

Grant Bluetooth, location, and local network permissions when prompted. For one-tap hotspot connection, the Runner signing configuration and provisioning profile must support Hotspot Configuration.

## iOS builds and version numbers

The `version: 4.0.3+17` entry in [`pubspec.yaml`](pubspec.yaml) maps to app version `4.0.3` and build number `17`. The demo displays `V4.0.3（17）`. After changing the version or upgrading Flutter, regenerate the build configuration from the repository root before running or archiving in Xcode. [Flutter iOS build and version numbers](https://docs.flutter.dev/deployment/ios#update-the-apps-build-and-version-numbers)

```bash
fvm flutter build ios --config-only --no-codesign
```

Flutter generates `ios/Flutter/Generated.xcconfig` with `FLUTTER_BUILD_NAME` and `FLUTTER_BUILD_NUMBER`, which populate `CFBundleShortVersionString` and `CFBundleVersion`. If the installed app still shows an old version, run the following commands, then choose **Product → Clean Build Folder** (`Shift + Command + K`) in Xcode and run or archive again. [package_info_plus version troubleshooting](https://pub.dev/packages/package_info_plus/versions/9.0.1#i-have-changed-version-in-pubspecyaml-and-plugin-returns-wrong-info)

```bash
fvm flutter clean
fvm flutter pub get
fvm flutter build ios --config-only --no-codesign
```

The iOS app uses `FlutterSceneDelegate` and registers the native channels and Flutter plugins in `didInitializeImplicitFlutterEngine` for the iOS 27 SDK's UIScene lifecycle.

## SDK guides and code

| Platform | English | 简体中文 |
| --- | --- | --- |
| Android | [Android SDK Development Guide](Android-SDK-Guide.en.md) | [Android SDK 开发文档](<android SDK开发文档.md>) |
| iOS | [iOS SDK Development Guide](iOS-SDK-Guide.en.md) | [iOS SDK 开发文档](<iOS SDK开发文档.md>) |

- [`lib/main.dart`](lib/main.dart) and [`lib/demo_function_panel.dart`](lib/demo_function_panel.dart) implement the Device tab and model-specific controls. [Demo feature list (Chinese)](<Demo功能列表.md>)
- [`lib/provider_record_pen.dart`](lib/provider_record_pen.dart) sends commands, dispatches events, and manages device state.
- [`lib/demo_test_page.dart`](lib/demo_test_page.dart) hosts automated tests and report controls.
- [Android MainActivity](android/app/src/main/kotlin/com/soni/soni_sdk_demo/MainActivity.kt) and [iOS AppDelegate](ios/Runner/AppDelegate.swift) bridge Flutter to the native SDKs.
- [`assets/`](assets/) contains demo assets and sample OTA firmware.

Key Flutter dependencies include `provider` for state, `permission_handler` for permissions, `wifi_iot` for Wi-Fi, `opus_flutter` and `opus_dart` for Opus decoding, `logger` for logs, and `path_provider` for file paths. [Full dependency list](pubspec.yaml)

## Wi-Fi status codes

Wi-Fi events use `cmd=12` and report `data.wifi_state`. Wait for `wifi_state=2` before starting a Wi-Fi file transfer or UFW update.

| Code | Meaning |
| --- | --- |
| `0` | The device hotspot is open |
| `1` | The device hotspot is closed |
| `2` | The TCP connection to the recorder is established |
| `3` | The TCP connection to the recorder is disconnected |
| `4` | A phone has joined the device hotspot |
| `5` | No phone is connected to the device hotspot |

## Troubleshooting

- **The recorder does not appear in the Bluetooth scan.** Confirm that it is powered on and available for connection. Check that Bluetooth is enabled and the app has the required permissions.
- **The phone joined the hotspot, but transfer fails or reports `ENONET`.** Check nearby Wi-Fi or local network permissions, the hotspot password, and the system join prompt. Confirm that the log shows `wifi_state=2`.
- **The firmware update fails.** Check that the firmware and update method match the recorder model. For UFW, confirm that the device entered update mode. For BK OTA, confirm that the recorder can reach the firmware URL. Read the firmware version after the recorder restarts to verify the result.
