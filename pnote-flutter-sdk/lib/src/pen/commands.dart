/// 声云录音笔 BLE 协议常量定义。
///
/// 参考《声云录音笔与APP 通讯协议》。所有指令的数据体格式为：
/// `数据类型(1B) | cmd(1B) | 参数...`
library;

/// BLE GATT UUID（16-bit，运行时转 128-bit）。
class BleUuids {
  BleUuids._();

  /// 主服务 UUID。
  static const String service = '0000ae20-0000-1000-8000-00805f9b34fb';

  /// 写特征（WRITE_WITHOUT_RESPONSE）：App 向设备发指令。
  static const String write = '0000ae21-0000-1000-8000-00805f9b34fb';

  /// 通知特征：设备回包主通道。
  static const String notify = '0000ae22-0000-1000-8000-00805f9b34fb';

  /// 通知特征：按键消息。
  static const String keyNotify = '0000ae23-0000-1000-8000-00805f9b34fb';

  /// 16-bit 短 UUID，用于扫描过滤。
  static const String serviceShort = 'ae20';
}

/// 帧层「数据类型」枚举。
class DataType {
  DataType._();

  /// 控制命令。
  static const int control = 0;

  /// 实时转写。
  static const int realtime = 1;

  /// 文件传输/操作。
  static const int file = 2;

  /// ACK / 按键命令（帧层 ACK 数据体仅有类型字节，无 cmd；
  /// 按键命令数据体含 cmd，二者据此区分）。
  static const int ack = 3;

  /// 按键命令（与 ack 同值 3，语义按是否带 cmd 区分）。
  static const int key = 3;
}

/// 控制命令（DataType.control）cmd 值。
class ControlCmd {
  ControlCmd._();

  /// 同步北京时间。参数 7B：年(2,小端)/月/日/时/分/秒。
  static const int syncTime = 0;

  /// 获取容量。回复 cmd=2：4B 剩余 + 4B 总量（KB，小端）。
  static const int getCapacity = 1;

  /// 回复容量。
  static const int replyCapacity = 2;

  /// 获取电量。回复 cmd=4：1B（0~100；110 充电中）。
  static const int getBattery = 3;

  /// 回复电量。
  static const int replyBattery = 4;

  /// 获取固件版本。回复 cmd=11：字符串如 "1.2.23"。
  static const int getVersion = 10;

  /// 回复固件版本。
  static const int replyVersion = 11;

  /// 获取 MAC。回复 cmd=13。
  static const int getMac = 12;

  /// 回复 MAC。
  static const int replyMac = 13;

  /// 设备端当前模式状态（dev→app）。1B 位掩码。
  static const int deviceMode = 14;

  /// app 前后台状态：1 前台 / 2 后台。
  static const int appShowState = 18;
}

/// 设备当前模式状态位掩码（ControlCmd.deviceMode 的 1B 值）。
class DeviceModeBit {
  DeviceModeBit._();

  static const int playing = 1 << 0; // bit0：播放
  static const int recording = 1 << 1; // bit1：录音
  static const int usbMode = 1 << 2; // bit2：USB 模式
  static const int realtimeAsr = 1 << 3; // bit3：实时转写
  static const int importing = 1 << 4; // bit4：导入音频
  static const int playPaused = 1 << 5; // bit5：播放暂停
  static const int busy = 1 << 6; // bit6：设备忙
}

/// 音频命令（DataType.realtime = 0x01，iOS `DATA_AUDIO`）cmd 值。
///
/// **App 主动录音走此通道**（对齐 iOS 端 `DataEncapsulation`）：
/// 开始 `01 00`、停止 `01 02`（iOS 连发两次）、
/// 暂停 `01 03 01`、继续 `01 03 00`。
///
/// 注意与 [KeyCmd] 的区别：[KeyCmd] 的 `startRecord`/`saveRecord`（DataType=3）
/// 在 iOS 里是 `DATA_TYPE_BTN` 的 `*BtnBackRecord`，语义是「设备物理按键触发后
/// App 回应给设备」，**不是 App 主动发起录音**。App 主动录音一律用本类。
class AudioCmd {
  AudioCmd._();

  /// 开始录音（实时转写）。数据体 `01 00`。
  static const int startRecord = 0x00;

  /// 实时音频数据（dev→app）：录音开始后设备持续下发的 opus 原始帧
  /// （`01 01` 亦可作 App 主动开流指令）。对齐 iOS `AUDIO_DATA`。
  static const int data = 0x01;

  /// 停止录音。数据体 `01 02`（iOS 连发两次以确保到达）。
  static const int stopRecord = 0x02;

  /// 暂停/继续录音。数据体 `01 03 <flag>`：flag=1 暂停 / flag=0 继续。
  static const int pausePlay = 0x03;

  /// 暂停/继续的参数值。
  static const int pauseFlag = 1;
  static const int resumeFlag = 0;

  /// 设备端触发的停止/暂停/继续（dev→app）。
  static const int pausePlayByDevice = 0x04;
}

/// 按键命令（DataType.key）cmd 值。
///
/// 注意方向：**奇数 cmd（1/3/5/7）是设备→app 的物理按键通知**（用户在录音笔上
/// 按了对应键）；**App 主动控制用偶数 cmd（2/4/6/8）**，设备用**同一 cmd** 回
/// 1B 结果（1 成功 / 2 失败）。
class KeyCmd {
  KeyCmd._();

  /// 设备→app：用户按下「开始录音」物理键的通知。
  static const int keyStartRecord = 1;

  /// App 开始录音。设备回 cmd=2：1B（1 成功 / 2 失败）。
  static const int startRecord = 2;
  static const int replyStartRecord = 2;

  /// 设备→app：用户按下「保存录音」物理键的通知。
  static const int keySaveRecord = 3;

  /// App 保存（停止）录音。设备回 cmd=4：1B。
  static const int saveRecord = 4;
  static const int replySaveRecord = 4;

  /// 设备→app：用户按下「暂停录音」物理键的通知。
  static const int keyPauseRecord = 5;

  /// App 暂停录音。设备回 cmd=6：1B。
  static const int pauseRecord = 6;
  static const int replyPauseRecord = 6;

  /// 设备→app：用户按下「继续录音」物理键的通知。
  static const int keyContinueRecord = 7;

  /// App 继续录音。设备回 cmd=8：1B。
  static const int continueRecord = 8;
  static const int replyContinueRecord = 8;

  /// 获取录音状态。设备回 cmd=20：1B（1 在录音 / 2 不在录音）。
  static const int getRecordState = 19;
  static const int replyRecordState = 20;
}

/// 文件操作（DataType.file）cmd 值。
class FileCmd {
  FileCmd._();

  /// 获取音频文件列表。设备回 cmd=1：列表结构。
  static const int getFileList = 0;
  static const int replyFileList = 1;

  /// 请求导入（下载）文件：4B offset（小端）+ 20B 文件名。
  static const int requestFile = 2;

  /// 请求导入（下载）文件**分段版**（对齐 iOS `FILE_SEND_IMPORT_AUDIO_FROM_END`）：
  /// 数据体 = offset(4B 小端) + end(4B 小端) + 文件名。回包仍走 cmd=3/4/5。
  static const int requestFileByFromToEnd = 12;

  /// 开始导入的文件（dev→app）。
  static const int fileStart = 3;

  /// 音频文件数据（dev→app）。
  static const int fileData = 4;

  /// 当前导入文件结束：1B（0 完成/1 不存在/2 offset 过大/3 其他停止）。
  static const int fileEnd = 5;

  /// 所有需要导入的文件结束（app→dev）。
  static const int allFilesEnd = 6;

  /// 终止文件导入（app→dev）。
  static const int abortImport = 7;

  /// 删除 1 或 n 个文件（app→dev）：文件列表，结构同文件列表。
  static const int deleteFiles = 8;

  /// 删除全部文件（app→dev）。
  static const int deleteAll = 9;

  /// 返回全部删除结果：1B（0 成功/1 失败）。
  static const int replyDeleteAll = 10;

  /// 返回「删除 1 或 n 个文件」结果（对齐 iOS `FILE_BACK_DEL_FILE`）：1B（0 成功/1 失败）。
  static const int replyDeleteFiles = 13;

  /// 文件列表导入完毕标记。
  static const int fileListDone = 18;
}
