import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:opus_dart/opus_dart.dart';
import 'package:opus_flutter/opus_flutter.dart' as opus_flutter;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:soni_sdk_demo/service_audio_export.dart';
import 'package:soni_sdk_demo/service_file_share.dart';
import 'package:soni_sdk_demo/service_network_permission.dart';
import 'package:soni_sdk_demo/wave_write.dart';

import 'bluetooth_constants.dart';
import 'demo_function_panel.dart';
import 'demo_home_tabs.dart';
import 'demo_log_header.dart';
import 'demo_test_page.dart';
import 'demo_theme.dart';
import 'device_auth_config.dart';
import 'file_transfer_test/file_transfer_test_runner.dart';
import 'log_clipboard.dart';
import 'logger.dart';
import 'ogg_opus_writer.dart';
import 'ota_automation/ota_automation_runner.dart';
import 'provider_record_pen.dart';
import 'test_report.dart';

void main() async {
  /// 等待初始化
  WidgetsFlutterBinding.ensureInitialized();

  if (!Platform.isAndroid) {
    final lib = await opus_flutter.load();
    initOpus(lib);
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => RecordPenProvider())],

      child: MaterialApp(
        title: 'SoniSDKDemo',
        debugShowCheckedModeBanner: false,
        theme: createDemoTheme(),
        home: const MyHomePage(
          title: deviceAes256Gcm ? 'SoniSDKDemo-BK解密' : 'SoniSDKDemo',
        ),
      ),
    );
  }
}

class AudioTaskQueue {
  Future<void> _pending = Future<void>.value();

  Future<void> run(Future<void> Function() operation) {
    final next = _pending.then((_) => operation());
    _pending = next.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return next;
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  late RecordPenProvider _recordPenProvider;
  late OtaAutomationRunner _otaRunner;
  late FileTransferTestRunner _transferTestRunner;
  final TestReportStore _testReports = TestReportStore();
  final ScrollController _scrollController = ScrollController();
  final List _data = [];
  bool _audioRateExpanded = false;
  bool _autoScrollLog = true;

  late SimpleOpusDecoder _recordDecoder;
  late SimpleOpusDecoder _transferDecoder;

  final AudioPlayer _audioPlayer = AudioPlayer();

  Directory? _directory;

  static const _recordPcmName = 'record_play.pcm';
  static const _transferPcmName = 'transfer_play.pcm';
  static const _recordWavName = 'record_play.wav';
  static const _transferWavName = 'transfer_play.wav';

  bool get _useOggStorage => Platform.isAndroid;
  String get _recordAudioName =>
      _useOggStorage ? 'record_play.ogg' : _recordWavName;
  String get _transferAudioName =>
      _useOggStorage ? 'transfer_play.ogg' : _transferWavName;

  int _recordPcmSamples = 0;
  int _transferPcmSamples = 0;
  int _recordOpusFrames = 0;
  int _recordOpusBytes = 0;
  int _transferOpusFrames = 0;
  int _transferOpusBytes = 0;
  DateTime? _lastRecordAudioLogAt;
  DateTime? _lastTransferAudioLogAt;
  static const _audioLogInterval = Duration(seconds: 1);
  File? _recordPcmFile;
  File? _transferPcmFile;
  IOSink? _recordPcmSink;
  IOSink? _transferPcmSink;
  OggOpusWriter? _recordOggWriter;
  OggOpusWriter? _transferOggWriter;
  final AudioTaskQueue _recordAudioQueue = AudioTaskQueue();
  final AudioTaskQueue _transferAudioQueue = AudioTaskQueue();
  bool _recordStarting = false;
  bool _transferStarting = false;
  Future<void>? _recordFinishRequest;
  bool _recordAudioFinished = false;
  bool _recordAudioExists = false;
  bool _transferAudioExists = false;
  bool _audioExportInProgress = false;
  String _appVersion = '';
  final TextEditingController _sendFileTimeIntervalController =
      TextEditingController(text: '13');
  String? _selectedDeviceAddress;
  final TextEditingController _authkeyController = TextEditingController();
  int? _authkeyDeviceType;
  final TextEditingController _otaFirmwareNameController =
      TextEditingController();
  File? _otaFirmwareFile;
  bool _otaRequestInProgress = false;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController _bkFirmwarePathController =
      TextEditingController();
  final TextEditingController _bkUpgradeUrlController = TextEditingController();
  File? _bkFirmwareFile;

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
    if (!_useOggStorage) {
      _recordDecoder = SimpleOpusDecoder(sampleRate: 16000, channels: 1);
      _transferDecoder = SimpleOpusDecoder(sampleRate: 16000, channels: 1);
    }

    _recordPenProvider = Provider.of<RecordPenProvider>(context, listen: false);
    _otaRunner = OtaAutomationRunner(
      _recordPenProvider, canStartTest: () => !_transferTestRunner.isBusy,
      onReport: _testReports.append,
    );
    _transferTestRunner = FileTransferTestRunner(
      _recordPenProvider,
      startTransfer: (name, canSend) => _startTransferFile(name, canSend: canSend),
      setStorage: (enabled) async {
        if (!enabled) await _recordFinishRequest;
        await _setAudioDecodeAndStoreEnabled(enabled);
      },
      canStartTest: () => !_otaRunner.isRunning,
      onReport: _testReports.append,
    );
    _recordPenProvider.addListener(_syncAuthkeyForDevice);
    _syncAuthkeyForDevice();
    _recordPenProvider.init();

    _recordPenProvider.streamController.stream.listen((event) async {
      if (event.containsKey('audio')) {
        final audioType = event['audioType'] as String? ?? AudioDataType.record;
        final frame = event['audio'] as List<int>;
        if (audioType == AudioDataType.file) {
          await _transferAudioQueue.run(
            () => _processAudioFrame(frame, audioType),
          );
        } else {
          await _recordAudioQueue.run(
            () => _processAudioFrame(frame, audioType),
          );
        }
        _logAudioProgress(frame, audioType);
        return;
      }

      _appendLog(_formatEventLog(event));

      if (event['cmd']?.toString() == '5' &&
          event['data']?['record_file_state']?.toString() == '0') {
        _appendLog(
          '[传输音频] 接收完成: 共 $_transferOpusFrames 帧, '
          'Opus ${(_transferOpusBytes / 1024).toStringAsFixed(1)}KB, '
          '${_formatDecodedDuration(_transferPcmSamples)}',
        );
        if (_recordPenProvider.audioDecodeAndStoreEnabled) {
          final message = _useOggStorage
              ? '[蓝牙调试][文件传输] 传输完成，Ogg封装中，请稍候'
              : '[蓝牙调试][文件传输] 传输完成，解码中，请稍候';
          _appendLog(message);
          Log.d(message);
          await _transferAudioQueue.run(_finishTransferAudio);
        }
      }

      // 设备上报录音结束：cmd=3 record_state=0，或设备按键停止 cmd=8 event=3
      if (event['cmd']?.toString() == '3' &&
          event['data']?['record_state']?.toString() == '0') {
        _scheduleFinishRecordAudio();
      }
      if (event['cmd']?.toString() == '8' &&
          event['data']?['event']?.toString() == '3') {
        _scheduleFinishRecordAudio();
      }
    });

    [
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location,
      Permission.nearbyWifiDevices,
      Permission.bluetoothConnect,
    ].request();

    _initDirectory();

    // 首页加载后引导外网说明，并主动探测互联网（触发机型网络授权）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      NetworkPermissionService.requestOnHomeEnter(context);
    });
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _appVersion = info.buildNumber.isEmpty
            ? info.version
            : '${info.version}（${info.buildNumber}）';
      });
    } catch (_) {}
  }

  Future<void> _initDirectory() async {
    _directory = await _resolveStorageDirectory();
    await _refreshAudioExists();
  }

  Future<Directory> _ensureDirectory() async {
    _directory ??= await _resolveStorageDirectory();
    return _directory!;
  }

  /// 获取可写目录：Android 用外部存储，i
  ///
  /// S 等其它平台用应用文档目录
  Future<Directory> _resolveStorageDirectory() async {
    if (Platform.isAndroid) {
      final dir = await getExternalStorageDirectory();
      if (dir != null) return dir;
    }
    return getApplicationDocumentsDirectory();
  }

  /// 日志行前缀：年月日 时分秒（本地）
  String _formatLogTime(DateTime t) {
    String p2(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${p2(t.month)}-${p2(t.day)} ${p2(t.hour)}:${p2(t.minute)}:${p2(t.second)}';
  }

  void _appendLog(String message) {
    if (!mounted) return;
    setState(() {
      _data.add('${_formatLogTime(DateTime.now())} $message');
    });
    if (_autoScrollLog) _scrollLogToBottom();
  }

  void _scrollLogToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_autoScrollLog || !_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  String _formatEventLog(dynamic event) {
    if (event is! Map) return event.toString();
    if (event[RecordPenProvider.otaTransferErrorKey] case final String error) {
      return '[蓝牙调试][OTA升级] 失败：$error';
    }
    final heartbeatLog = event['heartbeatLog'];
    if (heartbeatLog is String) return '[蓝牙调试][心跳] $heartbeatLog';
    final intervalLog = event['设置传输间隔'];
    if (intervalLog is String) return '[蓝牙调试][传输间隔] $intervalLog';
    final cmd = event['cmd']?.toString();
    if (cmd == '100' || cmd == '101' || cmd == '102') {
      final data = event['data'];
      final intervalState = data is Map
          ? data['offline_transfer_interval_state']?.toString()
          : null;
      final failed = event['state']?.toString() != '0' ||
          (cmd == '100' && intervalState != '0');
      final category = cmd == '100' ? '传输间隔' : '心跳';
      return '[蓝牙调试][$category] ${failed ? '异常 ' : ''}$event';
    }
    if (cmd == '5') {
      final data = event['data'] as Map?;
      final state = data?['record_file_state']?.toString();
      final name = data?['name']?.toString() ?? '';
      final stateText =
          {
            '0': '传输完成',
            '1': '文件不存在',
            '2': 'offset过大',
            '3': '已停止',
            '4': '传输中',
          }[state] ??
          'state=$state';
      return '[文件传输] $stateText${name.isNotEmpty ? ' ($name)' : ''}';
    }
    return event.toString();
  }

  void _logAudioProgress(List<int> frame, String audioType) {
    final now = DateTime.now();
    if (_isRecordAudio(audioType)) {
      _recordOpusFrames++;
      _recordOpusBytes += frame.length;
      if (_lastRecordAudioLogAt != null &&
          now.difference(_lastRecordAudioLogAt!) < _audioLogInterval) {
        return;
      }
      _lastRecordAudioLogAt = now;
      final duration = _recordPcmSamples / 16000;
      _appendLog(
        '[录音音频] $_recordOpusFrames 帧, '
        'Opus ${(_recordOpusBytes / 1024).toStringAsFixed(1)}KB, '
        '${_formatDecodedDuration(_recordPcmSamples, duration: duration, audioType: audioType)}',
      );
      return;
    }

    _transferOpusFrames++;
    _transferOpusBytes += frame.length;
    if (_lastTransferAudioLogAt != null &&
        now.difference(_lastTransferAudioLogAt!) < _audioLogInterval) {
      return;
    }
    _lastTransferAudioLogAt = now;
    final duration = _transferPcmSamples / 16000;
    _appendLog(
      '[传输音频] $_transferOpusFrames 帧, '
      'Opus ${(_transferOpusBytes / 1024).toStringAsFixed(1)}KB, '
      '${_formatDecodedDuration(_transferPcmSamples, duration: duration)}',
    );
  }

  String _formatDecodedDuration(
    int samples, {
    double? duration,
    String audioType = AudioDataType.file,
  }) {
    if (!_recordPenProvider.audioDecodeAndStoreEnabled) {
      return _useOggStorage ? '未存储' : '未解码/未存储';
    }
    if (_useOggStorage) {
      final writer = _isRecordAudio(audioType)
          ? _recordOggWriter
          : _transferOggWriter;
      return '已封装 ${(writer?.durationSeconds ?? 0).toStringAsFixed(1)}秒（Ogg Opus）';
    }
    return '已解码 ${(duration ?? samples / 16000).toStringAsFixed(1)}秒';
  }

  Future<void> _setAudioDecodeAndStoreEnabled(bool enabled) async {
    if (_recordPenProvider.audioDecodeAndStoreEnabled == enabled) return;
    _recordPenProvider.setAudioDecodeAndStoreEnabled(enabled);
    if (!enabled) {
      await _transferAudioQueue.run(_closeAudioSinks);
    }
  }

  Future<void> _closeAudioSinks() async {
    try {
      await _recordAudioQueue.run(() async {
        try {
          await _discardOggAudio(_recordOggWriter, _recordAudioName);
          await _recordPcmSink?.flush();
          await _recordPcmSink?.close();
        } finally {
          _recordPcmSink = null;
          _recordOggWriter = null;
          _recordFinishRequest = null;
        }
      });
      if (_useOggStorage) {
        await _discardOggAudio(_transferOggWriter, _transferAudioName);
      }
      await _transferPcmSink?.flush();
      await _transferPcmSink?.close();
    } catch (e) {
      Log.e('关闭音频写入失败: $e');
    } finally {
      _transferPcmSink = null;
      _transferOggWriter = null;
    }
  }

  Future<void> _discardOggAudio(OggOpusWriter? writer, String name) async {
    if (writer == null) return;
    final dir = await _ensureDirectory();
    final pending = File('${dir.path}/$name.part');
    try {
      await writer.close();
    } finally {
      if (await pending.exists()) await pending.delete();
    }
  }

  Future<void> _copyLogToClipboard() async {
    if (_data.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('暂无日志')));
      return;
    }
    final lineCount = _data.length;
    final parts = LogClipboard.split(_data.map((e) => e.toString()).join('\n'));
    if (parts.length > 1) {
      await _showLogCopyParts(parts, lineCount);
      return;
    }
    final message = await _copyLogText(parts.single, '已完整复制 $lineCount 行日志');
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<String> _copyLogText(String text, String successMessage) async {
    try {
      if (await LogClipboard.copy(text)) return successMessage;
      return '复制不完整：系统剪贴板未能保存全部内容，请缩短日志后重试';
    } catch (_) {
      return '复制失败：无法读写系统剪贴板，请缩短日志或重试';
    }
  }

  Future<void> _showLogCopyParts(List<String> parts, int lineCount) async {
    var index = 0;
    var copying = false;
    var message = '';
    final copiedParts = <int>{};
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('日志过长，请分段复制'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '本次共 $lineCount 行日志，超过单次安全复制长度（256 KB），'
                '已保留完整内容并分为 ${parts.length} 段。每次复制后请先粘贴，再复制下一段。',
              ),
              const SizedBox(height: 12),
              Text('第 ${index + 1} / ${parts.length} 段，已复制 ${copiedParts.length} 段'),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: copying || index == 0
                        ? null
                        : () {
                            setDialogState(() {
                              index--;
                              message = '';
                            });
                          },
                    child: const Text('上一段'),
                  ),
                  TextButton(
                    onPressed: copying || index == parts.length - 1
                        ? null
                        : () {
                            setDialogState(() {
                              index++;
                              message = '';
                            });
                          },
                    child: const Text('下一段'),
                  ),
                ],
              ),
              if (message.isNotEmpty) Text(message),
            ],
          ),
          actions: [
            TextButton(
              onPressed: copying ? null : () => Navigator.of(dialogContext).pop(),
              child: const Text('关闭'),
            ),
            FilledButton(
              onPressed: copying
                  ? null
                  : () async {
                      setDialogState(() => copying = true);
                      final successMessage = '已完整复制第 ${index + 1} 段';
                      final result = await _copyLogText(parts[index], successMessage);
                      if (!dialogContext.mounted) return;
                      setDialogState(() {
                        copying = false;
                        message = result;
                        if (result == successMessage) copiedParts.add(index);
                      });
                    },
              child: Text(copying ? '复制中…' : '复制当前段'),
            ),
          ],
        ),
      ),
    );
  }

  bool _isRecordAudio(String audioType) => audioType == AudioDataType.record;

  Future<void> _startRecord({bool? boneMic}) async {
    if (_recordStarting || _recordPenProvider.isRecording) return;
    _recordStarting = true;
    try {
      Future<void>? pendingFinish;
      await _recordAudioQueue.run(() async {
        pendingFinish = _recordFinishRequest;
      });
      await pendingFinish;
      await _recordAudioQueue.run(() async {
        if (!mounted || _recordPenProvider.isRecording) return;
        await _resetRecordAudio();
        if (!mounted) return;
        if (boneMic == null) {
          await _recordPenProvider.startRecord();
        } else {
          await _recordPenProvider.startRecordWithBoneMic(boneMic);
        }
      });
    } finally {
      _recordStarting = false;
    }
  }

  Future<void> _resetRecordAudio() async {
    if (!_recordPenProvider.audioDecodeAndStoreEnabled) return;
    final dir = await _ensureDirectory();
    _recordPcmSamples = 0;
    _recordOpusFrames = 0;
    _recordOpusBytes = 0;
    _lastRecordAudioLogAt = null;
    _recordAudioFinished = false;
    _recordFinishRequest = null;
    if (_useOggStorage) {
      await _recordOggWriter?.close();
      _recordOggWriter = OggOpusWriter(
        File('${dir.path}/$_recordAudioName.part').openWrite(),
      );
      if (mounted) setState(() => _recordAudioExists = false);
      return;
    }
    await _recordPcmSink?.close();
    _recordPcmFile = File('${dir.path}/$_recordPcmName');
    _recordPcmSink = _recordPcmFile!.openWrite();
  }

  Future<void> _scheduleFinishRecordAudio() async {
    await _recordAudioQueue.run(() async {
      if (!_recordPenProvider.audioDecodeAndStoreEnabled) return;
      if (_recordFinishRequest != null || _recordAudioFinished) return;
      late final Future<void> request;
      request = Future<void>.delayed(const Duration(seconds: 1), () {
        return _recordAudioQueue.run(() async {
          if (_recordFinishRequest != request) return;
          try {
            await _finishRecordAudio();
          } finally {
            _recordFinishRequest = null;
          }
        });
      });
      _recordFinishRequest = request;
    });
  }

  Future<void> _startTransferFile(String name, {bool Function()? canSend}) async {
    await _transferAudioQueue.run(() async {
      if (canSend?.call() == false) return;
      await _resetTransferAudio();
      if (canSend?.call() == false) return;
      await _recordPenProvider.sendFileFromPenToPhoneWithOffset(name, 0);
    });
  }

  Future<void> _resetTransferAudio() async {
    if (!_recordPenProvider.audioDecodeAndStoreEnabled) return;
    final dir = await _ensureDirectory();
    _transferPcmSamples = 0;
    _transferOpusFrames = 0;
    _transferOpusBytes = 0;
    _lastTransferAudioLogAt = null;
    if (_useOggStorage) {
      await _transferOggWriter?.close();
      _transferOggWriter = OggOpusWriter(
        File('${dir.path}/$_transferAudioName.part').openWrite(),
      );
      if (mounted) setState(() => _transferAudioExists = false);
      return;
    }
    await _transferPcmSink?.close();
    _transferPcmFile = File('${dir.path}/$_transferPcmName');
    _transferPcmSink = _transferPcmFile!.openWrite();
  }

  Future<void> _ensurePcmSink(String audioType) async {
    if (!_recordPenProvider.audioDecodeAndStoreEnabled) return;
    if (_isRecordAudio(audioType)) {
      if (_recordPcmSink != null) return;
      await _resetRecordAudio();
      return;
    }
    if (_transferPcmSink != null) return;
    await _resetTransferAudio();
  }

  Future<void> _processAudioFrame(List<int> frame, String audioType) async {
    if (!_recordPenProvider.audioDecodeAndStoreEnabled) return;
    try {
      if (_useOggStorage) {
        if (_isRecordAudio(audioType)) {
          if (_recordOggWriter == null) await _resetRecordAudio();
          await _recordOggWriter!.addPacket(Uint8List.fromList(frame));
        } else {
          if (_transferOggWriter == null) await _resetTransferAudio();
          await _transferOggWriter!.addPacket(Uint8List.fromList(frame));
        }
        return;
      }
      await _ensurePcmSink(audioType);
      final decoder = _isRecordAudio(audioType)
          ? _recordDecoder
          : _transferDecoder;
      final intPcm = decoder.decode(input: Uint8List.fromList(frame));

      if (_isRecordAudio(audioType)) {
        _recordPcmSamples += intPcm.length;
      } else {
        _transferPcmSamples += intPcm.length;
      }

      await _writePcmToFile(intPcm, audioType);
    } catch (e) {
      if (_useOggStorage) {
        Log.e('[蓝牙调试][Ogg封装][$audioType] 保存失败: $e');
      } else {
        Log.e("[$audioType] 解码失败: $e");
      }
    }
  }

  Future<void> _convertPcmToWav(String pcmName, String wavName) async {
    final dir = await _ensureDirectory();
    final pcmPath = '${dir.path}/$pcmName';
    final wavPath = '${dir.path}/$wavName';
    final pcmFile = File(pcmPath);
    if (!(await pcmFile.exists())) {
      throw Exception('PCM 文件不存在: $pcmPath');
    }

    final pending = File('$wavPath.part');
    try {
      await WavWriter.writeWavFile(
        filePath: pending.path,
        pcmFile: pcmFile,
        sampleRate: 16000,
        channels: 1,
      );
      await pending.rename(wavPath);
    } finally {
      if (await pending.exists()) await pending.delete();
    }

    Log.f('PCM 转 WAV 成功: $wavPath');
  }

  Future<void> _writePcmToFile(Int16List pcmData, String audioType) async {
    final sink = _isRecordAudio(audioType) ? _recordPcmSink : _transferPcmSink;
    sink?.add(_int16ListToUint8List(pcmData));
  }

  Future<void> _finishRecordAudio() async {
    if (!_recordPenProvider.audioDecodeAndStoreEnabled) return;
    if (_recordAudioFinished) return;
    try {
      if (_useOggStorage) {
        await _finishOggAudio(AudioDataType.record);
        return;
      }
      await _recordPcmSink?.flush();
      await _recordPcmSink?.close();
      _recordPcmSink = null;

      final fileSize = await _recordPcmFile?.length() ?? 0;
      if (fileSize == 0) return;

      _recordAudioFinished = true;
      final duration = _recordPcmSamples / 16000;
      Log.f(
        '录音 PCM: $_recordPcmName, ${duration.toStringAsFixed(2)}秒, $fileSize 字节',
      );
      _appendLog(
        '[录音音频] 结束: 共 $_recordOpusFrames 帧, '
        'Opus ${(_recordOpusBytes / 1024).toStringAsFixed(1)}KB, '
        '已解码 ${duration.toStringAsFixed(1)}秒',
      );

      await _convertPcmToWav(_recordPcmName, _recordWavName);
      await _refreshAudioExists();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('录音已保存: $_recordWavName')));
    } catch (e) {
      Log.e('录音结束处理失败: $e');
    }
  }

  Future<void> _finishTransferAudio() async {
    if (!_recordPenProvider.audioDecodeAndStoreEnabled) return;
    try {
      if (_useOggStorage) {
        await _finishOggAudio(AudioDataType.file);
        return;
      }
      await _transferPcmSink?.flush();
      await _transferPcmSink?.close();
      _transferPcmSink = null;

      final duration = _transferPcmSamples / 16000;
      final fileSize = await _transferPcmFile?.length() ?? 0;
      if (fileSize == 0) return;
      Log.f(
        '传输 PCM: $_transferPcmName, ${duration.toStringAsFixed(2)}秒, $fileSize 字节',
      );

      await _convertPcmToWav(_transferPcmName, _transferWavName);
      await _refreshAudioExists();
      const message = '[蓝牙调试][文件传输] 解码完成，已保存: $_transferWavName';
      _appendLog(message);
      Log.d(message);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('传输文件已保存: $_transferWavName')));
    } catch (e) {
      final message = _useOggStorage
          ? '[蓝牙调试][文件传输] Ogg封装或保存失败: $e'
          : '[蓝牙调试][文件传输] 解码或保存失败: $e';
      _appendLog(message);
      Log.e(message);
    }
  }

  Future<void> _finishOggAudio(String audioType) async {
    final isRecord = _isRecordAudio(audioType);
    final writer = isRecord ? _recordOggWriter : _transferOggWriter;
    if (writer == null) return;
    final name = isRecord ? _recordAudioName : _transferAudioName;
    if (isRecord) {
      _recordOggWriter = null;
    } else {
      _transferOggWriter = null;
    }
    final dir = await _ensureDirectory();
    final pending = File('${dir.path}/$name.part');
    try {
      await writer.close();
      if (writer.durationSeconds == 0) return;
      await pending.rename('${dir.path}/$name');
    } finally {
      if (await pending.exists()) await pending.delete();
    }
    if (isRecord) _recordAudioFinished = true;
    await _refreshAudioExists();
    final message = '[蓝牙调试][${isRecord ? '录音' : '文件传输'}] Ogg封装完成，已保存: $name';
    _appendLog(message);
    Log.d(message);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${isRecord ? '录音' : '传输文件'}已保存: $name')),
    );
  }

  /// 刷新本地音频文件是否存在，用于控制播放按钮的可用状态
  Future<void> _refreshAudioExists() async {
    final dir = await _ensureDirectory();
    final recordExists =
        (!_useOggStorage || _recordOggWriter == null) &&
        await File('${dir.path}/$_recordAudioName').exists();
    final transferExists =
        (!_useOggStorage || _transferOggWriter == null) &&
        await File('${dir.path}/$_transferAudioName').exists();
    if (!mounted) return;
    if (recordExists != _recordAudioExists ||
        transferExists != _transferAudioExists) {
      setState(() {
        _recordAudioExists = recordExists;
        _transferAudioExists = transferExists;
      });
    }
  }

  /// 播放指定的音频文件（录音 / 传输）
  Future<void> _playAudio(String audioName, String label) async {
    try {
      final dir = await _ensureDirectory();
      final path = '${dir.path}/$audioName';
      final file = File(path);
      if (!await file.exists()) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$label 音频不存在，请先录音/传输')));
        return;
      }
      await _audioPlayer.stop();
      await _audioPlayer.play(DeviceFileSource(path));
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('正在播放$label')));
    } catch (e) {
      Log.e('播放$label失败: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('播放$label失败: $e')));
    }
  }

  Future<void> _shareAudio() async {
    if (_audioExportInProgress) return;
    setState(() => _audioExportInProgress = true);
    try {
      final dir = await _ensureDirectory();
      final files = <String, File>{};
      for (final (label, name) in [
        ('实时录音', _recordAudioName),
        ('传输音频', _transferAudioName),
      ]) {
        final file = File('${dir.path}/$name');
        if (await AudioFileExporter.isSaved(file)) files[label] = file;
      }
      if (!mounted) return;
      if (files.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('暂无已保存的音频，请先录音或传输文件')),
        );
        return;
      }
      final file = files.length == 1
          ? files.values.single
          : await showDialog<File>(
              context: context,
              builder: (context) => SimpleDialog(
                title: const Text('选择要分享的音频'),
                children: [
                  for (final entry in files.entries)
                    SimpleDialogOption(
                      onPressed: () => Navigator.pop(context, entry.value),
                      child: Text(entry.key),
                    ),
                ],
              ),
            );
      if (file == null || !mounted) return;
      await FileSharer.share(
        file,
        await getTemporaryDirectory(),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('分享音频失败：$error')),
      );
    } finally {
      if (mounted) setState(() => _audioExportInProgress = false);
    }
  }

  @override
  void dispose() {
    _transferTestRunner.dispose();
    _otaRunner.dispose();
    _testReports.dispose();
    _recordPenProvider.removeListener(_syncAuthkeyForDevice);
    _audioPlayer.dispose();
    _scrollController.dispose();
    _sendFileTimeIntervalController.dispose();
    _authkeyController.dispose();
    _otaFirmwareNameController.dispose();
    _bkFirmwarePathController.dispose();
    _bkUpgradeUrlController.dispose();
    super.dispose();
  }

  Uint8List _int16ListToUint8List(Int16List input) {
    final bytes = Uint8List(input.length * 2);
    final byteData = ByteData.sublistView(bytes);
    for (int i = 0; i < input.length; i++) {
      byteData.setInt16(i * 2, input[i], Endian.little);
    }
    return bytes;
  }

  Map<String, String>? _findSelectedDevice(RecordPenProvider provider) {
    if (_selectedDeviceAddress == null) return null;
    for (final device in provider.discoveredDevices) {
      if (device['address'] == _selectedDeviceAddress) {
        return device;
      }
    }
    return null;
  }

  void _connectSelectedDevice(RecordPenProvider provider) {
    final device = _findSelectedDevice(provider);
    if (device == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先搜索并选择要连接的设备')));
      return;
    }
    provider.connect(device);
  }

  void _syncAuthkeyForDevice() {
    final type = _recordPenProvider.isConnected
        ? _recordPenProvider.deviceType
        : null;
    if (_authkeyDeviceType == type) return;
    _authkeyDeviceType = type;
    _authkeyController.text = deviceAuthKeys[type] ?? '';
  }

  Future<void> _authkeyConnect(RecordPenProvider provider) async {
    try {
      await provider.authkeyConnect(_authkeyController.text);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('AuthKey 认证调用失败: $e')));
    }
  }

  Future<void> _runDeviceSetting(
    String title,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$title 调用失败: $e')));
    }
  }

  Future<void> _showSetAuthkeyDialog() async {
    final controller = TextEditingController();
    final authkey = await _showInputDialog(
      title: '修改AuthKey',
      controller: controller,
      hint: '请输入新的 64 位十六进制 AuthKey',
      trimInput: false,
    );
    if (authkey == null || !mounted) return;
    await _runDeviceSetting(
      '修改AuthKey',
      () => _recordPenProvider.resetAuthkey(authkey),
    );
  }

  Future<void> _showSetWifiPasswordDialog() async {
    final controller = TextEditingController(text: '12345678');
    final password = await _showInputDialog(
      title: '修改热点密码',
      controller: controller,
      hint: '8-16 个字符，下次开启热点生效',
    );
    if (password == null || !mounted) return;
    await _runDeviceSetting(
      '修改热点密码',
      () => _recordPenProvider.setWifiPassword(password),
    );
  }

  Future<void> _showWifiPasswordConnectDialog({bool quickConnect = false}) async {
    final controller = TextEditingController(text: quickConnect ? '' : '12345678');
    final title = quickConnect ? '一键连接WiFi' : '密码连接';
    final password = await _showInputDialog(
      title: title,
      controller: controller,
      hint: quickConnect ? '请输入设备热点密码，无密码可留空' : '请输入设备热点密码',
      keyboardType: TextInputType.visiblePassword,
      trimInput: false,
    );
    if (password == null || (!quickConnect && password.isEmpty) || !mounted) return;
    await _runDeviceSetting(
      title,
      () => quickConnect
          ? _recordPenProvider.quickConnectDeviceWiFi(password: password)
          : _recordPenProvider.connectDeviceWiFi(password: password),
    );
  }

  Widget _heartbeatSwitch(
    String title,
    bool value,
    ValueChanged<bool>? onChanged,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: Text(title, style: const TextStyle(fontSize: 12))),
        SizedBox(
          width: 44,
          height: 32,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Switch(
              value: value,
              onChanged: onChanged,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showSetTransferIntervalDialog() async {
    final input = await _showInputDialog(
      title: '设置传输间隔',
      controller: _sendFileTimeIntervalController,
      hint: '13–255 毫秒',
      keyboardType: TextInputType.number,
    );
    if (input == null || !mounted) return;
    await _runDeviceSetting('设置传输间隔', () async {
      final interval = int.tryParse(input, radix: 10);
      if (interval == null) throw const FormatException('请输入整数毫秒值');
      await _recordPenProvider.setSendFileTimeInterval(interval);
    });
  }

  String? _requireSelectedTransferFile() {
    final name = _recordPenProvider.transFileName;
    if (name.isNotEmpty) return name;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('请先获取并选择传输文件')));
    return null;
  }

  Future<void> _pickOtaFirmware() async {
    try {
      final result = await FilePicker.pickFiles(
        type: Platform.isIOS ? FileType.any : FileType.custom,
        allowedExtensions: Platform.isIOS ? null : ['ufw'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final picked = result.files.single;
      final name = picked.name;
      if (!name.toLowerCase().endsWith('.ufw')) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('请选择 .ufw 固件文件')));
        return;
      }

      File file;
      final dir = await getTemporaryDirectory();
      file = File('${dir.path}/ota_$name');
      if (picked.bytes != null) {
        await file.writeAsBytes(picked.bytes!, flush: true);
      } else if (picked.path != null && picked.path!.isNotEmpty) {
        await File(picked.path!).copy(file.path);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('无法读取所选固件')));
        return;
      }

      if (!mounted) return;
      setState(() {
        _otaFirmwareFile = file;
        _otaFirmwareNameController.text = name;
      });
      _appendLog('[OTA] 已选择固件: $name');
    } catch (e) {
      Log.e('选择固件失败: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('选择固件失败: $e')));
    }
  }

  Future<bool> _confirmLeaveTest() async {
    if (!_otaRunner.isRunning && !_transferTestRunner.isRunning) return true;
    final interrupt = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('是否中断测试？'),
        content: const Text('当前测试正在进行，返回设备页会中断本次测试。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('继续测试'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('中断并返回'),
          ),
        ],
      ),
    );
    if (interrupt != true || !mounted) return false;
    await _otaRunner.interrupt();
    await _transferTestRunner.interrupt();
    return true;
  }

  Future<void> _requestAndSendSelectedOtaFirmware() async {
    final file = _otaFirmwareFile;
    if (file == null || _otaRequestInProgress) return;
    setState(() => _otaRequestInProgress = true);
    _appendLog('[蓝牙调试][OTA升级] 请求升级并发送固件: ${_otaFirmwareNameController.text}');
    try {
      await _recordPenProvider.requestAndSendOtaFile(file.path);
    } catch (e) {
      Log.e('[蓝牙调试][OTA升级] 请求并发送失败: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('请求并发送失败: $e')));
    } finally {
      if (mounted) setState(() => _otaRequestInProgress = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final recordPenProvider = context.watch<RecordPenProvider>();
    final discoveredDevices = recordPenProvider.discoveredDevices;
    if (_selectedDeviceAddress != null &&
        !discoveredDevices.any((d) => d['address'] == _selectedDeviceAddress)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _selectedDeviceAddress = null);
      });
    }

    return DemoHomeTabs(
      scaffoldKey: _scaffoldKey,
      testPage: DemoTestPage(
        provider: recordPenProvider,
        runner: _otaRunner,
        transferRunner: _transferTestRunner,
        reportStore: _testReports,
      ),
      onLeaveTest: _confirmLeaveTest,
      appBar: AppBar(
        toolbarHeight: 40,
        titleSpacing: 8,
        actions: const [SizedBox.shrink()],
        title: Text(
          _appVersion.isEmpty ? widget.title : '${widget.title} V$_appVersion',
          style: const TextStyle(fontSize: 13),
        ),
      ),
      endDrawer: Drawer(
        width: MediaQuery.sizeOf(context).width * 0.88,
        child: _buildBkOtaDrawer(),
      ),
      device: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: <Widget>[
            Expanded(flex: 2, child: _buildLogPanel()),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              height: 28,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  backgroundColor: const Color(0xFFF5F7FB),
                  textStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onPressed: () => setState(() {
                  _audioRateExpanded = !_audioRateExpanded;
                }),
                icon: Icon(
                  _audioRateExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                ),
                label: Text(_audioRateExpanded ? '收起音频传输速率' : '展开音频传输速率'),
              ),
            ),
            if (_audioRateExpanded) ...[
              const SizedBox(height: 6),
              _buildAudioRatePanel(recordPenProvider),
            ],
            const SizedBox(height: 10),
            Expanded(
              flex: 3,
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 50),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: DemoFunctionPanel(
                  fileSelector: DropdownButtonFormField<String>(
                    isExpanded: true,
                    isDense: true,
                    menuMaxHeight: 280,
                    value:
                        recordPenProvider.recordFileNames.contains(
                              recordPenProvider.transFileName,
                            ) &&
                            recordPenProvider.transFileName.isNotEmpty
                        ? recordPenProvider.transFileName
                        : null,
                    style: const TextStyle(fontSize: 11, color: Colors.black),
                    decoration: _compactInput(
                      '选择传输文件 (${recordPenProvider.recordFiles.length})',
                    ),
                    hint: const Text(
                      '先获取文件列表',
                      style: TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                    selectedItemBuilder: (context) => recordPenProvider
                        .recordFiles
                        .reversed
                        .map(
                          (file) => Align(
                            alignment: Alignment.centerLeft,
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Text(
                                file.displayLabel,
                                maxLines: 1,
                                softWrap: false,
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                    items: recordPenProvider.recordFiles
                        .reversed
                        .map(
                          (file) => DropdownMenuItem<String>(
                            value: file.name,
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Text(
                                file.displayLabel,
                                maxLines: 1,
                                softWrap: false,
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: recordPenProvider.recordFiles.isEmpty
                        ? null
                        : (value) {
                            if (value != null) {
                              recordPenProvider.setTransFileName(value);
                            }
                          },
                  ),
                  deviceSelector: Row(
                    spacing: 8,
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
                          isDense: true,
                          value: _selectedDeviceAddress,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.black,
                          ),
                          decoration: _compactInput(
                            '选择设备 (${discoveredDevices.length})',
                          ),
                          hint: const Text(
                            '搜索后选择设备',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey,
                            ),
                          ),
                          items: discoveredDevices
                              .map(
                                (device) => DropdownMenuItem<String>(
                                  value: device['address'],
                                  child: Text(
                                    '${device['address'] ?? ''}  ${device['name'] ?? ''}',
                                    maxLines: 1,
                                    softWrap: false,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: discoveredDevices.isEmpty
                              ? null
                              : (value) {
                                  setState(
                                    () => _selectedDeviceAddress = value,
                                  );
                                },
                        ),
                      ),
                      SizedBox(
                        height: 40,
                        child: FilledButton(
                          onPressed: _selectedDeviceAddress == null
                              ? null
                              : () => _connectSelectedDevice(
                                  recordPenProvider,
                                ),
                          child: const Text('连接'),
                        ),
                      ),
                    ],
                  ),
                  functionBuilder: _buildFunction,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFunction(int id) {
    final provider = _recordPenProvider;
    return switch (id) {
      2 => Row(
        spacing: 8,
        children: [
          Expanded(
            child: TextField(
              controller: _authkeyController,
              style: const TextStyle(fontSize: 11),
              decoration: _compactInput('AuthKey'),
            ),
          ),
          SizedBox(
            height: 40,
            child: FilledButton(
              onPressed: () => _authkeyConnect(provider),
              child: const Text('认证'),
            ),
          ),
        ],
      ),
      3 => _buttonItem('修改AuthKey', _showSetAuthkeyDialog),
      4 => _buttonItem('重置AuthKey', () {
        _runDeviceSetting('重置AuthKey', provider.unbondAuthkey);
      }),
      5 => _buttonItem('设置设备名', _showSetDeviceNameDialog),
      6 => _buttonItem(provider.deviceType == 199 ? '格式化' : '重置', () {
        _runDeviceSetting('格式化', provider.resetDevice);
      }),
      7 => _buttonItem('搜索设备', () {
        setState(() => _selectedDeviceAddress = null);
        provider.startSearch();
      }),
      8 => _buttonItem('停止搜索', provider.stopSearch),
      9 => _buttonItem('是否链接', provider.isDeviceConnected),
      10 => _buttonItem('断开链接', provider.closeConnect),
      11 => _buttonItem('录音状态', provider.getRecordState),
      12 => _buttonItem('开始录音', _startRecord),
      13 => _buttonItem('L09录音', _showL09RecordDialog),
      14 => _buttonItem('暂停录音', provider.pauseRecord),
      15 => _buttonItem('继续录音', provider.continueRecord),
      16 => _buttonItem('停止录音', () {
        provider.stopRecord();
        _scheduleFinishRecordAudio();
      }),
      17 => _buttonItem('▶ 播放录音', () {
        _playAudio(_recordAudioName, '录音');
      }, enabled: _recordAudioExists),
      18 => _buttonItem('后连：获取录音文件名', provider.getFileName),
      19 => _buttonItem('后连：获取时长和流', provider.getTimeOnlyRecording),
      20 => _buttonItem('获取电量', provider.getCBC),
      21 => _buttonItem('获取容量', provider.getDeviceCapacity),
      22 => _buttonItem('获取SN', provider.getSN),
      23 => _buttonItem('给设备下发时间', provider.asyncNowTime),
      24 => _buttonItem('获取当前增益', provider.getDeviceGain),
      25 => _buttonItem('设置当前增益', () => provider.setDeviceGain(3)),
      26 => _buttonItem('通知APP前后台', () => provider.sendAppShowState(2)),
      27 => _buttonItem('获取固件版本号', provider.getDeviceVersion),
      28 => _buttonItem('文件列表', provider.getRecordFileList),
      29 => _buttonItem('删除文件', () async {
        final name = _requireSelectedTransferFile();
        if (name == null) return;
        final confirmed = await _confirmDeleteFiles(fileName: name);
        if (!confirmed || !mounted) return;
        await provider.deleteFile(name);
      }),
      30 => _buttonItem('⚠️删除所有文件', () async {
        final confirmed = await _confirmDeleteFiles();
        if (!confirmed || !mounted) return;
        await provider.deleteAllFile();
      }),
      31 => _buttonItem('传输文件', () async {
        final name = _requireSelectedTransferFile();
        if (name == null || _transferStarting) return;
        _transferStarting = true;
        try {
          await _startTransferFile(name);
        } catch (e) {
          Log.e('[蓝牙调试][文件传输] 启动传输失败: $e');
        } finally {
          _transferStarting = false;
        }
      }),
      32 => _buttonItem('停止传输', () {
        final name = _requireSelectedTransferFile();
        if (name != null) {
          _runDeviceSetting('停止传输', () => provider.stopTransferFile(name));
        }
      }),
      33 => _buttonItem('▶ 播放传输', () {
        _playAudio(_transferAudioName, '传输音频');
      }, enabled: _transferAudioExists),
      34 => _buttonItem('⏹ 停止播放', _audioPlayer.stop),
      35 => _buttonItem('返回开始', provider.startBtnBackRecord),
      36 => _buttonItem('返回暂停', () {}),
      37 => _buttonItem('返回继续', () {}),
      38 => _buttonItem('返回停止', () {}),
      39 => _buttonItem('打开wifi', provider.openWiFi),
      40 =>
        [201, 202].contains(provider.deviceType)
            ? _buttonItem('密码连接', _showWifiPasswordConnectDialog)
            : _buttonItem(
                '连接(${provider.wifiName})',
                provider.connectDeviceWiFi,
              ),
      41 => _buttonItem('关闭wifi', provider.closeWiFi),
      42 => _buttonItem('wifi断开设备', provider.disconnectDeviceWiFi),
      43 => _buttonItem('连接状态', provider.getDeviceWiFiState),
      44 => _buttonItem('手机状态', provider.getWiFiHotspotState),
      45 => _buttonItem('一键连接WiFi', () {
        _showWifiPasswordConnectDialog(quickConnect: true);
      }),
      46 => _buttonItem('修改热点密码', _showSetWifiPasswordDialog),
      47 => _buttonItem('复位设备名', provider.resetDeviceName),
      48 => _buttonItem('设置直传Wi-Fi', _showSetWifiDirectDialog),
      49 => _buttonItem('设置上传URL', _showSetRemoteUrlDialog),
      50 => _buttonItem('复位直传Wi-Fi', provider.resetWifiDirect),
      51 => _buttonItem('获取直传Wi-Fi', provider.getWifiDirect),
      52 => _buttonItem('固件升级code', provider.getDeviceVersionCode),
      53 => _buttonItem('低功耗状态', provider.getDeviceLowPowerRecordMode),
      54 => _buttonItem('设置低功耗', () {
        provider.setDeviceLowPowerRecordMode(true);
      }),
      55 => Row(
        spacing: 5,
        children: [
          Expanded(
            child: TextField(
              controller: _otaFirmwareNameController,
              readOnly: true,
              style: const TextStyle(fontSize: 11),
              decoration: _compactInput('固件文件（.ufw）'),
            ),
          ),
          SizedBox(
            height: 32,
            width: 60,
            child: _buttonItem(
              '选择固件',
              _pickOtaFirmware,
              enabled: !_otaRequestInProgress,
            ),
          ),
        ],
      ),
      56 => SizedBox(
        height: 32,
        child: _buttonItem(
          '请求并发送',
          _requestAndSendSelectedOtaFirmware,
          enabled: _otaFirmwareFile != null && !_otaRequestInProgress,
        ),
      ),
      57 => _buttonItem('BK OTA 专属设置', () {
        _scaffoldKey.currentState?.openEndDrawer();
      }, bgColor: Colors.green),
      63 => _heartbeatSwitch(
        '设备发送心跳',
        provider.deviceHeartbeatEnabled,
        provider.isHeartbeatSettingPending
            ? null
            : (enabled) => _runDeviceSetting(
                '设备发送心跳',
                () => provider.setHeartbeatDataState(enabled),
              ),
      ),
      64 => _heartbeatSwitch(
        'App 回复心跳',
        provider.heartbeatReplyEnabled,
        (enabled) => provider.heartbeatReplyEnabled = enabled,
      ),
      65 => SizedBox(
        height: 32,
        child: _buttonItem('设置传输间隔', _showSetTransferIntervalDialog),
      ),
      66 => _buttonItem('分享音频', _shareAudio, enabled: !_audioExportInProgress),
      _ => throw ArgumentError.value(id, 'id', '未配置的 Demo 功能编号'),
    };
  }

  Widget _buildAudioRatePanel(RecordPenProvider provider) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E6F0)),
      ),
      child: Column(
        spacing: 6,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '音频传输速率',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Text(
                _useOggStorage ? '是否存储音频' : '是否解码加存储',
                style: const TextStyle(fontSize: 11, color: Color(0xFF5D6472)),
              ),
              Transform.scale(
                scale: 0.8,
                child: ListenableBuilder(
                  listenable: _transferTestRunner,
                  builder: (context, _) => Switch(
                    value: provider.audioDecodeAndStoreEnabled,
                    onChanged: _transferTestRunner.isRunning
                        ? null
                        : (value) {
                            _setAudioDecodeAndStoreEnabled(value);
                          },
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
            ],
          ),
          _audioRateRow(
            '实时录音',
            provider.audioRateSummary(AudioDataType.record),
          ),
          _audioRateRow('文件传输', provider.audioRateSummary(AudioDataType.file)),
          _audioRateRow(
            '',
            '平均速度 ${provider.audioAverageRateLabel(AudioDataType.file)}',
          ),
        ],
      ),
    );
  }

  Widget _audioRateRow(String label, String value) {
    return Row(
      children: [
        SizedBox(
          width: 58,
          child: Text(
            label,
            style: const TextStyle(fontSize: 11, color: Color(0xFF5D6472)),
          ),
        ),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: Color(0xFF1F2937)),
          ),
        ),
      ],
    );
  }

  /// 控制台风格的日志展示面板
  Widget _buildLogPanel() {
    const bgColor = Color(0xFF1E1E2E);
    const borderColor = Color(0xFF3A3A4F);

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          DemoLogHeader(
            lineCount: _data.length,
            autoScroll: _autoScrollLog,
            onAutoScrollChanged: (enabled) {
              setState(() => _autoScrollLog = enabled);
              if (enabled) _scrollLogToBottom();
            },
            onClear: () => setState(_data.clear),
            onCopy: _copyLogToClipboard,
          ),
          // 日志内容
          Expanded(
            child: _data.isEmpty
                ? const Center(
                    child: Text(
                      '暂无日志…',
                      style: TextStyle(
                        color: Color(0xFF6A6A80),
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    itemCount: _data.length,
                    itemBuilder: (_, index) {
                      final line = "${_data[index]}";
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 1.5),
                        child: Text(
                          line,
                          style: TextStyle(
                            color: _logLineColor(line),
                            fontSize: 12,
                            height: 1.3,
                            fontFamily: 'monospace',
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// 根据日志内容选择颜色，便于快速区分类型
  Color _logLineColor(String line) {
    final isHeartbeatOrInterval = line.contains('[蓝牙调试][心跳]') ||
        line.contains('[蓝牙调试][传输间隔]');
    if (line.contains('失败') ||
        line.contains('错误') ||
        line.contains('异常') ||
        line.contains('error') ||
        (isHeartbeatOrInterval &&
            (line.contains('超时') || line.contains('结果未知')))) {
      return const Color(0xFFFF6B6B);
    }
    if (isHeartbeatOrInterval ||
        line.contains('结束') ||
        line.contains('成功') ||
        line.contains('完成')) {
      return const Color(0xFF6BCB77);
    }
    if (line.contains('[录音音频]') || line.contains('[传输音频]')) {
      return const Color(0xFF4DABF7);
    }
    if (line.contains('[文件传输]')) {
      return const Color(0xFFFFD93D);
    }
    return const Color(0xFFD0D0DE);
  }

  /// BK OTA 专属设置（独立 Scaffold，保证 SnackBar 在抽屉层生效）
  Widget _buildBkOtaDrawer() {
    return ScaffoldMessenger(
      child: Builder(
        builder: (drawerContext) {
          void toast(String message) {
            ScaffoldMessenger.of(drawerContext)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(content: Text(message)));
          }

          final bottomInset = MediaQuery.viewInsetsOf(drawerContext).bottom;

          return Padding(
            padding: EdgeInsets.only(bottom: bottomInset),
            child: Scaffold(
              resizeToAvoidBottomInset: false,
              appBar: AppBar(
                title: const Text('BK OTA', style: TextStyle(fontSize: 16)),
                automaticallyImplyLeading: false,
                actions: [
                  IconButton(
                    onPressed: () => Navigator.of(drawerContext).maybePop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              body: SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    spacing: 10,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        spacing: 8,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _bkFirmwarePathController,
                              readOnly: true,
                              style: const TextStyle(fontSize: 11),
                              decoration: _compactInput('固件文件（.bin/.rbl）'),
                            ),
                          ),
                          SizedBox(
                            height: 32,
                            width: 100,
                            child: _buttonItem('选择固件', () async {
                              try {
                                final result = await FilePicker.pickFiles(
                                  type: Platform.isIOS
                                      ? FileType.any
                                      : FileType.custom,
                                  allowedExtensions: Platform.isIOS
                                      ? null
                                      : ['bin', 'rbl'],
                                  withData: true,
                                );
                                if (result == null || result.files.isEmpty) {
                                  return;
                                }

                                final picked = result.files.single;
                                final pickedName = picked.name.toLowerCase();
                                if (!pickedName.endsWith('.bin') &&
                                    !pickedName.endsWith('.rbl')) {
                                  toast('请选择 .bin 或 .rbl 固件文件');
                                  return;
                                }
                                File file;
                                if (picked.path != null &&
                                    picked.path!.isNotEmpty) {
                                  file = File(picked.path!);
                                } else if (picked.bytes != null) {
                                  final dir = await getTemporaryDirectory();
                                  final name = picked.name.isNotEmpty
                                      ? picked.name
                                      : 'update.bin';
                                  file = File('${dir.path}/picked_$name');
                                  await file.writeAsBytes(
                                    picked.bytes!,
                                    flush: true,
                                  );
                                } else {
                                  throw StateError('无法读取所选文件');
                                }

                                setState(() {
                                  _bkFirmwareFile = file;
                                  _bkFirmwarePathController.text = file.path;
                                });
                                toast('已选择固件');
                              } catch (e) {
                                toast('选择失败: $e');
                              }
                            }),
                          ),
                        ],
                      ),
                      TextField(
                        controller: _bkUpgradeUrlController,
                        readOnly: true,
                        style: const TextStyle(fontSize: 11),
                        decoration: _compactInput('BK 升级 URL（启动服务后自动填入）'),
                      ),
                      GridView.count(
                        padding: EdgeInsets.zero,
                        physics: const NeverScrollableScrollPhysics(),
                        shrinkWrap: true,
                        crossAxisCount: 4,
                        childAspectRatio: 2.2,
                        mainAxisSpacing: 5,
                        crossAxisSpacing: 5,
                        children: [
                          _buttonItem('启动HTTP', () async {
                            final file = _bkFirmwareFile;
                            if (file == null) {
                              toast('请先选择固件文件');
                              return;
                            }
                            try {
                              final url = await _recordPenProvider
                                  .startBkUpgradeHttpServer(firmwareFile: file);
                              setState(() {
                                _bkUpgradeUrlController.text = url;
                              });
                              toast('HTTP已启动');
                            } catch (e) {
                              toast('启动失败: $e');
                            }
                          }),
                          _buttonItem('停止HTTP', () async {
                            try {
                              await _recordPenProvider
                                  .stopBkUpgradeHttpServer();
                              toast('HTTP已停止');
                            } catch (e) {
                              toast('停止失败: $e');
                            }
                          }),
                          _buttonItem('发送升级URL', () async {
                            try {
                              var url = _bkUpgradeUrlController.text.trim();
                              if (url.isEmpty) {
                                final file = _bkFirmwareFile;
                                if (file == null) {
                                  toast('请先选择固件并启动HTTP');
                                  return;
                                }
                                url = await _recordPenProvider
                                    .startBkUpgradeHttpServer(
                                      firmwareFile: file,
                                    );
                                setState(() {
                                  _bkUpgradeUrlController.text = url;
                                });
                              }
                              await _recordPenProvider.setBKUpgradeHd(url);
                              toast('已发送升级URL');
                            } catch (e) {
                              toast('发送失败: $e');
                            }
                          }),
                          _buttonItem('BK版本号', () {
                            _recordPenProvider.getBKHDVersion();
                            toast('已请求 BK 版本号');
                          }, bgColor: Colors.red),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// 紧凑型输入框样式，减少纵向占用
  InputDecoration _compactInput(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 10, color: Colors.grey),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
    );
  }

  Future<bool> _confirmDeleteFiles({String? fileName}) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(fileName == null ? '确认删除所有文件' : '确认删除文件'),
        content: Text(
          fileName == null
              ? '确定删除设备上的所有录音文件吗？删除后无法恢复。'
              : '确定删除文件“$fileName”吗？删除后无法恢复。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _showL09RecordDialog() async {
    final enabled = await showDialog<bool>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('L09录音：选择麦克风'),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: FilledButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('数字麦（关闭骨麦）'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('骨麦（关闭数字麦）'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
          ),
        ],
      ),
    );
    if (enabled == null || !mounted) return;
    await _startRecord(boneMic: enabled);
  }

  Future<void> _showSetDeviceNameDialog() async {
    final controller = TextEditingController();
    final name = await _showInputDialog(
      title: '设置设备名',
      controller: controller,
      hint: '2-16 位英文或数字',
    );
    if (name == null || name.isEmpty) return;
    await _recordPenProvider.setDeviceName(name);
  }

  Future<void> _showSetWifiDirectDialog() async {
    final cachedWifi = await _loadWifiDirectCache();
    if (!mounted) return;
    final ssidController = TextEditingController(
      text: cachedWifi['ssid'] ?? '',
    );
    final passwordController = TextEditingController(
      text: cachedWifi['password'] ?? '',
    );
    final values = await showDialog<List<String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('设置直传 Wi-Fi'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ssidController,
              decoration: const InputDecoration(labelText: 'SSID'),
            ),
            TextField(
              controller: passwordController,
              decoration: const InputDecoration(labelText: '密码'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, [
              ssidController.text.trim(),
              passwordController.text,
            ]),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    if (values == null) return;
    await _saveWifiDirectCache(values[0], values[1]);
    if (values[0].isEmpty) return;
    await _recordPenProvider.setWifiDirect(values[0], values[1]);
  }

  Future<Map<String, String>> _loadWifiDirectCache() async {
    try {
      final file = await _wifiDirectCacheFile();
      if (!await file.exists()) return {};
      final data =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return {
        'ssid': data['ssid']?.toString() ?? '',
        'password': data['password']?.toString() ?? '',
      };
    } catch (error) {
      Log.e('加载直传 Wi-Fi 缓存失败: $error');
      return {};
    }
  }

  Future<void> _saveWifiDirectCache(String ssid, String password) async {
    final file = await _wifiDirectCacheFile();
    await file.writeAsString(
      jsonEncode({'ssid': ssid, 'password': password}),
      flush: true,
    );
  }

  Future<File> _wifiDirectCacheFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/wifi_direct_cache.json');
  }

  Future<void> _showSetRemoteUrlDialog() async {
    final controller = TextEditingController(
      text: 'https://example.com/audio/upload',
    );
    final url = await _showInputDialog(
      title: '设置上传 URL',
      controller: controller,
      hint: 'https://example.com/audio/upload',
      keyboardType: TextInputType.url,
    );
    if (url == null || url.isEmpty) return;
    await _recordPenProvider.setRemoteUrl(url);
  }

  Future<String?> _showInputDialog({
    required String title,
    required TextEditingController controller,
    required String hint,
    TextInputType? keyboardType,
    bool trimInput = true,
  }) {
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          keyboardType: keyboardType,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              trimInput ? controller.text.trim() : controller.text,
            ),
            child: const Text('确认'),
          ),
        ],
      ),
    );
  }

  Widget _buttonItem(
    String title,
    Function() onTap, {
    bool enabled = true,
    Color? bgColor,
  }) {
    return FilledButton(
      onPressed: enabled ? onTap : null,
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        backgroundColor: bgColor,
        disabledBackgroundColor: bgColor?.withValues(alpha: 0.38),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(title, style: const TextStyle(fontSize: 12)),
      ),
    );
  }
}
