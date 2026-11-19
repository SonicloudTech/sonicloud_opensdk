/// 协议数据模型与回包解析。
library;

import 'dart:convert';
import 'dart:typed_data';

/// 电量信息。
class BatteryInfo {
  /// 0~100 电量百分比；当 [charging] 为 true 时 [percent] 为充电态标记前的原值。
  final int percent;

  /// 是否充电中（设备用 110 表示）。
  final bool charging;

  const BatteryInfo({required this.percent, required this.charging});

  /// 解析电量回包参数（1B：0~100；110 充电中）。
  factory BatteryInfo.parse(Uint8List params) {
    if (params.isEmpty) return const BatteryInfo(percent: 0, charging: false);
    final raw = params[0];
    if (raw == 110) return const BatteryInfo(percent: 100, charging: true);
    return BatteryInfo(percent: raw, charging: false);
  }

  @override
  String toString() => 'BatteryInfo($percent%${charging ? ', charging' : ''})';
}

/// 容量信息（单位 KB）。
class Capacity {
  /// 剩余容量（KB）。
  final int freeKb;

  /// 总容量（KB）。
  final int totalKb;

  const Capacity({required this.freeKb, required this.totalKb});

  /// 已用容量（KB）。
  int get usedKb => (totalKb - freeKb).clamp(0, totalKb);

  /// 解析容量回包参数（4B 剩余 + 4B 总量，KB，小端）。
  factory Capacity.parse(Uint8List params) {
    if (params.length < 8) return const Capacity(freeKb: 0, totalKb: 0);
    final free = _readUint32Le(params, 0);
    final total = _readUint32Le(params, 4);
    return Capacity(freeKb: free, totalKb: total);
  }

  @override
  String toString() => 'Capacity(free=${freeKb}KB, total=${totalKb}KB)';
}

/// 录音状态。
enum RecordState {
  /// 不在录音（含已停止）。
  idle,

  /// 正在录音。
  recording,

  /// 暂停。
  paused,

  /// 未知。
  unknown,
}

/// 设备当前模式位掩码解析结果。
class DeviceMode {
  final int raw;
  const DeviceMode(this.raw);

  bool get playing => raw & (1 << 0) != 0;
  bool get recording => raw & (1 << 1) != 0;
  bool get usbMode => raw & (1 << 2) != 0;
  bool get realtimeAsr => raw & (1 << 3) != 0;
  bool get importing => raw & (1 << 4) != 0;
  bool get playPaused => raw & (1 << 5) != 0;
  bool get busy => raw & (1 << 6) != 0;

  /// 解析模式回包（1B 位掩码）。
  factory DeviceMode.parse(Uint8List params) =>
      DeviceMode(params.isEmpty ? 0 : params[0]);

  @override
  String toString() => 'DeviceMode(0x${raw.toRadixString(16)}, '
      'recording=$recording, playing=$playing)';
}

/// 录音文件信息。
class PenFile {
  /// 文件名（去除尾部空字节，不含 .opus 后缀）。
  final String name;

  /// 文件大小（字节）。
  final int sizeBytes;

  /// 文件时长（秒）。
  final int durationSec;

  const PenFile({
    required this.name,
    required this.sizeBytes,
    required this.durationSec,
  });

  /// 是否电话录音（call 前缀），否则普通录音（note 前缀）。
  bool get isCall => name.startsWith('call');

  @override
  String toString() =>
      'PenFile($name, ${sizeBytes}B, ${durationSec}s${isCall ? ', call' : ''})';
}

/// 文件下载结束码（cmd=5 回包第 1 字节）。
enum FileEndCode {
  /// 0：文件传输完成（已收齐）。
  completed,

  /// 1：文件不存在。
  notFound,

  /// 2：续传 offset 过大（超过文件大小）。
  offsetTooLarge,

  /// 3：其它停止。
  other;

  /// 从回包字节解析。未知值归为 [other]。
  static FileEndCode fromByte(int b) {
    switch (b) {
      case 0:
        return FileEndCode.completed;
      case 1:
        return FileEndCode.notFound;
      case 2:
        return FileEndCode.offsetTooLarge;
      default:
        return FileEndCode.other;
    }
  }
}

/// 文件下载结果。
class FileDownloadResult {
  FileDownloadResult({
    required this.endCode,
    required this.fileName,
    required this.receivedBytes,
  });

  /// 结束码（决定是否成功）。
  final FileEndCode endCode;

  /// 设备回传的当前文件名（cmd=3）。
  final String fileName;

  /// 实际收到的字节数。
  final int receivedBytes;

  /// 是否成功收齐。
  bool get success => endCode == FileEndCode.completed;

  @override
  String toString() =>
      'FileDownloadResult($fileName, $receivedBytes B, $endCode)';
}

/// 文件列表解析（真机抓包校准：2026-07-03）。
///
/// 结构：`4B(大端)文件个数 + N×[4B时间(秒,大端) + 4B大小(Byte,大端) + 文件名(变长,以 0x00 结尾)]`
///
/// 注意（与厂家 SDK demo 的差异）：demo 假设名字固定 20B，但**真机固件用变长文件名**
/// （实测 ` note 2070-00-00_00-02-08.`），且 count/time/size 均为**大端**。
/// demo 代码未适配当前固件，不能照抄——这里按真机字节校准。
class FileList {
  /// 解析一帧文件列表数据体参数（cmd 之后的部分）。
  static List<PenFile> parse(Uint8List params) {
    if (params.length < 4) return const [];
    final count = _readUint32Be(params, 0); // 大端（真机校准）
    if (count <= 0) return const [];

    final files = <PenFile>[];
    var j = 4;
    for (var i = 0; i < count; i++) {
      if (j + 8 > params.length) break;
      final duration = _readUint32Be(params, j);
      final size = _readUint32Be(params, j + 4);
      j += 8;
      // 文件名变长，以 '.' (0x2E) 结尾（含）。点之后直接是下一条记录，无填充。
      final dot = _indexOf(params, j, 0x2E);
      final nameEnd = dot < 0 ? params.length : dot + 1; // 含点
      final nameBytes = Uint8List.sublistView(params, j, nameEnd);
      files.add(PenFile(
        name: _decodeName(nameBytes),
        sizeBytes: size,
        durationSec: duration,
      ));
      j = nameEnd; // 点之后即下一条记录
    }
    return files;
  }

  /// 从 [start] 起找首个 [byte] 的下标，没有返回 -1。
  static int _indexOf(Uint8List buf, int start, int byte) {
    for (var i = start; i < buf.length; i++) {
      if (buf[i] == byte) return i;
    }
    return -1;
  }

  static String _decodeName(Uint8List bytes) {
    final raw = utf8.decode(bytes, allowMalformed: true).trim();
    // 设备名字形如 " note 2070-00-00_00-02-08."（新固件）或
    // "note20251020-104111."（老固件），均以 '.' 结尾。
    if (raw.isEmpty) return raw;
    // 去掉结尾的点，补 .opus（设备不上报后缀）。
    final stripped = raw.endsWith('.') ? raw.substring(0, raw.length - 1) : raw;
    if (stripped.contains('opus')) return stripped;
    return '$stripped.opus';
  }
}

/// 同步时间 payload 打包：年(2,小端)/月/日/时/分/秒，共 7 字节。
Uint8List encodeSyncTime(DateTime time) {
  final t = time;
  return Uint8List.fromList([
    t.year & 0xFF,
    (t.year >> 8) & 0xFF,
    t.month & 0xFF,
    t.day & 0xFF,
    t.hour & 0xFF,
    t.minute & 0xFF,
    t.second & 0xFF,
  ]);
}

int _readUint32Le(Uint8List buf, int offset) {
  return buf[offset] |
      (buf[offset + 1] << 8) |
      (buf[offset + 2] << 16) |
      (buf[offset + 3] << 24);
}

int _readUint32Be(Uint8List buf, int offset) {
  return (buf[offset] << 24) |
      (buf[offset + 1] << 16) |
      (buf[offset + 2] << 8) |
      buf[offset + 3];
}
