
## 一、概述

`pnote_flutter_sdk` 是一个**纯 Dart + flutter_blue_plus** 实现的声云录音笔 BLE 插件，

- 只做 **BLE**，但帧/CRC/ACK/指令编解码做成与传输无关的核心层，
  后续接 Socket 即可复用（`Transport` 抽象已预留）。
- 能力：扫描 → 连接 → 同步时间 → 电量/容量/版本/MAC → 录音控制（起/停/暂停/继续）→
  实时录音音频流（`recordDataStream`）→ 文件列表 / 下载（续传+分段）/ 删除 → AppJson 兼容层。

## 二、协议要点（来自 PDF）

### BLE GATT（16-bit UUID，运行时转 128-bit `0000aeXX-0000-1000-8000-00805f9b34fb`）
| UUID | 属性 | 用途 |
|------|------|------|
| `0xAE20` | Service | 主服务（扫描过滤） |
| `0xAE21` | WRITE_WITHOUT_RESPONSE | App 写指令 |
| `0xAE22` | NOTIFY | 设备回包主通道 |
| `0xAE23` | NOTIFY | 按键消息 |
| `0xAE24` | WRITE/NOTIFY | OTA（首版未用） |

WiFi 模式（首版未实现）：TCP/IP，设备为 server `192.168.1.1:27689`，复用同一套帧/指令。

### 帧格式
```
魔数(0x5A,1B) | 包序号(1B) | CRC16(2B) | 数据长度(2B) | 数据(nB)
```
- 包序号：0..255 循环；**收到设备包后必须回 ACK**（数据类型=3，包序号相同）。
- CRC：**CRC-16/XMODEM**，对「数据长度(2B) + 数据」计算。
- 数据体：`数据类型(1B) | cmd(1B) | 参数...`。

### 数据类型
| 值 | 含义 |
|----|------|
| 0 | 控制命令 |
| 1 | 实时转写 |
| 2 | 文件传输/操作 |
| 3 | ACK / 按键命令（ACK 帧无 cmd，按键帧带 cmd） |
| 4 | OTA |

### 指令集（cmd 明细）

方向：`↓` App→设备，`↑` 设备→App。

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
| 0x01 | ↑ | 实时 opus 音频帧 | 每帧 40B（20ms @16kbps，单声道）；controller 经 `recordDataStream` 透传，非录音期门控丢弃 |
| 0x02 | ↓ | 停止（保存）录音 | `01 02`，连发两次确保到达；设备即停止推流 |
| 0x03 | ↓ | 暂停 / 继续 | `01 03 01` 暂停 / `01 03 00` 继续 |
| 0x04 | ↑ | 设备端物理暂停/继续/停止 | 1B flag：`2` 停止 / `1` 暂停 / `0` 继续（映射为 0/2/3 发 `deviceRecordStream`） |

**文件通道（dataType = 2）**

| cmd | 方向 | 含义 | 数据体 / 响应 |
|----|----|------|------|
| 0 / 1 / 18 | ↓ / ↑ / ↑ | 取文件列表 / 列表帧（**多帧**） / 列表结束 | 列表结构见下节；controller 累积 cmd=1 帧至 cmd=18 收尾 |
| 2 | ↓ | 下载文件（断点续传） | offset(4B 小端) + 文件名；offset 传已收字节数即续传 |
| 12 | ↓ | 分段下载 | offset(4B 小端) + end(4B 小端) + 文件名，取 `[offset, end)` 区间 |
| 3 / 4 | ↑ / ↑ | 文件开始 / 文件数据块 | cmd3 回带当前文件名；cmd4 为文件字节（`fileDataStream`） |
| 5 | ↑ | 当前文件结束 | 1B 结束码：`0` 完成 / `1` 文件不存在 / `2` offset 过大 / `3` 其他停止 |
| 6 | ↑ | 全部文件结束 | — |
| 7 | ↓ | 终止下载 | 设备停止推流 |
| 8 / 13 | ↓ / ↑ | 删除文件（1 个或多个）/ 删除结果 | 请求 4B padding + 文件名（对齐 iOS 布局）；回包 1B：`0` 成功 / `1` 失败 |
| 9 / 10 | ↓ / ↑ | 删除全部 / 结果 | 回包 1B：`0` 成功 / `1` 失败 |

**按键通道（dataType = 3，与 ACK 同值——无 cmd 即 ACK 帧）**

| cmd | 方向 | 含义 | 说明 |
|----|----|------|------|
| 1 | ↑ | 用户按下「开始录音」物理键 | 奇数 cmd 均为设备通知；App 收到 1/3 应回发对应录音指令（对齐 iOS 按键应答） |
| 3 | ↑ | 用户按下「保存录音」物理键 | 同上 |
| 5 / 7 | ↑ | 按下「暂停」/「继续」物理键 | 同上 |
| 2 / 4 / 6 / 8 | ↓ | App 主动开始/保存/暂停/继续录音 | 设备用**同一 cmd** 回 1B 结果：`1` 成功 / `2` 失败（lite 的录音控制实际走音频通道，见 audio cmd 表） |
| 19 / 20 | ↓ / ↑ | 查录音状态 / 回包 | 回包 1B：`1` 在录音 / `2` 不在录音 |

### 文件列表结构（type=2 cmd=1，真机抓包校准 2026-07-03）
`4B(大端)文件个数 + N×[4B时间(秒,大端) + 4B大小(Byte,大端) + 文件名(变长,以 0x00 结尾)]`
- **count/time/size 均为大端**
- **文件名变长**：以 `.` (0x2E) 结尾（含），**点之后直接是下一条记录，无填充字节**。**新老固件名字格式不同**，但字段布局一致：
  - 新固件：`" note 2070-00-00_00-02-08."`（含前导空格、`_` 分隔）
  - 老固件：`"note20251020-104111."`（无空格）
- **多帧 + 收尾**：列表分多帧 cmd=1 到达，末尾 cmd=18（`fileListDone`）结束；controller 累积全部 cmd=1 帧后返回。
- `_decodeName`：去前导/结尾空白，去结尾 `.`，补 `.opus`（新老固件统一处理）。

## 三、文件结构

```
lib/
  pnote_flutter_sdk.dart             对外门面（唯一 public 入口）
  src/
    protocol/
      crc16_xmodem.dart              CRC-16/XMODEM（查表实现）
    pen/                             —— 声云录音笔协议栈 ——
      frame.dart                     帧编解码 + ACK 构造（字节序常量集中于此）
      frame_codec.dart               FrameAssembler：流式拆包（分片/粘包/噪声对齐）
      commands.dart                  BleUuids + 全部 cmd 常量（含未实现的预留）
      models.dart                    回包解析 + 时间打包
      app_protocol.dart              App 侧 JSON 事件协议（AppCmd 编号 + AppCodec 序列化）
      audio_pen_controller.dart      业务编排：收发/自动ACK/请求响应配对/事件分发
    transport/                       —— 传输层 ——
      transport.dart                 Transport 抽象（屏蔽底层差异）
      ble_transport.dart             flutter_blue_plus 实现（0xAE20 服务：ae21 写 /
                                     ae22+ae23 订阅；按 MTU 分片写）

test/
  crc16_xmodem_test.dart             CRC 已知向量
  frame_test.dart                    帧往返 + 拆包（粘包/分片/噪声）
  models_test.dart                   电量/容量/时间/文件列表/模式 解析
  controller_test.dart               假传输端到端：ACK、请求响应、超时
  app_protocol_test.dart             App JSON 兼容层（对齐iOS 端 SDK 输出格式）
  fake_transport.dart                共享假传输（内存收发 + 设备回包注入）

example/lib/main.dart                笔调试主页：扫描→连接→信息/录音控制/文件 + 日志控制台
example/lib/file_list_page.dart      文件列表页：自动拉取/下载（续传）/删除/解码播放
example/lib/opus_file_decoder.dart   opus 文件解码（下载文件本地试听）
```

> **opus 参数备忘（硬件确认，文件解码用）**：16000Hz / 单声道 / 20ms 帧；
> BLE 音频包 160B = 4 个独立 opus 帧（各 40B），必须逐帧解码。

## 四、各文件职责

### 协议核心层（`pen/`，纯 Dart，无蓝牙依赖，可离线单测）

| 文件 | 职责 | 关键 API |
|------|------|----------|
| `crc16_xmodem.dart` | CRC-16/XMODEM | `crc16Xmodem(data, {start, end})` |
| `frame.dart` | 帧编解码、ACK | `FrameCodec.encode/encodeCmd/ack/decode`、`Frame` |
| `frame_codec.dart` | 流式拆包 | `FrameAssembler.addBytes() → List<Frame>` |
| `commands.dart` | 常量定义 | `BleUuids`、`DataType`、`ControlCmd`、`KeyCmd`、`FileCmd`、`DeviceModeBit` |
| `models.dart` | 回包解析 | `BatteryInfo`、`Capacity`、`DeviceMode`、`PenFile`、`FileList`、`RecordState`、`encodeSyncTime()` |

### 传输层

| 文件 | 职责 |
|------|------|
| `transport.dart` | 抽象接口：`connect / send / incoming(Stream) / disconnect / state` |
| `ble_transport.dart` | flutter_blue_plus 实现：连接、发现服务（0xAE20：ae21 写 / ae22+ae23 订阅）、按 MTU 分片写 |

### App 兼容层（pen）

| 文件 | 职责 |
|------|------|
| `pen/app_protocol.dart` | `AppCmd`（app 侧 cmd 编号）+ `AppCodec`（模型→app JSON 事件），对齐iOS 端 SDK 输出格式 |

### 编排与门面

| 文件 | 职责 |
|------|------|
| `pen/audio_pen_controller.dart` | 维护包序号；收帧→回 ACK→请求响应配对（Completer+超时）→事件分发；实时音频流门控透传（`recordDataStream`） |
| `pnote_flutter_sdk.dart` | `AudioPenSdk`（扫描/连接）+ `AudioPenDevice`（笔会话门面） |

## 五、对外 API（`pnote_flutter_sdk.dart`）

```dart
// 入口
final sdk = AudioPenSdk();
sdk.isBluetoothOn;                       // 蓝牙是否开启
sdk.adapterState;                        // 适配器状态流
sdk.startSearch({timeout});              // Stream<List<ScanResult>>（按 0xAE20 过滤）
sdk.stopSearch();
final device = await sdk.connectDevice(bluetoothDevice);  // → AudioPenDevice
final d2 = await sdk.connectDeviceAndAddress(name, address); // 按名+址连接（扫描缓存匹配/按址直连，重连用，对齐 iOS 端）

// 设备会话
device.name / device.id / device.isDeviceConnected;
device.connectionState;                  // Stream<TransportState>
device.statusStream;                     // Stream<DeviceMode>（录音/播放等）
device.keyEventStream;                   // Stream<Frame>（按键事件）
device.deviceRecordStream;               // Stream<int>（设备端物理：0 停止 / 2 暂停 / 3 继续）
device.recordDataStream;                 // Stream<Uint8List>（实时录音 opus 帧，audio cmd=1，录音开始自动下发）
device.rawFrameStream;                   // Stream<Frame>（调试用原始帧）

await device.syncTime([time]);           // 同步时间
await device.getCBC();                   // → BatteryInfo
await device.getDeviceCapacity();        // → Capacity
await device.getDeviceVersion();         // → String
await device.getSn();                    // → String（协议无 SN，底层返回 MAC）
await device.startRecord();              // → bool
await device.stopRecord();               // → bool
await device.pauseRecord();              // → bool
await device.continueRecord();           // → bool
await device.getRecordState();           // → RecordState
await device.getRecordFileList();        // → List<PenFile>

// === 文件下载（设备主动推流） ===
device.fileDataStream;                  // Stream<Uint8List>：下载的每一块字节（cmd=4）
device.downloadProgressStream;          // Stream<int>：已收字节数
await device.startGetFile(fileName, {offset: 0}); // → FileDownloadResult（fileName 取自 PenFile.name）
await device.startGetFileByFromToEnd(fileName, {offset, end}); // 分段下载 [offset, end)
await device.stopGetFile();             // 终止下载（cmd=7）
await device.delFileData(fileName);     // 删除单个文件（file cmd=8→13）
await device.delAllFileData();          // 删除全部文件（file cmd=9→10，对齐 iOS 端 delAllFileData）

await device.closeConnect();

// === App 侧 JSON（上层兼容层，可直接下发给 app） ===
device.appEventStream;                   // Stream<String>：设备主动事件（按键 cmd=8/录音状态 cmd=9）
await device.getCBCAppJson();            // → '{"cmd":"6","state":"0","data":{"cbc":"95"}}'
await device.getDeviceCapacityAppJson(); // → cmd=13
await device.getDeviceVersionAppJson();  // → cmd=17
await device.getSnAppJson();             // → cmd=7（底层无 SN，用 MAC）
await device.getRecordStateAppJson();    // → cmd=9
await device.getRecordFileListAppJson(); // → cmd=4（data 为数组）
await device.startRecordAppJson();       // → cmd=3 record_state=1（stop/pause/continue 同族 ×4）
await device.delAllFileDataAppJson();    // → cmd=14 delete_state
// 也可手动转换：AppCodec.encode(AppCodec.battery(batteryInfo))
```

## 五·五、App 侧 JSON 兼容层（`src/pen/app_protocol.dart`）

目标：插件产出与**iOS/安卓 端 SDK 完全一致**的 JSON 事件，上层 app 代码（原先消费 iOS 端
`onDeviceStateEvent(String)`）零改动即可迁移。来源：《录音笔接口信息说明文档》。

统一格式：`{"cmd":"<app编号>","state":"0","data":{...}}`，**data 值统一为字符串**。

> ⚠️ **app 侧 cmd 与底层 BLE cmd 是两套独立编码**。例：电量 app=6 / BLE=4。

| app cmd | 功能 | data 字段 | 底层来源 | 状态 |
|--------|------|----------|---------|------|
| 1 | 搜索 | name/address/productType | scan | ✅ AppCodec |
| 2 | 连接 | connect_state/name/address | connect | ✅ AppCodec |
| 3 | 录音 | record_state/path/json | 录音控制 | ✅ AppCodec |
| 4 | 文件列表 | [{size/time/name}] + finish | file cmd0→1 | ✅ |
| 5 | 文件传输 | record_file_state/path/progress | file cmd2→5 | ✅ AppCodec（下载未接） |
| 6 | 电量 | cbc | ctrl cmd3→4 | ✅ |
| 7 | SN | sn | ⚠️ 底层无 SN → 用 MAC(cmd12→13) | ✅ |
| 8 | 物理按键 | event(1/3/5/7) | key 1/3/5/7 | ✅ appEventStream |
| 9 | 录音状态 | recordState | key cmd19→20 | ✅ |
| 13 | 容量 | residueSpace/totalSpace | ctrl cmd1→2 | ✅ |
| 14 | 删除文件 | delete_state | file cmd8→13（单个）/9→10（全部） | ✅ AppCodec（delFileData / delAllFileData + delAllFileDataAppJson） |
| 17 | 版本号 | version | ctrl cmd10→11 | ✅ |

> cmd=10/11/12/15/16/18~23（录音中查询 / WiFi / 增益 / OTA / 低功耗）的 AppCodec
> 与对应方法已随 lite 裁剪移除。

> 「AppCodec（…未接）」= 序列化函数已就绪，但对应的底层 BLE 请求/订阅还没接到 controller，
> 待相应功能实现后一行接上即可。


## 六、功能清单与状态


| 功能 | 指令 | 状态 |
|------|------|------|
| 扫描（0xAE20 过滤） | — | ✅ |
| 连接 / 断开 | — | ✅ |
| 同步时间 | control cmd=0 | ✅ |
| 获取容量 | control cmd=1→2 | ✅ |
| 获取电量 | control cmd=3→4 | ✅ |
| 获取固件版本 | control cmd=10→11 | ✅ |
| 获取 MAC（设备唯一标识，协议无 SN） | control cmd=12→13 | ✅ |
| 设备模式状态流 | control cmd=14 | ✅ |
| 开始/停止/暂停/继续录音 | audio type=1（开始 `01 00`/停止 `01 02`×2/暂停 `01 03 01`/继续 `01 03 00`，对齐 iOS，fire-and-forget） | ✅ |
| 物理按键通知（设备→app） | key cmd=1/3/5/7 | ✅ keyEventStream / appEventStream(cmd=8) |
| 设备端暂停/继续/停止（设备→app） | audio `01 04 <flag>`（2 停/1 暂停/0 继续，对齐 iOS） | ✅ deviceRecordStream / appEventStream(cmd=3) |
| 获取录音状态 | key cmd=19→20 | ✅ |
| 文件列表 | file cmd=0→1（多帧累积）→18 收尾 | ✅ |
| 按键事件流 | key（0xAE23） | ✅ |
| 实时录音音频流 | audio cmd=1（AUDIO_DATA）opus 原始帧，录音开始后设备自动下发，门控丢弃非录音期帧 | ✅ recordDataStream |
| 广播解密（异或 0x35）打印 | — | ✅ 仅调试日志（扫描过滤仍按 UUID） |
| 文件下载（续传） | file cmd=2 请求(offset+name)→设备推流 cmd=4→cmd=5 收尾；cmd=7 终止 | ✅ startGetFile/fileDataStream/downloadProgressStream |
| 文件分段下载 | file cmd=12 请求(offset(LE)+end(LE)+name)→设备推流 cmd=4→cmd=5 收尾（对齐 iOS `FILE_SEND_IMPORT_AUDIO_FROM_END`） | ✅ startGetFileByFromToEnd |
| 删除文件（单个） | file cmd=8 请求(4B padding+name)→13(1B 0成功/1失败) | ✅ delFileData（example 含确认弹窗+刷新列表） |
| 删除全部文件 | file cmd=9→10(1B 0成功/1失败) | ✅ delAllFileData（example 含确认弹窗） |

## 七、待真机校准点（PDF 未写死，已用常量集中）

1. **帧头字节序** — 真机已校准：`frame.dart` 顶部 `_crcBigEndian = false`（CRC 小端）、
   `_lenBigEndian = false`（长度小端）。
   依据：设备回包 `5a 00 0c 89 03 00 00 04 5f`，CRC 算出 `0x890c`，帧内为 `0c 89`（低字节在前）。
2. **CRC 初值** — 已确认：标准 XMODEM init=0x0000（真机回包校验通过）。
   - **CRC=0 跳过校验**：老固件帧的 CRC 字段恒为 0（未计算），`FrameCodec.decode`
     在 `verifyCrc && crc != 0` 时才校验，CRC=0 视为设备未填而放行（兼容老固件）。
3. **ACK 与按键 type=3 区分** — 现按「ACK 帧无 cmd、按键帧带 cmd」处理。
4. **电量/录音回复走 ae23** — 真机观察到电量回复(cmd=4)从 0xAE23(按键通道)下发；
   ae22/ae23 均订阅并汇入同一字节流，故通道无关紧要。
5. **notify 分片** — 长回包（文件列表）可能分片，`FrameAssembler` 负责重组。

## 七·五、调试日志

`AudioPenSdk(debugLog: true)`（默认开）会用 `debugPrint`（`I/flutter` 通道）把底层信息打到控制台，
按 `[TAG]` 前缀分类。终端 `flutter run` 与 `adb logcat` 都能直接看到。校准/上线后传 `debugLog: false` 关闭。

> 注意：早期版本用 `dart:developer` 的 `developer.log()`，它只在 DevTools 的 Logging 面板显示，
> **不会**出现在 `flutter run` 终端/logcat —— 故已全部改为 `debugPrint`。

| Tag | 来源 | 内容 |
|-----|------|------|
| `[BLE-SCAN]` | `pnote_flutter_sdk.dart` `_logScanResult` | 每个设备打印一次（去重）：名称 / 广播名 / MAC / RSSI / 可连接 / TxPower / **Service UUIDs（含 0xAE20）** / Service Data / **Manufacturer Data 原始字节 + ^0x35 解密（类别 0x03=WiFi卡片机 + MAC）** |
| `[BLE-GATT]` | `ble_transport.dart` `_logServices` | 连接后发现的**所有**服务与特征：Service UUID + 每个 Char UUID 及属性（READ/WRITE/WRITE_NR/NOTIFY/INDICATE） |
| `[BLE→ae21]` | `ble_transport.dart` `send` | App 发出的原始帧 hex |
| `[BLE←ae22]` | `ble_transport.dart` notify | 设备主通道回包原始 hex |
| `[BLE←ae23]` | `ble_transport.dart` notify | 设备按键通道回包原始 hex |

辅助方法：
- `AudioPenSdk.scanAll()` — 不带 0xAE20 过滤的扫描，用于排查"过滤后扫不到设备"时确认设备到底广播了什么。
- `bytesToHex(bytes)`（`ble_transport.dart`）— 字节转 `"5a 00 ..."` hex 串。

**运行时开关**：`device.debugLog`（getter/setter）可随时开关**原始字节**打印（`[BLE→ae21]`/
`[BLE←ae22]`/`[BLE←ae23]`）。解码后的**原始帧调试流** `device.rawFrameStream` 是否消费由上层决定
（example 顶部「原始调试」开关同时控制二者：关掉后既不打印原始字节，也不再输出 `← Frame`）。
构造时的 `AudioPenSdk(debugLog:)` 只是初值，连接后可用 `device.debugLog = false` 改。

> 说明：底层协议**无 SN 指令**（SN 是 iOS 端上层 SDK 概念）。设备唯一标识用 **MAC**（control cmd 12→13，
> `device.getSn()`，底层返回 MAC），或广播 Manufacturer Data 解密出的 MAC。

## 八、验证

```bash
flutter analyze          # 期望：No issues found（根 + example 各跑一次）
flutter test             # 期望：所有用例通过（当前 51/51）
./run.sh -d <真机id>     # 真机：扫描→连接→读电量/容量/版本→录音→文件列表
```

真机调试顺序：先看 example 日志区的 `rawFrameStream` 原始帧能否解出（核对魔数/CRC/seq），
再逐条对指令。无真机时可用 `test/fake_transport.dart` 注入回包跑通编排。

## 九、平台配置

- **Android** `example/android/app/src/main/AndroidManifest.xml`：
  `BLUETOOTH_SCAN`(neverForLocation) / `BLUETOOTH_CONNECT` / 旧版 `BLUETOOTH`+`ADMIN`+`ACCESS_FINE_LOCATION`；
  `minSdk >= 21`（`example/android/app/build.gradle.kts`）。
- **iOS** `example/ios/Runner/Info.plist`：`NSBluetoothAlwaysUsageDescription`。
- 运行时仍需在 App 内动态申请蓝牙/定位权限（example 依赖系统弹窗，正式接入建议用 permission_handler）。
