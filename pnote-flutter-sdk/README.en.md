# pnote_flutter_sdk (lite)

English | [简体中文](./README.md)

BLE Flutter plugin for the Shengyun voice recorder pen — **lite edition**. Pure Dart implementation on top of `flutter_blue_plus`, no native SDK required.

## Features

| Capability | Description |
|------|------|
| Scan / connect | Filters by service `0xAE20`; reconnect by name + address (`connectDeviceAndAddress`) |
| Device info | Time sync / battery / storage / firmware version / MAC |
| Recording control | Start / stop / pause / resume / state query; mirrors physical-key and device-side pause/resume events |
| Realtime audio stream | Raw opus frames pushed automatically while recording (`recordDataStream`), for live transcription / monitoring |
| File management | List / download (resumable, byte-range) / delete one / delete all |
| AppJson compatibility layer | Emits JSON events identical to the iOS SDK (`getCBCAppJson()` etc., ×11) |

## Getting started

### 1. Add the dependency

```yaml
dependencies:
  pnote_flutter_sdk:
    git:
      url: https://github.com/SonicloudTech/sonicloud_opensdk.git
      path: pnote-flutter-sdk
```

### 2. Configure permissions

**Android** `AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.BLUETOOTH_SCAN"
    android:usesPermissionFlags="neverForLocation" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<!-- Android 11 and below -->
<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
```

**iOS** `Info.plist`:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Required to connect to the voice recorder pen</string>
```

Runtime permissions must be requested by your app (the example app relies on the system prompt; `permission_handler` is recommended for production apps).

### 3. Usage

```dart
final sdk = AudioPenSdk();

// Scan (filtered by 0xAE20)
sdk.startSearch().listen((results) {
  // results: List<ScanResult> (flutter_blue_plus type)
});

// Connect
final device = await sdk.connectDevice(results.first.device);

// Basic info
await device.syncTime();
final battery = await device.getCBC();          // BatteryInfo
final capacity = await device.getDeviceCapacity();
final version = await device.getDeviceVersion();

// Recording
await device.startRecord();
await device.stopRecord();

// Files
final files = await device.getRecordFileList(); // List<PenFile>
await device.startGetFile(files.first.name);    // streamed via fileDataStream
await device.delAllFileData();

// Disconnect
await device.closeConnect();
```

## API reference

### AudioPenSdk — scanning & connection entry point

| Method / property | Returns | Description |
|------|------|------|
| `AudioPenSdk({debugLog = true})` | — | Entry point; `debugLog` toggles scan/GATT/raw-byte logging |
| `isBluetoothOn` | `Future<bool>` | Whether Bluetooth is supported and turned on |
| `adapterState` | `Stream<BluetoothAdapterState>` | Adapter state stream (on/off/turning on/…) |
| `startSearch({timeout = 15s})` | `Stream<List<ScanResult>>` | Scan filtered by service `0xAE20`; emits **cumulative** result lists, stops automatically on timeout. `ScanResult` is a flutter_blue_plus type |
| `scanAll({timeout = 15s})` | `Stream<List<ScanResult>>` | Unfiltered scan of all nearby BLE devices (for debugging "cannot find device") |
| `stopSearch()` | `Future<void>` | Stop scanning |
| `connectDevice(device)` | `Future<AudioPenDevice>` | Connect to a `ScanResult.device`, returns a device session |
| `connectDeviceAndAddress(name, address)` | `Future<AudioPenDevice>` | Reconnect by name + address: matches the current scan cache first, then falls back to connecting by address directly (works even if the device is not advertising — ideal for last-session reconnect) |

### AudioPenDevice · connection & state

| Method / property | Returns | Description |
|------|------|------|
| `name` | `String` | Device name |
| `id` | `String` | Device ID (the MAC address) |
| `isDeviceConnected` | `bool` | Whether currently connected |
| `connectionState` | `Stream<TransportState>` | Connection state stream: `disconnected` / `connecting` / `connected` |
| `closeConnect()` | `Future<void>` | Disconnect and release all resources |
| `debugLog` (get/set), `setShowLog(bool)` | — | Runtime switch for raw-byte/GATT logging |

### Device info

| Method | Returns | Description |
|------|------|------|
| `syncTime([time])` | `Future<void>` | Sync time to the device (defaults to now) |
| `getCBC()` | `Future<BatteryInfo>` | Battery: `percent` (0–100), `charging` |
| `getDeviceCapacity()` | `Future<Capacity>` | Storage: `freeKb` / `totalKb` / `usedKb` (KB) |
| `getDeviceVersion()` | `Future<String>` | Firmware version string (e.g. `"1.2.23"`) |
| `getSn()` | `Future<String>` | SN — the protocol has no SN command, MAC is returned instead |

### Recording control

| Method | Returns | Description |
|------|------|------|
| `startRecord()` | `Future<bool>` | Start recording; the device then pushes the realtime opus stream automatically (see `recordDataStream`) |
| `stopRecord()` | `Future<bool>` | Stop and save; the command is **sent twice** to guarantee delivery, and the audio-stream gate is closed |
| `pauseRecord()` / `continueRecord()` | `Future<bool>` | Pause / resume recording |
| `getRecordState()` | `Future<RecordState>` | Query recording state: `idle` / `recording` / `paused` / `unknown` |

### File management

| Method | Returns | Description |
|------|------|------|
| `getRecordFileList()` | `Future<List<PenFile>>` | File list; multi-frame replies are accumulated automatically. `PenFile`: `name`, `sizeBytes`, `durationSec`, `isCall` (call recording) |
| `startGetFile(name, {offset = 0})` | `Future<FileDownloadResult>` | Download a whole file; pass bytes already received as `offset` to resume |
| `startGetFileByFromToEnd(name, {offset, end})` | `Future<FileDownloadResult>` | Download the byte range `[offset, end)` |
| `stopGetFile([fileName])` | `Future<void>` | Abort the current download (`fileName` kept only for iOS-parity, optional) |
| `delFileData(name)` | `Future<bool>` | Delete one file, returns success |
| `delAllFileData()` | `Future<bool>` | Delete all files, returns success |

`FileDownloadResult`: `endCode` (`completed` / `notFound` / `offsetTooLarge` / `other`), `fileName` (name echoed by the device), `receivedBytes`, `success`.

### Streams

| Stream | Type | Description |
|------|------|------|
| `statusStream` | `Stream<DeviceMode>` | Device mode state (1-byte bitmask): `recording` / `playing` / `usbMode` / `realtimeAsr` / `importing` / `playPaused` / `busy` |
| `keyEventStream` | `Stream<Frame>` | Physical key events: cmd `1` start / `3` save / `5` pause / `7` resume. Per the protocol, on receiving 1/3 the app should send the corresponding record command back (see the example app) |
| `deviceRecordStream` | `Stream<int>` | Device-side physical pause/resume/stop: `0` stop / `2` pause / `3` resume |
| `recordDataStream` | `Stream<Uint8List>` | Realtime recording opus raw bytes (40 B/frame = 20 ms @16 kbps; trailing partial frames are dropped); produced only while recording |
| `fileDataStream` | `Stream<Uint8List>` | Every file chunk pushed by the device during a download |
| `downloadProgressStream` | `Stream<int>` | Download progress (cumulative bytes received) |
| `appEventStream` | `Stream<String>` | Unified app JSON event stream (key/mode/device-side events merged; format below) |
| `debugLogStream` | `Stream<String>` | Low-level debug log lines (when `debugLog` is on) |
| `rawFrameStream` | `Stream<Frame>` | All successfully parsed raw frames (debugging) |

### AppJson compatibility layer (×11)

Emits JSON events byte-for-byte identical to the iOS SDK, so apps migrating from the native SDK switch **without code changes**. Unified format:

```json
{"cmd":"<id>","state":"0","data":{ ... }}
```

(All values inside `data` are serialized as strings, matching the iOS SDK.)

| Method | cmd | Event |
|------|------|------|
| `getCBCAppJson()` | 6 | Battery: `{"cbc":"95"}` |
| `getSnAppJson()` | 7 | SN / MAC |
| `startRecordAppJson()` / `stopRecordAppJson()` / `pauseRecordAppJson()` / `continueRecordAppJson()` | 3 | Recording control results (`record_state`: `1` recording / `0` stopped / `2` paused) |
| `getRecordFileListAppJson()` | 4 | File list (with duration/size) |
| `getDeviceCapacityAppJson()` | 13 | Storage |
| `delAllFileDataAppJson()` | 14 | Delete-all result (`delete_state`: `0` ok / `1` failed) |
| `getRecordStateAppJson()` | 9 | Recording state query result |
| `getDeviceVersionAppJson()` | 17 | Firmware version |

### Protocol cmd cheat sheet

The frame body is `dataType(1B) | cmd(1B) | params`; frames carry a `0x5A` magic header + CRC-16/XMODEM (little-endian length). Every device data frame must be ACKed with the same sequence number (`dataType=3`, no cmd) — **handled automatically by the SDK**. Direction: `↓` app→device, `↑` device→app.

**Control channel (dataType = 0)**

| cmd | Dir | Meaning | Body / reply format |
|----|----|------|------|
| 0 | ↓ | Sync time | 7 B: year(2 B LE)/month/day/hour/min/sec |
| 1 / 2 | ↓ / ↑ | Get storage / reply | Reply 8 B: free(4 B) + total(4 B), KB, little-endian |
| 3 / 4 | ↓ / ↑ | Get battery / reply | Reply 1 B: `0–100` level; `110` = charging |
| 10 / 11 | ↓ / ↑ | Get firmware version / reply | Reply string, e.g. `"1.2.23"` |
| 12 / 13 | ↓ / ↑ | Get MAC / reply | Reply string (colon-separated, may carry an `s` prefix) |
| 14 | ↑ | Device mode state (unsolicited) | 1 B bitmask: bit0 playing / bit1 recording / bit2 USB / bit3 realtime ASR / bit4 importing / bit5 play-paused / bit6 busy |
| 18 | ↓ | App foreground/background | 1 B: `1` foreground / `2` background |

**Audio channel (dataType = 1 — recording control & realtime stream)**

| cmd | Dir | Meaning | Body |
|----|----|------|------|
| 0x00 | ↓ | Start recording | `01 00` (device then pushes opus frames automatically) |
| 0x01 | ↑ | Realtime opus audio frame | 40 B/frame (20 ms @16 kbps, mono); passed through as `recordDataStream` |
| 0x02 | ↓ | Stop (save) recording | `01 02`, sent twice to guarantee delivery; device stops streaming |
| 0x03 | ↓ | Pause / resume | `01 03 01` pause / `01 03 00` resume |
| 0x04 | ↑ | Device-side physical pause/resume/stop | 1 B flag: `2` stop / `1` pause / `0` resume (mapped to 0/2/3 on `deviceRecordStream`) |

**File channel (dataType = 2)**

| cmd | Dir | Meaning | Body / reply |
|----|----|------|------|
| 0 / 1 / 18 | ↓ / ↑ / ↑ | Get file list / list frames (**multi-frame**) / list done | Each frame: count/records; the SDK accumulates until cmd=18. Record layout: duration(4 B BE) + size(4 B BE) + name (variable length, `.`-terminated) |
| 2 | ↓ | Download file (resumable) | offset(4 B LE) + name; pass bytes received so far to resume |
| 12 | ↓ | Range download | offset(4 B LE) + end(4 B LE) + name, fetches `[offset, end)` |
| 3 / 4 | ↑ / ↑ | File start / file data chunk | cmd 3 echoes the current file name; cmd 4 is file bytes (`fileDataStream`) |
| 5 | ↑ | Current file end | 1 B end code: `0` completed / `1` not found / `2` offset too large / `3` other stop |
| 6 | ↑ | All files end | — |
| 7 | ↓ | Abort download | Device stops streaming |
| 8 / 13 | ↓ / ↑ | Delete file(s) / result | Request: 4 B padding + name; reply 1 B: `0` ok / `1` failed |
| 9 / 10 | ↓ / ↑ | Delete all / result | Reply 1 B: `0` ok / `1` failed |

**Key channel (dataType = 3 — same value as ACK: no cmd means an ACK frame)**

| cmd | Dir | Meaning | Notes |
|----|----|------|------|
| 1 | ↑ | User pressed the physical "start" key | Odd cmds are device notifications; on 1/3 the app should reply with the matching record command (iOS parity) |
| 3 | ↑ | User pressed the physical "save" key | Same as above |
| 5 / 7 | ↑ | Physical "pause" / "resume" key | Same as above |
| 2 / 4 / 6 / 8 | ↓ | App-initiated start/save/pause/resume | Device replies with the **same cmd**, 1 B: `1` ok / `2` failed |
| 19 / 20 | ↓ / ↑ | Query recording state / reply | Reply 1 B: `1` recording / `2` idle |

For the full frame layout (magic/length/CRC byte order), calibration notes and on-device test records, see [ARCHITECTURE.md](ARCHITECTURE.md) (Chinese).

## Notes

- **BLE requires a real device**: emulators have no Bluetooth; scan results will always be empty.
- Debug switches: `AudioPenSdk(debugLog: true)` prints scan/GATT/raw-byte logs (`[BLE-SCAN]` prefixes); after connecting, turn it off with `device.debugLog = false`; `sdk.scanAll()` scans unfiltered to troubleshoot advertising issues.
- The protocol layer (frame codec / CRC / reply parsing) has no Bluetooth dependency and is unit-testable offline (`flutter test`, 51 cases).

## License

MIT — see [LICENSE](LICENSE).
