import 'package:flutter/material.dart';

import 'asr/pen_asr_service.dart';
import 'design/tokens.dart';
import 'l10n/gen/app_localizations.dart';
import 'session.dart';

/// ASR socket 状态 → 徽标文案/颜色（首页转写卡与录音全屏页共用）。
(String, Color) asrStateStyle(AppLocalizations l10n, PenAsrSocketState state) =>
    switch (state) {
      PenAsrSocketState.connected => (l10n.connected, AppColors.success),
      PenAsrSocketState.connecting => (l10n.asrConnecting, AppColors.warning),
      PenAsrSocketState.disconnected =>
        (l10n.asrDisconnected, AppColors.danger),
    };

/// 拆「说话人N：正文」为 (说话人含冒号, 正文)；无前缀返回 (null, 原文)。
/// 存储层（落盘 txt / AI 输入）保持单行前缀，仅显示层拆两行。
(String?, String) splitSpeaker(String line) {
  final m = RegExp(r'^\s*((?:说话人[^\s:：]+|Speaker\s*[^:：]+)[:：])\s*')
      .firstMatch(line);
  if (m == null) return (null, line);
  return (m.group(1)!, line.substring(m.end));
}

/// 实时转写文本流：定稿正文 + 临时高亮（斜体主色），新字幕自动滚到底。
/// 首页转写卡（限高收缩）与录音全屏页（撑满剩余空间）共用。
class TranscriptFlow extends StatefulWidget {
  const TranscriptFlow({super.key, required this.session, this.shrinkWrap = false});

  final Session session;

  /// 在无限高容器内按内容收缩（首页卡用）；全屏页传 false 撑满。
  final bool shrinkWrap;

  @override
  State<TranscriptFlow> createState() => _TranscriptFlowState();
}

class _TranscriptFlowState extends State<TranscriptFlow> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final session = widget.session;
    final hasTemp = session.tempTranscript != null;
    final itemCount = session.transcript.length + (hasTemp ? 1 : 0);

    // 新字幕到达后滚到底部。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });

    if (itemCount == 0) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: Text(l10n.asrEmptyHint,
            style: const TextStyle(color: AppColors.muted, fontSize: 13)),
      );
    }

    return ListView.builder(
      controller: _scroll,
      shrinkWrap: widget.shrinkWrap,
      padding: const EdgeInsets.only(right: 10),
      itemCount: itemCount,
      itemBuilder: (_, i) {
        final isTemp = i >= session.transcript.length;
        final text = isTemp ? session.tempTranscript! : session.transcript[i];
        // 说话人与正文分上下两行（说话人小字置顶）。
        final (speaker, body) = splitSpeaker(text);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: speaker == null
              ? Text(
                  body,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    color: isTemp ? AppColors.primary : AppColors.ink,
                    fontStyle:
                        isTemp ? FontStyle.italic : FontStyle.normal,
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      speaker,
                      style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.muted),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      body,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.45,
                        color: isTemp ? AppColors.primary : AppColors.ink,
                        fontStyle:
                            isTemp ? FontStyle.italic : FontStyle.normal,
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}
