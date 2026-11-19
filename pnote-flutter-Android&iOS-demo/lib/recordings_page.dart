import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:pnote_flutter_sdk/pnote_flutter_sdk.dart';

import 'audio/recording_store.dart';
import 'design/tokens.dart';
import 'l10n/gen/app_localizations.dart';
import 'session.dart';

/// 单个文件的下载/播放展示状态。
class _FileUi {
  bool downloading = false;

  /// 用户暂停（断点保留，可续传）。
  bool paused = false;

  /// 总已收字节（跨暂停续传累计）。
  int received = 0;

  /// 下载会话序号：暂停后再续传时 +1，旧会话迟到的回包按过期丢弃。
  int attempt = 0;
  FileDownloadResult? result;
  String? error;
}

class RecordingsPage extends StatefulWidget {
  const RecordingsPage({super.key, required this.session});

  final Session session;

  @override
  State<RecordingsPage> createState() => RecordingsPageState();
}

class RecordingsPageState extends State<RecordingsPage> {
  List<PenFile> _files = const [];
  bool _loading = false;
  String? _loadError;
  final _ui = <String, _FileUi>{};

  /// 已完整落盘到手机的文件名（可播放）。
  final _saved = <String>{};

  StreamSubscription<int>? _progressSub;
  StreamSubscription<Uint8List>? _dataSub;
  IOSink? _sink;

  final _store = RecordingStore.instance;
  final _player = AudioPlayer();
  String? _playerFor;
  String? _convertingFor;

  @override
  void initState() {
    super.initState();
    unawaited(() async {
      try {
        final s = await AudioSession.instance;
        await s.configure(const AudioSessionConfiguration.music());
      } catch (_) {}
    }());
    if (widget.session.connected) _load();
  }

  /// 每次进入本页时由 HomeShell 调用：自动重新拉取设备文件列表。
  void refresh() {
    if (widget.session.device != null && !_loading) _load();
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    _dataSub?.cancel();
    unawaited(_sink?.close());
    unawaited(_player.dispose());
    super.dispose();
  }

  AppLocalizations get _loc => AppLocalizations.of(context)!;

  Future<void> _load() async {
    final d = widget.session.device;
    if (d == null) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      _files = await d.getRecordFileList();
      _saved.clear();
      for (final f in _files) {
        if (await _store.hasOpus(f.name)) _saved.add(f.name);
      }
      widget.session.log(_loc.logFileListLoaded(_files.length));
    } catch (e) {
      _loadError = '$e';
      widget.session.log(_loc.logFileListFailed('$e'), LogKind.error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _download(PenFile f) async {
    final d = widget.session.device;
    final ui = _ui.putIfAbsent(f.name, _FileUi.new);
    if (d == null || (ui.downloading && !ui.paused)) return;
    final myAttempt = ++ui.attempt;
    final resumed = ui.paused;
    ui
      ..downloading = true
      ..paused = false
      ..result = null
      ..error = null;
    setState(() {});
    if (!resumed) {
      ui.received = 0;
      widget.session.log(_loc.logDownloadStarted(f.name));
    } else {
      widget.session.log(
          _loc.logDownloadResumed(f.name, fmtBytes(ui.received)));
    }

    // 续传从断点 append 接写；首下截断重写。
    final base = ui.received;
    final file = await _store.opusFile(f.name);
    _sink = file.openWrite(mode: base == 0 ? FileMode.write : FileMode.append);

    // 续传会话的进度流从 0 重计，展示时加回断点基数。
    _progressSub?.cancel();
    _progressSub = d.downloadProgressStream.listen((received) {
      if (mounted && myAttempt == ui.attempt && ui.downloading) {
        setState(() => ui.received = base + received);
      }
    });

    // 落盘：设备推流字节直接写 .opus 文件。
    _dataSub?.cancel();
    _dataSub = d.fileDataStream.listen((chunk) => _sink?.add(chunk));

    try {
      final r = await d.startGetFile(f.name, offset: base);
      // 暂停后已续传新会话：本会话结果作废（文件正由新会话接管）。
      if (myAttempt != ui.attempt) return;
      await _teardownTransfer();
      ui.result = r;
      final completed = r.endCode == FileEndCode.completed;
      if (completed) {
        _saved.add(f.name);
        // 下载完成的本地文件同步进首页「近期录音」（base 为续传前已收字节）。
        widget.session.addDownloadedToRecent(f.name, base + r.receivedBytes);
      } else if (!ui.paused) {
        // 未收齐且非用户暂停的残片不保留，避免被当成完整缓存播放。
        await _store.remove(f.name);
        ui.received = 0;
      }
      widget.session.log(
        completed
            ? _loc.logDownloadCompleted(f.name, fmtBytes(r.receivedBytes))
            : _loc.logDownloadStoppedCode(
                r.endCode.name, f.name, fmtBytes(r.receivedBytes)),
        completed ? LogKind.event : LogKind.error,
      );
    } catch (e) {
      if (myAttempt == ui.attempt) {
        await _teardownTransfer();
        if (!ui.paused) {
          await _store.remove(f.name);
          ui.received = 0;
          ui.error = '$e';
          widget.session.log(
              _loc.logDownloadFailed(f.name, '$e'), LogKind.error);
        }
      }
    } finally {
      if (myAttempt == ui.attempt) {
        ui.downloading = false;
        if (mounted) setState(() {});
      }
    }
  }

  /// 用户暂停：发 cmd=7 让设备停推，断点落盘保留（不走删除路径）。
  Future<void> _pause(PenFile f) async {
    final ui = _ui[f.name];
    final d = widget.session.device;
    if (ui == null || !ui.downloading || ui.paused || d == null) return;
    ui.paused = true;
    setState(() {});
    await d.stopGetFile();
    await _teardownTransfer();
    widget.session.log(
        _loc.logDownloadPaused(f.name, fmtBytes(ui.received)), LogKind.event);
  }

  Future<void> _teardownTransfer() async {
    await _progressSub?.cancel();
    _progressSub = null;
    await _dataSub?.cancel();
    _dataSub = null;
    final sink = _sink;
    _sink = null;
    if (sink != null) {
      try {
        await sink.flush();
      } catch (_) {}
      try {
        await sink.close();
      } catch (_) {}
    }
  }

  Future<void> _play(PenFile f) async {
    if (_convertingFor != null) return;
    if (_playerFor == f.name) {
      if (_player.playing) {
        await _player.pause();
      } else {
        await _player.play();
      }
      return;
    }
    setState(() => _convertingFor = f.name);
    try {
      final wav = await _store.toWav(f.name);
      await _player.setFilePath(wav.path);
      setState(() => _playerFor = f.name);
      await _player.play();
    } catch (e) {
      widget.session.log(_loc.logPlayFailed('$e'), LogKind.error);
    } finally {
      if (mounted) setState(() => _convertingFor = null);
    }
  }

  Future<void> _stopPlayer() async {
    await _player.stop();
    if (mounted) setState(() => _playerFor = null);
  }

  Future<void> _confirmDelete(PenFile f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final l10n = AppLocalizations.of(ctx)!;
        return AlertDialog(
          title: Text(l10n.deleteRecordingTitle),
          content: Text(l10n.deleteRecordingBody(f.name)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              style:
                  FilledButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.delete),
            ),
          ],
        );
      },
    );
    if (ok != true || !mounted) return;
    final d = widget.session.device;
    if (d == null) return;
    try {
      final success = await d.delFileData(f.name);
      if (_playerFor == f.name) await _stopPlayer();
      await _store.remove(f.name);
      _ui.remove(f.name);
      widget.session.removeRecent(f.name);
      widget.session.log(
          success
              ? _loc.logDeleteOk(f.name)
              : _loc.logDeleteFailedState(f.name),
          success ? LogKind.event : LogKind.error);
      await _load();
    } catch (e) {
      widget.session.log(_loc.logDeleteFailed('$e'), LogKind.error);
    }
  }

  Future<void> _confirmDeleteAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final l10n = AppLocalizations.of(ctx)!;
        return AlertDialog(
          title: Text(l10n.deleteAllTitle),
          content: Text(l10n.deleteAllBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              style:
                  FilledButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.deleteAll),
            ),
          ],
        );
      },
    );
    if (ok != true || !mounted) return;
    final d = widget.session.device;
    if (d == null) return;
    try {
      final json = await d.delAllFileDataAppJson();
      await _stopPlayer();
      _ui.clear();
      for (final f in _files) {
        await _store.remove(f.name);
        widget.session.removeRecent(f.name);
      }
      widget.session.log('→ $json', LogKind.event);
      await _load();
    } catch (e) {
      widget.session.log(_loc.logDeleteAllFailed('$e'), LogKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListenableBuilder(
      listenable: widget.session,
      builder: (_, _) {
        if (!widget.session.connected) {
          // 连接建立后再进到本页时拉取列表。
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (widget.session.connected && _files.isEmpty && !_loading) {
              _load();
            }
          });
          return _emptyState(l10n);
        }
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _files.isEmpty
                          ? l10n.recordings
                          : l10n.recordingsCount(_files.length),
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppColors.muted),
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.tooltipRefresh,
                    onPressed: _loading ? null : _load,
                    icon: _loading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh,
                            size: 20, color: AppColors.primary),
                  ),
                  TextButton(
                    onPressed: _files.isEmpty ? null : _confirmDeleteAll,
                    style: TextButton.styleFrom(
                        foregroundColor: AppColors.danger),
                    child: Text(l10n.deleteAll),
                  ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                child: _files.isEmpty && _loadError == null
                    ? ListView(
                        children: [
                          const SizedBox(height: 120),
                          Center(
                            child: Text(l10n.noFiles,
                                style:
                                    const TextStyle(color: AppColors.muted)),
                          ),
                        ],
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                        itemCount: _files.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (_, i) => _tile(l10n, _files[i]),
                      ),
              ),
            ),
            if (_playerFor != null) _miniPlayer(),
            if (_loadError != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(l10n.loadFailed(_loadError!),
                    style: const TextStyle(
                        color: AppColors.danger, fontSize: 12)),
              ),
          ],
        );
      },
    );
  }

  Widget _emptyState(AppLocalizations l10n) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.library_music_outlined,
              size: 44, color: AppColors.borderStrong),
          const SizedBox(height: 12),
          Text(l10n.noDevice,
              style: const TextStyle(
                  fontWeight: FontWeight.w600, color: AppColors.ink)),
          const SizedBox(height: 4),
          Text(l10n.noDeviceHint,
              style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
        ],
      ),
    );
  }

  Widget _tile(AppLocalizations l10n, PenFile f) {
    final ui = _ui[f.name];
    final downloading = ui?.downloading ?? false;
    final paused = ui?.paused ?? false;
    final saved = _saved.contains(f.name);
    final playingThis = _playerFor == f.name;
    final convertingThis = _convertingFor == f.name;
    final failed = ui?.error != null ||
        (ui?.result != null && ui!.result!.endCode != FileEndCode.completed);
    final progress = (f.sizeBytes > 0 && ui != null)
        ? (ui.received / f.sizeBytes).clamp(0.0, 1.0)
        : null;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        // 暂停中整条可点 = 继续；传输中禁点。
        onTap: saved || (downloading && !paused)
            ? null
            : () => _download(f),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: saved ? AppColors.primaryFaint : AppColors.fill,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  saved
                      ? Icons.graphic_eq
                      : f.isCall
                          ? Icons.call_outlined
                          : Icons.mic_none,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(f.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: AppColors.ink),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 3),
                    Text(
                      _subtitle(l10n, f, ui),
                      style: TextStyle(
                          fontSize: 12.5,
                          color: failed ? AppColors.danger : AppColors.muted),
                    ),
                    if ((downloading || paused) && progress != null) ...[
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 5,
                          backgroundColor: AppColors.fill,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 4),
              if (convertingThis)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (saved)
                _playButton(l10n, f, playingThis)
              else if (downloading && !paused)
                IconButton(
                  tooltip: l10n.pause,
                  onPressed: () => _pause(f),
                  icon: const Icon(Icons.pause_circle,
                      size: 26, color: AppColors.primary),
                )
              else if (paused)
                IconButton(
                  tooltip: l10n.resume,
                  onPressed: () => _download(f),
                  icon: const Icon(Icons.play_circle,
                      size: 26, color: AppColors.primary),
                )
              else
                IconButton(
                  tooltip: l10n.tooltipDownload,
                  onPressed: () => _download(f),
                  icon: const Icon(Icons.download_outlined,
                      size: 20, color: AppColors.primary),
                ),
              IconButton(
                tooltip: l10n.tooltipDelete,
                onPressed: downloading && !paused
                    ? null
                    : () => _confirmDelete(f),
                icon: const Icon(Icons.delete_outline,
                    size: 20, color: AppColors.mutedFaint),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _playButton(AppLocalizations l10n, PenFile f, bool playingThis) {
    return StreamBuilder<bool>(
      stream: _player.playingStream,
      builder: (_, snap) {
        final playing = playingThis && (snap.data ?? false);
        return IconButton(
          tooltip: l10n.tooltipPlay,
          onPressed: () => _play(f),
          icon: playing
              ? const Icon(Icons.pause_circle,
                  size: 26, color: AppColors.primary)
              : const Icon(Icons.play_circle,
                  size: 26, color: AppColors.primary),
        );
      },
    );
  }

  String _subtitle(AppLocalizations l10n, PenFile f, _FileUi? ui) {
    if (ui == null && _saved.contains(f.name)) {
      return l10n.downloadDone(fmtBytes(f.sizeBytes));
    }
    final base =
        '${l10n.tapToDownload} · ${fmtDuration(f.durationSec)} · ${fmtBytes(f.sizeBytes)}';
    if (ui == null) return base;
    if (ui.paused) {
      return l10n.downloadPaused(fmtBytes(ui.received));
    }
    if (ui.downloading) {
      final pct = f.sizeBytes > 0 ? (ui.received * 100 ~/ f.sizeBytes) : 0;
      return '${l10n.downloadingPercent(pct)} · ${fmtBytes(ui.received)}';
    }
    if (ui.error != null) return l10n.downloadFailed;
    final r = ui.result;
    if (r == null) return base;
    if (r.endCode == FileEndCode.completed) {
      return l10n.downloadDone(fmtBytes(r.receivedBytes));
    }
    return l10n.downloadStopped(r.endCode.name);
  }

  // ---------------- 迷你播放条 ----------------

  Widget _miniPlayer() {
    return Card(
      margin: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 4, 2),
        child: Column(
          children: [
            Row(
              children: [
                StreamBuilder<bool>(
                  stream: _player.playingStream,
                  builder: (_, snap) {
                    final playing = snap.data ?? false;
                    return IconButton(
                      onPressed: () async {
                        if (playing) {
                          await _player.pause();
                        } else {
                          await _player.play();
                        }
                      },
                      icon: Icon(
                        playing ? Icons.pause_circle : Icons.play_circle,
                        size: 34,
                        color: AppColors.primary,
                      ),
                    );
                  },
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _playerFor!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.ink),
                      ),
                      StreamBuilder<Duration>(
                        stream: _player.positionStream,
                        builder: (_, posSnap) => StreamBuilder<Duration?>(
                          stream: _player.durationStream,
                          builder: (_, durSnap) {
                            final total = durSnap.data?.inSeconds ?? 0;
                            return Text(
                              '${fmtDuration(posSnap.data?.inSeconds ?? 0)} / ${fmtDuration(total)}',
                              style: const TextStyle(
                                  fontSize: 11, color: AppColors.muted),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _stopPlayer,
                  icon:
                      const Icon(Icons.close, size: 20, color: AppColors.muted),
                ),
              ],
            ),
            StreamBuilder<Duration>(
              stream: _player.positionStream,
              builder: (_, posSnap) => StreamBuilder<Duration?>(
                stream: _player.durationStream,
                builder: (_, durSnap) {
                  final totalMs = durSnap.data?.inMilliseconds ?? 0;
                  final posMs =
                      (posSnap.data?.inMilliseconds ?? 0).clamp(0, totalMs);
                  return SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 12),
                    ),
                    child: Slider(
                      value: totalMs > 0 ? posMs / totalMs : 0,
                      onChanged: totalMs > 0
                          ? (v) => _player.seek(
                              Duration(milliseconds: (v * totalMs).round()))
                          : null,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
