import 'file_transfer_size_check.dart';

/// 设备模块中英文文案；测试模块及原始设备日志不参与切换。
class DeviceLocalizations {
  static const bkDemoTitle = 'SoniSDKDemo-BK解密';

  final bool isEnglish;

  const DeviceLocalizations({this.isEnglish = false});

  String fileSizeCheck(FileTransferSizeCheck check) {
    final target = check.expectedBytes?.toString() ?? _text('未知', 'unknown');
    final result = switch (check.matches) {
      true => _text('文件大小校验通过', 'File size check passed'),
      false => _text('文件大小校验失败', 'File size check failed'),
      null => _text('文件大小未校验', 'File size not checked'),
    };
    return _text(
      '$result（收到：${check.receivedBytes}/目标：$target 字节）',
      '$result (Received: ${check.receivedBytes}/Target: $target bytes)',
    );
  }

  String _text(String chinese, String english) => isEnglish ? english : chinese;

  String get switchLanguage => isEnglish ? '切换中文' : '切换英文';

  String deviceModelName(int? type, String fallback) {
    if (!isEnglish) return fallback;
    return switch (type) {
      48 => 'JL01 (new 7911)',
      64 || 65 => 'JL02 (Aigo 7012)',
      66 => 'JL02 (AOC 7012)',
      _ => fallback,
    };
  }

  String get device => _text('设备', 'Device');
  String get other => _text('其他', 'Other');
  String get unknown => _text('未知', 'Unknown');
  String get log => _text('日志', 'Log');
  String get autoScroll => _text('自动滚底', 'Auto-scroll');
  String get clearLog => _text('清屏', 'Clear');
  String get copyLog => _text('复制log', 'Copy log');
  String get noLogs => _text('暂无日志', 'No logs');
  String get emptyLog => _text('暂无日志…', 'No logs…');
  String get copyIncomplete => _text(
    '复制不完整：系统剪贴板未能保存全部内容，请缩短日志后重试',
    'Copy incomplete: the clipboard could not save all content. Shorten the log and retry.',
  );
  String get copyFailed => _text(
    '复制失败：无法读写系统剪贴板，请缩短日志或重试',
    'Copy failed: unable to access the clipboard. Shorten the log or retry.',
  );
  String get copyPartsTitle =>
      _text('日志过长，请分段复制', 'Log too long: copy in parts');
  String get previousPart => _text('上一段', 'Previous');
  String get nextPart => _text('下一段', 'Next');
  String get close => _text('关闭', 'Close');
  String get copying => _text('复制中…', 'Copying…');
  String get copyCurrentPart => _text('复制当前段', 'Copy this part');
  String get noSavedAudio => _text(
    '暂无已保存的音频，请先录音或传输文件',
    'No saved audio. Record or transfer a file first.',
  );
  String get selectShareAudio => _text('选择要分享的音频', 'Select audio to share');
  String rawOpusAudio(String label) =>
      _text('$label（原始 Opus）', '$label (raw Opus)');
  String get selectDeviceFirst =>
      _text('请先搜索并选择要连接的设备', 'Search and select a device first.');
  String get setAuthkey => _text('修改AuthKey', 'Change AuthKey');
  String get newAuthkeyHint => _text(
    '请输入新的 64 位十六进制 AuthKey',
    'Enter a new 64-digit hexadecimal AuthKey',
  );
  String get setWifiPassword => _text('修改热点密码', 'Set hotspot password');
  String get wifiPasswordHint => _text(
    '8-16 个字符，下次开启热点生效',
    '8–16 characters; applies next time the hotspot starts',
  );
  String get quickConnectWifi => _text('一键连接WiFi', 'Quick Wi-Fi');
  String get passwordConnect => _text('密码连接', 'Use password');
  String get optionalWifiPasswordHint => _text(
    '请输入设备热点密码，无密码可留空',
    'Enter the hotspot password, or leave blank if none',
  );
  String get enterWifiPassword =>
      _text('请输入设备热点密码', 'Enter the hotspot password');
  String get setTransferInterval => _text('设置传输间隔', 'Transfer interval');
  String get transferIntervalHint => _text('13–255 毫秒', '13–255 ms');
  String get integerIntervalRequired =>
      _text('请输入整数毫秒值', 'Enter an integer in milliseconds');
  String get selectTransferFileFirst =>
      _text('请先获取并选择传输文件', 'Get the file list and select a file first.');
  String get selectUfwFirmware =>
      _text('请选择 .ufw 固件文件', 'Select a .ufw firmware file.');
  String get unreadableFirmware =>
      _text('无法读取所选固件', 'Unable to read the selected firmware.');
  String get collapseAudioRate =>
      _text('收起音频传输速率', 'Hide audio transfer rates');
  String get expandAudioRate => _text('展开音频传输速率', 'Show audio transfer rates');
  String get getFileListFirst => _text('先获取文件列表', 'Get the file list first');
  String get selectDeviceHint =>
      _text('搜索后选择设备', 'Search, then select a device');
  String get connect => _text('连接', 'Connect');
  String get authenticate => _text('认证', 'Authenticate');
  String get resetAuthkey => _text('重置AuthKey', 'Reset AuthKey');
  String get setDeviceName => _text('设置设备名', 'Set name');
  String get formatDevice => _text('格式化', 'Format');
  String get resetDevice => _text('重置', 'Reset');
  String get searchDevices => _text('搜索设备', 'Search');
  String get stopSearch => _text('停止搜索', 'Stop search');
  String get checkConnection => _text('是否链接', 'Connected?');
  String get disconnect => _text('断开链接', 'Disconnect');
  String get recordState => _text('录音状态', 'Record state');
  String get startRecord => _text('开始录音', 'Record');
  String get l09Record => _text('L09录音', 'L09 record');
  String get pauseRecord => _text('暂停录音', 'Pause');
  String get resumeRecord => _text('继续录音', 'Resume');
  String get stopRecord => _text('停止录音', 'Stop record');
  String get playRecord => _text('▶ 播放录音', '▶ Recording');
  String get recording => _text('录音', 'recording');
  String get getRecordingName => _text('后连：获取录音文件名', 'Get recording name');
  String get getRecordingStream => _text('后连：获取时长和流', 'Get duration/stream');
  String get getBattery => _text('获取电量', 'Battery');
  String get getCapacity => _text('获取容量', 'Capacity');
  String get getSn => _text('获取SN', 'Get SN');
  String get syncTime => _text('同步设备时间', 'Sync time');
  String get getGain => _text('获取当前增益', 'Get gain');
  String get setGain => _text('设置当前增益', 'Set gain');
  String get appState => _text('通知APP前后台', 'App state');
  String get getVersion => _text('获取固件版本号', 'FW version');
  String get fileList => _text('文件列表', 'File list');
  String get deleteFile => _text('删除文件', 'Delete file');
  String get deleteAllFiles => _text('⚠️删除所有文件', '⚠️ Delete all');
  String get transferFile => _text('传输文件', 'Transfer');
  String get stopTransfer => _text('停止传输', 'Stop transfer');
  String get playTransfer => _text('▶ 播放传输', '▶ Transferred');
  String get transferAudio => _text('传输音频', 'transferred audio');
  String get stopPlayback => _text('⏹ 停止播放', '⏹ Stop play');
  String get returnStart => _text('返回开始', 'Return start');
  String get returnPause => _text('返回暂停', 'Return pause');
  String get returnResume => _text('返回继续', 'Return resume');
  String get returnStop => _text('返回停止', 'Return stop');
  String get openWifi => _text('打开wifi', 'Wi-Fi on');
  String get closeWifi => _text('关闭wifi', 'Wi-Fi off');
  String get disconnectWifi => _text('wifi断开设备', 'Disconnect Wi-Fi');
  String get wifiState => _text('连接状态', 'Wi-Fi state');
  String get phoneState => _text('手机状态', 'Phone state');
  String get resetDeviceName => _text('复位设备名', 'Reset name');
  String get setWifiDirect => _text('设置直传Wi-Fi', 'Set direct Wi-Fi');
  String get setUploadUrl => _text('设置上传URL', 'Set upload URL');
  String get resetWifiDirect => _text('复位直传Wi-Fi', 'Reset direct Wi-Fi');
  String get getWifiDirect => _text('获取直传Wi-Fi', 'Get direct Wi-Fi');
  String get firmwareCode => _text('固件升级code', 'FW code');
  String get getLowPower => _text('低功耗状态', 'Low-power state');
  String get setLowPower => _text('设置低功耗', 'Set low power');
  String get ufwFirmware => _text('固件文件（.ufw）', 'Firmware (.ufw)');
  String get selectFirmware => _text('选择固件', 'Browse');
  String get requestAndSend => _text('请求并发送', 'Request & send');
  String get bkOtaSettings => _text('BK OTA 专属设置', 'BK OTA settings');
  String get deviceHeartbeat => _text('设备发送心跳', 'Device heartbeat');
  String get appHeartbeat => _text('App 回复心跳', 'App heartbeat reply');
  String get shareAudio => _text('分享音频', 'Share audio');
  String get audioTransferRate => _text('音频传输速率', 'Audio transfer rates');
  String get storeAudio => _text('是否存储音频', 'Save audio');
  String get decodeAndStore => _text('是否解码加存储', 'Decode & save');
  String get liveRecording => _text('实时录音', 'Live recording');
  String get fileTransfer => _text('文件传输', 'File transfer');
  String get bkFirmware => _text('固件文件（.bin/.rbl）', 'Firmware (.bin/.rbl)');
  String get selectBkFirmware =>
      _text('请选择 .bin 或 .rbl 固件文件', 'Select a .bin or .rbl firmware file.');
  String get unreadableFile =>
      _text('无法读取所选文件', 'Unable to read the selected file.');
  String get firmwareSelected => _text('已选择固件', 'Firmware selected');
  String get bkUpgradeUrl =>
      _text('BK 升级 URL（启动服务后自动填入）', 'BK upgrade URL (filled when HTTP starts)');
  String get startHttp => _text('启动HTTP', 'Start HTTP');
  String get stopHttp => _text('停止HTTP', 'Stop HTTP');
  String get selectFirmwareFirst =>
      _text('请先选择固件文件', 'Select a firmware file first.');
  String get httpStarted => _text('HTTP已启动', 'HTTP started');
  String get httpStopped => _text('HTTP已停止', 'HTTP stopped');
  String get sendUpgradeUrl => _text('发送升级URL', 'Send URL');
  String get selectFirmwareStartHttp =>
      _text('请先选择固件并启动HTTP', 'Select firmware and start HTTP first.');
  String get upgradeUrlSent => _text('已发送升级URL', 'Upgrade URL sent');
  String get bkVersion => _text('BK版本号', 'BK version');
  String get bkVersionRequested => _text('已请求 BK 版本号', 'BK version requested');
  String get confirmDeleteAll => _text('确认删除所有文件', 'Delete all files?');
  String get confirmDeleteFile => _text('确认删除文件', 'Delete file?');
  String get deleteAllWarning => _text(
    '确定删除设备上的所有录音文件吗？删除后无法恢复。',
    'Delete all recordings on the device? This cannot be undone.',
  );
  String get cancel => _text('取消', 'Cancel');
  String get delete => _text('确认删除', 'Delete');
  String get selectL09Mic =>
      _text('L09录音：选择麦克风', 'L09 recording: select microphone');
  String get digitalMic => _text('数字麦（关闭骨麦）', 'Digital mic (bone mic off)');
  String get boneMic => _text('骨麦（关闭数字麦）', 'Bone mic (digital mic off)');
  String get deviceNameHint => _text('2-16 位英文或数字', '2–16 letters or digits');
  String get directWifiTitle => _text('设置直传 Wi-Fi', 'Set direct Wi-Fi');
  String get ssid => _text('SSID', 'SSID');
  String get password => _text('密码', 'Password');
  String get confirm => _text('确认', 'Confirm');
  String get uploadUrlTitle => _text('设置上传 URL', 'Set upload URL');
  String get authkey => _text('AuthKey', 'AuthKey');
  String get bkOta => _text('BK OTA', 'BK OTA');
  String get uploadUrlHint => _text(
    'https://example.com/audio/upload',
    'https://example.com/audio/upload',
  );

  String appTitle(String title) =>
      isEnglish && title == bkDemoTitle ? 'SoniSDKDemo-BK Decryption' : title;

  String selectDevice(int count) =>
      _text('选择设备 ($count)', 'Select device ($count)');
  String selectTransferFile(int count) =>
      _text('选择传输文件 ($count)', 'Select transfer file ($count)');
  String logLineCount(int count) => _text('$count 行', '$count lines');
  String copiedLogLines(int count) =>
      _text('已完整复制 $count 行日志', 'Copied all $count log lines');
  String logPartsDescription(int lines, int parts) => _text(
    '本次共 $lines 行日志，超过单次安全复制长度（256 KB），已保留完整内容并分为 $parts 段。每次复制后请先粘贴，再复制下一段。',
    'The $lines log lines exceed the safe copy size (256 KB). All content is preserved in $parts parts. Paste each part before copying the next.',
  );
  String logPartProgress(int index, int total, int copied) => _text(
    '第 $index / $total 段，已复制 $copied 段',
    'Part $index / $total; $copied copied',
  );
  String copiedLogPart(int index) =>
      _text('已完整复制第 $index 段', 'Copied all of part $index');
  String recordingSaved(String name) =>
      _text('录音已保存: $name', 'Recording saved: $name');
  String transferSaved(String name) =>
      _text('传输文件已保存: $name', 'Transferred file saved: $name');
  String audioMissing(String label) => _text(
    '$label 音频不存在，请先录音/传输',
    'No $label audio. Record or transfer first.',
  );
  String playingAudio(String label) => _text('正在播放$label', 'Playing $label');
  String playbackFailed(String label, Object error) =>
      _text('播放$label失败: $error', 'Failed to play $label: $error');
  String shareAudioFailed(Object error) =>
      _text('分享音频失败：$error', 'Failed to share audio: $error');
  String authkeyFailed(Object error) =>
      _text('AuthKey 认证调用失败: $error', 'AuthKey authentication failed: $error');
  String settingFailed(String title, Object error) =>
      _text('$title 调用失败: $error', '$title failed: ${_settingError(error)}');

  String _settingError(Object error) {
    if (error is! FormatException) return error.toString();
    return switch (error.message) {
      '传输间隔须为 13–255 毫秒' => 'Transfer interval must be 13–255 ms',
      '热点密码需为 8-16 个字符' => 'Hotspot password must contain 8–16 characters',
      _ => error.toString(),
    };
  }

  String selectFirmwareFailed(Object error) =>
      _text('选择固件失败: $error', 'Failed to select firmware: $error');
  String requestAndSendFailed(Object error) =>
      _text('请求并发送失败: $error', 'Request and send failed: $error');
  String connectWifi(String name) => _text('连接($name)', 'Connect ($name)');
  String averageRate(String rate) => _text('平均速度 $rate', 'Average $rate');
  String rateSummary(String current, String minimum, String maximum) => _text(
    '当前 $current，最低 $minimum，最高 $maximum',
    'Now $current, min $minimum, max $maximum',
  );
  String selectFailed(Object error) =>
      _text('选择失败: $error', 'Selection failed: $error');
  String startFailed(Object error) =>
      _text('启动失败: $error', 'Start failed: $error');
  String stopFailed(Object error) =>
      _text('停止失败: $error', 'Stop failed: $error');
  String sendFailed(Object error) =>
      _text('发送失败: $error', 'Send failed: $error');
  String deleteFileWarning(String name) => _text(
    '确定删除文件“$name”吗？删除后无法恢复。',
    'Delete "$name"? This cannot be undone.',
  );
}
