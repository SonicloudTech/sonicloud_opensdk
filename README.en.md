# SoniCloud Recorder SDK

> A recorder card and a complete BLE integration reference.

SoniCloud Recorder is an open-source integration example for recorder hardware. It includes the BLE protocol SDKs, cross-platform samples, a desktop console, and protocol test material for teams building recording, transfer, transcription, or meeting-note workflows.

**Languages:** [简体中文](README.md) | English

## What is included

| Resource | Audience | Contents |
| --- | --- | --- |
| Mobile SDKs | Android, iOS, HarmonyOS and Flutter developers | BLE discovery and connection, recording control, real-time audio, file transfer, Wi-Fi, OTA, device information and callbacks |
| Windows/macOS demo | Desktop application and tool developers | Python BLE protocol implementation, command-line REPL, Web console, audio playback and offline speech-to-text |
| Protocol and tests | Teams that need hardware-level customization | BLE GATT, frame format, CRC, file download, recording events and compatibility rules |
| Integration guides | Hardware vendors and application teams | Three-platform SDK integration and the standard BLE command architecture |

## Capabilities

- One API model for Android, iOS, HarmonyOS and Flutter scanning, connection, recording and device events.
- Hardware-key recording start, pause, resume and stop events with explicit application confirmation.
- 16 kHz mono Opus frames for application-owned decoding, playback, ASR or meeting-note services.
- File listing, offset-based download, resume, validation, local storage and deletion.
- Battery, capacity, firmware, serial number, authorization, recording state, duration and gain information.
- BLE-controlled Wi-Fi setup for file or firmware transfer. OTA firmware data is sent over Wi-Fi/TCP, not BLE.
- A desktop console for scanning, connection checks, recording, downloads, playback and transcription.
- A `VendorAdapter` boundary for new chipsets and device variants.

## Run the desktop demo

Requirements: Python 3.10+, a BLE adapter, and a discoverable recorder.

```bash
cd pnote-web-win&Mac-demo
python -m venv .venv
source .venv/bin/activate                 # Windows PowerShell: .venv\\Scripts\\Activate.ps1
pip install -r requirements.txt
python main.py --web
```

Open `http://127.0.0.1:8000`. The Web console supports Chinese and English; choose the language in the top-right selector. The command-line REPL can be checked with:

```text
record> scan
record> connect 0
record> smoke
record> list
record> download 0
record> transcribe 0
```

Optional features:

```bash
pip install -r requirements-asr.txt
pip install -r requirements-web.txt
python -m unittest discover tests -v
```

The first transcription run downloads approximately 900 MB of model data from ModelScope; later runs can work offline.

## Mobile integration

Start with [the SDK integration guide](SDK%20集成引导.docx), then select the platform sample:

```bash
cd pnote-sdk-flutter-demo-main
flutter pub get
flutter run
```

Use a physical device to verify Bluetooth, recording, Wi-Fi and OTA. The main Flutter integration entry point is `lib/provider_record_pen.dart`.

- **Android:** add `pnote-android-sdk/*.aar` to `app/libs` and use `PNote.init`, `PNote.startSearch` and `PNote.connectDevice`.
- **iOS:** add `pnote-ios-sdk/libPNote.a` and `PNode.h`, implement `WindBleDelegate`, and use the search/connection APIs.
- **HarmonyOS:** import `pnote-harmony-sdk/har_recordersdk.har`, request Bluetooth permissions, and connect with the scan callback's `deviceId`.

## Protocol notes

- Layering: application → SDK state machine → standard BLE protocol → `VendorAdapter` → firmware.
- Reference GATT: service `0xAE20`, write characteristic `AE21`, data notification `AE22`, key notification `AE23`.
- Frame: `MAGIC(0x5A) + SEQ + CRC-16/XMODEM + LEN + TYPE/CMD/PARAMS`.
- Notifications may contain partial or multiple frames; data and key notifications use independent parser buffers.
- Real-time and file callbacks carry raw Opus bytes at 16 kHz mono. The SDK does not decode Opus or create WAV headers.
- OTA starts with BLE mode/environment control, then transfers firmware over Wi-Fi/TCP.

See the [protocol document](pnote-web-win%26Mac-demo/docs/%E5%8D%8F%E8%AE%AE.md) for field definitions, command tables and captured frames.

## Compatibility and security

Keep vendor-specific fields inside `VendorAdapter` and expose capabilities through version negotiation. Do not commit ASR keys, authorization codes, serial numbers or real recordings. Redact logs and packet captures before sharing them.

The example code is released under the [MIT License](LICENSE). Bundled AAR, static libraries, HAR packages, firmware, private protocols and some documents may contain proprietary material; redistribution and commercial use are governed by the accompanying package terms and agreements.

For hardware specifications, samples, full protocol material or support, contact [SoniCloud](https://www.sinicloud.com/). When reporting an issue, include the operating system, target platform, SDK/demo version, firmware version, reproduction steps and sanitized logs.
