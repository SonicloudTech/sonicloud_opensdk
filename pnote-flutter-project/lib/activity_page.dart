import 'package:flutter/material.dart';

import 'l10n/gen/app_localizations.dart';
import 'session.dart';

class ActivityPage extends StatelessWidget {
  const ActivityPage({super.key, required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListenableBuilder(
      listenable: session,
      builder: (_, _) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.terminal,
                        size: 15, color: Color(0xFF475569)),
                    const SizedBox(width: 6),
                    Text(
                      '${l10n.tabActivity} · ${session.logs.length}',
                      style: const TextStyle(
                          color: Color(0xFF64748B), fontSize: 12),
                    ),
                    const Spacer(),
                    InkWell(
                      onTap: session.logs.isEmpty ? null : session.clearLogs,
                      child: Icon(Icons.delete_sweep,
                          size: 17,
                          color: session.logs.isEmpty
                              ? const Color(0xFF1E293B)
                              : const Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFF1E293B)),
              Expanded(
                child: session.logs.isEmpty
                    ? Center(
                        child: Text(
                          l10n.activityEmpty,
                          style: const TextStyle(
                              color: Color(0xFF334155), fontSize: 12),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        itemCount: session.logs.length,
                        itemExtent: 22,
                        itemBuilder: (_, i) => _line(session.logs[i]),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _line(LogEntry e) {
    final color = switch (e.kind) {
      LogKind.event => const Color(0xFF7DD3FC),
      LogKind.error => const Color(0xFFFCA5A5),
      LogKind.info => const Color(0xFFCBD5E1),
    };
    final t = e.time;
    final ts = '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Text.rich(
        TextSpan(
          style: const TextStyle(
              fontFamily: 'monospace', fontSize: 11, height: 1.9),
          children: [
            TextSpan(
                text: '$ts  ',
                style: const TextStyle(color: Color(0xFF334155))),
            TextSpan(text: e.text, style: TextStyle(color: color)),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

String _two(int n) => n.toString().padLeft(2, '0');
