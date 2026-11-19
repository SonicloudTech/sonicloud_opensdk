import 'package:flutter/material.dart';

import 'asr/pen_asr_service.dart';
import 'design/status_badge.dart';
import 'design/tokens.dart';
import 'l10n/gen/app_localizations.dart';
import 'session.dart';
import 'transcript_flow.dart';

/// 录音全屏页：录音开始（App 按钮或笔身物理键）自动弹出；
/// 录音期间不可退出（PopScope 拦返回），停止（任意路径）后自动返回首页。
class RecordingOverlayPage extends StatefulWidget {
  const RecordingOverlayPage({super.key, required this.session});

  final Session session;

  @override
  State<RecordingOverlayPage> createState() => _RecordingOverlayPageState();
}

class _RecordingOverlayPageState extends State<RecordingOverlayPage> {
  bool _popped = false;

  Session get session => widget.session;

  @override
  void initState() {
    super.initState();
    session.addListener(_onSessionChanged);
  }

  @override
  void dispose() {
    session.removeListener(_onSessionChanged);
    super.dispose();
  }

  /// 录音结束（停止按钮 / 物理键 / 意外断连）自动返回。
  void _onSessionChanged() {
    if (!session.recording && !_popped && mounted) {
      _popped = true;
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListenableBuilder(
      listenable: session,
      builder: (_, _) => PopScope(
        // 录音期间禁止返回；停止后放行兜底（正常路径由监听器自动 pop）。
        canPop: !session.recording,
        child: Scaffold(
          backgroundColor: AppColors.bg,
          body: SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 28),
                _status(l10n),
                const SizedBox(height: 10),
                Text(
                  fmtDuration(session.recordSeconds),
                  style: const TextStyle(
                    fontSize: 54,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                    letterSpacing: -1,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 24),
                Expanded(child: _transcriptCard(context, l10n)),
                const SizedBox(height: 16),
                _controls(l10n),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 状态行：文字 + 颜色双编码（录音中红 / 已暂停琥珀）。
  Widget _status(AppLocalizations l10n) {
    final paused = session.paused;
    final (text, color, icon) = paused
        ? (l10n.pausedStatus, AppColors.warning, Icons.pause_circle)
        : (l10n.recordingStatus, AppColors.danger, Icons.fiber_manual_record);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Text(text,
            style: TextStyle(
                color: color, fontWeight: FontWeight.w700, fontSize: 15)),
      ],
    );
  }

  Widget _transcriptCard(BuildContext context, AppLocalizations l10n) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ValueListenableBuilder<PenAsrSocketState>(
                  valueListenable: session.asr.socketState,
                  builder: (_, state, _) {
                    final (label, color) = asrStateStyle(l10n, state);
                    return StatusBadge(label: label, color: color);
                  },
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(l10n.liveTranscript,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: AppColors.ink)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Expanded(
              child: session.asrEnabled
                  ? TranscriptFlow(session: session)
                  : Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 14, horizontal: 8),
                      child: Text(l10n.transcriptOffHint,
                          style: const TextStyle(
                              color: AppColors.muted, fontSize: 13)),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _controls(AppLocalizations l10n) {
    final paused = session.paused;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: paused ? session.resumeRecord : session.pauseRecord,
              icon: Icon(paused ? Icons.play_arrow : Icons.pause, size: 18),
              label: Text(paused ? l10n.resume : l10n.pause),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              onPressed: session.stopRecord,
              icon: const Icon(Icons.stop, size: 18),
              label: Text(l10n.stopAndSave),
            ),
          ),
        ],
      ),
    );
  }
}
