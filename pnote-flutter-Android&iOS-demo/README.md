# PNote Demo App

录音笔（蓝牙智能笔）配套演示 App。基于 [pnote_flutter_sdk](https://github.com/chenqiangchenqiang/pnote-flutter-sdk) 演示设备连接、录音控制、实时转写、文件管理与本地回放的完整链路。

- 平台：Android / iOS（Flutter）
- 语言：中文 / 英文（默认跟随系统，**非中文系统一律英文**）
- 主题色：`#3D9AFF`（设计令牌见 `lib/design/tokens.dart`）

## 功能总览

| 模块 | 能力 |
|---|---|
| 设备连接 | BLE 扫描 / 连接 / 重连；权限与蓝牙状态引导；AppBar 右上角设备摘要（在线状态 + 名称 + 电量图形） |
| 录音 | App 内录音控制（开始 / 暂停 / 继续 / 停止保存）；笔身物理按键全量镜像；录音全屏页自动弹出且录制中不可退出；实时计时 |
| 实时转写 | 录音流 opus→PCM 切片上行 WebSocket（厦大线路）；临时句「正在说」高亮 + 定稿正文；断线重连退避；停录转写文本落盘 |
| 本地录音 | 录音实时流同步落盘（与转写共用数据流）；断连保留半段可播；转写 txt 随音频保存 |
| 音频回放 | 音频详情页（信息 + 播放控制 + 转写内容 + AI 生成占位）；播完自动归位 |
| 设备文件 | 文件列表每次进入自动刷新；下载 / 删除（单个 / 全部，确认弹窗）；**下载支持暂停与断点续传**；迷你播放条 |
| 近期录音 | 自录 + 设备下载统一汇总；超 5 条提供「更多」全量页；支持删除（含转写文本） |

完整 UI/交互说明见 [docs/app-features.md](docs/app-features.md)（已交付 UI 设计）。

## 技术栈

- Flutter（项目经 FVM 管理，`3.47.7`；Dart SDK `^3.13.5`）
- `pnote_flutter_sdk`：录音笔 BLE 协议封装（扫描 / 连接 / 录音指令 / 文件传输 / 设备信息）
- `flutter_blue_plus`：BLE 传输层
- `opus_codec` / `opus_codec_dart`：opus 解码 FFI（40B 定长帧 → PCM s16le/16k/单声道）
- `web_socket_channel` + `crypto`：实时转写上行与 md5 token
- `just_audio` + `audio_session`：本地回放
- `path_provider`：本地存储定位

## 快速开始

```bash
fvm flutter pub get
fvm flutter run          # 需真机 + 已开机的录音笔
```

> 模拟器无蓝牙，请使用真机调试。

### 心云开放平台凭证配置

实时转写（ASR）与 AI 纪要依赖 [声云开放平台](https://open.sinicloud.com) 的鉴权。凭证统一配置在 [lib/asr/sinicloud_auth.dart](lib/asr/sinicloud_auth.dart) 顶部的三个常量：

```dart
static const _appId = 'YOUR_APP_ID';       // 开放平台 AppID
static const _apiKey = 'YOUR_API_KEY';     // 开放平台 API Key
static const _apiSecret = 'YOUR_API_SECRET'; // 开放平台 API Secret
```

公开仓库内置的是占位符，运行前请替换为你自己申请的凭证（开放平台控制台获取）。apiSecret 属于敏感信息，切勿提交真实值到公开仓库；正式产品应由自家后端中转签发 token。

### 所需权限（Android，已在 Manifest 声明）

`BLUETOOTH_SCAN` / `BLUETOOTH_CONNECT`（Android 12+）、`BLUETOOTH` / `BLUETOOTH_ADMIN`（旧系统）、`ACCESS_FINE_LOCATION`（旧系统扫描定位）、`INTERNET`（转写）。

App 内置权限引导：未授权 / 蓝牙未开时给出对应提示卡与「去系统设置」入口；**权限检查先于蓝牙状态检查**（Android 12+ 未授权时适配器状态恒为 unknown，先查蓝牙会误报）。

## 目录结构

```
lib/
├── main.dart                  # 入口、AppBar 设备摘要、语言切换、Tab 框架
├── session.dart               # 全局会话状态：扫描/连接/录音/转写分流/本地落盘/近期录音
├── devices_page.dart          # 首页：扫描视图 + 已连接仪表盘 + 近期录音区
├── device_detail_page.dart    # 设备信息页（电量/存储/固件/刷新/断连）
├── recording_overlay_page.dart# 录音全屏页（自动弹出、不可退出）
├── recordings_page.dart       # 设备文件页（下载/暂停续传/删除/迷你播放条）
├── recent_recordings_page.dart# 近期录音全量页（删除）+ 共用条目组件
├── audio_detail_page.dart     # 本地音频详情页（信息/播放/转写/AI 占位）
├── transcript_flow.dart       # 实时转写文本流组件（首页已移除，全屏页使用）
├── ble_permissions.dart       # 权限申请与引导
├── asr/
│   └── pen_asr_service.dart   # 转写 WebSocket 服务（握手/心跳/重连/切片）
├── audio/
│   ├── recording_store.dart   # 本地存储（recordings/ 与 recordings/app/）+ opus→wav
│   ├── opus_bootstrap.dart    # opus 解码器初始化/帧解码引导
│   └── wav.dart               # WAV 封装
├── design/
│   ├── tokens.dart            # 设计令牌（#3D9AFF 主色系）
│   ├── status_badge.dart      # 状态徽标（圆点+文字）
│   └── battery_level.dart     # 电量图形（按百分比填充）
└── l10n/                      # arb + 生成代码（gen/）
```

## 核心机制速记

- **音频流**：录音开始后设备持续下发 `AUDIO_DATA` opus 帧（固件约定 **40B/帧、20ms/帧**，即 2000B/s）；该流为 broadcast，转写与本地落盘并行订阅互不影响；时长可由字节数反推
- **转写链路**：opus 帧解码为 PCM → 按 100ms（3200B）切片上行 `wss://asr.chatmin.cn:1444/dotcwsasr`（token = md5('TR'+userid+sid)）；`errCode=3` 为临时句、`0` 为定稿
- **本地存储**：App 自录 → `recordings/app/REC_*.opus`（+ 同名 `.txt` 转写）；设备下载 → `recordings/` 根目录；播放前懒转 `.wav`
- **断点续传**：下载暂停发协议 `cmd=7`，继续时 `startGetFile(name, offset: 已收字节)`，本地 append 接写；会话序号防旧会话迟到回包误删文件
- **物理按键**：笔身开始(1)/停止(3)/暂停(5)/继续(7) 同步驱动 App 状态机（含录音全屏页自动弹出/返回）

## 国际化

- 文案源：`lib/l10n/app_en.arb`（模板）/ `app_zh.arb`
- 生成：`fvm flutter gen-l10n`（配置见 `l10n.yaml`）
- 语言规则：系统 `zh*` → 中文，其余 → 英文；AppBar 菜单可手动锁定 English / 中文

## 相关仓库

- SDK：[pnote-flutter-sdk](https://github.com/chenqiangchenqiang/pnote-flutter-sdk)（协议实现与 API 文档见其 README / ARCHITECTURE.md）
