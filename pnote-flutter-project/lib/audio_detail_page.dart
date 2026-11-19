import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mind_map/mind_map.dart';
import 'package:just_audio/just_audio.dart';
import 'package:markdown_widget/markdown_widget.dart';

import 'ai/summary_service.dart';
import 'audio/recording_store.dart';
import 'design/markdown_theme_config.dart';
import 'design/tokens.dart';
import 'l10n/gen/app_localizations.dart';
import 'session.dart';
import 'transcript_flow.dart';
import 'widgets/mindmap_view.dart';

enum _DetailTab { transcript, summary, mindmap }

/// 本地录音详情页：信息+播放合并卡 + 内容四段（转写/纪要/导图/图片）+
/// 底部 AI 生成按钮（就地启动，不跳转）。进入只装载不自动播，用户点播。
class AudioDetailPage extends StatefulWidget {
  const AudioDetailPage({
    super.key,
    required this.session,
    required this.recording,
  });

  final Session session;
  final LocalRecording recording;

  @override
  State<AudioDetailPage> createState() => _AudioDetailPageState();
}

class _AudioDetailPageState extends State<AudioDetailPage> {
  final _store = RecordingStore.instance;
  final _ai = SummaryService.instance;
  final _player = AudioPlayer();
  StreamSubscription<ProcessingState>? _stateSub;

  // 播放。
  bool _preparing = true;
  String? _error;
  String? _transcript;

  // 内容段。
  _DetailTab _tab = _DetailTab.transcript;

  // AI 产物：纪要主流程 + 导图懒加载（PNG 可视化摘要不走：取地址必经
  // summaryImagePng 计费接口，已按需求裁掉图片 Tab）。
  String? _taskId;
  String? _summary;
  bool _aiRunning = false;
  String? _aiError;
  List<MindmapNode>? _mind;
  String? _mindError;
  bool _mindLoading = false;

  // 脑图实例页面级持有：Tab 切换/刷新不重建，缩放与主题保持。
  final _mindmapRepaintKey = GlobalKey();
  late final MindMap _mindMapInstance;

  @override
  void initState() {
    _mindMapInstance = MindMap(repaintKey: _mindmapRepaintKey);
    super.initState();
    super.initState();
    unawaited(() async {
      try {
        final s = await AudioSession.instance;
        await s.configure(const AudioSessionConfiguration.music());
      } catch (_) {}
    }());
    // 播完回到初始位置，播放键恢复可播。
    // 自然播完时 playing 仍为 true，直接 seek(0) 会被当作继续播放，须先 pause。
    _stateSub = _player.processingStateStream.listen((s) {
      if (s == ProcessingState.completed) {
        unawaited(() async {
          await _player.pause();
          await _player.seek(Duration.zero);
        }());
      }
    });
    unawaited(_prepare());
    if (!widget.recording.fromDevice) {
      unawaited(_loadTranscript());
      unawaited(_loadAiCache());
    }
  }

  @override
  void dispose() {
    unawaited(_stateSub?.cancel() ?? Future<void>.value());
    unawaited(_player.dispose());
    super.dispose();
  }

  /// 只做转换与装载，不自动播放——播放由用户点击触发。
  Future<void> _prepare() async {
    try {
      // 设备下载文件在 recordings 根目录，App 自录在 app 子目录，转换路径不同。
      final wav = widget.recording.fromDevice
          ? await _store.toWav(widget.recording.name)
          : await _store.appToWav(widget.recording.name);
      await _player.setFilePath(wav.path);
    } catch (e) {
      _error = '$e';
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
  }

  Future<void> _loadTranscript() async {
    try {
      final f = await _store.appTranscriptFile(widget.recording.name);
      if (await f.exists()) {
        final text = await f.readAsString();
        if (mounted) setState(() => _transcript = text);
      }
    } catch (_) {}
  }

  /// 进页即读 AI 产物缓存：生成过的纪要直接显示（按钮态随之「已生成」）。
  Future<void> _loadAiCache() async {
    try {
      final name = widget.recording.name;
      final taskIdFile = await _store.appTaskIdFile(name);
      if (await taskIdFile.exists()) {
        final id = (await taskIdFile.readAsString()).trim();
        if (id.isNotEmpty) _taskId = id;
      }
      final summaryFile = await _store.appSummaryFile(name);
      if (await summaryFile.exists()) {
        final text = await summaryFile.readAsString();
        if (text.trim().isNotEmpty) _summary = text;
      }
      if (_summary != null && _taskId != null) {
        // 缓存命中纪要（已生成过）：导图预取是免费的（同任务只计一次费），直接拉。
        unawaited(_loadMind());
      } else if (_taskId != null && mounted) {
        // 有 task_id 但纪要未落盘：上次生成中断在轮询中，自动续轮询；
        // 按钮随即进入「生成中…」禁用态，无需再手动点（不会重复提交/扣费）。
        unawaited(_runAi());
        return;
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  // ---------------- AI 纪要主流程 ----------------

  void _startAi() {
    final t = _transcript ?? '';
    if (t.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(AppLocalizations.of(context)!.aiNoTranscript)),
      );
      return;
    }
    setState(() => _tab = _DetailTab.summary);
    unawaited(_runAi());
  }

  Future<void> _runAi() async {
    // 输出语种跟随当前界面语言：中文（含繁中系统）→ zh，其余 → en。
    final language =
        Localizations.localeOf(context).languageCode.startsWith('zh')
            ? 'zh'
            : 'en';
    setState(() {
      _aiRunning = true;
      _aiError = null;
    });
    final name = widget.recording.name;
    try {
      // 已提交过（task_id 缓存）则续轮询，否则提交。
      final taskIdFile = await _store.appTaskIdFile(name);
      String taskId;
      if (await taskIdFile.exists() &&
          (await taskIdFile.readAsString()).trim().isNotEmpty) {
        taskId = (await taskIdFile.readAsString()).trim();
      } else {
        final t = await _ai.createAnalysis(_transcript!,
            userId: widget.session.userId, language: language);
        widget.session.log(widget.session.L.logAiSubmitted(t), LogKind.event);
        await taskIdFile.writeAsString(t);
        taskId = t;
      }
      _taskId = taskId;

      final userId = widget.session.userId;
      await _ai.pollUntilDone(taskId, userId: userId);
      final summary = await _ai.fetchSummary(taskId, userId: userId);
      await (await _store.appSummaryFile(name)).writeAsString(summary);
      widget.session.log(
          widget.session.L.logAiDone(name.replaceAll('.opus', '')),
          LogKind.event);
      if (mounted) {
        setState(() {
          _summary = summary;
          _aiRunning = false;
        });
        // 全自动：纪要完成即后台预取导图（切到导图 Tab 秒开）。
        unawaited(_loadMind());
      }
    } catch (e) {
      widget.session.log(widget.session.L.logAiFailed('$e'), LogKind.error);
      if (mounted) {
        setState(() {
          _aiError = '$e';
          _aiRunning = false;
        });
      }
    }
  }

  void _switchTab(_DetailTab tab) {
    setState(() => _tab = tab);
    // 纪要就绪后导图按需懒加载（首次拉取计一次费）。
    final ready = _summary != null && !_aiRunning;
    if (tab == _DetailTab.mindmap && ready && _mind == null && !_mindLoading) {
      unawaited(_loadMind());
    }
  }

  Future<void> _loadMind() async {
    final taskId = _taskId;
    if (taskId == null) return;
    setState(() {
      _mindLoading = true;
      _mindError = null;
    });
    try {
      final raw = await _ai.fetchMindmap(taskId, userId: widget.session.userId);
      final nodes =
          raw.whereType<Map<String, dynamic>>().map(MindmapNode.fromJson).toList();
      widget.session.log(widget.session.L.logAiMindmapReady, LogKind.event);
      if (mounted) {
        setState(() {
          _mind = nodes;
          _mindLoading = false;
        });
      }
    } catch (e) {
      widget.session.log(widget.session.L.logAiFailed('$e'), LogKind.error);
      if (mounted) {
        setState(() {
          _mindError = '$e';
          _mindLoading = false;
        });
      }
    }
  }

  // ---------------- 布局 ----------------

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.audioDetailTitle)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: _headerCard(l10n),
          ),
          // 与内容卡同宽（横向 20 边距），三段 Expanded 均分总宽。
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            child: _tabBar(l10n),
          ),
          Expanded(child: _tabView(l10n)),
          // 有结果后底部不再占位：仅未生成/生成中显示按钮。
          if (_summary == null) _aiButton(l10n),
        ],
      ),
    );
  }

  /// AI 按钮：未生成=可点启动 / 生成中=禁用「生成中…」；有结果后整块隐藏。
  Widget _aiButton(AppLocalizations l10n) {
    final running = _aiRunning;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: Center(
          child: FilledButton.icon(
            onPressed: running ? null : _startAi,
            icon: running
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.auto_awesome, size: 18),
            label:
                Text(running ? l10n.aiGenerating : l10n.aiGenerateButton),
          ),
        ),
      ),
    );
  }

  /// 等分三段的内容切换条：白底圆角外框 + 细分隔线，
  /// 选中段仅背景变化（淡蓝底深蓝字），宽度严格均分。
  Widget _tabBar(AppLocalizations l10n) {
    final labels = {
      _DetailTab.transcript: l10n.aiTabTranscript,
      _DetailTab.summary: l10n.aiTabSummary,
      _DetailTab.mindmap: l10n.aiTabMindmap,
    };
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          for (var i = 0; i < _DetailTab.values.length; i++)
            Expanded(
              child: InkWell(
                onTap: () => _switchTab(_DetailTab.values[i]),
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _tab == _DetailTab.values[i]
                        ? AppColors.primaryFaint
                        : Colors.transparent,
                    border: i == 0
                        ? null
                        : const Border(
                            left: BorderSide(color: AppColors.border)),
                  ),
                  child: Text(
                    labels[_DetailTab.values[i]]!,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: _tab == _DetailTab.values[i]
                          ? AppColors.primaryDark
                          : AppColors.muted,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _tabView(AppLocalizations l10n) {
    return switch (_tab) {
      _DetailTab.transcript => _transcriptTab(l10n),
      _DetailTab.summary => _summaryTab(l10n),
      _DetailTab.mindmap => _mindmapTab(l10n),
    };
  }

  Widget _transcriptTab(AppLocalizations l10n) {
    final t = _transcript ?? '';
    if (t.trim().isEmpty) return _hintView(l10n.aiNoTranscript);
    final lines = t.split('\n');
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 说话人与正文分上下两行（与全屏录音页同款拆分）。
                for (var i = 0; i < lines.length; i++) ...[
                  if (i > 0) const SizedBox(height: 8),
                  ..._transcriptLine(lines[i]),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _transcriptLine(String raw) {
    final (speaker, body) = splitSpeaker(raw);
    if (speaker == null) {
      return [
        Text(body,
            style: const TextStyle(
                fontSize: 14, height: 1.5, color: AppColors.inkSoft)),
      ];
    }
    return [
      Text(speaker,
          style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: AppColors.muted)),
      const SizedBox(height: 2),
      Text(body,
          style: const TextStyle(
              fontSize: 14, height: 1.5, color: AppColors.inkSoft)),
    ];
  }

  Widget _summaryTab(AppLocalizations l10n) {
    if (_aiRunning) return _busyView(l10n.aiAnalyzing);
    if (_aiError != null) {
      return _errorView(l10n.aiFailed(_aiError!), () => unawaited(_runAi()));
    }
    if (_summary == null) return _hintView(l10n.aiNotStartedHint);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            // MarkdownBlock 无内部滚动，专用于嵌在外层 ListView 里
            //（MarkdownWidget 自带滚动视图，嵌套会 unbounded height 崩溃）。
            child: MarkdownBlock(
              data: _summary!,
              config: MarkdownThemeConfigOwn.ownStyle,
            ),
          ),
        ),
      ],
    );
  }

  Widget _mindmapTab(AppLocalizations l10n) {
    if (_aiRunning) return _busyView(l10n.aiAnalyzing);
    if (_summary == null) return _hintView(l10n.aiNeedFirst);
    if (_mindLoading) return _busyView(l10n.aiGenerating);
    if (_mindError != null) {
      return _errorView(
          l10n.aiMindmapFailed(_mindError!), () => unawaited(_loadMind()));
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: MindMapNewView(
          repaintKey: _mindmapRepaintKey,
          mindmap: _mind ?? const [],
          mindMapInstance: _mindMapInstance,
        ),
      ),
    );
  }

  /// 信息 + 播放合并卡：名称完整换行不截断，元信息用行式布局避免被切。
  Widget _headerCard(AppLocalizations l10n) {
    final rec = widget.recording;
    final d = rec.savedAt;
    String two(int n) => n.toString().padLeft(2, '0');
    final savedAt = '${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              rec.name.replaceAll('.opus', ''),
              style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  height: 1.35,
                  color: AppColors.ink),
            ),
            const SizedBox(height: 8),
            // 元信息一行图标式：时长/大小/保存时间，紧贴名称下方。
            Wrap(
              spacing: 18,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _metaItem(Icons.timer_outlined, fmtDuration(rec.durationSec)),
                _metaItem(Icons.sd_storage_outlined, fmtBytes(rec.bytes)),
                _metaItem(Icons.event_outlined, savedAt),
              ],
            ),
            const SizedBox(height: 8),
            _playerSection(l10n),
          ],
        ),
      ),
    );
  }

  Widget _metaItem(IconData icon, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: AppColors.muted),
        const SizedBox(width: 4),
        Text(value,
            style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.ink)),
      ],
    );
  }

  Widget _playerSection(AppLocalizations l10n) {
    if (_preparing) {
      return Row(
        children: [
          const SizedBox(
              width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 12),
          Text(l10n.audioPreparing,
              style: const TextStyle(color: AppColors.muted, fontSize: 13)),
        ],
      );
    }
    if (_error != null) {
      return Text(l10n.loadFailed(_error!),
          style: const TextStyle(color: AppColors.danger, fontSize: 13));
    }
    return Column(
      children: [
        // 当前时间居左 · 播放键居中 · 总时长居右。
        StreamBuilder<Duration>(
          stream: _player.positionStream,
          builder: (_, posSnap) => StreamBuilder<Duration?>(
            stream: _player.durationStream,
            builder: (_, durSnap) {
              final total = durSnap.data?.inSeconds ?? 0;
              const timeStyle = TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                  fontFeatures: [FontFeature.tabularFigures()]);
              return Row(
                children: [
                  Text(fmtDuration(posSnap.data?.inSeconds ?? 0),
                      style: timeStyle),
                  const Spacer(),
                  StreamBuilder<bool>(
                    stream: _player.playingStream,
                    builder: (_, snap) {
                      final playing = snap.data ?? false;
                      return IconButton(
                        tooltip: l10n.tooltipPlay,
                        onPressed: () async {
                          if (playing) {
                            await _player.pause();
                          } else {
                            await _player.play();
                          }
                        },
                        icon: Icon(
                          playing ? Icons.pause_circle : Icons.play_circle,
                          size: 38,
                          color: AppColors.primary,
                        ),
                      );
                    },
                  ),
                  const Spacer(),
                  Text(fmtDuration(total), style: timeStyle),
                ],
              );
            },
          ),
        ),
        StreamBuilder<Duration>(
          stream: _player.positionStream,
          builder: (_, posSnap) => StreamBuilder<Duration?>(
            stream: _player.durationStream,
            builder: (_, durSnap) {
              final totalMs = durSnap.data?.inMilliseconds ?? 0;
              final posMs = (posSnap.data?.inMilliseconds ?? 0).clamp(0, totalMs);
              return SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
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
    );
  }

  // ---------------- 通用状态视图 ----------------

  Widget _busyView(String text) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
              width: 30,
              height: 30,
              child: CircularProgressIndicator(strokeWidth: 2.5)),
          const SizedBox(height: 16),
          Text(text, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _hintView(String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.muted, fontSize: 13),
        ),
      ),
    );
  }

  Widget _errorView(String msg, VoidCallback onRetry) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 44, color: AppColors.borderStrong),
            const SizedBox(height: 12),
            Text(
              msg,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted, fontSize: 13.5),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(l10n.retry),
            ),
          ],
        ),
      ),
    );
  }
}
