/// 业务编排：发指令、收帧、回 ACK、请求-响应配对、事件分发。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'commands.dart';
import 'frame.dart';
import 'frame_codec.dart';
import 'models.dart';
import '../transport/transport.dart';

/// 一个待完成的请求（等待匹配 (dataType, cmd) 的回包）。
class _PendingRequest {
  _PendingRequest(this.dataType, this.cmd);
  final int dataType;
  final int cmd;
  final Completer<Frame> completer = Completer<Frame>();
}

/// 文件列表多帧累积器（对齐 iOS：列表分多帧 cmd=1 到达，cmd=18 收尾）。
/// 收到的每帧 [Frame] 经 [FileList.parse] 解析后追加，结束帧完成 future。
class _FileListAccumulator {
  _FileListAccumulator();
  final Completer<List<PenFile>> completer = Completer<List<PenFile>>();
  final List<PenFile> files = [];
}

/// 文件下载会话：设备推流（cmd=4）累积，cmd=5/6 收尾完成 future。
class _DownloadSession {
  _DownloadSession(this.requestedName);
  final String requestedName;
  String fileName = ''; // 设备 cmd=3 回传的当前文件名
  int received = 0; // 已收字节数
  final Completer<FileDownloadResult> completer = Completer<FileDownloadResult>();
}

/// 录音笔会话控制器：在 [Transport] 之上实现协议编排。
class AudioPenController {
  AudioPenController(this._transport, {this.responseTimeout = const Duration(seconds: 5)});

  final Transport _transport;

  /// 请求超时。
  final Duration responseTimeout;

  /// BLE 解帧器（维护半包缓冲，按 0x5A 帧边界重组）。
  final FrameAssembler _assembler = FrameAssembler();

  final List<_PendingRequest> _pending = [];

  /// 文件列表多帧累积（对齐 iOS：列表可能分多帧到达，最后以 cmd=18 结束）。
  _FileListAccumulator? _fileListAcc;

  StreamSubscription<Uint8List>? _incomingSub;
  int _seq = 0;

  final _statusCtrl = StreamController<DeviceMode>.broadcast();
  final _keyEventCtrl = StreamController<Frame>.broadcast();
  final _rawFrameCtrl = StreamController<Frame>.broadcast();

  /// 实时录音音频流（opus 原始帧，audio `AUDIO_DATA`）。对齐 iOS `deviceRecordData:`。
  final _recordDataCtrl = StreamController<Uint8List>.broadcast();

  /// 是否处于实时取流状态（对齐 iOS `isRecording` 守卫：未开流时丢弃 AUDIO_DATA）。
  bool _streaming = false;

  /// 设备端暂停/继续/停止录音事件（audio 通道 `AUDIO_PAUSE_PLAY_BY_DEVICE`）。
  /// 值对齐 iOS：0 停止 / 1 录音中 / 2 暂停 / 3 继续。
  final _deviceRecordCtrl = StreamController<int>.broadcast();

  /// 文件下载会话（设备主动推流 cmd=4，cmd=5/6 收尾）。
  _DownloadSession? _downloadSession;
  final _fileDataCtrl = StreamController<Uint8List>.broadcast();
  final _downloadProgressCtrl = StreamController<int>.broadcast();

  /// 设备模式状态流（cmd=14）。
  Stream<DeviceMode> get statusStream => _statusCtrl.stream;

  /// 按键事件流（来自 0xAE23 通道的按键命令帧）。
  Stream<Frame> get keyEventStream => _keyEventCtrl.stream;

  /// 设备端暂停/继续/停止录音事件流（audio `AUDIO_PAUSE_PLAY_BY_DEVICE`）。
  /// 值：0 停止 / 2 暂停 / 3 继续（对齐 iOS 映射）。
  Stream<int> get deviceRecordStream => _deviceRecordCtrl.stream;

  /// 文件下载数据流（设备 cmd=4 推送的每一块字节）。仅在 [downloadFile] 期间产出。
  Stream<Uint8List> get fileDataStream => _fileDataCtrl.stream;

  /// 文件下载进度流（已收字节数）。仅在 [downloadFile] 期间产出。
  Stream<int> get downloadProgressStream => _downloadProgressCtrl.stream;

  /// 所有解析成功的原始帧（调试用）。
  Stream<Frame> get rawFrameStream => _rawFrameCtrl.stream;

  /// 实时录音音频流（opus 原始字节，audio `AUDIO_DATA`）。仅 [startRecord] 后
  /// （门控置位）产出，[stopRecord] 后丢弃；对齐 iOS `deviceRecordData:`。
  Stream<Uint8List> get recordDataStream => _recordDataCtrl.stream;

  /// 启动：订阅传输层字节流。
  void start() {
    _incomingSub = _transport.incoming.listen(_processBytes);
  }

  void _processBytes(Uint8List chunk) {
    final frames = _assembler.addBytes(chunk);
    for (final frame in frames) {
      _handleFrame(frame);
    }
  }

  void _handleFrame(Frame frame) {
    // ACK 帧（数据类型=3 且无 cmd）不需回 ACK，也不参与请求配对。
    final isAck = frame.dataType == DataType.ack && frame.payload.isEmpty;
    if (isAck) return;

    // 收到设备数据包，立即回 ACK（相同包序号）。
    _sendAck(frame.seq);

    if (!_rawFrameCtrl.isClosed) _rawFrameCtrl.add(frame);

    // 文件列表多帧累积（对齐 iOS：cmd=1 多帧 + cmd=18 收尾）。
    if (_fileListAcc != null &&
        frame.dataType == DataType.file &&
        (frame.cmd == FileCmd.replyFileList ||
            frame.cmd == FileCmd.fileListDone)) {
      final acc = _fileListAcc!;
      if (frame.cmd == FileCmd.replyFileList) {
        acc.files.addAll(FileList.parse(frame.params));
      } else {
        // cmd=18 结束帧：完成并清空累积器（即使前面没收到 cmd=1 也算空列表完成）。
        _fileListAcc = null;
        if (!acc.completer.isCompleted) acc.completer.complete(acc.files);
      }
      // 文件列表帧不参与通用请求配对。
      return;
    }

    // 文件下载（设备主动推流：cmd=3 文件名 / cmd=4 数据 / cmd=5 当前文件结束 /
    // cmd=6 全部结束）。
    final dl = _downloadSession;
    if (dl != null &&
        frame.dataType == DataType.file &&
        (frame.cmd == FileCmd.fileStart ||
            frame.cmd == FileCmd.fileData ||
            frame.cmd == FileCmd.fileEnd ||
            frame.cmd == FileCmd.allFilesEnd)) {
      switch (frame.cmd) {
        case FileCmd.fileStart:
          dl.fileName = String.fromCharCodes(frame.params).trim();
          break;
        case FileCmd.fileData:
          final chunk = Uint8List.fromList(frame.params);
          dl.received += chunk.length;
          if (!_fileDataCtrl.isClosed) _fileDataCtrl.add(chunk);
          if (!_downloadProgressCtrl.isClosed) _downloadProgressCtrl.add(dl.received);
          break;
        case FileCmd.fileEnd:
          final endCode = frame.params.isNotEmpty
              ? FileEndCode.fromByte(frame.params[0])
              : FileEndCode.other;
          _finishDownload(dl, endCode);
          break;
        case FileCmd.allFilesEnd:
          // 批量全部结束，视为当前文件完成。
          _finishDownload(dl, FileEndCode.completed);
          break;
      }
      // 下载帧不参与通用请求配对。
      return;
    }

    // 完成等待中的请求（匹配 dataType + cmd）。
    for (var i = _pending.length - 1; i >= 0; i--) {
      final p = _pending[i];
      if (p.dataType == frame.dataType && p.cmd == frame.cmd) {
        _pending.removeAt(i);
        if (!p.completer.isCompleted) p.completer.complete(frame);
      }
    }

    // 主动事件分发。
    if (frame.dataType == DataType.control &&
        frame.cmd == ControlCmd.deviceMode) {
      if (!_statusCtrl.isClosed) {
        _statusCtrl.add(DeviceMode.parse(frame.params));
      }
    } else if (frame.dataType == DataType.realtime &&
        frame.cmd == AudioCmd.data) {
      // 实时 opus 音频帧（对齐 iOS AUDIO_DATA）：params 即纯 opus 字节。
      // 未开流时丢弃（对齐 iOS isRecording 守卫）。
      if (_streaming && !_recordDataCtrl.isClosed) {
        _recordDataCtrl.add(Uint8List.fromList(frame.params));
      }
    } else if (frame.dataType == DataType.realtime &&
        frame.cmd == AudioCmd.pausePlayByDevice &&
        frame.params.isNotEmpty) {
      // 设备端暂停/继续/停止（对齐 iOS paserAudioData）：
      // flag 2→停止(0) / 1→暂停(2) / 0→继续(3)。
      final flag = frame.params[0];
      final state = switch (flag) {
        2 => 0, // 停止
        1 => 2, // 暂停
        0 => 3, // 继续
        _ => flag,
      };
      if (!_deviceRecordCtrl.isClosed) _deviceRecordCtrl.add(state);
    } else if (frame.dataType == DataType.key && frame.payload.isNotEmpty) {
      if (!_keyEventCtrl.isClosed) _keyEventCtrl.add(frame);
    }
  }

  int _nextSeq() {
    final s = _seq;
    _seq = (_seq + 1) & 0xFF;
    return s;
  }

  /// 业务发送（控制指令、文件下载请求等）。
  Future<void> _sendRaw(Uint8List bytes) => _transport.send(bytes);

  /// 发送 ACK：与数据帧同一通道回给设备。
  Future<void> _sendAck(int seq) {
    return _transport.send(FrameCodec.ack(seq));
  }

  /// 发送一条命令（不等待回复）。
  Future<void> sendCommand(int dataType, int cmd, {List<int> params = const []}) {
    final frame = FrameCodec.encodeCmd(dataType, cmd, _nextSeq(), params: params);
    return _sendRaw(frame);
  }

  /// 发送命令并等待指定 (dataType, replyCmd) 的回包。
  Future<Frame> request(
    int dataType,
    int cmd, {
    List<int> params = const [],
    required int replyDataType,
    required int replyCmd,
  }) async {
    final pending = _PendingRequest(replyDataType, replyCmd);
    _pending.add(pending);
    await sendCommand(dataType, cmd, params: params);
    try {
      return await pending.completer.future.timeout(responseTimeout);
    } on TimeoutException {
      _pending.remove(pending);
      rethrow;
    }
  }

  // ---- 高层 API ----

  /// 同步北京时间（默认当前时间）。
  Future<void> syncTime([DateTime? time]) {
    final payload = encodeSyncTime(time ?? DateTime.now());
    return sendCommand(DataType.control, ControlCmd.syncTime, params: payload);
  }

  /// 获取电量。
  Future<BatteryInfo> getBattery() async {
    final f = await request(
      DataType.control,
      ControlCmd.getBattery,
      replyDataType: DataType.control,
      replyCmd: ControlCmd.replyBattery,
    );
    return BatteryInfo.parse(f.params);
  }

  /// 获取容量。
  Future<Capacity> getCapacity() async {
    final f = await request(
      DataType.control,
      ControlCmd.getCapacity,
      replyDataType: DataType.control,
      replyCmd: ControlCmd.replyCapacity,
    );
    return Capacity.parse(f.params);
  }

  /// 获取固件版本。
  Future<String> getVersion() async {
    final f = await request(
      DataType.control,
      ControlCmd.getVersion,
      replyDataType: DataType.control,
      replyCmd: ControlCmd.replyVersion,
    );
    return String.fromCharCodes(f.params).trim();
  }

  /// 获取 MAC（协议无 SN，MAC 即设备唯一标识）。
  /// 回包为字符串格式，中间加冒号，可能带 's' 前缀。
  Future<String> getMac() async {
    final f = await request(
      DataType.control,
      ControlCmd.getMac,
      replyDataType: DataType.control,
      replyCmd: ControlCmd.replyMac,
    );
    return String.fromCharCodes(f.params).trim();
  }

  /// 开始录音。对齐 iOS `DataEncapsulation.startRecord`：走 audio 通道 `01 00`。
  ///
  /// iOS SDK 为 fire-and-forget（发送后立即回调 record_state=1，不等设备应答），
  /// 故这里发送成功即返回 true。音频流随录音自动开启：设备收到 `01 00` 后
  /// 自动持续下发 `AUDIO_DATA` opus 帧，经 [recordDataStream] 产出。
  Future<bool> startRecord() async {
    _streaming = true;
    await sendCommand(DataType.realtime, AudioCmd.startRecord);
    return true;
  }

  /// 停止（保存）录音。对齐 iOS `DataEncapsulation.stopRecord`：走 audio 通道
  /// `01 02`，且**连发两次**以确保到达。同时关闭音频流门控（对齐 iOS
  /// `isRecording = NO`），在途 opus 帧即被丢弃。
  Future<bool> stopRecord() async {
    _streaming = false;
    await sendCommand(DataType.realtime, AudioCmd.stopRecord);
    await sendCommand(DataType.realtime, AudioCmd.stopRecord);
    return true;
  }

  /// 暂停录音。对齐 iOS `DataEncapsulation.pauseRecord`：`01 03 01`。
  Future<bool> pauseRecord() async {
    await sendCommand(DataType.realtime, AudioCmd.pausePlay,
        params: const [AudioCmd.pauseFlag]);
    return true;
  }

  /// 继续录音。对齐 iOS `DataEncapsulation.continueRecord`：`01 03 00`。
  Future<bool> resumeRecord() async {
    await sendCommand(DataType.realtime, AudioCmd.pausePlay,
        params: const [AudioCmd.resumeFlag]);
    return true;
  }

  /// 获取录音状态（1 在录音 / 2 不在录音）。
  Future<RecordState> getRecordState() async {
    final f = await request(
      DataType.key,
      KeyCmd.getRecordState,
      replyDataType: DataType.key,
      replyCmd: KeyCmd.replyRecordState,
    );
    if (f.params.isEmpty) return RecordState.unknown;
    return f.params[0] == 1 ? RecordState.recording : RecordState.idle;
  }

  /// 获取文件列表（对齐 iOS：列表可能分多帧 cmd=1 到达，cmd=18 收尾）。
  Future<List<PenFile>> getFileList() async {
    final acc = _FileListAccumulator();
    _fileListAcc = acc;
    await sendCommand(DataType.file, FileCmd.getFileList);
    try {
      return await acc.completer.future.timeout(responseTimeout);
    } on TimeoutException {
      _fileListAcc = null;
      rethrow;
    }
  }

  /// 下载一个录音文件。设备收到请求后主动推流（cmd=4），收齐或失败时 future 完成。
  ///
  /// - [name]：文件名（取自 [PenFile.name]）。
  /// - [offset]：续传起始偏移（字节，小端 4B）。0 = 从头下载；断点续传传已收字节数。
  ///
  /// 期间数据块经 [fileDataStream] 产出、进度（已收字节）经 [downloadProgressStream]
  /// 产出。超时默认 5 分钟（文件可能较大）。
  Future<FileDownloadResult> downloadFile(
    String name, {
    int offset = 0,
    int? end,
    Duration timeout = const Duration(minutes: 5),
  }) async {
    final session = _DownloadSession(name);
    _downloadSession = session;
    final nameBytes = utf8.encode(name);
    final offsetLe = <int>[
      offset & 0xFF,
      (offset >> 8) & 0xFF,
      (offset >> 16) & 0xFF,
      (offset >> 24) & 0xFF,
    ];
    // end != null → 分段下载（cmd=12，body=offset+end+name）；否则续传下载（cmd=2，body=offset+name）。
    // 两者回包均走 cmd=3/4/5，复用同一下载会话。
    final int cmd;
    final List<int> params;
    if (end != null) {
      cmd = FileCmd.requestFileByFromToEnd;
      final endLe = <int>[
        end & 0xFF,
        (end >> 8) & 0xFF,
        (end >> 16) & 0xFF,
        (end >> 24) & 0xFF,
      ];
      params = <int>[...offsetLe, ...endLe, ...nameBytes];
    } else {
      cmd = FileCmd.requestFile;
      params = <int>[...offsetLe, ...nameBytes];
    }
    await sendCommand(DataType.file, cmd, params: params);
    try {
      return await session.completer.future.timeout(timeout);
    } on TimeoutException {
      _downloadSession = null;
      rethrow;
    }
  }

  /// 终止当前文件下载（发 cmd=7）。设备停止推流。
  Future<void> abortDownload() async {
    await sendCommand(DataType.file, FileCmd.abortImport);
  }

  /// 删除一个录音文件（对齐 iOS `delFileData:`）。设备回 cmd=13：1B（0 成功/1 失败）。
  ///
  /// 请求帧数据体 = 4B padding（对齐 iOS 布局 type+cmd+4B+name）+ 文件名(UTF-8 变长)。
  Future<bool> delFileData(String name) async {
    final f = await request(
      DataType.file,
      FileCmd.deleteFiles,
      params: <int>[0, 0, 0, 0, ...utf8.encode(name)],
      replyDataType: DataType.file,
      replyCmd: FileCmd.replyDeleteFiles,
    );
    // 0 成功 / 1 失败（空体视为失败）。
    return f.params.isNotEmpty && f.params[0] == 0;
  }

  /// 删除全部录音文件（对齐 iOS `delAllFileData`）。无参帧，设备回 cmd=10：1B（0 成功/1 失败）。
  Future<bool> deleteAllFiles() async {
    final f = await request(
      DataType.file,
      FileCmd.deleteAll,
      replyDataType: DataType.file,
      replyCmd: FileCmd.replyDeleteAll,
    );
    // 0 成功 / 1 失败（空体视为失败）。
    return f.params.isNotEmpty && f.params[0] == 0;
  }

  /// 完成下载会话：清空并 complete future。
  void _finishDownload(_DownloadSession dl, FileEndCode endCode) {
    _downloadSession = null;
    if (!dl.completer.isCompleted) {
      dl.completer.complete(FileDownloadResult(
        endCode: endCode,
        fileName: dl.fileName.isEmpty ? dl.requestedName : dl.fileName,
        receivedBytes: dl.received,
      ));
    }
  }

  /// 释放资源。
  Future<void> dispose() async {
    await _incomingSub?.cancel();
    _incomingSub = null;
    for (final p in _pending) {
      if (!p.completer.isCompleted) {
        p.completer.completeError(StateError('controller disposed'));
      }
    }
    _pending.clear();
    final acc = _fileListAcc;
    if (acc != null && !acc.completer.isCompleted) {
      acc.completer.completeError(StateError('controller disposed'));
    }
    _fileListAcc = null;
    final dl = _downloadSession;
    if (dl != null && !dl.completer.isCompleted) {
      dl.completer.completeError(StateError('controller disposed'));
    }
    _downloadSession = null;
    _assembler.reset();
    await _statusCtrl.close();
    await _keyEventCtrl.close();
    await _deviceRecordCtrl.close();
    await _fileDataCtrl.close();
    await _downloadProgressCtrl.close();
    await _recordDataCtrl.close();
    await _rawFrameCtrl.close();
  }
}
