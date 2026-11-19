import 'dart:async';
import 'dart:io';

import 'package:pnote_flutter_sdk/pnote_flutter_sdk.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import 'opus_file_decoder.dart';

/// 文件列表页：进入后自动拉取，支持下拉刷新、下载录音、解码播放。
class FileListPage extends StatefulWidget {
  const FileListPage({super.key, required this.device, this.onAppJson});

  final AudioPenDevice device;

  /// 拉取成功后回传 App 侧 JSON（cmd=4），供主页控制台打印。
  final void Function(String json)? onAppJson;

  @override
  State<FileListPage> createState() => _FileListPageState();
}

/// 单个文件的下载/播放状态。
class _FileState {
  _FileState(this.name);
  final String name;

  bool downloading = false;
  int received = 0; // 已下载字节
  int? total; // 文件总字节（来自 PenFile.sizeBytes）

  bool decoded = false; // 是否已转 wav
  String? wavPath;
  String? error;

  bool get downloadDone => decoded || error != null;
  double? get progress =>
      total == null ? null : (received / total!).clamp(0.0, 1.0);
}

class _FileListPageState extends State<FileListPage> {
  List<PenFile>? _files; // null = 尚未加载完成
  bool _loading = false;
  String? _error;

  /// 每个文件的下载/播放状态（按文件名索引）。
  final Map<String, _FileState> _states = {};
  final AudioPlayer _player = AudioPlayer();
  String? _playingName;
  StreamSubscription? _playerSub;

  @override
  void initState() {
    super.initState();
    _load();
    _playerSub = _player.playerStateStream.listen((s) {
      if (s.processingState == ProcessingState.completed) {
        setState(() => _playingName = null);
        _player.stop();
      }
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // 列表请求始终走 BLE；TCP 连上时设备经 TCP 推文件数据（cmd=4）走 WiFi
      // 高速下载，故这里不再断开 TCP（断开反而会丢失高速下载通道）。
      final files = await widget.device.getRecordFileList();
      if (!mounted) return;
      widget.onAppJson?.call(AppCodec.encode(AppCodec.fileList(files)));
      setState(() {
        _files = files;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  /// 把文件名转成安全的磁盘文件名（去掉空格等）。
  String _safeName(String name) => name.replaceAll(RegExp(r'\s'), '');

  Future<Directory> _tempDir() => getTemporaryDirectory();

  /// 下载并解码播放某个文件。
  Future<void> _downloadAndPlay(PenFile f) async {
    final state = _states.putIfAbsent(f.name, () => _FileState(f.name));
    if (state.downloading) return; // 防重复点击
    setState(() {
      state.downloading = true;
      state.received = 0;
      state.total = f.sizeBytes;
      state.decoded = false;
      state.error = null;
    });

    final safe = _safeName(f.name);
    final dir = await _tempDir();
    final opusPath = '${dir.path}/$safe';
    final wavPath =
        '${dir.path}/${safe.replaceAll(RegExp(r'\.opus$'), '')}.wav';

    // 订阅下载流：数据块追加写文件、进度更新。
    final outFile = File(opusPath);
    final raf = await outFile.open(mode: FileMode.write);
    final dataSub = widget.device.fileDataStream.listen((chunk) async {
      raf.writeFromSync(chunk);
      setState(() => state.received += chunk.length);
    });
    final progSub = widget.device.downloadProgressStream.listen((n) {
      setState(() => state.received = n);
    });

    try {
      final result = await widget.device.startGetFile(f.name);
      await dataSub.cancel();
      await progSub.cancel();
      await raf.close();

      if (!result.success) {
        setState(() {
          state.downloading = false;
          state.error = _endCodeText(result.endCode);
        });
        _toast('下载失败：${_endCodeText(result.endCode)}');
        return;
      }
      // 解码 opus → wav
      await opusFileToWav(opusPath, wavPath);
      if (!mounted) return;
      setState(() {
        state.downloading = false;
        state.decoded = true;
        state.wavPath = wavPath;
      });
      // 自动播放
      _play(state);
    } catch (e) {
      await dataSub.cancel();
      await progSub.cancel();
      try {
        await raf.close();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        state.downloading = false;
        state.error = '$e';
      });
      _toast('下载/解码失败：$e');
    }
  }

  Future<void> _play(_FileState state) async {
    if (state.wavPath == null) return;
    try {
      await _player.setFilePath(state.wavPath!);
      await _player.play();
      setState(() => _playingName = state.name);
    } catch (e) {
      _toast('播放失败：$e');
    }
  }

  Future<void> _stop() async {
    await _player.stop();
    setState(() => _playingName = null);
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    _playerSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final files = _files;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '文件列表'
          '${files != null ? ' (${files.length})' : ''}',
        ),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
          ),
        ],
      ),
      body: _listArea(files),
    );
  }

  Widget _listArea(List<PenFile>? files) {
    if (_error != null) {
      return _CenteredMessage(
        icon: Icons.error_outline,
        text: '加载失败\n$_error',
        action: FilledButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh),
          label: const Text('重试'),
        ),
      );
    }
    if (files == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (files.isEmpty) {
      return const _CenteredMessage(
        icon: Icons.folder_off_outlined,
        text: '设备上没有录音文件',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        itemCount: files.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) => _fileTile(files[i]),
      ),
    );
  }

  Widget _fileTile(PenFile f) {
    final st = _states[f.name];
    final downloading = st?.downloading ?? false;
    final progress = st?.progress;
    final decoded = st?.decoded ?? false;
    final error = st?.error;
    final playing = _playingName == f.name;

    return ListTile(
      leading: Icon(f.isCall ? Icons.call : Icons.mic_none),
      title: Text(f.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            error ??
                (decoded
                    ? '已可播放'
                    : '时长 ${_fmtDuration(f.durationSec)} · 大小 ${_fmtSize(f.sizeBytes)}'),
            style: error != null
                ? const TextStyle(color: Colors.red, fontSize: 12)
                : const TextStyle(fontSize: 12),
          ),
          if (downloading && progress != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: LinearProgressIndicator(value: progress),
            ),
        ],
      ),
      trailing: _trailing(f, st, downloading, decoded, playing),
      isThreeLine: true,
      onTap: () {
        if (decoded) {
          playing ? _stop() : _play(st!);
        } else if (!downloading) {
          _downloadAndPlay(f);
        }
      },
    );
  }

  Widget _trailing(
    PenFile f,
    _FileState? st,
    bool downloading,
    bool decoded,
    bool playing,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _statusIcon(downloading, decoded, playing),
        IconButton(
          icon: const Icon(Icons.delete_outline, size: 20),
          tooltip: '删除',
          // 下载中禁用，避免删一个正在传输的文件。
          onPressed: downloading ? null : () => _confirmDelete(f),
        ),
      ],
    );
  }

  Widget _statusIcon(bool downloading, bool decoded, bool playing) {
    if (downloading) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (decoded) {
      return Icon(
        playing ? Icons.stop : Icons.play_arrow,
        color: Theme.of(context).colorScheme.primary,
      );
    }
    return const Icon(Icons.download_outlined);
  }

  // ---- 删除文件（对齐 iOS 端 delFileData:） ----

  Future<void> _confirmDelete(PenFile f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除录音'),
        content: Text('确定删除「${f.name}」吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _delete(f);
  }

  Future<void> _delete(PenFile f) async {
    try {
      final success = await widget.device.delFileData(f.name);
      if (!mounted) return;
      if (success) {
        _toast('已删除：${f.name}');
        setState(() {
          _files?.removeWhere((e) => e.name == f.name);
          _states.remove(f.name);
          if (_playingName == f.name) {
            _player.stop();
            _playingName = null;
          }
        });
      } else {
        _toast('删除失败：设备返回失败');
      }
    } catch (e) {
      if (!mounted) return;
      _toast('删除失败：$e');
    }
  }
}

String _endCodeText(FileEndCode code) {
  switch (code) {
    case FileEndCode.completed:
      return '完成';
    case FileEndCode.notFound:
      return '文件不存在';
    case FileEndCode.offsetTooLarge:
      return 'offset 过大';
    case FileEndCode.other:
      return '其它停止';
  }
}

String _fmtDuration(int sec) {
  final h = sec ~/ 3600;
  final m = (sec % 3600) ~/ 60;
  final s = sec % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

String _fmtSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).disabledColor),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}
