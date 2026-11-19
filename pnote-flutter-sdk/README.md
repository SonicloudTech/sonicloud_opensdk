# pnote_flutter_sdk（lite 精简版）

[English](./README.en.md) | 简体中文

声云录音笔 BLE Flutter 插件 **lite 精简版** —— 纯 Dart 实现，基于 flutter_blue_plus，不依赖原生 SDK。

## 功能一览

| 能力 | 说明 |
|------|------|
| 扫描 / 连接 | 按 0xAE20 服务过滤；支持按名+地址重连（`connectDeviceAndAddress`） |
| 设备信息 | 时间同步 / 电量 / 容量 / 固件版本 / MAC |
| 录音控制 | 开始 / 停止 / 暂停 / 继续 / 状态查询；接收设备端物理按键与暂停继续事件 |
| 实时音频流 | 录音时设备自动下发 opus 原始帧（`recordDataStream`），供实时转写 / 监听消费 |
| 文件管理 | 列表 / 下载（断点续传、区间分段）/ 删除单个 / 删除全部 |
| AppJson 兼容层 | 产出与 iOS/Android 端 SDK 完全一致的 JSON 事件（`getCBCAppJson()` 等 ×11） |

## 快速上手

### 1. 添加依赖

```yaml
dependencies:
  pnote_flutter_sdk:
    git:
      url: https://github.com/SonicloudTech/sonicloud_opensdk.git
      path: pnote-flutter-sdk
```

### 2. 配置权限

**Android** `AndroidManifest.xml`：

```xml
<uses-permission android:name="android.permission.BLUETOOTH_SCAN"
    android:usesPermissionFlags="neverForLocation" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<!-- Android 11 及以下 -->
<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
```

**iOS** `Info.plist`：

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>用于连接录音笔</string>
```

运行时权限需在 App 内动态申请（示例工程依赖系统弹窗，正式接入建议用 permission_handler）。

### 3. 使用

```dart
final sdk = AudioPenSdk();

// 扫描（按 0xAE20 过滤）
sdk.startSearch().listen((results) {
  // results: List<ScanResult>（flutter_blue_plus 类型）
});

// 连接
final device = await sdk.connectDevice(results.first.device);

// 基础信息
await device.syncTime();
final battery = await device.getCBC();          // BatteryInfo
final capacity = await device.getDeviceCapacity();
final version = await device.getDeviceVersion();

// 录音
await device.startRecord();
await device.stopRecord();

// 文件
final files = await device.getRecordFileList(); // List<PenFile>
await device.startGetFile(files.first.name);    // 经 fileDataStream 推流
await device.delAllFileData();

// 断开
await device.closeConnect();
```

## API 参考

### AudioPenSdk —— 扫描与连接入口

| 方法 / 属性 | 返回 | 说明 |
|------|------|------|
| `AudioPenSdk({debugLog = true})` | — | 构造入口；`debugLog` 控制扫描/GATT/原始字节日志打印 |
| `isBluetoothOn` | `Future<bool>` | 蓝牙是否可用且已开启 |
| `adapterState` | `Stream<BluetoothAdapterState>` | 蓝牙适配器状态流（开启/关闭/开启中等） |
| `startSearch({timeout = 15s})` | `Stream<List<ScanResult>>` | 扫描（按 0xAE20 服务过滤）；结果为**累计列表**流，超时自动停止。`ScanResult` 为 flutter_blue_plus 类型 |
| `scanAll({timeout = 15s})` | `Stream<List<ScanResult>>` | 不过滤扫描周围全部 BLE 设备（排查"扫不到设备"时用） |
| `stopSearch()` | `Future<void>` | 停止扫描 |
| `connectDevice(device)` | `Future<AudioPenDevice>` | 连接 `ScanResult.device`，返回设备会话对象 |
| `connectDeviceAndAddress(name, address)` | `Future<AudioPenDevice>` | 按名+地址重连：先匹配本次扫描缓存，未命中则按地址直连（设备未在广播也能发起，适合上次会话重连） |

### AudioPenDevice · 连接与状态

| 方法 / 属性 | 返回 | 说明 |
|------|------|------|
| `name` | `String` | 设备名称 |
| `id` | `String` | 设备 ID（即 MAC 地址） |
| `isDeviceConnected` | `bool` | 当前是否已连接 |
| `connectionState` | `Stream<TransportState>` | 连接状态流：`disconnected` / `connecting` / `connected` |
| `closeConnect()` | `Future<void>` | 断开连接并释放全部资源 |
| `debugLog`（get/set）、`setShowLog(bool)` | — | 运行时开关原始字节/GATT 日志 |

### 设备信息

| 方法 | 返回 | 说明 |
|------|------|------|
| `syncTime([time])` | `Future<void>` | 同步时间到设备（默认取当前时间） |
| `getCBC()` | `Future<BatteryInfo>` | 电量：`percent`（0~100）、`charging`（充电中） |
| `getDeviceCapacity()` | `Future<Capacity>` | 容量：`freeKb` / `totalKb` / `usedKb`（单位 KB） |
| `getDeviceVersion()` | `Future<String>` | 固件版本号（如 `"1.2.23"`） |
| `getSn()` | `Future<String>` | SN——协议无独立 SN 指令，底层用 MAC 代替 |

### 录音控制

| 方法 | 返回 | 说明 |
|------|------|------|
| `startRecord()` | `Future<bool>` | 开始录音；设备随即自动下发实时 opus 流（见 `recordDataStream`） |
| `stopRecord()` | `Future<bool>` | 停止并保存录音；内部**连发两次**确保到达，同时关闭音频流门控 |
| `pauseRecord()` / `continueRecord()` | `Future<bool>` | 暂停 / 继续录音 |
| `getRecordState()` | `Future<RecordState>` | 查询录音状态：`idle` / `recording` / `paused` / `unknown` |

### 文件管理

| 方法 | 返回 | 说明 |
|------|------|------|
| `getRecordFileList()` | `Future<List<PenFile>>` | 文件列表；设备分多帧上报，内部自动累积。`PenFile`：`name`（文件名）、`sizeBytes`、`durationSec`、`isCall`（是否通话录音） |
| `startGetFile(name, {offset = 0})` | `Future<FileDownloadResult>` | 下载整个文件；`offset` 传已收字节数即断点续传 |
| `startGetFileByFromToEnd(name, {offset, end})` | `Future<FileDownloadResult>` | 分段下载 `[offset, end)` 字节区间 |
| `stopGetFile([fileName])` | `Future<void>` | 终止当前下载（`fileName` 仅为对齐 iOS 端签名保留，可不传） |
| `delFileData(name)` | `Future<bool>` | 删除单个文件，返回是否成功 |
| `delAllFileData()` | `Future<bool>` | 删除全部文件，返回是否成功 |

下载结果 `FileDownloadResult`：`endCode`（`completed` / `notFound` / `offsetTooLarge` / `other`）、`fileName`（设备回带的当前文件名）、`receivedBytes`（实收字节数）、`success`（是否完整收齐）。

### 数据流（Stream）

| 流 | 类型 | 说明 |
|------|------|------|
| `statusStream` | `Stream<DeviceMode>` | 设备模式状态（1B 位掩码）：`recording` / `playing` / `usbMode` / `realtimeAsr` / `importing` / `playPaused` / `busy` |
| `keyEventStream` | `Stream<Frame>` | 机身物理按键事件：cmd `1` 开始 / `3` 保存 / `5` 暂停 / `7` 继续。按协议约定，收到 1/3 时 App 应回发对应录音指令（见 example 的处理方式） |
| `deviceRecordStream` | `Stream<int>` | 设备端物理暂停/继续/停止：`0` 停止 / `2` 暂停 / `3` 继续 |
| `recordDataStream` | `Stream<Uint8List>` | 实时录音 opus 原始字节流（40B/帧 = 20ms @16kbps，尾帧不足整帧自动丢弃）；仅在录音期间产出，停止录音即停 |
| `fileDataStream` | `Stream<Uint8List>` | 下载期间设备推送的每一块文件字节 |
| `downloadProgressStream` | `Stream<int>` | 下载进度（累计已收字节数） |
| `appEventStream` | `Stream<String>` | App 统一 JSON 事件流（按键/模式/设备端事件合并下发，格式见下方 AppJson） |
| `debugLogStream` | `Stream<String>` | 底层调试日志行（`debugLog` 开启时产出，可上屏显示） |
| `rawFrameStream` | `Stream<Frame>` | 全部解析成功的原始帧（调试用） |

### AppJson 兼容层（×11）

产出与 iOS 端 SDK 完全一致的 JSON 事件，从原生 SDK 迁移的 App **零改动**即可切换。统一格式：

```json
{"cmd":"<编号>","state":"0","data":{ ... }}
```

（`data` 内各值统一序列化为字符串，与 iOS 端行为一致。）

| 方法 | cmd | 事件说明 |
|------|------|------|
| `getCBCAppJson()` | 6 | 电量：`{"cbc":"95"}` |
| `getSnAppJson()` | 7 | SN / MAC |
| `startRecordAppJson()` / `stopRecordAppJson()` / `pauseRecordAppJson()` / `continueRecordAppJson()` | 3 | 录音控制结果（`record_state`：`1` 录音 / `0` 停止 / `2` 暂停） |
| `getRecordFileListAppJson()` | 4 | 文件列表（含时长/大小） |
| `getDeviceCapacityAppJson()` | 13 | 容量 |
| `delAllFileDataAppJson()` | 14 | 全部删除结果（`delete_state`：`0` 成功 / `1` 失败） |
| `getRecordStateAppJson()` | 9 | 录音状态查询结果 |
| `getDeviceVersionAppJson()` | 17 | 固件版本 |

### 协议 cmd 速查

帧数据体统一为 `数据类型(1B) | cmd(1B) | 参数`；帧层带魔数 0x5A 头 + CRC16-XMODEM 校验（小端长度）。App 收到设备数据帧需回相同包序号的 ACK（`dataType=3` 无 cmd），**SDK 内部已自动处理**。下表方向：`↓` App→设备，`↑` 设备→App。

**控制通道（dataType = 0）**

| cmd | 方向 | 含义 | 数据体 / 响应格式 |
|----|----|------|------|
| 0 | ↓ | 同步时间 | 7B：年(2B 小端)/月/日/时/分/秒 |
| 1 / 2 | ↓ / ↑ | 查容量 / 容量回包 | 回包 8B：剩余(4B) + 总量(4B)，KB，小端 |
| 3 / 4 | ↓ / ↑ | 查电量 / 电量回包 | 回包 1B：`0~100` 电量；`110` 充电中 |
| 10 / 11 | ↓ / ↑ | 查固件版本 / 版本回包 | 回包字符串，如 `"1.2.23"` |
| 12 / 13 | ↓ / ↑ | 查 MAC / MAC 回包 | 回包字符串（带冒号，可能带 `s` 前缀） |
| 14 | ↑ | 设备模式状态（主动上报） | 1B 位掩码：bit0 播放 / bit1 录音 / bit2 USB / bit3 实时转写 / bit4 导入 / bit5 播放暂停 / bit6 忙 |
| 18 | ↓ | App 前后台状态 | 1B：`1` 前台 / `2` 后台 |

**音频通道（dataType = 1，录音控制与实时流）**

| cmd | 方向 | 含义 | 数据体 |
|----|----|------|------|
| 0x00 | ↓ | 开始录音 | `01 00`（发后设备自动持续下发 opus 流） |
| 0x01 | ↑ | 实时 opus 音频帧 | 每帧 40B（20ms @16kbps，单声道）；SDK 经 `recordDataStream` 透传 |
| 0x02 | ↓ | 停止（保存）录音 | `01 02`，连发两次确保到达；设备即停止推流 |
| 0x03 | ↓ | 暂停 / 继续 | `01 03 01` 暂停 / `01 03 00` 继续 |
| 0x04 | ↑ | 设备端物理暂停/继续/停止 | 1B flag：`2` 停止 / `1` 暂停 / `0` 继续（SDK 映射为 0/2/3 发 `deviceRecordStream`） |

**文件通道（dataType = 2）**

| cmd | 方向 | 含义 | 数据体 / 响应 |
|----|----|------|------|
| 0 / 1 / 18 | ↓ / ↑ / ↑ | 取文件列表 / 列表帧（**多帧**） / 列表结束 | 每帧 N 条记录：时长(4B 大端)+大小(4B 大端)+文件名（变长，以 `.` 结尾）；SDK 自动累积成完整列表 |
| 2 | ↓ | 下载文件（断点续传） | offset(4B 小端) + 文件名；offset 传已收字节数即续传 |
| 12 | ↓ | 分段下载 | offset(4B 小端) + end(4B 小端) + 文件名，取 `[offset, end)` 区间 |
| 3 / 4 | ↑ / ↑ | 文件开始 / 文件数据块 | cmd3 回带当前文件名；cmd4 为文件字节（经 `fileDataStream`） |
| 5 | ↑ | 当前文件结束 | 1B 结束码：`0` 完成 / `1` 文件不存在 / `2` offset 过大 / `3` 其他停止 |
| 6 | ↑ | 全部文件结束 | — |
| 7 | ↓ | 终止下载 | 设备停止推流 |
| 8 / 13 | ↓ / ↑ | 删除文件（1 个或多个）/ 删除结果 | 请求 4B padding + 文件名；回包 1B：`0` 成功 / `1` 失败 |
| 9 / 10 | ↓ / ↑ | 删除全部 / 结果 | 回包 1B：`0` 成功 / `1` 失败 |

**按键通道（dataType = 3，与 ACK 同值——无 cmd 即 ACK 帧）**

| cmd | 方向 | 含义 | 说明 |
|----|----|------|------|
| 1 | ↑ | 用户按下「开始录音」物理键 | 奇数 cmd 均为设备通知；App 收到 1/3 应回发对应录音指令（对齐 iOS 行为） |
| 3 | ↑ | 用户按下「保存录音」物理键 | 同上 |
| 5 / 7 | ↑ | 按下「暂停」/「继续」物理键 | 同上 |
| 2 / 4 / 6 / 8 | ↓ | App 主动开始/保存/暂停/继续录音 | 设备用**同一 cmd** 回 1B 结果：`1` 成功 / `2` 失败 |
| 19 / 20 | ↓ / ↑ | 查录音状态 / 回包 | 回包 1B：`1` 在录音 / `2` 不在录音 |

完整帧格式（魔数/长度/CRC 字节布局）、字节序校准点与真机验证记录见 [ARCHITECTURE.md](ARCHITECTURE.md)。

## 注意事项

- **BLE 必须真机调试**：模拟器无蓝牙，扫描列表恒空。
- 调试开关：`AudioPenSdk(debugLog: true)` 打印扫描/GATT/原始字节日志（`[BLE-SCAN]` 等前缀）；连接后可用 `device.debugLog = false` 关闭；`sdk.scanAll()` 可不过滤扫描排查广播问题。
- 协议层（帧编解码 / CRC / 回包解析）无蓝牙依赖，可离线单元测试（`flutter test`，51 个用例）。

## License

MIT（见 [LICENSE](LICENSE)）。
