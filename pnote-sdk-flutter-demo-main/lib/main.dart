import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:opus_dart/opus_dart.dart';
import 'package:opus_flutter/opus_flutter.dart' as opus_flutter;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:soni_sdk_demo/service_system_ability.dart';
import 'package:soni_sdk_demo/wave_write.dart';

import 'bluetooth_constants.dart';
import 'app_localization.dart';
import 'logger.dart';
import 'provider_record_pen.dart';

void main() async {
  /// 等待初始化
  WidgetsFlutterBinding.ensureInitialized();

  final lib = await opus_flutter.load();
  initOpus(lib);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => RecordPenProvider())],
      child: ValueListenableBuilder<String>(
        valueListenable: AppLocale.language,
        builder: (context, language, child) => MaterialApp(
          title: 'Soni Recorder SDK Demo',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: const ColorScheme.light(
              primary: Color(0xff3a7afe),
            ),
          ),
          home: MyHomePage(
            title: deviceAes256Gcm ? 'Soni Recorder SDK (BK)' : 'Soni Recorder SDK',
          ),
        ),
      ),
    );
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
  bool _recordFinishScheduled = false;
  bool _recordAudioFinished = false;
  bool _recordWavExists = false;
  bool _transferWavExists = false;
  final TextEditingController _controller = TextEditingController(
    text: '',
  );
  final TextEditingController _sendFileTimeIntervalController =
      TextEditingController(text: '13');
  String? _selectedDeviceAddress;

  @override
  void initState() {
    super.initState();
    _recordDecoder = SimpleOpusDecoder(sampleRate: 16000, channels: 1);
    _transferDecoder = SimpleOpusDecoder(sampleRate: 16000, channels: 1);

    _recordPenProvider = Provider.of<RecordPenProvider>(context, listen: false);
    _recordPenProvider.init();

    _recordPenProvider.streamController.stream.listen((event) async {
      if (event.containsKey('audio')) {
        final audioType =
            event['audioType'] as String? ?? AudioDataType.record;
        final frame = event['audio'] as List<int>;
        await _decodeAudioFrame(frame, audioType);
        _logAudioProgress(frame, audioType);
        return;
      }

      _appendLog(_formatEventLog(event));

      if (event['cmd']?.toString() == '5' &&
          event['data']?['record_file_state']?.toString() == '0') {
        _appendLog(
          '[传输音频] 结束: 共 $_transferOpusFrames 帧, '
          'Opus ${(_transferOpusBytes / 1024).toStringAsFixed(1)}KB, '
          '已解码 ${(_transferPcmSamples / 16000).toStringAsFixed(1)}秒',
        );
        _finishTransferAudio();
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
  }

  Future<void> _initDirectory() async {
    _directory = await _resolveStorageDirectory();
    await _refreshWavExists();
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
      final stateText = {
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
        '已解码 ${duration.toStringAsFixed(1)}秒',
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
      '已解码 ${duration.toStringAsFixed(1)}秒',
    );
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

  Future<void> _resetRecordPcm() async {
    final dir = await _ensureDirectory();
    _recordPcmSamples = 0;
    _recordOpusFrames = 0;
    _recordOpusBytes = 0;
    _lastRecordAudioLogAt = null;
    _recordAudioFinished = false;
    _recordFinishScheduled = false;
    await _recordPcmSink?.close();
    _recordPcmFile = File('${dir.path}/$_recordPcmName');
    _recordPcmSink = _recordPcmFile!.openWrite();
  }

  Future<void> _scheduleFinishRecordAudio() async {
    if (_recordFinishScheduled || _recordAudioFinished) return;
    _recordFinishScheduled = true;
    await Future.delayed(const Duration(seconds: 1));
    await _finishRecordAudio();
    _recordFinishScheduled = false;
  }

  Future<void> _resetTransferPcm() async {
    final dir = await _ensureDirectory();
    _transferPcmSamples = 0;
    _transferOpusFrames = 0;
    _transferOpusBytes = 0;
    _lastTransferAudioLogAt = null;
    await _transferPcmSink?.close();
    _transferPcmFile = File('${dir.path}/$_transferPcmName');
    _transferPcmSink = _transferPcmFile!.openWrite();
  }

  Future<void> _ensurePcmSink(String audioType) async {
    if (_isRecordAudio(audioType)) {
      if (_recordPcmSink != null) return;
      await _resetRecordPcm();
      return;
    }
    if (_transferPcmSink != null) return;
    await _resetTransferPcm();
  }

  Future<void> _decodeAudioFrame(List<int> frame, String audioType) async {
    try {
      await _ensurePcmSink(audioType);
      final decoder =
          _isRecordAudio(audioType) ? _recordDecoder : _transferDecoder;
      final intPcm = decoder.decode(input: Uint8List.fromList(frame));

      if (_isRecordAudio(audioType)) {
        _recordPcmSamples += intPcm.length;
      } else {
        _transferPcmSamples += intPcm.length;
      }

      await _writePcmToFile(intPcm, audioType);
    } catch (e) {
      Log.e("[$audioType] 解码失败: $e");
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

    final pcmData = await pcmFile.readAsBytes();
    await WavWriter.writeWavFile(
      filePath: wavPath,
      pcmData: pcmData,
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
    if (_recordAudioFinished) return;
    try {
      await _recordPcmSink?.flush();
      await _recordPcmSink?.close();
      _recordPcmSink = null;

      final fileSize = await _recordPcmFile?.length() ?? 0;
      if (fileSize == 0) return;

      _recordAudioFinished = true;
      final duration = _recordPcmSamples / 16000;
      Log.f('录音 PCM: $_recordPcmName, ${duration.toStringAsFixed(2)}秒, $fileSize 字节');
      _appendLog(
        '[录音音频] 结束: 共 $_recordOpusFrames 帧, '
        'Opus ${(_recordOpusBytes / 1024).toStringAsFixed(1)}KB, '
        '已解码 ${duration.toStringAsFixed(1)}秒',
      );

      await _convertPcmToWav(_recordPcmName, _recordWavName);
      await _refreshWavExists();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('录音已保存: $_recordWavName')),
      );
    } catch (e) {
      Log.e('录音结束处理失败: $e');
    }
  }

  Future<void> _finishTransferAudio() async {
    try {
      await _transferPcmSink?.flush();
      await _transferPcmSink?.close();
      _transferPcmSink = null;

      final duration = _transferPcmSamples / 16000;
      final fileSize = await _transferPcmFile?.length() ?? 0;
      Log.f('传输 PCM: $_transferPcmName, ${duration.toStringAsFixed(2)}秒, $fileSize 字节');

      await _convertPcmToWav(_transferPcmName, _transferWavName);
      await _refreshWavExists();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('传输文件已保存: $_transferWavName')),
      );
    } catch (e) {
      Log.e('传输结束处理失败: $e');
    }
  }

  /// 刷新本地 WAV 文件是否存在，用于控制播放按钮的可用状态
  Future<void> _refreshWavExists() async {
    final dir = await _ensureDirectory();
    final recordExists = await File('${dir.path}/$_recordWavName').exists();
    final transferExists = await File('${dir.path}/$_transferWavName').exists();
    if (!mounted) return;
    if (recordExists != _recordWavExists ||
        transferExists != _transferWavExists) {
      setState(() {
        _recordWavExists = recordExists;
        _transferWavExists = transferExists;
      });
    }
  }

  /// 播放指定的 WAV 文件（录音 / 传输）
  Future<void> _playWav(String wavName, String label) async {
    try {
      final dir = await _ensureDirectory();
      final path = '${dir.path}/$wavName';
      final file = File(path);
      if (!await file.exists()) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$label 音频不存在，请先录音/传输')),
        );
        return;
      }
      await _audioPlayer.stop();
      await _audioPlayer.play(DeviceFileSource(path));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('正在播放$label')),
      );
    } catch (e) {
      Log.e('播放$label失败: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('播放$label失败: $e')),
      );
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _scrollController.dispose();
    _controller.dispose();
    _sendFileTimeIntervalController.dispose();
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先搜索并选择要连接的设备')),
      );
      return;
    }
    provider.connect({
      'name': device['name'] ?? '',
      'address': device['address'] ?? '',
    });
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
      appBar: AppBar(
        title: Text(widget.title,style: TextStyle(fontSize: 14)),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Language',
            icon: const Icon(Icons.language),
            onSelected: (value) => AppLocale.language.value = value,
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'zh', child: Text('中文')),
              PopupMenuItem(value: 'en', child: Text('English')),
            ],
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _data.clear();
              });
            },
            child: Text(AppLocale.text('清屏')),
          ),
          TextButton(
            onPressed: _copyLogToClipboard,
            child: Text(AppLocale.text('复制log')),
          ),
        ],
      ),
      resizeToAvoidBottomInset: true,
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: <Widget>[
            _buildLogPanel(),
            const SizedBox(height: 10),
            Expanded(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: Column(
                  spacing: 10,
                  children: <Widget>[
                    TextField(
                      // call 2026-03-13_17-58-50.opus
                      controller: _controller,
                      style: const TextStyle(fontSize: 13),
                      decoration: _compactInput("传输文件名（含后缀）"),
                      onChanged: (v) {
                        _recordPenProvider.setTransFileName(v);
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
                        style: const TextStyle(fontSize: 13, color: Colors.black),
                        decoration: _compactInput('选择设备 (${discoveredDevices.length})'),
                        hint: const Text(
                          '搜索后选择设备',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        items: discoveredDevices
                            .map(
                              (device) => DropdownMenuItem<String>(
                                value: device['address'],
                                child: Text(
                                  device['address'] ?? '',
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: discoveredDevices.isEmpty
                            ? null
                            : (value) {
                                setState(() => _selectedDeviceAddress = value);
                              },
                      ),
                    ),
                    SizedBox(
                      height: 40,
                      child: FilledButton(
                        onPressed: _selectedDeviceAddress == null
                            ? null
                            : () => _connectSelectedDevice(recordPenProvider),
                        child: Text(AppLocale.text('连接')),
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
                      await _resetRecordPcm();
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
                      _playWav(_recordWavName, '录音');
                    }, enabled: _recordWavExists),
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
                      _recordPenProvider.deleteFile(
                        _recordPenProvider.transFileName,
                      );
                    }),
                    _buttonItem("⚠️删除所有文件", () {
                      _recordPenProvider.deleteAllFile();
                    }),
                    _buttonItem("传输文件", () async {
                      await _resetTransferPcm();
                      _recordPenProvider.sendFileFromPenToPhoneWithOffset(
                        _recordPenProvider.transFileName,
                        0,
                      );
                    }),
                    _buttonItem("停止传输", () {
                      _recordPenProvider.stopTransferFile(
                        _recordPenProvider.transFileName,
                      );
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
                      _playWav(_transferWavName, '传输音频');
                    }, enabled: _transferWavExists),
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
                Text("第二代wifi版本"),
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
                    _buttonItem("连接(${_recordPenProvider.wifiName})", () {
                      _recordPenProvider.connectDeviceWiFi();
                    }),
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
                    _buttonItem("固件版本号", () {
                      _recordPenProvider.getDeviceVersion();
                    }),
                    _buttonItem("固件升级code", () {
                      _recordPenProvider.getDeviceVersionCode();
                    }),
                    _buttonItem("请求升级", () {
                      _recordPenProvider.requestDeviceGotoOtaMode();
                    }),
                    _buttonItem("发送固件V5", () async {
                      await _recordPenProvider.sendOtaAssetFile(
                        assetPath: "assets/update512.ufw",
                      );
                    }),
                    _buttonItem("低功耗状态", () {
                      _recordPenProvider.getDeviceLowPowerRecordMode();
                    }),
                    _buttonItem("设置低功耗", () {
                      _recordPenProvider.setDeviceLowPowerRecordMode(true);
                    }),
                  ],
                ),

                Row(
                  spacing: 8,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _sendFileTimeIntervalController,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(fontSize: 13),
                        decoration: _compactInput("文件传输间隔（毫秒）"),
                      ),
                    ),
                    SizedBox(
                      height: 38,
                      child: FilledButton(
                        onPressed: () {
                          final interval = int.tryParse(
                            _sendFileTimeIntervalController.text.trim(),
                          );
                          if (interval == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('请输入有效的时间间隔')),
                            );
                            return;
                          }
                          _recordPenProvider.setSendFileTimeInterval(interval);
                        },
                        child: const Text('设置间隔'),
                      ),
                    ),
                  ],
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
              border: Border(
                bottom: BorderSide(color: borderColor),
              ),
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
    if (line.contains('结束') ||
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

  /// 紧凑型输入框样式，减少纵向占用
  InputDecoration _compactInput(String hint) {
    return InputDecoration(
      hintText: AppLocale.text(hint),
      hintStyle: const TextStyle(fontSize: 12, color: Colors.grey),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
    );
  }

  _buttonItem(String title, Function() onTap, {bool enabled = true}) {
    return FilledButton(
      onPressed: enabled ? onTap : null,
      style: ButtonStyle(padding: MaterialStateProperty.all(EdgeInsets.zero)),
      child: FittedBox(child: Text(AppLocale.text(title), style: const TextStyle(fontSize: 12))),
    );
  }
}
