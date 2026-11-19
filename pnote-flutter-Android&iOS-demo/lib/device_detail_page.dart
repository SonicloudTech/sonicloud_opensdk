import 'package:flutter/material.dart';

import 'design/status_badge.dart';
import 'design/tokens.dart';
import 'l10n/gen/app_localizations.dart';
import 'session.dart';

/// 设备详情页：设备信息、刷新、断连入口都收在这里，首页不再展示设备详情。
class DeviceDetailPage extends StatefulWidget {
  const DeviceDetailPage({super.key, required this.session});

  final Session session;

  @override
  State<DeviceDetailPage> createState() => _DeviceDetailPageState();
}

class _DeviceDetailPageState extends State<DeviceDetailPage> {
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

  /// 手动或意外断连后详情页失去意义，自动返回首页（首页会回到扫描视图）。
  void _onSessionChanged() {
    if (!session.connected && mounted) {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final d = session.device;
        if (d == null) return const SizedBox.shrink();

        final battery = session.battery;
        final capacity = session.capacity;
        final usedRatio = capacity == null || capacity.totalKb == 0
            ? null
            : capacity.usedKb / capacity.totalKb;

        return Scaffold(
          appBar: AppBar(
            title: Text(l10n.deviceInfoTitle),
            actions: [
              IconButton(
                tooltip: l10n.tooltipRefresh,
                onPressed: session.refreshInfo,
                icon: const Icon(Icons.refresh,
                    size: 20, color: AppColors.primary),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppColors.fill,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.mic,
                            color: AppColors.primary, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              d.name.isEmpty ? l10n.voiceRecorder : d.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 17,
                                  color: AppColors.ink),
                            ),
                            const SizedBox(height: 3),
                            Text(d.id,
                                style: const TextStyle(
                                    fontSize: 12, color: AppColors.muted)),
                          ],
                        ),
                      ),
                      StatusBadge(
                          label: l10n.connected, color: AppColors.success),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _meterRow(
                        icon: battery?.charging == true
                            ? Icons.battery_charging_full
                            : Icons.battery_std,
                        label: l10n.battery,
                        value: battery == null ? '—' : '${battery.percent}%',
                        ratio: battery == null ? null : battery.percent / 100,
                        color: _batteryColor(battery?.percent),
                      ),
                      const SizedBox(height: 12),
                      _meterRow(
                        icon: Icons.sd_storage_outlined,
                        label: l10n.storage,
                        value: capacity == null
                            ? '—'
                            : '${fmtKb(capacity.usedKb)} / ${fmtKb(capacity.totalKb)}',
                        ratio: usedRatio,
                        color: AppColors.primary,
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                              child:
                                  _kvTile(l10n.firmware, session.version ?? '—')),
                          const SizedBox(width: 12),
                          Expanded(child: _kvTile(l10n.syncedTitle, l10n.syncedValue)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // 断连是破坏性操作：红色系、与信息区拉开距离。
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.danger,
                  side: const BorderSide(color: AppColors.danger),
                ),
                onPressed: session.disconnect,
                icon: const Icon(Icons.bluetooth_disabled, size: 18),
                label: Text(l10n.disconnect),
              ),
            ],
          ),
        );
      },
    );
  }

  Color _batteryColor(int? percent) {
    if (percent == null) return AppColors.muted;
    if (percent <= 20) return AppColors.danger;
    if (percent <= 50) return AppColors.warning;
    return AppColors.success;
  }

  Widget _meterRow({
    required IconData icon,
    required String label,
    required String value,
    required double? ratio,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: AppColors.muted),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(fontSize: 13, color: AppColors.muted)),
            const Spacer(),
            Text(value,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 6,
            backgroundColor: AppColors.fill,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _kvTile(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
          const SizedBox(height: 2),
          Text(value,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}
