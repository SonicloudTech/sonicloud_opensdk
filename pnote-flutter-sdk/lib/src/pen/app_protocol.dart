/// App 侧 JSON 事件协议（上层兼容层）。
///
/// 这一层把底层 BLE 协议解析出的模型，转成iOS 端 SDK 暴露给 app 上层的
/// **统一 JSON 事件**格式，使上层 app 代码（原先消费 `onDeviceStateEvent(String)`）
/// 无需改动即可从iOS 端 SDK 迁移到本插件。
///
/// 统一格式：
/// ```json
/// {"cmd":"6","state":"0","data":{"cbc":"95"}}
/// ```
/// - `cmd`：**app 侧**指令编号（与底层 BLE cmd 不同）。
/// - `state`：`"0"` 正常，非 `"0"` 异常。
/// - `data`：各指令自定义字段；**值统一用字符串**（与iOS 端 SDK 一致）。
///
/// 参考《录音笔接口信息说明文档》。
library;

import 'dart:convert';

import 'models.dart';

/// App 侧指令编号（注意：与底层 BLE 协议的 cmd 是两套独立编码）。
class AppCmd {
  AppCmd._();

  /// 搜索：data{name,address,productType}。
  static const int search = 1;

  /// 连接：data{connect_state,name,address}。
  static const int connect = 2;

  /// 录音：data{record_state,fileName}。
  static const int record = 3;

  /// 录音文件名列表：data 为数组 [{size,time,name}]，外带 finish。
  static const int fileList = 4;

  /// 录音文件传输：data{record_file_state,path,progress}。
  static const int fileTransfer = 5;

  /// 电池电量：data{cbc}。
  static const int battery = 6;

  /// SN 码：data{sn}。（底层协议无 SN，用 MAC 代替，见 [AppCodec.sn]）
  static const int sn = 7;

  /// 录音笔物理按钮按键返回：data{event}（1 开始/3 保存/5 暂停/7 继续）。
  static const int keyEvent = 8;

  /// 录音状态键返回：data{recordState}（1 在录音/2 不在录音）。
  static const int recordState = 9;

  /// 容量数据返回：data{residueSpace,totalSpace}（KB）。
  static const int capacity = 13;

  /// 删除文件返回：data{delete_state}（0 成功/1 失败）。
  static const int deleteFile = 14;

  /// 获取版本号返回：data{version}。
  static const int version = 17;
}

/// 把底层模型转换为 app 侧统一 JSON 事件。
///
/// 每个方法返回 `Map<String, dynamic>`，调用 [encode] 得到可下发的 JSON 字符串。
/// 约定：`data` 内的值统一序列化为字符串（与iOS 端 SDK 行为一致）。
class AppCodec {
  AppCodec._();

  /// 构造统一事件骨架。[data] 可为 Map 或 List。
  static Map<String, dynamic> event(int cmd, {int state = 0, Object? data}) {
    return <String, dynamic>{
      'cmd': '$cmd',
      'state': '$state',
      if (data != null) 'data': data,
    };
  }

  /// 序列化为下发字符串。
  static String encode(Map<String, dynamic> event) => jsonEncode(event);

  // ---- 各指令构造 ----

  /// 搜索到设备（cmd=1）。
  static Map<String, dynamic> search({
    required String name,
    required String address,
    String productType = '',
  }) =>
      event(AppCmd.search, data: {
        'name': name,
        'address': address,
        'productType': productType,
      });

  /// 连接状态（cmd=2）。[connected] 1 成功 / 0 断开。
  static Map<String, dynamic> connect({
    required bool connected,
    required String name,
    required String address,
  }) =>
      event(AppCmd.connect, data: {
        'connect_state': connected ? '1' : '0',
        'name': name,
        'address': address,
      });

  /// 录音状态（cmd=3）。对齐 iOS `backRecordJson`：
  /// `{"cmd":"3","state":"0","data":{"record_state":"N","fileName":""}}`。
  /// [recordState] 0 停止/未录音, 1 录音, 2 暂停。
  static Map<String, dynamic> record({
    required int recordState,
    String fileName = '',
  }) =>
      event(AppCmd.record, data: {
        'record_state': '$recordState',
        'fileName': fileName,
      });

  /// 文件列表（cmd=4）。[finish] 0 传输中 / 1 完成。
  static Map<String, dynamic> fileList(
    List<PenFile> files, {
    bool finish = true,
  }) =>
      <String, dynamic>{
        'cmd': '${AppCmd.fileList}',
        'state': '0',
        'finish': finish ? '1' : '0',
        'data': [
          for (final f in files)
            {
              'size': '${f.sizeBytes}',
              'time': '${f.durationSec}',
              'name': f.name,
            }
        ],
      };

  /// 文件传输状态（cmd=5）。
  static Map<String, dynamic> fileTransfer({
    required int fileState,
    String path = '',
    int? progress,
  }) =>
      event(AppCmd.fileTransfer, data: {
        'record_file_state': '$fileState',
        'path': path,
        if (progress != null) 'progress': '$progress',
      });

  /// 电量（cmd=6）。充电中时 cbc=110。
  static Map<String, dynamic> battery(BatteryInfo info) => event(
        AppCmd.battery,
        data: {'cbc': '${info.charging ? 110 : info.percent}'},
      );

  /// SN（cmd=7）。底层协议无 SN，传入设备 MAC 作为唯一标识。
  static Map<String, dynamic> sn(String snOrMac) =>
      event(AppCmd.sn, data: {'sn': snOrMac});

  /// 物理按键事件（cmd=8）。[event] 1 开始/3 保存/5 暂停/7 继续。
  static Map<String, dynamic> keyEvent(int eventCode) =>
      event(AppCmd.keyEvent, data: {'event': '$eventCode'});

  /// 录音状态键返回（cmd=9）。1 在录音 / 2 不在录音。
  static Map<String, dynamic> recordStateReply(RecordState state) {
    final v = switch (state) {
      RecordState.recording => 1,
      RecordState.idle => 2,
      RecordState.paused => 2,
      RecordState.unknown => 2,
    };
    return event(AppCmd.recordState, data: {'recordState': '$v'});
  }

  /// 容量（cmd=13），KB。
  static Map<String, dynamic> capacity(Capacity c) => event(
        AppCmd.capacity,
        data: {
          'residueSpace': '${c.freeKb}',
          'totalSpace': '${c.totalKb}',
        },
      );

  /// 删除文件结果（cmd=14）。0 成功 / 1 失败。
  static Map<String, dynamic> deleteFile(int deleteState) =>
      event(AppCmd.deleteFile, data: {'delete_state': '$deleteState'});

  /// 版本号（cmd=17）。
  static Map<String, dynamic> version(String ver) =>
      event(AppCmd.version, data: {'version': ver});
}
