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
import 'package:soni_sdk_demo/service_network_permission.dart';
import 'package:soni_sdk_demo/wave_write.dart';

import 'bluetooth_constants.dart';
import 'logger.dart';
import 'ogg_opus_writer.dart';
import 'provider_record_pen.dart';

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
        title: 'SoniSDkDemo',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: const ColorScheme.light(primary: Color(0xff3a7afe)),
        ),
        home: const MyHomePage(
          title: deviceAes256Gcm ? 'SoniSDkDemo-BK解密' : 'SoniSDkDemo',
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
  final ScrollController _scrollController = ScrollController();
  final List _data = [];

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
  bool _transferStarting = false;
  bool _recordFinishScheduled = false;
  bool _recordAudioFinished = false;
  bool _recordAudioExists = false;
  bool _transferAudioExists = false;
  String _appVersion = '';
  final TextEditingController _sendFileTimeIntervalController =
      TextEditingController(text: '13');
  String? _selectedDeviceAddress;
  final TextEditingController _authkeyController = TextEditingController(
    text: '0xae4b1e65f7ba1282d2060876d324253c95e9475307b4e9e14f9a708dcc54b250',
  );
  final TextEditingController _otaFirmwareNameController =
      TextEditingController();
  File? _otaFirmwareFile;
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
    _recordPenProvider.init();

    _recordPenProvider.streamController.stream.listen((event) async {
      if (event.containsKey('audio')) {
        final audioType = event['audioType'] as String? ?? AudioDataType.record;
        final frame = event['audio'] as List<int>;
        if (audioType == AudioDataType.file) {
          await _transferAudioQueue.run(
            () => _processAudioFrame(frame, audioType),
          );
        } else if (_useOggStorage) {
          await _recordAudioQueue.run(
            () => _processAudioFrame(frame, audioType),
          );
        } else {
          await _processAudioFrame(frame, audioType);
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
      setState(() => _appVersion = info.version);
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
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  String _formatEventLog(dynamic event) {
    if (event is! Map) return event.toString();
    final cmd = event['cmd']?.toString();
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
      if (_useOggStorage) {
        await _recordAudioQueue.run(() async {
          await _recordOggWriter?.close();
        });
        await _transferOggWriter?.close();
      }
      await _recordPcmSink?.flush();
      await _recordPcmSink?.close();
      await _transferPcmSink?.flush();
      await _transferPcmSink?.close();
    } catch (e) {
      Log.e('关闭音频写入失败: $e');
    } finally {
      _recordPcmSink = null;
      _transferPcmSink = null;
      _recordOggWriter = null;
      _transferOggWriter = null;
      _recordFinishScheduled = false;
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
    final text = _data.map((e) => e.toString()).join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已复制 ${_data.length} 行日志')));
  }

  bool _isRecordAudio(String audioType) => audioType == AudioDataType.record;

  Future<void> _resetRecordAudio() async {
    if (!_recordPenProvider.audioDecodeAndStoreEnabled) return;
    final dir = await _ensureDirectory();
    _recordPcmSamples = 0;
    _recordOpusFrames = 0;
    _recordOpusBytes = 0;
    _lastRecordAudioLogAt = null;
    _recordAudioFinished = false;
    _recordFinishScheduled = false;
    if (_useOggStorage) {
      await _recordOggWriter?.close();
      _recordOggWriter = OggOpusWriter(
        File('${dir.path}/$_recordAudioName').openWrite(),
      );
      if (mounted) setState(() => _recordAudioExists = false);
      return;
    }
    await _recordPcmSink?.close();
    _recordPcmFile = File('${dir.path}/$_recordPcmName');
    _recordPcmSink = _recordPcmFile!.openWrite();
  }

  Future<void> _scheduleFinishRecordAudio() async {
    if (!_recordPenProvider.audioDecodeAndStoreEnabled) return;
    if (_recordFinishScheduled || _recordAudioFinished) return;
    _recordFinishScheduled = true;
    await Future.delayed(const Duration(seconds: 1));
    if (_useOggStorage) {
      await _recordAudioQueue.run(_finishRecordAudio);
    } else {
      await _finishRecordAudio();
    }
    _recordFinishScheduled = false;
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
        File('${dir.path}/$_transferAudioName').openWrite(),
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

    await WavWriter.writeWavFile(
      filePath: wavPath,
      pcmFile: pcmFile,
      sampleRate: 16000,
      channels: 1,
    );

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
    await writer.close();
    final name = isRecord ? _recordAudioName : _transferAudioName;
    if (isRecord) {
      _recordAudioFinished = true;
      _recordOggWriter = null;
    } else {
      _transferOggWriter = null;
    }
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

  @override
  void dispose() {
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
    provider.connect({
      'name': device['name'] ?? '',
      'address': device['address'] ?? '',
    });
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

  void _showAuthkeyUnsupported() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('暂不支持')));
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
    final controller = TextEditingController();
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
        type: FileType.custom,
        allowedExtensions: ['ufw'],
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

  Future<void> _sendSelectedOtaFirmware() async {
    final file = _otaFirmwareFile;
    if (file == null) return;
    _appendLog('[OTA] 开始发送固件: ${_otaFirmwareNameController.text}');
    try {
      await _recordPenProvider.sendOtaFile(file.path);
    } catch (e) {
      Log.e('发送固件失败: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('发送固件失败: $e')));
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

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        toolbarHeight: 40,
        titleSpacing: 8,
        title: Text(
          _appVersion.isEmpty ? widget.title : '${widget.title}  v$_appVersion',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: const TextStyle(fontSize: 12),
            ),
            onPressed: () {
              setState(() {
                _data.clear();
              });
            },
            child: const Text("清屏"),
          ),
          TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: const TextStyle(fontSize: 12),
            ),
            onPressed: _copyLogToClipboard,
            child: const Text("复制log"),
          ),
        ],
      ),
      endDrawer: Drawer(
        width: MediaQuery.sizeOf(context).width * 0.88,
        child: _buildBkOtaDrawer(),
      ),
      resizeToAvoidBottomInset: true,
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: <Widget>[
            _buildLogPanel(),
            const SizedBox(height: 10),
            _buildAudioRatePanel(recordPenProvider),
            const SizedBox(height: 10),
            Expanded(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: Column(
                  spacing: 10,
                  children: <Widget>[
                    DropdownButtonFormField<String>(
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
                    Column(
                      spacing: 5,
                      children: [
                        Row(
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
                                          device['address'] ?? '',
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
                        Row(
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
                                onPressed: () => _authkeyConnect(
                                  recordPenProvider,
                                ),
                                child: const Text('认证'),
                              ),
                            ),
                          ],
                        ),
                        GridView.count(
                          padding: EdgeInsets.zero,
                          physics: const NeverScrollableScrollPhysics(),
                          shrinkWrap: true,
                          crossAxisCount: 5,
                          childAspectRatio: 2.5,
                          mainAxisSpacing: 5,
                          crossAxisSpacing: 5,
                          children: [
                            _buttonItem('修改AuthKey', _showAuthkeyUnsupported),
                            _buttonItem('重置AuthKey', _showAuthkeyUnsupported),
                            _buttonItem("设置设备名", _showSetDeviceNameDialog),
                          ],
                        ),
                        GridView.count(
                          padding: EdgeInsets.zero,
                          physics: const NeverScrollableScrollPhysics(),
                          shrinkWrap: true,
                          crossAxisCount: 5,
                          childAspectRatio: 2.5,
                          mainAxisSpacing: 5,
                          crossAxisSpacing: 5,
                          children: [
                            _buttonItem("搜索设备", () {
                              setState(() => _selectedDeviceAddress = null);
                              recordPenProvider.startSearch();
                            }),
                            _buttonItem("停止搜索", () {
                              recordPenProvider.stopSearch();
                            }),
                            _buttonItem("是否链接", () {
                              recordPenProvider.isDeviceConnected();
                            }),
                            _buttonItem("断开链接", () {
                              recordPenProvider.closeConnect();
                            }),
                          ],
                        ),
                        GridView.count(
                          padding: EdgeInsets.zero,
                          physics: const NeverScrollableScrollPhysics(),
                          shrinkWrap: true,
                          crossAxisCount: 5,
                          childAspectRatio: 2.5,
                          mainAxisSpacing: 5,
                          crossAxisSpacing: 5,
                          children: [
                            _buttonItem("录音状态", () {
                              _recordPenProvider.getRecordState();
                            }),
                            _buttonItem("开始录音", () async {
                              if (_useOggStorage) {
                                await _recordAudioQueue.run(_resetRecordAudio);
                              } else {
                                await _resetRecordAudio();
                              }
                              _recordPenProvider.startRecord();
                            }),
                            _buttonItem("暂停录音", () {
                              _recordPenProvider.pauseRecord();
                            }),
                            _buttonItem("继续录音", () {
                              _recordPenProvider.continueRecord();
                            }),
                            _buttonItem("停止录音", () async {
                              _recordPenProvider.stopRecord();
                              _scheduleFinishRecordAudio();
                            }),
                            _buttonItem("▶ 播放录音", () {
                              _playAudio(_recordAudioName, '录音');
                            }, enabled: _recordAudioExists),
                            _buttonItem("后连：获取录音文件名", () {
                              _recordPenProvider.getFileName();
                            }),
                            _buttonItem("后连：获取时长和流", () {
                              _recordPenProvider.getTimeOnlyRecording();
                            }),
                          ],
                        ),
                        GridView.count(
                          padding: EdgeInsets.zero,
                          physics: const NeverScrollableScrollPhysics(),
                          shrinkWrap: true,
                          crossAxisCount: 5,
                          childAspectRatio: 2.5,
                          mainAxisSpacing: 5,
                          crossAxisSpacing: 5,
                          children: [
                            _buttonItem("获取电量", () {
                              _recordPenProvider.getCBC();
                            }),
                            _buttonItem("获取容量", () {
                              _recordPenProvider.getDeviceCapacity();
                            }),
                            _buttonItem("获取SN", () {
                              _recordPenProvider.getSN();
                            }),
                            _buttonItem("给设备下发时间", () {
                              _recordPenProvider.asyncNowTime();
                            }),
                            _buttonItem("获取当前增益", () {
                              _recordPenProvider.getDeviceGain();
                            }),
                            _buttonItem("设置当前增益", () {
                              _recordPenProvider.setDeviceGain(3);
                            }),
                            _buttonItem("通知APP前后台", () {
                              _recordPenProvider.sendAppShowState(2);
                            }),
                            _buttonItem("获取固件版本号", () {
                              _recordPenProvider.getDeviceVersion();
                            }),
                          ],
                        ),
                        GridView.count(
                          padding: EdgeInsets.zero,
                          physics: const NeverScrollableScrollPhysics(),
                          shrinkWrap: true,
                          crossAxisCount: 5,
                          childAspectRatio: 2.5,
                          mainAxisSpacing: 5,
                          crossAxisSpacing: 5,
                          children: [
                            _buttonItem("文件列表", () {
                              _recordPenProvider.getRecordFileList();
                            }),
                            _buttonItem("删除文件", () {
                              final name = _requireSelectedTransferFile();
                              if (name == null) return;
                              _recordPenProvider.deleteFile(name);
                            }),
                            _buttonItem("⚠️删除所有文件", () {
                              _recordPenProvider.deleteAllFile();
                            }),
                            _buttonItem("传输文件", () async {
                              final name = _requireSelectedTransferFile();
                              if (name == null) return;
                              if (_transferStarting) return;
                              _transferStarting = true;
                              try {
                                await _transferAudioQueue.run(() async {
                                  await _resetTransferAudio();
                                  await _recordPenProvider
                                      .sendFileFromPenToPhoneWithOffset(name, 0);
                                });
                              } catch (e) {
                                Log.e('[蓝牙调试][文件传输] 启动传输失败: $e');
                              } finally {
                                _transferStarting = false;
                              }
                            }),
                            _buttonItem("停止传输", () {
                              final name = _requireSelectedTransferFile();
                              if (name == null) return;
                              _recordPenProvider.stopTransferFile(name);
                            }),
                          ],
                        ),
                        GridView.count(
                          padding: EdgeInsets.zero,
                          physics: const NeverScrollableScrollPhysics(),
                          shrinkWrap: true,
                          crossAxisCount: 5,
                          childAspectRatio: 2.5,
                          mainAxisSpacing: 5,
                          crossAxisSpacing: 5,
                          children: [
                            _buttonItem("▶ 播放传输", () {
                              _playAudio(_transferAudioName, '传输音频');
                            }, enabled: _transferAudioExists),
                            _buttonItem("⏹ 停止播放", () {
                              _audioPlayer.stop();
                            }),
                          ],
                        ),
                        GridView.count(
                          padding: EdgeInsets.zero,
                          physics: const NeverScrollableScrollPhysics(),
                          shrinkWrap: true,
                          crossAxisCount: 5,
                          childAspectRatio: 2.5,
                          mainAxisSpacing: 5,
                          crossAxisSpacing: 5,
                          children: [
                            _buttonItem("返回开始", () {
                              _recordPenProvider.startBtnBackRecord();
                            }),
                            _buttonItem("返回暂停", () {}),
                            _buttonItem("返回继续", () {}),
                            _buttonItem("返回停止", () {}),
                          ],
                        ),
                        Text(
                          "第二代wifi版本",
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        GridView.count(
                          padding: EdgeInsets.zero,
                          physics: const NeverScrollableScrollPhysics(),
                          shrinkWrap: true,
                          crossAxisCount: 5,
                          childAspectRatio: 2.5,
                          mainAxisSpacing: 5,
                          crossAxisSpacing: 5,
                          children: [
                            _buttonItem("打开wifi", () {
                              _recordPenProvider.openWiFi();
                            }),
                            _buttonItem(
                              "连接(${_recordPenProvider.wifiName})",
                              () {
                                _recordPenProvider.connectDeviceWiFi();
                              },
                            ),
                            _buttonItem('密码连接', _showWifiPasswordConnectDialog),
                            _buttonItem("关闭wifi", () {
                              _recordPenProvider.closeWiFi();
                            }),
                            _buttonItem("wifi断开设备", () {
                              _recordPenProvider.disconnectDeviceWiFi();
                            }),
                            _buttonItem("连接状态", () {
                              _recordPenProvider.getDeviceWiFiState();
                            }),
                            _buttonItem("手机状态", () {
                              _recordPenProvider.getWiFiHotspotState();
                            }),
                            _buttonItem("一键连接WiFi", () {
                              _showWifiPasswordConnectDialog(quickConnect: true);
                            }),
                            _buttonItem('修改热点密码', _showSetWifiPasswordDialog),
                          ],
                        ),
                        Text(
                          "直连Wi-Fi版本",
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        GridView.count(
                          padding: EdgeInsets.zero,
                          physics: const NeverScrollableScrollPhysics(),
                          shrinkWrap: true,
                          crossAxisCount: 5,
                          childAspectRatio: 2.5,
                          mainAxisSpacing: 5,
                          crossAxisSpacing: 5,
                          children: [
                            _buttonItem("复位设备名", () {
                              _recordPenProvider.resetDeviceName();
                            }),
                            _buttonItem("设置直传Wi-Fi", _showSetWifiDirectDialog),
                            _buttonItem("设置上传URL", _showSetRemoteUrlDialog),
                            _buttonItem("复位直传Wi-Fi", () {
                              _recordPenProvider.resetWifiDirect();
                            }),
                            _buttonItem("获取直传Wi-Fi", () {
                              _recordPenProvider.getWifiDirect();
                            }),
                          ],
                        ),
                        const SizedBox(height: 32),
                        GridView.count(
                          padding: EdgeInsets.zero,
                          physics: const NeverScrollableScrollPhysics(),
                          shrinkWrap: true,
                          crossAxisCount: 5,
                          childAspectRatio: 2.5,
                          mainAxisSpacing: 5,
                          crossAxisSpacing: 5,
                          children: [
                            _buttonItem("固件版本号", () {
                              _recordPenProvider.getDeviceVersion();
                            }),
                            _buttonItem("固件升级code", () {
                              _recordPenProvider.getDeviceVersionCode();
                            }),
                            _buttonItem("请求升级", () {
                              _recordPenProvider.requestDeviceGotoOtaMode();
                            }),
                            _buttonItem("低功耗状态", () {
                              _recordPenProvider.getDeviceLowPowerRecordMode();
                            }),
                            _buttonItem("设置低功耗", () {
                              _recordPenProvider.setDeviceLowPowerRecordMode(
                                true,
                              );
                            }),
                          ],
                        ),
                        Row(
                          spacing: 8,
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
                              width: 88,
                              child: _buttonItem('选择固件', _pickOtaFirmware),
                            ),
                            SizedBox(
                              height: 32,
                              width: 88,
                              child: _buttonItem(
                                '发送固件',
                                _sendSelectedOtaFirmware,
                                enabled: _otaFirmwareFile != null,
                              ),
                            ),
                          ],
                        ),

                        // Row(
                        //   spacing: 8,
                        //   children: [
                        //     Expanded(
                        //       child: TextField(
                        //         controller: _sendFileTimeIntervalController,
                        //         keyboardType: TextInputType.number,
                        //         style: const TextStyle(fontSize: 11),
                        //         decoration: _compactInput("文件传输间隔（毫秒）"),
                        //       ),
                        //     ),
                        //     SizedBox(
                        //       height: 32,
                        //       child: FilledButton(
                        //         onPressed: () {
                        //           final interval = int.tryParse(
                        //             _sendFileTimeIntervalController.text.trim(),
                        //           );
                        //           if (interval == null) {
                        //             ScaffoldMessenger.of(context).showSnackBar(
                        //               const SnackBar(content: Text('请输入有效的时间间隔')),
                        //             );
                        //             return;
                        //           }
                        //           _recordPenProvider.setSendFileTimeInterval(interval);
                        //         },
                        //         child: const Text('设置间隔'),
                        //       ),
                        //     ),
                        //   ],
                        // ),
                        Text(
                          "BK OTA专区",
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        SizedBox(
                          width: double.infinity,
                          height: 32,
                          child: _buttonItem(
                            'BK OTA 专属设置',
                            () => _scaffoldKey.currentState?.openEndDrawer(),
                            bgColor: Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
                child: Switch(
                  value: provider.audioDecodeAndStoreEnabled,
                  onChanged: (value) {
                    _setAudioDecodeAndStoreEnabled(value);
                  },
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
    const headerColor = Color(0xFF2A2A3C);
    const borderColor = Color(0xFF3A3A4F);

    return Container(
      height: 140,
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
          // 顶部标题栏
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: const BoxDecoration(
              color: headerColor,
              border: Border(bottom: BorderSide(color: borderColor)),
            ),
            child: Row(
              children: [
                // _dot(const Color(0xFFFF5F56)),
                // const SizedBox(width: 6),
                // _dot(const Color(0xFFFFBD2E)),
                // const SizedBox(width: 6),
                // _dot(const Color(0xFF27C93F)),
                const Icon(Icons.terminal, size: 14, color: Color(0xFF8A8AA0)),
                const SizedBox(width: 6),
                const Text(
                  '日志',
                  style: TextStyle(
                    color: Color(0xFFCDCDDA),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3A3A4F),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${_data.length} 行',
                    style: const TextStyle(
                      color: Color(0xFF9A9AB0),
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
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
    if (line.contains('失败') ||
        line.contains('错误') ||
        line.contains('异常') ||
        line.contains('error')) {
      return const Color(0xFFFF6B6B);
    }
    if (line.contains('结束') || line.contains('成功') || line.contains('完成')) {
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
        padding: EdgeInsets.zero,
        backgroundColor: bgColor,
        disabledBackgroundColor: bgColor?.withValues(alpha: 0.38),
      ),
      child: FittedBox(
        child: Text(title, style: const TextStyle(fontSize: 12)),
      ),
    );
  }
}
