# Demo 功能列表（仅关注在展开 / 收起音频传输速率下方的按钮方法，顶部的日志台和传输速率模块位置功能不做改动）

## 一、SDK 提供功能

| 编号 | 功能 | Android SDK 方法 | iOS SDK 方法 |
| --- | --- | --- | --- |
| SDK-001 | 初始化 SDK | `init` | `Shared / delegate` |
| SDK-002 | 搜索设备 | `startSearch` | `startSearch` |
| SDK-003 | 停止搜索 | `stopSearch` | `stopSearch` |
| SDK-004 | 连接设备 | `connectDevice` | `connectDeviceAndAddress / connectDevice` |
| SDK-005 | 断开连接 | `closeConnect` | `closeConnect` |
| SDK-006 | 查询连接状态 | `isDeviceConnected` | `isDeviceConnected` |
| SDK-007 | 查询录音状态 | `getRecordState` | `getRecordState` |
| SDK-008 | 开始录音 | `startRecord()` | `startRecord` |
| SDK-009 | 暂停录音 | `pauseRecord` | `pauseRecord` |
| SDK-010 | 继续录音 | `continueRecord` | `continueRecord` |
| SDK-011 | 停止录音 | `stopRecord` | `stopRecord` |
| SDK-012 | 获取当前录音文件名 | `getFileNameOnlyRecording` | `getFileNameOnlyRecording` |
| SDK-013 | 获取当前录音时长 | `getTimeOnlyRecording` | `getTimeOnlyRecording` |
| SDK-014 | 应答按键开始录音 | `startBtnBackRecord` | `startBtnBackRecord` |
| SDK-015 | 应答按键暂停录音 | `pauseBtnBackRecord` | `pauseBtnBackRecord` |
| SDK-016 | 应答按键继续录音 | `continueBtnBackRecord` | `continueBtnBackRecord` |
| SDK-017 | 应答按键停止录音 | `stopBtnBackRecord` | `stopBtnBackRecord` |
| SDK-018 | 通知 App 前后台状态 | `sendAppShowState` | `sendAppShowState` |
| SDK-019 | 获取录音文件列表 | `getRecordFileList` | `getRecordFileList` |
| SDK-020 | 传输录音文件 | `startGetFile` | `startGetFile` |
| SDK-021 | 停止文件传输 | `stopGetFile` | `stopGetFile` |
| SDK-022 | 删除录音文件 | `deleteReordFile` | `delFileData` |
| SDK-023 | 删除所有录音文件 | `deleteAllReordFile` | `delAllFileData` |
| SDK-024 | 按起止位置传输文件 | `startGetFileByFromToEnd` | `startGetFileByFromToEnd` |
| SDK-025 | 获取电量 | `getCBC` | `getCBC` |
| SDK-026 | 获取 SN | `getSn` | `getSn` |
| SDK-027 | 同步时间 | `syncTime` | `syncTime` |
| SDK-028 | 获取容量 | `getDeviceCapacity` | `getDeviceCapacity` |
| SDK-029 | 获取录音增益 | `getDeviceGain` | `getDeviceGain` |
| SDK-030 | 设置录音增益 | `setDeviceGain` | `setDeviceGain` |
| SDK-031 | 获取固件版本号 | `getDeviceVersion` | `getDeviceVersion` |
| SDK-032 | 获取固件版本 Code | `getDeviceVersionCode` | `getDeviceVersionCode` |
| SDK-033 | 设置设备名称 | `SetDeviceName` | `setDeviceName` |
| SDK-034 | 复位设备名称 | `ResetDeviceName` | `resetDeviceName` |
| SDK-035 | 重置设备 | `RestDevice` | `restDevice` |
| SDK-036 | 请求进入 OTA 模式 | `requestDeviceGotoOtaMode` | `requestDeviceGotoOtaMode` |
| SDK-037 | 发送 OTA 固件 | `sendOtaFile` | `sendOtaFile` |
| SDK-038 | 查询低功耗录音模式 | `getDeviceLowPowerRecordMode` | `getDeviceLowPowerRecordMode` |
| SDK-039 | 设置低功耗录音模式 | `setDeviceLowPowerRecordMode` | `setDeviceLowPowerRecordMode` |
| SDK-040 | 设置文件传输间隔 | `sendFileTimeInterval` | — |
| SDK-041 | 设备业务数据回调 | `onDeviceDataEvent` | `deviceDataEvent` |
| SDK-042 | 实时录音数据回调 | `onDeviceRecordData` | `deviceRecordData` |
| SDK-043 | 文件数据回调 | `onDeviceFileData` | `deviceFileData` |
| SDK-044 | SDK 日志开关 | `setShowLog` | `setShowLog` |
| SDK-045 | SDK 日志监听 | `setLogDataListener` | `logInfo` |
| SDK-046 | 设备日志监听 | `setDevicesLogDataListener` | — |
| SDK-047 | AuthKey 认证 | `authkeyConnect` | `authkeyConnect` |
| SDK-048 | 修改 AuthKey | `ResetAuthkey` | `resetAuthkey` |
| SDK-049 | 解绑并恢复默认 AuthKey | `UnbondAuthkey` | `unbondAuthkey` |
| SDK-050 | 设置设备热点密码 | `SetWifiPassword` | `setWifiPassword` |
| SDK-051 | 选择麦克风并开始录音 | `startRecord(int)` | `startRecord:` |
| SDK-052 | 获取 BK 固件版本 | `getBKHDVersion` | `getBKHDVersion` |
| SDK-053 | 设置 BK 升级 URL | `setBK_UPGRADEHD` | `setBKUpgradeHD` |
| SDK-054 | 打开设备 Wi-Fi | `openWiFi` | `openWiFi` |
| SDK-055 | 关闭设备 Wi-Fi | `closeWiFi` | `closeWiFi` |
| SDK-056 | 连接设备 Wi-Fi | `connectDeviceWiFi` | `connectDeviceWiFi` |
| SDK-057 | 断开设备 Wi-Fi | `disconnectDeviceWiFi` | `disconnectDeviceWiFi` |
| SDK-058 | 一键连接设备 Wi-Fi | `quickConnectDeviceWiFi` | `quickConnectDeviceWiFiWithWiFiTimeout:tcpTimeout:password:` |
| SDK-059 | 查询设备 Wi-Fi 连接状态 | `getDeviceWiFiState` | `getDeviceWiFiState` |
| SDK-060 | 查询手机连接设备热点的状态 | `getWiFiHotspotState` | `getWiFiHotspotState` |
| SDK-061 | 设置直传 Wi-Fi | `SetWifi` | `setWiFiDirectSSID:password:` |
| SDK-062 | 设置上传 URL | `SetRemoteURL` | `setRemoteURL` |
| SDK-063 | 复位直传 Wi-Fi | `ResetWifi` | `resetWiFiDirect` |
| SDK-064 | 获取直传 Wi-Fi | `GetWifi` | `getWiFiDirect` |

## 二、Demo 现有按钮或输入框功能

同一 SDK 方法的重复入口合并统计；“—”表示无 SDK 调用，占位入口标注“占位”。

| 编号 | 按钮或输入框功能 | SDK 功能编号 |
| --- | --- | --- |
| DEMO-001 | 选择设备 / 连接 | SDK-004 |
| DEMO-002 | AuthKey 输入 / 认证 | SDK-047 |
| DEMO-003 | 修改AuthKey | SDK-048 |
| DEMO-004 | 重置AuthKey | SDK-049 |
| DEMO-005 | 设置设备名 / 名称输入 | SDK-033 |
| DEMO-006 | 重置 | SDK-035 |
| DEMO-007 | 搜索设备 | SDK-002 |
| DEMO-008 | 停止搜索 | SDK-003 |
| DEMO-009 | 是否链接 | SDK-006 |
| DEMO-010 | 断开链接 | SDK-005 |
| DEMO-011 | 录音状态 | SDK-007 |
| DEMO-012 | 开始录音 | SDK-008 |
| DEMO-013 | L09录音 / 数字麦、骨麦选择 | SDK-051 |
| DEMO-014 | 暂停录音 | SDK-009 |
| DEMO-015 | 继续录音 | SDK-010 |
| DEMO-016 | 停止录音 | SDK-011 |
| DEMO-017 | 播放录音 | — |
| DEMO-018 | 后连：获取录音文件名 | SDK-012 |
| DEMO-019 | 后连：获取时长和流 | SDK-013 |
| DEMO-020 | 获取电量 | SDK-025 |
| DEMO-021 | 获取容量 | SDK-028 |
| DEMO-022 | 获取SN | SDK-026 |
| DEMO-023 | 给设备下发时间 | SDK-027 |
| DEMO-024 | 获取当前增益 | SDK-029 |
| DEMO-025 | 设置当前增益 | SDK-030 |
| DEMO-026 | 通知APP前后台 | SDK-018 |
| DEMO-027 | 获取固件版本号 / 固件版本号 | SDK-031 |
| DEMO-028 | 文件列表 | SDK-019 |
| DEMO-029 | 删除文件 | SDK-022 |
| DEMO-030 | 删除所有文件 | SDK-023 |
| DEMO-031 | 选择传输文件 / 传输文件 | SDK-020 |
| DEMO-032 | 停止传输 | SDK-021 |
| DEMO-033 | 播放传输 | — |
| DEMO-034 | 停止播放 | — |
| DEMO-035 | 返回开始 | SDK-014 |
| DEMO-036 | 返回暂停（占位） | SDK-015 |
| DEMO-037 | 返回继续（占位） | SDK-016 |
| DEMO-038 | 返回停止（占位） | SDK-017 |
| DEMO-039 | 打开wifi | SDK-054 |
| DEMO-040 | 连接（热点名）/ 密码连接 / 密码输入 | SDK-056 |
| DEMO-041 | 关闭wifi | SDK-055 |
| DEMO-042 | wifi断开设备 | SDK-057 |
| DEMO-043 | 连接状态 | SDK-059 |
| DEMO-044 | 手机状态 | SDK-060 |
| DEMO-045 | 一键连接WiFi / 密码输入 | SDK-058 |
| DEMO-046 | 修改热点密码 / 密码输入 | SDK-050 |
| DEMO-047 | 复位设备名 | SDK-034 |
| DEMO-048 | 设置直传Wi-Fi / SSID、密码输入 | SDK-061 |
| DEMO-049 | 设置上传URL / URL 输入 | SDK-062 |
| DEMO-050 | 复位直传Wi-Fi | SDK-063 |
| DEMO-051 | 获取直传Wi-Fi | SDK-064 |
| DEMO-052 | 固件升级code | SDK-032 |
| DEMO-053 | 低功耗状态 | SDK-038 |
| DEMO-054 | 设置低功耗 | SDK-039 |
| DEMO-055 | 选择 OTA 固件 / 固件名称显示（.ufw） | — |
| DEMO-056 | 请求并发送 OTA 固件 | SDK-036、SDK-037 |
| DEMO-057 | BK OTA 专属设置 | — |
| DEMO-058 | 选择 BK 固件 / 固件路径显示（.bin/.rbl） | — |
| DEMO-059 | 启动HTTP | — |
| DEMO-060 | 停止HTTP | — |
| DEMO-061 | 发送升级URL / BK 升级 URL 显示 | SDK-053 |
| DEMO-062 | BK版本号 | SDK-052 |

## 三、所有设备公共方法（显示在 展开 / 收起音频传输速率下方）
demo 下方按钮排布
| 文件列表选择框 |独占一行
| DEMO-001 |独占一行
| DEMO-007 | DEMO-008 | DEMO-009 | DEMO-010 |表示每行显示几个按钮，靠左排列 后面都按此规则
| DEMO-012 | DEMO-014 | DEMO-015 | DEMO-016 | DEMO-011 |
| DEMO-020 | DEMO-021 | DEMO-022 | DEMO-024 | DEMO-027 |
| DEMO-028 | DEMO-031 | DEMO-032 | DEMO-029 | DEMO-030 |
| DEMO-017 | DEMO-033 | DEMO-034 | DEMO-023 | DEMO-025 |

## 四、对应设备型号的其他功能（显示在公共方法按钮下方，标题：’type‘ ‘型号名称’ ‘设备name’，居中、不斜体，三项间距 24）
设备型号 下方为其他功能 每行显示几个按钮，靠左排列
设备型号 1
型号名称：CB08
| DEMO-035 | DEMO-036 | DEMO-037 | DEMO-038 | DEMO-026 |
| DEMO-018 | DEMO-019 | DEMO-053 | DEMO-054 |  |

设备型号 3 4 8
型号名称：CB08
| DEMO-039 | DEMO-040 连接（热点名） | DEMO-042 | DEMO-041 | DEMO-043 |
| DEMO-044 | DEMO-045 | DEMO-052 | DEMO-053 | DEMO-054 |
| DEMO-055 | DEMO-056 |两个方法占一行

设备型号 5
型号名称：D10
| DEMO-048 | DEMO-051 | DEMO-050 | DEMO-049 |  |
| DEMO-005 | DEMO-047 |  |  |  |

设备型号 198
型号名称：C08-FB
| DEMO-039 | DEMO-040 连接（热点名） | DEMO-042 | DEMO-041 | DEMO-043 |
| DEMO-005 | DEMO-047 | DEMO-057（缩小版 颜色不变） |  |  |

设备型号 199
型号名称：C08-DX
| DEMO-039 | DEMO-040 连接（热点名） | DEMO-042 | DEMO-041 | DEMO-043 |
| DEMO-044 | DEMO-045 | DEMO-005 | DEMO-047 |  |
| DEMO-006（改名格式化） | DEMO-057（缩小版 颜色不变） |  |  |  |

设备型号 200
型号名称：C08-AI
| DEMO-039 | DEMO-040 连接（热点名） | DEMO-042 | DEMO-041 | DEMO-043 |
| DEMO-044 | DEMO-045| DEMO-057（缩小版 颜色不变） |  |  |

设备型号 201
型号名称：L09
| DEMO-002 |(独占一行)
| DEMO-039 | DEMO-040 密码连接 | DEMO-042 | DEMO-041 | DEMO-043 |
| DEMO-044 | DEMO-045 | DEMO-005 | DEMO-047 | DEMO-046 |
| DEMO-013 | DEMO-003 | DEMO-004 | DEMO-057（缩小版 颜色不变） |   |

设备型号 202
型号名称：C10
| DEMO-002 |(独占一行)
| DEMO-039 | DEMO-040 密码连接 | DEMO-042 | DEMO-041 | DEMO-043 |
| DEMO-044 | DEMO-045| DEMO-005 | DEMO-047 | DEMO-046 |
| DEMO-057（缩小版 颜色不变）| DEMO-003 ｜ DEMO-004｜  ｜  ｜

其他设备型号（非上面明确的设备类型）
型号名称：其他
| DEMO-039 | DEMO-040 连接（热点名） | DEMO-042 | DEMO-041 | DEMO-043 |
| DEMO-044 | DEMO-045 | DEMO-052 |  |  |
| DEMO-055 | DEMO-056 |两个方法占一行

|  |  |  |  |  |
