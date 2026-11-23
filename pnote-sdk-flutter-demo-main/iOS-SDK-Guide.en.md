# Soni iOS SDK Development Guide

[iOS SDK 中文文档](<iOS SDK开发文档.md>) · [Android SDK guide](Android-SDK-Guide.en.md) · [Demo README](README.en.md)

## Integrate and initialize the SDK

Add [`libPNote.a`](ios/Runner/sonilib/libPNote.a) to your Xcode app target under **Build Phases → Link Binary With Libraries**, and make [`PNode.h`](ios/Runner/sonilib/PNode.h) available to the target. Import the header in Objective-C or from your app's bridging header for Swift. [Demo bridging header](ios/Runner/Runner-Bridging-Header.h)

Implement `WindBleDelegate` and assign an instance to the `delegate` of `[PNode Shared]` before issuing commands. The SDK holds the delegate weakly, so keep it alive in your app. In Swift, the demo assigns `PNode.shared().delegate = self` in `AppDelegate`.

| Delegate method | Payload |
| --- | --- |
| `deviceDataEvent:(NSString *)data` | JSON command results and unsolicited device events |
| `deviceRecordData:(NSData *)recordData` | Live recording audio |
| `deviceFileData:(NSData *)fileData` | Audio from a recorder file transfer |
| `logInfo:(NSString *)log` | SDK log text |

Add the Bluetooth and local network usage descriptions for the features you use. The demo also declares location usage for Wi-Fi information. [Demo Info.plist](ios/Runner/Info.plist)

### Event format

Device events are asynchronous. Use `cmd` to dispatch each event. The top-level `state` is typically `0` for a normal response and nonzero for an error. Check any command-specific field in `data` to confirm the device operation succeeded.

```json
{
  "cmd": "2",
  "state": "0",
  "data": {
    "connect_state": "1",
    "name": "Soni Recorder",
    "address": "00000000-0000-4000-8000-000000000001"
  }
}
```

The API names below are Objective-C instance methods on `[PNode Shared]`. See the [iOS bridge](ios/Runner/AppDelegate.swift) for usage from Swift.

## Discover and connect to a recorder

| Operation | API | Event and fields |
| --- | --- | --- |
| Start scanning | `startSearch` | `cmd=1`: `name`, `address`, `productType` |
| Stop scanning | `stopSearch` | |
| Connect | `connectDeviceAndAddress:(NSString *)deviceName :(NSString *)address` | `cmd=2`: `connect_state`, `name`, `address` |
| Check the connection | `isDeviceConnected` | Returns `BOOL` synchronously |
| Disconnect | `closeConnect` | `cmd=2` |

Use the name and address from the scan event. The SDK also exposes `connectDevice:(NSString *)name` for connection by name. In the connection event, `connect_state` is `1` for connected and `0` for disconnected. The SDK also reports unexpected disconnects, such as when the recorder is powered off. Synchronize the recorder clock after connecting. See [Device information and settings](#device-information-and-settings).

### AuthKey authentication and binding

On models that support AuthKey, connect over Bluetooth first. Pass the device's current AuthKey to `authkeyConnect:`, then wait for `cmd=31` and confirm the authentication result before issuing commands that require authentication.

The key is 64 hexadecimal characters (32 bytes). Either letter case is accepted, with optional surrounding whitespace and an optional `0x` or `0X` prefix. The prefix is excluded from the 64-character count. Validate the key before calling. The SDK sends no command for an invalid key, so there is no device response for that input.

| API | Event | Effect |
| --- | --- | --- |
| `authkeyConnect:(NSString *)authkey` | `cmd=31` | Authenticate with the current key |
| `resetAuthkey:(NSString *)authkey` | `cmd=32` | Set a new key after authenticating with the current key |
| `unbondAuthkey` | `cmd=33` | Remove the binding and restore the factory key after authenticating |

All three events report `data.authkey_state` as a decimal string. Use the recorder's firmware protocol to interpret the operation result. Once the device confirms a key change or unbinding, use the new key or factory key for subsequent authentication. Method names are case-sensitive.

### Device name and factory reset

| API | Event and fields |
| --- | --- |
| `setDeviceName:(NSString *)name` | `cmd=25`: `device_name_state` |
| `resetDeviceName` | `cmd=26`: `device_name_state` |
| `restDevice` | `cmd=35`: `reset_device_state` |

Validate device names as 2–16 ASCII letters or digits (`[A-Za-z0-9]`). The name reset restores the factory name. The device reset restores factory settings, deletes recordings, and reboots the device. In both result fields, `0` means success and `1` means failure. Wait for the event to confirm the outcome.

## Recording

| Operation | API | Event and fields |
| --- | --- | --- |
| Start recording | `startRecord` or `startRecord:(NSInteger)boneMic` on L09 | `cmd=3`: `record_state`, `fileName` |
| Pause recording | `pauseRecord` | `cmd=3` |
| Resume recording | `continueRecord` | `cmd=3` |
| Stop recording | `stopRecord` | `cmd=3` |
| Query recording status | `getRecordState` | `cmd=9`: `recordState` is `1` while recording and `2` otherwise |
| Query elapsed recording time | `getTimeOnlyRecording` | `cmd=10`: `recordTime` in seconds |
| Query the current recording filename | `getFileNameOnlyRecording` | `cmd=11`: `recordName` |

For `cmd=3`, `record_state` is `0` for idle or stopped, `1` for recording, and `2` for paused. `deviceRecordData:` delivers live audio. The documented Opus format is 16 kHz mono with 40 bytes per frame.

On L09, pass `0` to `startRecord:` for the digital microphone or `1` for the bone-conduction microphone. The SDK sends no recording command for other values.

```objective-c
[[PNode Shared] startRecord:0]; // Digital microphone
```

In Swift, use `PNode.shared().startRecord(0)`.

### Recorder button requests

Call `sendAppShowState:(int)state` when the app lifecycle changes. Pass `1` on entering the foreground and `2` on entering the background. While connected, the recorder can request a recording action through `cmd=8`. After handling the request in the app, call the matching acknowledgement so the recorder can proceed.

| `data.event` | Request | Acknowledgement |
| --- | --- | --- |
| `1` | Start | `startBtnBackRecord` |
| `3` | Stop and save | `stopBtnBackRecord` |
| `5` | Pause | `pauseBtnBackRecord` |
| `7` | Resume | `continueBtnBackRecord` |

## Recording files

| Operation | API | Event |
| --- | --- | --- |
| List recordings | `getRecordFileList` | `cmd=4` |
| Download from an offset | `startGetFile:(NSString *)fileName :(NSString *)offset` | `cmd=5` |
| Download a range | `startGetFileByFromToEnd:(NSString *)fileName :(NSString *)offset :(NSString *)end` | `cmd=5` |
| Stop a download | `stopGetFile:(NSString *)fileName` | `cmd=5` |
| Delete one recording | `delFileData:(NSString *)fileName` | `cmd=14` |
| Delete all recordings | `delAllFileData` | `cmd=14` |

- **`cmd=4`.** Each item in the `data` array contains `name`, `size` (bytes), and `time` (seconds). Collect items across callbacks until the top-level `finish` is `1`. A value of `0` means more list data is pending.
- **`cmd=5`.** Read the file name from `data.name`. `record_file_state` is `0` for complete, `1` for file missing, `2` for offset too large (reserved), `3` for another stop condition, and `4` for in progress. Receive audio bytes through `deviceFileData:`.
- **`cmd=14`.** `data.delete_state` is `0` for success or `1` for failure.

Pass a nonempty filename. Pass offsets as decimal strings. Use `@"0"` to download from the beginning. For range downloads, the numeric value of `end` must be greater than `offset`.

### Offline file transfer interval

After connecting over Bluetooth, call `sendFileTimeInterval:(uint8_t)interval` to set the spacing between device packets in milliseconds. The demo accepts `13–255` ms. Validate the integer before converting it to `uint8_t` in Objective-C or `UInt8` in Swift.

```objective-c
[[PNode Shared] sendFileTimeInterval:20];
```

The device reports `cmd=100`. `data.offline_transfer_interval_state` is `0` for success and `1` for failure.

## Wi-Fi

Use quick connect to open the recorder hotspot and connect to it.

| API | Operation |
| --- | --- |
| `openWiFi` / `closeWiFi` | Open or close the recorder hotspot |
| `getWiFiHotspotState` | Check whether a phone has joined the hotspot |
| `connectDeviceWiFi` / `disconnectDeviceWiFi` | Initiate or close the connection to the recorder over Wi-Fi |
| `getDeviceWiFiState` | Query the recorder's TCP connection status |

These methods report through `cmd=12` with `data.wifi_state` and `data.wifiName`. The recorder can also send this event when a phone joins its hotspot. The [README status table](README.en.md#wi-fi-status-codes) lists all six values. Wait for `wifi_state=2` before starting a Wi-Fi transfer or UFW update.

### Quick connect to the recorder hotspot

To disconnect from Wi-Fi, or if quick connect fails, call `disconnectDeviceWiFi` and then `closeWiFi`.

Keep Bluetooth connected and finish AuthKey authentication first on models that require it. Quick connect opens the device hotspot, joins it, and establishes TCP. Enable **Hotspot Configuration** under the app target's Signing & Capabilities. Use signing and a provisioning profile that support `com.apple.developer.networking.HotspotConfiguration`. Keep the app in the foreground and handle any iOS network-join confirmation.

```objective-c
[[PNode Shared] quickConnectDeviceWiFiWithWiFiTimeout:30 tcpTimeout:10 password:@"12345678"];
[[PNode Shared] quickConnectDeviceWiFiWithWiFiTimeout:30 tcpTimeout:10 password:@""];
```

Choose the call that matches the device hotspot. Pass its current password, or use `@""` or `nil` for an open hotspot. `wifiTimeout` is the total connection timeout in seconds. `tcpTimeout` is the timeout in seconds for one TCP attempt. Nonpositive values use defaults of 30 and 10 seconds, respectively. Set the total timeout above the per-attempt timeout.

### Set the recorder hotspot password

With Bluetooth connected, call `setWifiPassword:(NSString *)password` on supported models. The password must contain 8–16 characters. An invalid password is rejected before a command is sent. The result is sent as `cmd=34` with `data.wifi_password_state`, a decimal string defined by the recorder firmware. After confirmed success, the new password takes effect on the next hotspot start.

### Configure Wi-Fi Direct upload

These settings let a supported recorder join an external Wi-Fi network and upload audio to a server. Keep Bluetooth connected while configuring the device. Supply SSID, password, and upload URL as UTF-8 strings of at most 65,535 bytes each.

| API | Event and fields |
| --- | --- |
| `setWiFiDirectSSID:(NSString *)ssid password:(NSString *)password` | `cmd=27`: `wifi_direct_state` |
| `setRemoteURL:(NSString *)remoteURL` | `cmd=28`: `wifi_direct_state` |
| `resetWiFiDirect` | `cmd=29`: empty `data` object |
| `getWiFiDirect` | `cmd=30`: `ssid` and connection `status` |

For `cmd=27` and `cmd=28`, `wifi_direct_state` is `0` for success and `1` for failure. For `cmd=30`, `status` is `0` for a successful connection or `1` for a failed connection. Query the status after setting the parameters to confirm that the recorder connected.

## Firmware updates

### UFW OTA

1. Confirm the battery is above 20% and the recorder has an active TCP connection (`wifi_state=2`).
2. Call `getDeviceVersionCode` and read `data.versionCode` from `cmd=18`. It is a string such as `"0001"`. Continue if the target firmware version code is newer than the installed one.
3. Call `requestDeviceGotoOtaMode` and wait for `cmd=19`. Read `data.prepareState`. Values `0` and `3` mean the device can enter OTA mode. Value `1` means it cannot enter, for example because the SD card or storage is unavailable or full. Value `2` means the TCP connection is missing.
4. Pass the entire UFW firmware file to `sendOtaFile:(NSData *)data` in one call. The SDK splits it into packets. Track bytes sent and total bytes in `data.progress` and `data.total` from `cmd=20`. If Bluetooth or Wi-Fi disconnects during transfer, the recorder exits OTA mode.
5. Wait for `cmd=21`. `data.receiveState=0` means the recorder received the file and is preparing to restart. A value of `1` means the file was rejected. After restart, reconnect over Bluetooth and call `getDeviceVersionCode` again. Compare the returned code with the target to verify the update.

### BK OTA

Call `getBKHDVersion` and compare the installed BK firmware version with the target version. To update, host the firmware at an HTTP or HTTPS URL that the recorder can reach. The response must include `Content-Length`. Pass the URL to `setBKUpgradeHD:(NSString *)url`. If the filename contains special characters, percent-encode the filename component of the path and pass the full URL as a normal URL.

BK events use `cmd=40` or `cmd=41`. A raw `cmd=40` event can carry `data.log`. For structured events, read `data.type` and `data.value`.

| Type | Meaning of `value` |
| --- | --- |
| `01` | BK firmware version |
| `08` | URL accepted (`0`) or rejected (`1`) |
| `09` | Download progress (`0–100`) |
| `0A` | Firmware validation passed (`0`) or failed (`1`) |

The demo accepts events from either command ID and verifies the resulting firmware version after a successful validation.

## Device heartbeat

Keep Bluetooth connected to a JieLi recorder that supports the heartbeat protocol. Call `setHeartbeatDataState:(int)state` with `1` to enable device heartbeats or `0` to disable them. Other values throw `NSInvalidArgumentException`.

| Direction | Protocol command | Event or action |
| --- | --- | --- |
| Recorder to app | `0x32` | `cmd=101`, the recorder sent a heartbeat |
| App to recorder | `0x33` | Call `sendBackHeartbeatData` to reply |
| App to recorder | `0x34` | Call `setHeartbeatDataState:(int)state` to configure heartbeats |
| Recorder to app | `0x35` | `cmd=102`, the recorder reports the setting |

Reply to a successful `cmd=101` event without waiting for `cmd=102`. This example handles the heartbeat in `WindBleDelegate`.

```objective-c
- (void)deviceDataEvent:(NSString *)data {
    NSData *jsonData = [data dataUsingEncoding:NSUTF8StringEncoding];
    if (!jsonData) return;

    id event = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:NULL];
    if (![event isKindOfClass:[NSDictionary class]]) return;

    if ([[event[@"cmd"] description] isEqualToString:@"101"] &&
        [[event[@"state"] description] isEqualToString:@"0"]) {
        [[PNode Shared] sendBackHeartbeatData];
    }
    // Dispatch other command events here.
}
```

For `cmd=102`, `data.heartbeat_state` is `"00"` when enabled and `"01"` when disabled. Check both `state` and `heartbeat_state`. Some firmware returns an empty `data` object, so handle a missing field. The demo uses the pending setting for an acknowledgement with no reported state and times out after five seconds. Its device heartbeat switch controls what the recorder sends. Its auto-reply switch controls whether the app replies and defaults to on.

## Device information and settings

Call `syncTime` after connecting and again after successful AuthKey authentication. The SDK handles time synchronization for each device model.

| API | Event and fields |
| --- | --- |
| `getCBC` | `cmd=6`: `cbc` is battery percentage (`0–100`) or charging (`110`) |
| `getSn` | `cmd=7`: `sn` is the serial number |
| `getDeviceCapacity` | `cmd=13`: `residueSpace` and `totalSpace` in KB |
| `getDeviceGain` | `cmd=15`: `gain` is `1` for low, `2` for medium, or `3` for high |
| `setDeviceGain:(int)gain` | `cmd=16`: `gain_state` is `0` for success or `1` for failure |
| `getDeviceVersion` | `cmd=17`: `version` is the firmware version string |
| `getDeviceLowPowerRecordMode` | `cmd=22`: `low_power_state` is `0` for off or `1` for on |
| `setDeviceLowPowerRecordMode:(int)state` | Pass `0` to disable or `1` to enable. For `cmd=23`, `low_power_state` is `0` for success or `1` for failure |
