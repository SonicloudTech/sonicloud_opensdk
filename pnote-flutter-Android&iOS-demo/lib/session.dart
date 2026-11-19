import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:pnote_flutter_sdk/pnote_flutter_sdk.dart';

import 'asr/pen_asr_service.dart';
import 'asr/sinicloud_auth.dart';
import 'audio/opus_bootstrap.dart';
import 'audio/recording_store.dart';
import 'l10n/gen/app_localizations.dart';

/// Activity 控制台日志级别。
enum LogKind { info, event, error }

class LogEntry {
  LogEntry(this.time, this.kind, this.text);

  final DateTime time;
  final LogKind kind;
  final String text;
}

/// 本地保存的一条录音：App 自录（recordings/app）或设备下载（recordings 根目录）。
class LocalRecording {
  LocalRecording(
    this.name,
    this.bytes,
    this.savedAt, {
    this.fromDevice = false,
  });

  final String name;
  final int bytes;
  final DateTime savedAt;

  /// true = 设备下载文件（recordings 根目录），false = App 自录（app 子目录）。
  /// 决定音频详情页用哪条转换/播放路径。
  final bool fromDevice;

  /// 时长由字节数反推：固件约定 40B/帧、20ms/帧。
  int get durationSec => bytes ~/ kOpusFrameSize * 20 ~/ 1000;
}

/// 全 App 共享的会话状态：扫描、连接、设备信息、录音状态、日志。
class Session extends ChangeNotifier {
  final sdk = AudioPenSdk(debugLog: false);

  /// 由 HomeShell 每次构建时注入（跟随当前语言），供无 context 的日志文案使用。
  AppLocalizations? l10n;
  AppLocalizations get L => l10n!;

  // ---- 扫描 ----
  bool scanning = false;
  List<ScanResult> results = const [];
  StreamSubscription<List<ScanResult>>? _scanSub;

  // ---- 连接 ----
  AudioPenDevice? device;
  String? _lastName;
  String? _lastAddress;
  final _subs = <StreamSubscription>[];

  // ---- 设备信息 ----
  BatteryInfo? battery;
  Capacity? capacity;
  String? version;

  // ---- 录音 ----
  bool recording = false;
  bool paused = false;
  int recordSeconds = 0;
  Timer? _recordTimer;

  // ---- 日志 ----
  final logs = <LogEntry>[];

  // ---- 本地录音（App 侧落盘，首页「近期录音」数据源） ----
  final _store = RecordingStore.instance;
  final recentRecordings = <LocalRecording>[];
  IOSink? _recSink;
  String? _recName;
  StreamSubscription<Uint8List>? _recDataSub;

  bool get connected => device != null;
  String? get lastDeviceName => _lastName;

  /// 客户自定义用户 ID（开放平台 X-SC-User-Id；与转写 userid 同源派生）。
  String get userId => 'sn${device?.id.replaceAll(':', '') ?? 'app'}';

  // ---- 实时转写 ----

  final asr = PenAsrService.instance;

  /// 声云开放平台访问令牌（启动即取，2h 有效自动缓存，供后续云端能力使用）。
  final auth = SinicloudAuth.instance;

  /// 转写开关（首页录音卡的 Switch；录音中切换立即生效）。
  bool asrEnabled = true;

  /// 定稿字幕（errCode=0）。
  final transcript = <String>[];

  /// 临时字幕（errCode=3，“正在说”）。
  String? tempTranscript;

  StreamSubscription<Map<String, dynamic>>? _asrResultsSub;

  Session() {
    asr.onConnecting = () => log(L.logAsrConnecting);
    asr.onConnected = () => log(L.logAsrConnected, LogKind.event);
    asr.onDisconnected = () => log(L.logAsrDisconnected, LogKind.error);
    asr.onConnectFailed = (e) => log(L.logAsrConnectFailed(e), LogKind.error);
    asr.onReconnectScheduled = (n, s) => log(L.logAsrReconnect(n, s));
    asr.onDecodeWarn = () => log(L.logAsrDecodeWarn, LogKind.error);
    asr.onLowBalance = (sec) => log(L.logAsrLowBalance(sec), LogKind.error);
    asr.onServerError = (code, msg) =>
        log(L.logAsrServerError(code, msg), LogKind.error);
    _asrResultsSub = asr.results.listen(_onAsrResult);
    unawaited(_loadRecentRecordings());
    unawaited(_warmUpToken());
  }

  /// 打开 App 先获取声云访问令牌（无网络等失败仅记录，不阻塞启动）。
  Future<void> _warmUpToken() async {
    final ok = await auth.fetchToken() != null;
    log(
      ok ? L.logTokenFetched : L.logTokenFailed,
      ok ? LogKind.event : LogKind.error,
    );
  }

  /// 启动时扫本地两个录音目录（自录 + 设备下载），恢复「近期录音」列表。
  Future<void> _loadRecentRecordings() async {
    try {
      final files = <File>[
        ...await _store.listAppOpus(),
        ...await _store.listDownloadedOpus(),
      ]..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      for (final f in files) {
        if (recentRecordings.length >= 20) break;
        recentRecordings.add(
          LocalRecording(
            f.uri.pathSegments.last,
            await f.length(),
            f.lastModifiedSync(),
            fromDevice: !f.parent.path.endsWith('app'),
          ),
        );
      }
      notifyListeners();
    } catch (_) {}
  }

  /// 设备文件下载完成后同步进「近期录音」。
  void addDownloadedToRecent(String name, int bytes) {
    recentRecordings.insert(
      0,
      LocalRecording(name, bytes, DateTime.now(), fromDevice: true),
    );
    if (recentRecordings.length > 20) {
      recentRecordings.removeRange(20, recentRecordings.length);
    }
    notifyListeners();
  }

  /// 本地文件被删除时同步移出「近期录音」。
  void removeRecent(String name) {
    final before = recentRecordings.length;
    recentRecordings.removeWhere((r) => r.name == name);
    if (recentRecordings.length != before) notifyListeners();
  }

  /// 删除一条本地录音：自录含转写文本，下载件按设备文件目录清理（不动设备端）。
  Future<void> deleteLocalRecording(LocalRecording rec) async {
    try {
      if (rec.fromDevice) {
        await _store.remove(rec.name);
      } else {
        await _store.removeApp(rec.name);
      }
      removeRecent(rec.name);
    } catch (e) {
      log(L.logDeleteFailed('$e'), LogKind.error);
    }
  }

  /// 开放平台结果分流：errCode=3 临时（反复覆盖）/ 0 定稿（追加）。
  /// role=1 时帧携带 spkid，行前缀「说话人N：」随文本进全屏页与落盘 txt。
  void _onAsrResult(Map<String, dynamic> json) {
    final text = json['result']?.toString() ?? '';
    final errCode = json['errCode']?.toString() ?? '';
    if (text.isEmpty) return;
    final spk = json['spkid']?.toString() ?? '';
    final withSpeaker =
        spk.isEmpty ? text : '${L.speakerPrefix(spk)}$text';
    if (errCode == '3') {
      tempTranscript = withSpeaker;
    } else if (errCode == '0') {
      transcript.add(withSpeaker);
      tempTranscript = null;
    }
    notifyListeners();
  }

  /// 录音开始后按需启动转写（按钮/物理按键路径共用）。
  Future<void> _startAsrIfEnabled() async {
    final d = device;
    if (!asrEnabled || d == null) return;
    transcript.clear();
    tempTranscript = null;
    notifyListeners();
    // userid 规则沿用源项目 sn+用户标识；demo 无登录体系，用设备 MAC 派生。
    final userKey = d.id.replaceAll(':', '');
    try {
      await asr.start(d.recordDataStream, 'sn$userKey');
      log(L.logAsrSessionStarted, LogKind.event);
    } catch (e) {
      log(L.logAsrStartFailed('$e'), LogKind.error);
    }
  }

  /// 切换转写开关。
  Future<void> setAsrEnabled(bool v) async {
    asrEnabled = v;
    notifyListeners();
    if (!v) {
      await asr.finishSession();
    } else if (recording && !asr.sessionActive) {
      await _startAsrIfEnabled();
    }
  }

  void log(String text, [LogKind kind = LogKind.info]) {
    debugPrint('[DEMO] $text');
    logs.insert(0, LogEntry(DateTime.now(), kind, text));
    if (logs.length > 500) logs.removeRange(500, logs.length);
    notifyListeners();
  }

  void clearLogs() {
    logs.clear();
    notifyListeners();
  }

  // ---- 扫描 ----

  Future<void> startScan() async {
    scanning = true;
    results = const [];
    notifyListeners();
    _scanSub?.cancel();
    _scanSub = sdk.startSearch(timeout: const Duration(seconds: 15)).listen((
      r,
    ) {
      results = r;
      notifyListeners();
    });
    await FlutterBluePlus.isScanning.firstWhere((s) => s == false);
    scanning = false;
    notifyListeners();
  }

  Future<void> stopScan() => sdk.stopSearch();

  // ---- 连接 ----

  Future<void> connect(ScanResult r) =>
      _connectAndSetup(() => sdk.connectDevice(r.device));

  /// 按名字+地址重连上次设备（设备未在广播也能发起）。
  Future<void> reconnect() => _connectAndSetup(
    () => sdk.connectDeviceAndAddress(_lastName!, _lastAddress!),
  );

  Future<void> _connectAndSetup(
    Future<AudioPenDevice> Function() connect,
  ) async {
    try {
      final d = await connect();
      device = d;
      _lastName = d.name;
      _lastAddress = d.id;
      notifyListeners();
      log(
        L.logConnected(d.name.isEmpty ? L.unnamedDevice : d.name, d.id),
        LogKind.event,
      );

      _subs.add(
        d.connectionState.listen((s) {
          if (s == TransportState.disconnected && device != null) {
            log(L.logUnexpectedDisconnect, LogKind.error);
            _teardown();
          }
        }),
      );
      _subs.add(
        d.keyEventStream.listen((f) async {
          log(L.logPhysicalKey(f.cmd), LogKind.event);
          // 物理按键：1 开始 / 3 保存(停止) / 5 暂停 / 7 继续；
          // 收到开始/停止按键时回发对应指令（设备期望的按键应答）。
          switch (f.cmd) {
            case 1:
              _enterRecording();
              await d.startRecord();
            case 3:
              _enterStopped();
              await d.stopRecord();
            case 5:
              _enterPaused();
            case 7:
              _enterResumed();
          }
        }),
      );
      _subs.add(
        d.deviceRecordStream.listen((state) {
          // 设备端物理操作：0 停止 / 2 暂停 / 3 继续。
          log(L.logDeviceRecordState(state), LogKind.event);
          switch (state) {
            case 0:
              _enterStopped();
            case 2:
              _enterPaused();
            case 3:
              _enterResumed();
          }
        }),
      );
      _subs.add(
        d.appEventStream.listen(
          (json) => log(L.logAppEvent(json), LogKind.event),
        ),
      );

      try {
        await d.syncTime();
        log(L.logTimeSynced);
        await refreshInfo();
      } catch (e) {
        log(L.logSetupFailed('$e'), LogKind.error);
      }
    } catch (e) {
      log(L.logConnectFailed('$e'), LogKind.error);
    }
  }

  void _teardown() {
    _stopTimer();
    // 录音中断连：保留已落盘的半段（可播放），不静默丢弃。
    unawaited(_finishLocalSave());
    unawaited(asr.finishSession());
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    device = null;
    battery = null;
    capacity = null;
    version = null;
    recording = false;
    paused = false;
    recordSeconds = 0;
    notifyListeners();
  }

  Future<void> disconnect() async {
    final d = device;
    _teardown();
    await d?.closeConnect();
    log(L.logDisconnected);
  }

  // ---- 设备信息 ----

  Future<void> refreshInfo() async {
    final d = device;
    if (d == null) return;
    try {
      battery = await d.getCBC();
      capacity = await d.getDeviceCapacity();
      version = await d.getDeviceVersion();
      notifyListeners();
      log(
        L.logDeviceInfo(
          battery!.percent,
          fmtKb(capacity!.usedKb),
          fmtKb(capacity!.totalKb),
          version!,
        ),
        LogKind.event,
      );
    } catch (e) {
      log(L.logRefreshFailed('$e'), LogKind.error);
    }
  }

  // ---- 录音控制 ----

  Future<void> startRecord() => _record(
    () => L.actionStartRecording,
    (d) => d.startRecordAppJson(),
    _enterRecording,
  );

  Future<void> stopRecord() => _record(
    () => L.actionStopRecording,
    (d) => d.stopRecordAppJson(),
    _enterStopped,
  );

  Future<void> pauseRecord() => _record(
    () => L.actionPauseRecording,
    (d) => d.pauseRecordAppJson(),
    _enterPaused,
  );

  Future<void> resumeRecord() => _record(
    () => L.actionResumeRecording,
    (d) => d.continueRecordAppJson(),
    _enterResumed,
  );

  Future<void> _record(
    String Function() label,
    Future<String> Function(AudioPenDevice) action,
    VoidCallback onDone,
  ) async {
    final d = device;
    if (d == null) return;
    try {
      log('→ ${await action(d)}', LogKind.event);
      onDone();
    } catch (e) {
      log(L.logActionFailed(label(), '$e'), LogKind.error);
    }
  }

  // ---- 本地录音落盘 ----

  /// 录音开始：tee 实时 opus 流到本地文件（与转写共用 broadcast 流，互不影响）。
  Future<void> _startLocalSave() async {
    final d = device;
    if (d == null) return;
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final name =
        'REC_${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}${two(now.second)}.opus';
    try {
      _recSink = (await _store.appOpusFile(name)).openWrite();
      _recName = name;
      _recDataSub = d.recordDataStream.listen((c) => _recSink?.add(c));
    } catch (e) {
      log(L.logLocalSaveFailed('$e'), LogKind.error);
    }
  }

  /// 录音结束：关流收尾，进「近期录音」。空文件不保留。
  /// 暂停期间设备不发帧，文件自然缺失该段，无需特殊处理。
  Future<void> _finishLocalSave() async {
    final sink = _recSink;
    final name = _recName;
    _recSink = null;
    _recName = null;
    await _recDataSub?.cancel();
    _recDataSub = null;
    if (sink == null || name == null) return;
    try {
      await sink.flush();
      await sink.close();
      final f = await _store.appOpusFile(name);
      final bytes = await f.length();
      if (bytes < kOpusFrameSize) {
        await f.delete();
        return;
      }
      final rec = LocalRecording(name, bytes, DateTime.now());
      recentRecordings.insert(0, rec);
      if (recentRecordings.length > 20) {
        recentRecordings.removeRange(20, recentRecordings.length);
      }
      log(
        L.logSavedLocally(
          name.replaceAll('.opus', ''),
          fmtDuration(rec.durationSec),
        ),
        LogKind.event,
      );
      // 转写定稿随录音一并落盘（未开启转写则跳过，详情页不显示转写卡）。
      if (transcript.isNotEmpty) {
        try {
          await (await _store.appTranscriptFile(name))
              .writeAsString(transcript.join('\n'));
        } catch (e) {
          log(L.logLocalSaveFailed('$e'), LogKind.error);
        }
      }
      notifyListeners();
    } catch (e) {
      log(L.logLocalSaveFailed('$e'), LogKind.error);
    }
  }

  // ---- 录音计时（UI 与物理按键/设备端事件共用） ----

  void _startTimer() {
    _stopTimer();
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      recordSeconds++;
      notifyListeners();
    });
  }

  void _stopTimer() {
    _recordTimer?.cancel();
    _recordTimer = null;
  }

  void _enterRecording() {
    if (recording) return;
    recording = true;
    paused = false;
    recordSeconds = 0;
    _startTimer();
    unawaited(_startLocalSave());
    unawaited(_startAsrIfEnabled());
    notifyListeners();
  }

  void _enterStopped() {
    if (!recording) return;
    _stopTimer();
    recording = false;
    paused = false;
    unawaited(_finishLocalSave());
    unawaited(asr.finishSession());
    notifyListeners();
  }

  void _enterPaused() {
    if (!recording || paused) return;
    _stopTimer();
    paused = true;
    notifyListeners();
  }

  void _enterResumed() {
    if (!recording || !paused) return;
    paused = false;
    _startTimer();
    notifyListeners();
  }

  @override
  void dispose() {
    _stopTimer();
    _scanSub?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _asrResultsSub?.cancel();
    _recDataSub?.cancel();
    unawaited(_finishLocalSave());
    unawaited(asr.finishSession());
    device?.closeConnect();
    super.dispose();
  }
}

/// KB → 人类可读。
String fmtKb(int kb) => fmtBytes(kb * 1024);

String fmtBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(kb < 10 ? 1 : 0)} KB';
  final mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
  return '${(mb / 1024).toStringAsFixed(2)} GB';
}

String fmtDuration(int sec) {
  final h = sec ~/ 3600;
  final m = (sec % 3600) ~/ 60;
  final s = sec % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}
