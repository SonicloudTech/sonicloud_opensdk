import 'package:flutter/material.dart';

import 'audio_detail_page.dart';
import 'design/tokens.dart';
import 'l10n/gen/app_localizations.dart';
import 'session.dart';

/// 近期录音条目：首页折叠区与全量页共用。
/// 图标 + 名称 + `时长 · 日期`，trailing 由调用方定制（首页箭头 / 全量页删除）。
class RecentRecordingTile extends StatelessWidget {
  const RecentRecordingTile({
    super.key,
    required this.session,
    required this.rec,
    this.trailing,
  });

  final Session session;
  final LocalRecording rec;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final d = rec.savedAt;
    String two(int n) => n.toString().padLeft(2, '0');
    final meta =
        '${fmtDuration(rec.durationSec)} · ${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => AudioDetailPage(session: session, recording: rec),
          )),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.fill,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.graphic_eq,
                  color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rec.name.replaceAll('.opus', ''),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: AppColors.ink),
                  ),
                  const SizedBox(height: 2),
                  Text(meta,
                      style:
                          const TextStyle(fontSize: 12, color: AppColors.muted)),
                ],
              ),
            ),
            const SizedBox(width: 4),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

/// 全部近期录音（本地）：点击进音频详情，行尾可删除（确认弹窗，删本地文件）。
class RecentRecordingsPage extends StatelessWidget {
  const RecentRecordingsPage({super.key, required this.session});

  final Session session;

  Future<void> _confirmDelete(BuildContext context, LocalRecording rec) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final l = AppLocalizations.of(ctx)!;
        return AlertDialog(
          title: Text(l.deleteRecordingTitle),
          content: Text(l.deleteLocalBody(rec.name.replaceAll('.opus', ''))),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.cancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.delete),
            ),
          ],
        );
      },
    );
    if (ok != true) return;
    await session.deleteLocalRecording(rec);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.recentTitle)),
      body: ListenableBuilder(
        listenable: session,
        builder: (_, _) {
          final recent = session.recentRecordings;
          if (recent.isEmpty) {
            return Center(
              child: Text(l10n.noRecent,
                  style: const TextStyle(color: AppColors.muted, fontSize: 13)),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              Card(
                child: Column(
                  children: [
                    for (var i = 0; i < recent.length; i++)
                      RecentRecordingTile(
                        session: session,
                        rec: recent[i],
                        trailing: IconButton(
                          tooltip: l10n.tooltipDelete,
                          onPressed: () => _confirmDelete(context, recent[i]),
                          icon: const Icon(Icons.delete_outline,
                              size: 20, color: AppColors.mutedFaint),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
