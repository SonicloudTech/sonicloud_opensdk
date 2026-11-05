import 'package:flutter/services.dart';
import 'logger.dart';

///
/// @author ChenQiang
/// @fileName service_record.dart
/// @date 2025-12-17
/// @description 录音控制服务
/// 职责：开始、暂停、继续、停止录音，控制 APP 与设备交互
///

class RecordPenRecordService {
  final MethodChannel _methodChannel = const MethodChannel(
    'com.soni.soni_sdk_demo/recordPen',
  );

  /// 启动录音
  Future<void> startRecord() async {
    try {
      Log.d('🔴 启动录音');
      await _methodChannel.invokeMethod('startRecord');
    } catch (e) {
      Log.e('❌ 启动录音失败: $e');
    }
  }

  /// L09 启动录音：开启骨麦时关闭数字麦，关闭骨麦时开启数字麦
  Future<void> startRecordWithBoneMic(bool enabled) async {
    try {
      await _methodChannel.invokeMethod('startRecordWithBoneMic', {
        'enabled': enabled,
      });
    } catch (e) {
      Log.e('[录音调试][L09] 启动录音失败: $e');
    }
  }

  /// 暂停录音
  Future<void> pauseRecord() async {
    try {
      Log.d('⏸️ 暂停录音');
      await _methodChannel.invokeMethod('pauseRecord');
    } catch (e) {
      Log.e('❌ 暂停录音失败: $e');
    }
  }

  /// 继续录音
  Future<void> continueRecord() async {
    try {
      Log.d('▶️ 继续录音');
      await _methodChannel.invokeMethod('continueRecord');
    } catch (e) {
      Log.e('❌ 继续录音失败: $e');
    }
  }

  /// 停止录音
  Future<void> stopRecord() async {
    try {
      Log.d('⏹️ 停止录音');
      await _methodChannel.invokeMethod('stopRecord');
    } catch (e) {
      Log.e('❌ 停止录音失败: $e');
    }
  }

  /// 设备按键返回 - 开始录音
  Future<void> startBtnBackRecord() async {
    try {
      await _methodChannel.invokeMethod('startBtnBackRecord');
    } catch (e) {
      Log.e('❌ 设备按键启动录音失败: $e');
    }
  }

  /// 设备按键返回 - 暂停录音
  Future<void> pauseBtnBackRecord() async {
    try {
      await _methodChannel.invokeMethod('pauseBtnBackRecord');
    } catch (e) {
      Log.e('❌ 设备按键暂停录音失败: $e');
    }
  }

  /// 设备按键返回 - 继续录音
  Future<void> continueBtnBackRecord() async {
    try {
      await _methodChannel.invokeMethod('continueBtnBackRecord');
    } catch (e) {
      Log.e('❌ 设备按键继续录音失败: $e');
    }
  }

  /// 设备按键返回 - 停止录音
  Future<void> stopBtnBackRecord() async {
    try {
      Log.d('🛑 设备按键停止录音');
      await _methodChannel.invokeMethod('stopBtnBackRecord');
    } catch (e) {
      Log.e('❌ 设备按键停止录音失败: $e');
    }
  }

  /// APP 录音模式下：启动应用录音
  Future<void> startRecordOnlyApp(String fileName, bool isNew) async {
    try {
      Log.d('📱 启动 APP 录音模式: $fileName (isNew=$isNew)');
      await _methodChannel.invokeMethod('startRecordOnlyApp', {
        'fileName': fileName,
        'isNew': isNew,
      });
    } catch (e) {
      Log.e('❌ 启动 APP 录音失败: $e');
    }
  }

  /// APP 录音模式下：获取 APP 录制的文件，并拼接之前的数据
  Future<void> startGetFileByFromToEnd(String fileName, String end) async {
    try {
      Log.d('📤 获取 APP 录制文件并拼接: $fileName');
      await _methodChannel.invokeMethod('startGetFileByFromToEnd', {
        'fileName': fileName,
        'end': end,
      });
    } catch (e) {
      Log.e('❌ 获取并拼接文件失败: $e');
    }
  }

  /// 传输文件到手机（支持断点续传）
  Future<void> sendFileFromPenToPhoneWithOffset(
    String fileName,
    int offset,
  ) async {
    try {
      Log.d('📥 传输文件: $fileName (offset=$offset)');
      await _methodChannel.invokeMethod('startGetFile', {
        'fileName': fileName,
        'offset': offset,
      });
    } catch (e) {
      Log.e('❌ 传输文件失败: $e');
    }
  }

  /// 停止传输文件
  Future<void> stopTransferFile(String fileName) async {
    try {
      Log.d('⏹️ 停止传输: $fileName');
      await _methodChannel.invokeMethod('stopGetFile', {'fileName': fileName});
    } catch (e) {
      Log.e('❌ 停止传输失败: $e');
    }
  }
}
