## 0.2.0

- 新增实时录音音频流 `recordDataStream`（`AudioPenDevice` 与 controller 均可取）：
  开始录音（`01 00`）后设备自动持续下发 opus 原始帧（audio `AUDIO_DATA`，cmd=0x01），
  透传给上层供实时转写 / 实时监听消费；不在录音状态时帧被门控丢弃（对齐 iOS
  `isRecording` 守卫）。

## 0.1.0

lite 精简版首个版本（纯 Dart + flutter_blue_plus，不依赖原生 SDK）。

- 扫描（0xAE20 过滤）/ 连接 / 按名+址重连
- 时间同步、电量、容量、固件版本、MAC
- 录音控制（开始/停止/暂停/继续）
- 物理按键事件、设备端暂停/继续/停止事件双向同步
- 文件列表、下载（断点续传、区间分段）、删除单个/全部
- 公开 API 方法名对齐 iOS 端；AppJson 兼容层输出与 iOS 端 SDK 一致的 JSON 事件
- 48 个单元测试；example 真机调试工程（文件下载/解码试听）


