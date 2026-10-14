import 'package:flutter/foundation.dart';
import 'dart:ui' as ui;

class AppLocale {
  static final ValueNotifier<String> language = ValueNotifier<String>(
    ui.PlatformDispatcher.instance.locale.languageCode.toLowerCase().startsWith('zh') ? 'zh' : 'en',
  );

  static String text(String value) => language.value == 'en' ? (_english[value] ?? value) : value;

  static const Map<String, String> _english = {
    '清屏': 'Clear', '复制log': 'Copy log', '传输文件名（含后缀）': 'File name (with extension)',
    '选择设备': 'Select device', '搜索后选择设备': 'Search, then select a device', '连接': 'Connect',
    '搜索设备': 'Scan devices', '停止搜索': 'Stop scan', '是否链接': 'Connection status', '断开链接': 'Disconnect',
    '录音状态': 'Recording state', '开始录音': 'Start recording', '暂停录音': 'Pause recording', '继续录音': 'Resume recording',
    '停止录音': 'Stop recording', '▶ 播放录音': '▶ Play recording', '后连：获取录音文件名': 'Read filename after connect',
    '后连：获取时长和流': 'Read duration and stream after connect', '获取电量': 'Get battery', '获取容量': 'Get capacity',
    '获取SN': 'Get serial number', '给设备下发时间': 'Set device time', '获取当前增益': 'Get current gain',
    '设置当前增益': 'Set current gain', '通知APP前后台': 'Notify app foreground/background', '获取固件版本号': 'Get firmware version',
    '文件列表': 'File list', '删除文件': 'Delete file', '⚠️删除所有文件': '⚠️ Delete all files', '传输文件': 'Transfer file',
    '停止传输': 'Stop transfer', '▶ 播放传输': '▶ Play transfer', '⏹ 停止播放': '⏹ Stop playback', '第二代wifi版本': 'Wi-Fi (generation 2)',
    '打开wifi': 'Enable Wi-Fi', '关闭wifi': 'Disable Wi-Fi', 'wifi断开设备': 'Disconnect device Wi-Fi', '连接状态': 'Connection status',
    '手机状态': 'Phone status', '固件版本号': 'Firmware version', '固件升级code': 'Firmware upgrade code', '请求升级': 'Request upgrade',
    '发送固件V5': 'Send firmware V5', '低功耗状态': 'Low-power state', '设置低功耗': 'Set low-power mode',
    '文件传输间隔（毫秒）': 'File transfer interval (ms)', '设置间隔': 'Set interval', '暂无日志': 'No logs',
  };
}
