import 'dart:async';

import 'package:pnote_flutter_sdk/pnote_flutter_sdk.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'file_list_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '声云录音笔 SDK Demo',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const HomePage(),
    );
  }
}

/// 一条带类型的日志（用于控制台着色）。
enum _LogKind { info, app, error, frame, raw }

class _LogEntry {
  _LogEntry(this.time, this.kind, this.text);
  final DateTime time;
  final _LogKind kind;
  final String text;
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  final _sdk = AudioPenSdk();

  StreamSubscription<List<ScanResult>>? _scanSub;
  List<ScanResult> _results = const [];
  bool _scanning = false;

  // 上次成功连接的设备（名字+地址），扫描页提供一键重连
  String? _lastName;
  String? _lastAddress;

  AudioPenDevice? _device;
  final _logs = <_LogEntry>[];
  final _subs = <StreamSubscription>[];

  /// 原始调试开关：控制是否打印原始字节(`[BLE…]`)和解码后的原始帧(`← Frame`)。
  bool _rawDebug = true;

  // 设备信息
  BatteryInfo? _battery;
  Capacity? _capacity;
  String? _version;

  // 录音状态（本地驱动，用于 UI 反馈）
  bool _recording = false;
  bool _paused = false;
  int _recordSeconds = 0;
  Timer? _recordTimer;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  void _log(String msg, [_LogKind kind = _LogKind.info]) {
    debugPrint('[DEMO] $msg');
    setState(() => _logs.insert(0, _LogEntry(DateTime.now(), kind, msg)));
  }

  void _clearLogs() => setState(() => _logs.clear());

  Future<void> _startScan() async {
    setState(() {
      _scanning = true;
      _results = const [];
    });
    _scanSub?.cancel();
    _scanSub = _sdk.startSearch(timeout: const Duration(seconds: 15)).listen((r) {
      setState(() => _results = r);
    });
    FlutterBluePlus.isScanning
        .firstWhere((scanning) => scanning == false)
        .then((_) {
      if (mounted) setState(() => _scanning = false);
    });
  }

  Future<void> _connect(ScanResult r) async {
    _log('连接 ${r.device.platformName}...');
    await _connectAndSetup(() => _sdk.connectDevice(r.device));
  }

  /// 一键重连上次设备（走 `connectDeviceAndAddress`：扫描缓存按名+址匹配，
  /// 未命中则按地址直连——设备未在广播也能发起）。
  Future<void> _reconnect() {
    _log('重连 $_lastName ($_lastAddress)...');
    return _connectAndSetup(
        () => _sdk.connectDeviceAndAddress(_lastName!, _lastAddress!));
  }

  /// 连接 + 统一接线（订阅各流、记录重连信息、同步时间）。
  Future<void> _connectAndSetup(
      Future<AudioPenDevice> Function() connect) async {
    try {
      final device = await connect();
      device.debugLog = _rawDebug;
      _subs.add(device.debugLogStream.listen((line) {
        if (_rawDebug) _log(line, _LogKind.raw);
      }));
      _subs.add(device.rawFrameStream.listen((f) {
        if (_rawDebug) _log('← $f', _LogKind.frame);
      }));
      _subs.add(device.keyEventStream.listen((f) async {
        _log('按键事件 cmd=${f.cmd}', _LogKind.app);
        // 物理按键同步 UI：1 开始 / 3 保存(停止) / 5 暂停 / 7 继续。
        // 收到开始/停止按键时，App 回发对应录音指令（对齐设备期望的按键应答）。
        switch (f.cmd) {
          case 1:
            _enterRecording();
            _log('回应：发送开始录音指令', _LogKind.app);
            await device.startRecord();
          case 3:
            _enterStopped();
            _log('回应：发送停止录音指令', _LogKind.app);
            await device.stopRecord();
          case 5:
            _enterPaused();
          case 7:
            _enterResumed();
        }
      }));
      _subs.add(device.statusStream.listen((m) => _log('状态 $m')));
      // 设备端暂停/继续/停止（audio 0x04）：0 停止 / 2 暂停 / 3 继续。
      _subs.add(device.deviceRecordStream.listen((state) {
        _log('设备端录音状态变化: $state', _LogKind.app);
        switch (state) {
          case 0:
            _enterStopped();
          case 2:
            _enterPaused();
          case 3:
            _enterResumed();
        }
      }));
      _subs.add(device.appEventStream.listen((json) {
        _log('APP事件 $json', _LogKind.app);
      }));
      setState(() {
        _device = device;
        _lastName = device.name;
        _lastAddress = device.id;
      });
      _log('已连接');
      await device.syncTime();
      _log('已同步时间');
    } catch (e) {
      _log('连接失败: $e', _LogKind.error);
    }
  }

  Future<void> _disconnect() async {
    _stopTimer();
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    await _device?.closeConnect();
    setState(() {
      _device = null;
      _battery = null;
      _capacity = null;
      _version = null;
      _recording = false;
      _paused = false;
      _recordSeconds = 0;
    });
    _log('已断开');
  }

  Future<void> _run(String label, Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      _log('$label 失败: $e', _LogKind.error);
    }
  }

  // ---- 录音状态与计时 ----

  void _startTimer() {
    _recordTimer?.cancel();
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _recordSeconds++);
    });
  }

  void _stopTimer() {
    _recordTimer?.cancel();
    _recordTimer = null;
  }

  Future<void> _onStart() => _run('开始录音', () async {
        _log('APP↓ ${await _device!.startRecordAppJson()}', _LogKind.app);
        _enterRecording();
      });

  Future<void> _onStop() => _run('停止录音', () async {
        _log('APP↓ ${await _device!.stopRecordAppJson()}', _LogKind.app);
        _enterStopped();
      });

  Future<void> _onPause() => _run('暂停录音', () async {
        _log('APP↓ ${await _device!.pauseRecordAppJson()}', _LogKind.app);
        _enterPaused();
      });

  Future<void> _onResume() => _run('继续录音', () async {
        _log('APP↓ ${await _device!.continueRecordAppJson()}', _LogKind.app);
        _enterResumed();
      });

  // ---- UI 录音状态转换（按钮与物理按键/设备端事件共用）----

  void _enterRecording() {
    if (_recording) return;
    setState(() {
      _recording = true;
      _paused = false;
      _recordSeconds = 0;
    });
    _startTimer();
  }

  void _enterStopped() {
    if (!_recording) return;
    _stopTimer();
    setState(() {
      _recording = false;
      _paused = false;
    });
  }

  void _enterPaused() {
    if (!_recording || _paused) return;
    _stopTimer();
    setState(() => _paused = true);
  }

  void _enterResumed() {
    if (!_recording || !_paused) return;
    setState(() => _paused = false);
    _startTimer();
  }

  Future<void> _refreshAll() => _run('刷新信息', () async {
        final b = await _device!.getCBC();
        final c = await _device!.getDeviceCapacity();
        final v = await _device!.getDeviceVersion();
        setState(() {
          _battery = b;
          _capacity = c;
          _version = v;
        });
        _log('信息已刷新：电量${b.percent}% / 版本$v');
      });

  /// 删除设备上全部录音（需二次确认，不可恢复）。
  Future<void> _onDeleteAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除全部录音'),
        content: const Text('确定删除设备上全部录音文件吗？此操作不可恢复。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run('删除全部', () async {
      final j = await _device!.delAllFileDataAppJson();
      _log('APP↓ $j', _LogKind.app);
    });
  }

  @override
  void dispose() {
    _stopTimer();
    _pulse.dispose();
    _scanSub?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _device?.closeConnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connected = _device != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('声云录音笔 SDK Demo'),
        actions: [
          Row(
            children: [
              const Text('原始调试', style: TextStyle(fontSize: 12)),
              Switch(
                value: _rawDebug,
                onChanged: (v) {
                  setState(() => _rawDebug = v);
                  _device?.debugLog = v;
                  _log('原始调试: ${v ? '开' : '关'}');
                },
              ),
            ],
          ),
          if (connected)
            IconButton(
              onPressed: _disconnect,
              icon: const Icon(Icons.bluetooth_disabled),
              tooltip: '断开',
            ),
        ],
      ),
      body: connected ? _buildConnected() : _buildScan(),
    );
  }

  // ---- 扫描页 ----

  Widget _buildScan() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: _scanning ? null : _startScan,
            icon: _scanning
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.search),
            label: Text(_scanning ? '扫描中…' : '扫描录音笔'),
          ),
        ),
        if (_lastName != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _reconnect,
                icon: const Icon(Icons.history),
                label: Text('重连 $_lastName'),
              ),
            ),
          ),
        if (_results.isEmpty && !_scanning)
          const Expanded(
            child: Center(
              child: Text('点击上方按钮扫描附近录音笔',
                  style: TextStyle(color: Colors.grey)),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              itemCount: _results.length,
              itemBuilder: (_, i) {
                final r = _results[i];
                final name = r.device.platformName.isEmpty
                    ? '(未命名)'
                    : r.device.platformName;
                return ListTile(
                  leading: CircleAvatar(
                    child: Text('${r.rssi}',
                        style: const TextStyle(fontSize: 12)),
                  ),
                  title: Text(name),
                  subtitle: Text(r.device.remoteId.str),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _connect(r),
                );
              },
            ),
          ),
      ],
    );
  }

  // ---- 已连接页 ----

  Widget _buildConnected() {
    return Column(
      children: [
        if (_recording) _buildRecordingBanner(),
        _buildInfoCard(),
        _buildActionGroups(),
        _buildConsole(),
      ],
    );
  }

  /// 录音中横幅：脉冲红点 + 计时。
  Widget _buildRecordingBanner() {
    final label = _paused ? '已暂停' : '录音中';
    final color = _paused ? Colors.orange : Colors.red;
    return Container(
      width: double.infinity,
      color: color.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          FadeTransition(
            opacity: _paused
                ? const AlwaysStoppedAnimation(1.0)
                : _pulse,
            child: Icon(Icons.fiber_manual_record, color: color, size: 16),
          ),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(color: color, fontWeight: FontWeight.bold)),
          const Spacer(),
          Text(_fmtTime(_recordSeconds),
              style: TextStyle(
                  color: color,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  fontSize: 16)),
        ],
      ),
    );
  }

  /// 设备信息卡：图标行 + 电量条 + 刷新全部。
  Widget _buildInfoCard() {
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.mic, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _device!.name.isEmpty ? '已连接设备' : _device!.name,
                    style: Theme.of(context).textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton.icon(
                  onPressed: _refreshAll,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('刷新'),
                ),
              ],
            ),
            const Divider(),
            _batteryRow(),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _infoTile(Icons.sd_storage, '容量',
                      _capacity == null
                          ? '—'
                          : '${_fmtMb(_capacity!.freeKb)}/${_fmtMb(_capacity!.totalKb)}'),
                ),
                Expanded(
                  child: _infoTile(
                      Icons.info_outline, '版本', _version ?? '—'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _batteryRow() {
    final pct = _battery?.percent;
    final charging = _battery?.charging ?? false;
    return Row(
      children: [
        Icon(charging ? Icons.battery_charging_full : Icons.battery_std,
            size: 18, color: _batteryColor(pct)),
        const SizedBox(width: 8),
        SizedBox(width: 48, child: Text(pct == null ? '电量' : '$pct%')),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct == null ? 0 : pct / 100,
              minHeight: 8,
              backgroundColor: Colors.grey.shade300,
              color: _batteryColor(pct),
            ),
          ),
        ),
        if (charging)
          const Padding(
            padding: EdgeInsets.only(left: 8),
            child: Text('充电中', style: TextStyle(fontSize: 12)),
          ),
      ],
    );
  }

  Color _batteryColor(int? pct) {
    if (pct == null) return Colors.grey;
    if (pct <= 20) return Colors.red;
    if (pct <= 50) return Colors.orange;
    return Colors.green;
  }

  Widget _infoTile(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
              Text(value,
                  style: const TextStyle(fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ],
    );
  }

  /// 按功能分组的可折叠操作区。
  Widget _buildActionGroups() {
    return Flexible(
      child: SingleChildScrollView(
        child: Column(
          children: [
            _group(Icons.info_outline, '设备信息', initiallyExpanded: true,
                children: [
                  _btn(Icons.battery_std, '电量', () => _run('电量', () async {
                        final b = await _device!.getCBC();
                        setState(() => _battery = b);
                        _log('APP↓ ${await _device!.getCBCAppJson()}',
                            _LogKind.app);
                      })),
                  _btn(Icons.sd_storage, '容量', () => _run('容量', () async {
                        final c = await _device!.getDeviceCapacity();
                        setState(() => _capacity = c);
                        _log('APP↓ ${await _device!.getDeviceCapacityAppJson()}',
                            _LogKind.app);
                      })),
                  _btn(Icons.tag, '版本', () => _run('版本', () async {
                        final v = await _device!.getDeviceVersion();
                        setState(() => _version = v);
                        _log('APP↓ ${await _device!.getDeviceVersionAppJson()}',
                            _LogKind.app);
                      })),
                  _btn(Icons.fingerprint, 'SN/MAC', () => _run('SN/MAC',
                      () async {
                        _log('APP↓ ${await _device!.getSnAppJson()}',
                            _LogKind.app);
                      })),
                ]),
            _group(Icons.mic, '录音控制', initiallyExpanded: true, children: [
              _btn(Icons.fiber_manual_record, '开始',
                  _recording ? null : _onStart,
                  color: Colors.red),
              _btn(Icons.stop, '停止', _recording ? _onStop : null),
              _btn(Icons.pause, '暂停',
                  (_recording && !_paused) ? _onPause : null),
              _btn(Icons.play_arrow, '继续',
                  (_recording && _paused) ? _onResume : null),
              _btn(Icons.help_outline, '录音状态', () => _run('录音状态', () async {
                    final s = await _device!.getRecordState();
                    _log('录音状态: $s');
                    _log('APP↓ ${await _device!.getRecordStateAppJson()}',
                        _LogKind.app);
                  })),
            ]),
            _group(Icons.folder, '文件', children: [
              _btn(Icons.list, '文件列表', () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => FileListPage(
                      device: _device!,
                      onAppJson: (json) => _log('APP↓ $json', _LogKind.app),
                    ),
                  ),
                );
              }),
              _btn(Icons.delete_sweep, '删除全部', _onDeleteAll),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _group(IconData icon, String title,
      {required List<Widget> children, bool initiallyExpanded = false}) {
    return ExpansionTile(
      leading: Icon(icon, size: 20),
      title: Text(title, style: const TextStyle(fontSize: 14)),
      initiallyExpanded: initiallyExpanded,
      tilePadding: const EdgeInsets.symmetric(horizontal: 16),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(spacing: 8, runSpacing: 8, children: children),
        ),
      ],
    );
  }

  /// 带图标的按钮；[onTap] 为 null 时禁用。
  Widget _btn(IconData icon, String label, VoidCallback? onTap,
      {Color? color}) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18, color: onTap == null ? null : color),
      label: Text(label),
    );
  }

  // ---- 日志控制台 ----

  Widget _buildConsole() {
    return Expanded(
      child: Container(
        color: const Color(0xFF1E1E1E),
        width: double.infinity,
        child: Column(
          children: [
            Container(
              color: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  const Icon(Icons.terminal, color: Colors.white54, size: 16),
                  const SizedBox(width: 6),
                  Text('控制台 · ${_logs.length}',
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 12)),
                  const Spacer(),
                  InkWell(
                    onTap: _logs.isEmpty ? null : _clearLogs,
                    child: Icon(Icons.delete_sweep,
                        color: _logs.isEmpty
                            ? Colors.white24
                            : Colors.white54,
                        size: 18),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: _logs.length,
                itemBuilder: (_, i) => _logLine(_logs[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _logLine(_LogEntry e) {
    final color = switch (e.kind) {
      _LogKind.app => Colors.greenAccent,
      _LogKind.error => Colors.redAccent,
      _LogKind.frame => Colors.white38,
      _LogKind.raw => Colors.lightBlueAccent.shade100,
      _LogKind.info => Colors.white70,
    };
    final ts = '${_two(e.time.hour)}:${_two(e.time.minute)}:${_two(e.time.second)}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
          children: [
            TextSpan(
                text: '$ts ',
                style: const TextStyle(color: Colors.white30)),
            TextSpan(text: e.text, style: TextStyle(color: color)),
          ],
        ),
      ),
    );
  }
}

String _fmtTime(int sec) {
  final m = sec ~/ 60;
  final s = sec % 60;
  return '${_two(m)}:${_two(s)}';
}

/// KB → 人类可读（MB/GB）。
String _fmtMb(int kb) {
  if (kb < 1024) return '${kb}KB';
  final mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)}MB';
  return '${(mb / 1024).toStringAsFixed(2)}GB';
}

String _two(int n) => n.toString().padLeft(2, '0');
