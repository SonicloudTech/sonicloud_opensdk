# SoniCloud Project

Flutter project for the PNote Bluetooth voice-recorder pen. Built on [pnote_flutter_sdk](https://github.com/chenqiangchenqiang/pnote-flutter-sdk), it demonstrates the complete chain: device connection, recording control, live transcription with speaker separation, file management, local playback, and AI meeting-summary / mind-map generation.

> English | [中文](README.zh-CN.md)

- Platforms: Android / iOS (Flutter)
- Languages: Chinese / English (follows the system locale; **any non-Chinese system gets English**)
- Theme color: `#3D9AFF` (design tokens in `lib/design/tokens.dart`)
- Prebuilt test APK: [project-apk/](project-apk) (debug-signed, for evaluation only — build your own for production)

**Video**

https://github.com/user-attachments/assets/606a73df-dad9-48d2-b2ed-ecc00dbb7535

## Features

| Module | Capabilities |
|---|---|
| Device connection | BLE scan / connect / reconnect; permission & Bluetooth-state guidance; device summary chip in the AppBar (online dot + name + battery graphic) |
| Recording | In-app recording controls (start / pause / resume / stop & save); full mirroring of the pen's physical buttons; recording auto-opens a fullscreen page that cannot be exited while recording; live timer |
| Live transcription | Opus→PCM audio chunks streamed to Sonicloud `talentStreamAsr` (`role=1` speaker separation); interim sentences highlighted + finalized text with two-line speaker labels; reconnect with backoff; transcript saved on stop |
| Local recordings | Recording stream saved to disk in parallel with transcription (shared broadcast stream); partial file stays playable after disconnect; transcript `.txt` saved alongside |
| Playback | Audio detail page (info + player + transcript/summary/mind-map tabs); resets to start when playback completes |
| AI generation | One-tap meeting summary (Markdown) + interactive mind map from the transcript; fully automatic chain (mind map auto-fetched after the summary); auto-resumes polling when re-entering mid-generation; task_id & results cached to disk to prevent duplicate submissions and billing |
| Device files | File list auto-refreshed on entry; download / delete (single / all, with confirmation); **download pause & resume**; mini player bar |
| Recent recordings | App recordings + device downloads unified; "More" page beyond 5 entries; delete support (including transcripts) |

Full UI/interaction spec: [docs/app-features.md](docs/app-features.md).

## Tech Stack

- Flutter (managed with FVM, `3.47.7`; Dart SDK `^3.13.5`)
- `pnote_flutter_sdk`: BLE protocol wrapper for the recorder pen (scan / connect / recording commands / file transfer / device info)
- `flutter_blue_plus`: BLE transport
- `opus_codec` / `opus_codec_dart`: opus decode FFI (40-byte fixed frames → PCM s16le/16k/mono)
- `web_socket_channel` + `crypto`: transcription uplink and auth signing
- `just_audio` + `audio_session`: local playback
- `markdown_widget`: AI summary Markdown rendering
- `flutter_mind_map`: interactive mind map (vendored local package `flutter_mind_map-1.0.1/`)
- `path_provider`: local storage locations

## Quick Start

```bash
fvm flutter pub get
fvm flutter run          # requires a physical device + a powered-on recorder pen
```

> Emulators have no Bluetooth — use a physical device.

### Sonicloud Open Platform credentials

Live transcription (ASR) and AI summarization require [Sonicloud开放平台](https://open.sinicloud.com) authentication. Set the three constants at the top of [lib/asr/sinicloud_auth.dart](lib/asr/sinicloud_auth.dart):

```dart
static const _appId = 'YOUR_APP_ID';         // Open Platform AppID
static const _apiKey = 'YOUR_API_KEY';       // Open Platform API Key
static const _apiSecret = 'YOUR_API_SECRET'; // Open Platform API Secret
```

This public repository ships placeholders — replace them with your own credentials (from the platform console) before running. apiSecret is sensitive: never commit real values to a public repository; production apps should proxy token issuance through their own backend.

### Required Android permissions (declared in the Manifest)

`BLUETOOTH_SCAN` / `BLUETOOTH_CONNECT` (Android 12+), `BLUETOOTH` / `BLUETOOTH_ADMIN` (legacy), `ACCESS_FINE_LOCATION` (legacy scanning), `INTERNET` (transcription).

The app includes permission guidance: prompt cards with an "open system settings" entry when permissions are missing or Bluetooth is off; **the permission check precedes the Bluetooth-state check** (on Android 12+ the adapter state is always `unknown` before permission is granted — checking Bluetooth first would misreport).

## Project Layout

```
lib/
├── main.dart                  # Entry, AppBar device summary, language switch, tab shell
├── session.dart               # Global session state: scan/connect/record/transcript fan-out/local save/recent list
├── devices_page.dart          # Home: scan view + connected dashboard + recent recordings
├── device_detail_page.dart    # Device info page (battery/storage/firmware/refresh/disconnect)
├── recording_overlay_page.dart# Fullscreen recording page (auto-opened, non-exitable)
├── recordings_page.dart       # Device files (download/pause-resume/delete/mini player)
├── recent_recordings_page.dart# All recent recordings page (delete) + shared item widget
├── audio_detail_page.dart     # Audio detail (info/player/transcript·summary·mind-map tabs/AI)
├── transcript_flow.dart       # Live transcript flow widget (two-line speaker display)
├── ble_permissions.dart       # Permission requests & guidance
├── asr/
│   ├── pen_asr_service.dart   # Transcription WebSocket service (Sonicloud line/reconnect/speaker routing)
│   └── sinicloud_auth.dart    # Sonicloud Open Platform token fetch & cache
├── ai/
│   └── summary_service.dart   # AI summary/mind-map APIs (createAnalysis/polling/summary/mindmap)
├── audio/
│   ├── recording_store.dart   # Local storage (recordings/ and recordings/app/) + opus→wav
│   ├── opus_bootstrap.dart    # Opus decoder init/frame-decode bootstrap
│   └── wav.dart               # WAV container
├── widgets/                   # Mind-map widgets (embedded/fullscreen/data model)
├── design/
│   ├── tokens.dart            # Design tokens (#3D9AFF primary palette)
│   ├── markdown_theme_config.dart # Summary Markdown theme mapping
│   ├── status_badge.dart      # Status badge (dot + text)
│   └── battery_level.dart     # Battery graphic (filled by percentage)
└── l10n/                      # arb + generated code (gen/)
```

## Implementation Notes

- **Audio stream**: once recording starts, the device continuously sends `AUDIO_DATA` opus frames (firmware convention: **40 B/frame, 20 ms/frame**, i.e. 2000 B/s); the stream is broadcast — transcription and local saving subscribe in parallel; duration can be derived from the byte count
- **Transcription pipeline**: opus frames decoded to PCM → sliced into 100 ms (3200 B) chunks → uplinked to `wss://openapi.sinicloud.com/talentStreamAsr` (dual-header auth; `role=1` enables speaker separation); `errCode 1000` connected, `3` interim, `0 + End>0` finalized, `10` stream end
- **AI summary pipeline**: transcript → `createAnalysis` → poll `analysisDetail` → `summary` (Markdown) → auto-fetch `mindmap`; `language` follows the system locale (zh/en); task_id & results cached to disk — no duplicate submission or billing on re-entry
- **Local storage**: app recordings → `recordings/app/REC_*.opus` (+ matching `.txt` transcript); device downloads → `recordings/` root; lazy `.wav` conversion before playback
- **Resumable download**: pause sends protocol `cmd=7`; resume calls `startGetFile(name, offset: receivedBytes)` and appends to the local file; an attempt token guards against stale session replies
- **Physical buttons**: pen start(1)/stop(3)/pause(5)/resume(7) drive the app state machine (including auto open/close of the fullscreen recording page)

## Localization

- Sources: `lib/l10n/app_en.arb` (template) / `app_zh.arb`
- Generation: `fvm flutter gen-l10n` (see `l10n.yaml`)
- Rule: system `zh*` → Chinese, everything else → English; the AppBar menu can lock English / 中文 manually

## Related Repositories

- SDK: [pnote-flutter-sdk](https://github.com/chenqiangchenqiang/pnote-flutter-sdk) (protocol implementation & API docs in its README / ARCHITECTURE.md)
