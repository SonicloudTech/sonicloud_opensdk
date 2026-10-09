# Soni SDK Demo（Flutter）

The app bar includes a language menu for `中文` and `English`. Protocol events and device payloads keep their original values for debugging.

基于 Flutter 的录音笔 SDK 演示工程，用于验证蓝牙连接、录音控制、文件传输、Wi-Fi 连接和 OTA 升级等完整链路。  
工程通过 `MethodChannel` / `EventChannel` 与 Android / iOS 原生 SDK 通信，适合作为 SDK 联调与功能验收 Demo。

## 主要功能

- 设备搜索与连接（蓝牙）
- 录音控制（开始/暂停/停止）
- 录音文件列表查询与文件下载
- 实时音频数据接收（Opus）与本地解码（PCM/WAV）
- 设备 Wi-Fi 热点管理与连接状态回传
- OTA 升级流程（进入升级模式、发送固件）
- 固件版本、SN、电量、按键状态等设备信息读取

## 技术栈与关键依赖

- Flutter / Dart（`sdk: ^3.9.0`）
- 状态管理：`provider`
- 权限管理：`permission_handler`
- Wi-Fi 管理：`wifi_iot`
- 音频编解码：`opus_flutter`、`opus_dart`
- 日志：`logger`
- 路径与文件：`path_provider`

## 目录结构

```text
.
├── lib
│   ├── main.dart                     # 页面与测试入口
│   ├── provider_record_pen.dart      # 录音笔能力聚合 Provider（核心）
│   ├── service_bluetooth.dart        # 蓝牙相关调用封装
│   ├── service_record.dart           # 录音相关调用封装
│   ├── service_transfer_files.dart   # 文件传输辅助
│   ├── service_system_ability.dart   # 系统能力与权限工具
│   ├── wave_write.dart               # PCM 转 WAV
│   └── logger.dart                   # 日志输出
├── android
│   └── app/src/main/kotlin/.../MainActivity.kt   # Android 原生通道实现
├── ios
│   └── Runner/...                                  # iOS 原生通道实现
├── assets                           # 资源与 OTA 固件（示例）
├── android SDK开发文档(最新版本)-2026.04.23.md
└── iOS SDK开发文档(最新版本)-2026.04.23.md
```

## 环境要求

- Flutter SDK（建议与项目当前版本兼容）
- Xcode（iOS 构建）
- Android Studio / Android SDK（Android 构建）
- 真机设备（蓝牙、Wi-Fi、录音、热点等能力不建议使用模拟器）

## 快速开始

1. 安装依赖

   ```bash
   flutter pub get
   ```

2. 连接设备并运行

   ```bash
   flutter run
   ```

3. 首次启动时授权（Android）
   - 蓝牙扫描/连接
   - 定位权限
   - 附近 Wi-Fi 设备权限（Android 13+）

## 联调说明

- Flutter 侧核心入口：`lib/provider_record_pen.dart`
  - 包含命令发送、事件分发、状态管理与 UI 数据流推送
- 原生桥接：
  - Android：`android/app/src/main/kotlin/com/soni/soni_sdk_demo/MainActivity.kt`
  - iOS：`ios/Runner` 下对应通道实现
- SDK 协议与命令说明请参考根目录两份平台 SDK 文档。

## Wi-Fi 状态码说明

`wifi_state` 含义如下：

- `0`：WiFi 热点打开
- `1`：WiFi 热点关闭
- `2`：WiFi 连接成功
- `3`：WiFi 断开连接
- `4`：有手机 WiFi 连接
- `5`：当前没有手机连接设备 WiFi 热点

## 常见问题排查

- 连接 Wi-Fi 后 socket 报错（如 `ENONET`）
  - 检查是否已授权 Wi-Fi / 定位相关权限
  - 确认已成功连接到目标热点后再建立 TCP
  - 建议在真机上测试并观察日志回调状态
- 无法搜索/连接蓝牙设备
  - 检查蓝牙与定位权限是否全部授权
  - 确认设备已开机且处于可连接状态
- OTA 失败
  - 确认设备已进入升级模式
  - 检查固件文件路径与格式是否正确

## 备注

- 本项目为 SDK Demo，偏重联调验证，不等同于生产级 App 架构。
- 若接入业务项目，建议将通道层、设备层与 UI 层进一步解耦并补充自动化测试。
