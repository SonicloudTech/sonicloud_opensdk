# SoniCloud Recorder SDK

**Languages:** English | [简体中文](README.zh-CN.md)

> A recorder card and a complete BLE integration reference.

SoniCloud Recorder is an open-source reference project for hardware vendors, software developers, and system integrators. It combines recorder hardware with BLE protocol SDKs, cross-platform integration samples, and a desktop demo to help teams move from device connectivity to recording, transfer, transcription, and product integration.

<img src="img/录音卡片.png" alt="SoniCloud recorder card" width="480" style="max-width: 100%; height: auto;">

## Project overview

The project demonstrates a layered approach to recorder hardware integration: standard BLE commands, a vendor adaptation layer, and cross-platform SDK wrappers. The recorder card captures and stores audio; the SDK manages BLE sessions, protocol traffic, device state, and data streams; the application owns its UI, audio decoding, storage, transcription, and business integration. Differences between chipsets, including service UUIDs, characteristics, packetization, and private commands, remain inside the adapter layer.

## What is included

| Resource | Audience | Contents |
| --- | --- | --- |
| Mobile SDKs | Android, iOS, HarmonyOS, and Flutter developers | Platform wrappers, BLE discovery and connection, recording control, real-time audio, file transfer, Wi-Fi, OTA, device information, and event callbacks |
| Windows/macOS demo | Desktop application and tool developers | Python BLE protocol implementation, command-line REPL, Web console, and recorder controls |
| Protocol and test material | Teams that need hardware-level customization | BLE GATT, frame format, CRC, file downloads, recording events, and compatibility rules |
| Integration guides | Hardware vendors, app teams, and technical reviewers | Multiplatform SDK integration and the standard BLE command architecture |

## Capabilities

- A unified interface model for scanning, connecting, controlling recordings, and receiving device events on Android, iOS, HarmonyOS, and Flutter.
- Hardware-key recording start, pause, resume, and stop events with explicit application confirmation.
- Raw 16 kHz mono Opus frames for application-owned decoding, playback, ASR, or meeting-notes services.
- File listing, segmented downloads by filename and offset, resume support, validation, local storage, and deletion.
- Battery, capacity, firmware version, serial number, authorization code, recording state, duration, and gain information.
- BLE-controlled Wi-Fi setup followed by Wi-Fi/TCP transfer for recordings or firmware. BLE is used for OTA control, not for the firmware payload.
- A Windows/macOS desktop demo for scanning, connection checks, recording control, file downloads, playback, and streaming.
- An isolated offline Voice Engine based on sherpa-onnx, with SenseVoice ASR, Kokoro multilingual TTS, model manifests, SHA-256 verification, and Flutter/Android/iOS bridge entry points.
- Standard commands and a `VendorAdapter` boundary for adding chipsets, device models, and industry applications without duplicating integration work.

## Repository layout

```text
sonicloud_opensdk/
├── pnote-android-sdk/                  # Android AAR
├── pnote-ios-sdk/                      # iOS static library and header
├── pnote-harmony-sdk/                  # HarmonyOS HAR SDK
├── pnote-sdk-flutter-demo-main/        # Flutter integration demo
├── pnote-web-win&Mac-demo/             # BLE REPL and Web demo
│   ├── recorder/                       # Protocol, BLE, device session, and Web backend
│   ├── web/                            # Front-end page
│   ├── tests/                          # Protocol and device-simulation tests
│   └── docs/协议.md                    # CB08 communication protocol V1.0
├── Speech-to-text—text-to-speech/      # Isolated offline ASR/TTS and mobile bridges
├── img/                                # Project images
│   ├── 录音卡片.png                     # Product image
│   ├── 硬件参数.png                     # Hardware specifications
│   └── 微信.png                         # Contact QR code
├── SDK 集成引导.docx                   # SDK integration guide
├── demo.mp4                            # Demonstration video
└── LICENSE                             # MIT License
```

## Run the desktop demo in five minutes

Requirements: Python 3.10 or later, a working BLE adapter, and a recorder card that is ready to connect.

```bash
cd pnote-web-win&Mac-demo
python -m venv .venv
source .venv/bin/activate                 # Windows PowerShell: .venv\\Scripts\\Activate.ps1
pip install -r requirements.txt
python main.py --web
```

Open `http://127.0.0.1:8000` in a browser. The web console supports Chinese and English; use the selector in the top-right corner to switch languages. You can also verify the command-line REPL:

```text
record> scan
record> connect 0
record> smoke
record> list
record> download 0
record> transcribe 0
```

See the [desktop demo README](pnote-web-win%26Mac-demo/README.md) for the complete command list. Offline voice is isolated in [Speech-to-text—text-to-speech](Speech-to-text%E2%80%94text-to-speech/README.md); the Web page remains optional:

```bash
cd "../Speech-to-text—text-to-speech"
pip install -r requirements-python.txt
python scripts/fetch_voice_models.py --all
cd "../pnote-web-win&Mac-demo"
pip install -r requirements-web.txt
python -m unittest discover tests -v
```

Model archives are pinned in `Speech-to-text—text-to-speech/models/manifest.json`, downloaded from official sherpa-onnx releases, and verified with SHA-256 before extraction. Model weights are intentionally kept out of normal Git history. The existing SDK remains unchanged.

### Windows/macOS Web demo

The desktop demo provides both a command-line REPL and a browser-based Web console for device discovery, connection checks, recording control, file downloads, WAV playback, and real-time streaming. Offline ASR/TTS is maintained separately under `Speech-to-text—text-to-speech` so the existing SDK remains unchanged.

![SoniCloud recorder BLE console](pnote-web-win%26Mac-demo/%E5%BD%95%E9%9F%B3%E5%8D%A1%20ble%20%E6%8E%A7%E5%88%B6%E5%8F%B0.png)

## Mobile integration

Before integrating, read the [SDK integration guide](SDK%20%E9%9B%86%E6%88%90%E5%BC%95%E5%AF%BC.docx) for permissions, dependencies, initialization, callbacks, audio processing, resumable file transfer, and OTA acceptance testing. For the cross-vendor standardization model, see the protocol notes and documents included in this repository.

### Flutter

```bash
cd pnote-sdk-flutter-demo-main
flutter pub get
flutter run
```

Use a physical device to verify Bluetooth, recording, Wi-Fi, and OTA. The main integration entry point is `lib/provider_record_pen.dart`; see the [Flutter demo README](pnote-sdk-flutter-demo-main/README.md).

### Android

Copy the [Android AAR](pnote-android-sdk/pnote_20260827161403.aar) to your app's `app/libs` or `src/main/libs` directory. Add the `fileTree` dependency and the SDK's RxJava, Retrofit, EventBus, and other required dependencies, then call:

```java
PNote.init(context, deviceDataListener);
PNote.startSearch();
PNote.connectDevice(name, address);
```

Callbacks include JSON device events, real-time Opus data, and file Opus data. See the [Android SDK guide](pnote-sdk-flutter-demo-main/android%20SDK%E5%BC%80%E5%8F%91%E6%96%87%E6%A1%A3%28%E6%9C%80%E6%96%B0%E7%89%88%E6%9C%AC%29-2026.04.23.md) for the complete API.

### iOS

Add [libPNote.a](pnote-ios-sdk/libPNote.a) and [PNode.h](pnote-ios-sdk/PNode.h) to Xcode, implement `WindBleDelegate`, and call APIs such as `startSearch` and `connectDeviceAndAddress`. See the [iOS SDK guide](pnote-sdk-flutter-demo-main/iOS%20SDK%E5%BC%80%E5%8F%91%E6%96%87%E6%A1%A3%28%E6%9C%80%E6%96%B0%E7%89%88%E6%9C%AC%29-2026.04.23.md) for the complete API and OTA workflow.

### HarmonyOS

The HarmonyOS SDK is distributed as [har_recordersdk.har](pnote-harmony-sdk/har_recordersdk.har) and currently targets HarmonyOS API 12 or later. Import the HAR package, request Bluetooth permissions, and connect with the `deviceId` returned by the scan callback. This `deviceId` may be a system-generated privacy identifier; the `address` field is for display only. Business results are returned asynchronously through `DEVICE_DATA` events.

## Protocol implementation notes

- Layering: application/business layer → SDK core and state machine → standard BLE protocol → `VendorAdapter` → device firmware.
- Reference BLE GATT: service `0xAE20`, write characteristic `AE21`, data notification `AE22`, and key notification `AE23`.
- Generic frame: `MAGIC(0x5A) + SEQ + CRC-16/XMODEM + LEN + TYPE/CMD/PARAMS`. Buffer by length, validate, deduplicate, reassemble, and correlate responses with requests.
- Notifications may contain partial frames, multiple frames, or noise across packets. Data and key notifications use independent parser buffers, while the sender fragments frames according to the negotiated MTU and preserves their order.
- Core commands cover device information, battery and capacity, recording state, file listing and downloads, time synchronization, key responses, Wi-Fi state, parameter settings, and OTA state. Unknown commands should return an identifiable error.
- Treat a file list as complete when `finish=1` or the platform SDK reports completion. Downloads use a 4-byte little-endian `offset`; the application should validate file size and audio decodability.
- Real-time recording and file callbacks contain raw Opus bytes. The baseline format is 16 kHz mono, 40 bytes per frame, and 20 ms per frame. The SDK does not decode Opus or generate WAV headers.
- OTA uses BLE for mode and environment control, then Wi-Fi/TCP for the firmware payload. Check battery, version, and TCP state before upgrading; stop the task if either BLE or Wi-Fi disconnects.

See the [protocol document](pnote-web-win%26Mac-demo/docs/%E5%8D%8F%E8%AE%AE.md) for field definitions, command tables, captured frames, and compatibility rules.

## Integration checklist

1. Use the desktop demo with a real device to verify discovery, connection, time synchronization, a read-only check, and at least one file download.
2. Request the required Bluetooth permissions for the target platform. Initialize the SDK, register device-event, real-time-audio, and file-data callbacks, and then start discovery.
3. Connect with the identifier returned by the scan callback. After connection, synchronize time, then read battery, capacity, firmware version, and the file list.
4. Convert callbacks into the application's event queue or state-management layer. A method call means that a request was submitted; completion is represented by an asynchronous event.
5. Send 40-byte Opus frames to a dedicated decoder task. Finalize files on the completion event, record the offset, and validate size and decodability before showing them to users.
6. Run OTA only after Wi-Fi/TCP is connected, an update is needed, and the battery is at least 20 percent. Mark the upgrade as failed if BLE or Wi-Fi disconnects; do not blindly resend the entire firmware.
7. When adding a chipset or model, extend `VendorAdapter`, capability flags, and version negotiation instead of exposing vendor-private fields to application code.
8. Never hard-code or commit cloud ASR keys, authorization codes, real recordings, or device identifiers. Redact logs and packet captures before sharing them.

## Use cases

The project is suitable for meeting recording and note-taking, interviews, classroom training, content creation, inspection records, companion apps for smart hardware, corporate gift and promotional recorders, and other products that need to integrate multiple recorder chipsets into one application.

## Hardware adaptation and support

Hardware integration typically follows this sequence: confirm capabilities → implement `VendorAdapter` → integrate the SDK → validate on real hardware. The hardware team should provide chipset capabilities, BLE services and characteristics, private commands, firmware versions, protocol material, and test scenarios. The adapter maps those differences to the standard interface; the application team then uses Android, iOS, HarmonyOS, or Flutter APIs to build the product workflow.

For hardware specifications, sample devices, the HarmonyOS SDK, complete protocol material, or technical support, contact [SoniCloud](https://www.sinicloud.com/). Include the target platform, expected volume, device model, firmware version, and intended use case.

<img src="img/微信.png" alt="SoniCloud contact QR code" width="200" style="max-width: 100%; height: auto;">

## License and usage boundaries

The example code is released under the [MIT License](LICENSE). AAR files, static libraries, HAR packages, firmware, device-private protocols, and some documents may contain SoniCloud or vendor-owned material and are not necessarily open source. Redistribution and commercial use are governed by the accompanying package terms and applicable agreements.

Interfaces, command numbers, and behavior are defined by the current SDK, firmware, protocol version, and real-device validation results. The SDK does not replace application-side Opus decoding, file storage, permission handling, or security controls. Do not use private protocols with hardware or products without authorization.

## Related repository

- **[SoniCloud Smart Mouse SDK (`mouse-sdk`)](https://github.com/SonicloudTech/mouse-sdk)** ([Gitee mirror](https://gitee.com/SonicloudTech/mouse-sdk)): a cross-platform and cross-architecture smart-mouse SDK for Windows, macOS, and Linux, including UOS, Kylin, and Fangde on x86_64 and ARM64. It provides USB and BLE channels, button/event/audio support, a pure C ABI, and bilingual documentation and samples. The former `uMouse/` directory has moved to that repository.

## Feedback and issues

When filing an issue, include the operating system and version, target platform, SDK/demo version, device firmware version, reproduction steps, and relevant logs or TX/RX frame hex. Redact serial numbers, addresses, authorization codes, recordings, and other real-device data before sharing it.
