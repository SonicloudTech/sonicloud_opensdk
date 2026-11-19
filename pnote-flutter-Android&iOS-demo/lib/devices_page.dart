import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'ble_permissions.dart';
import 'design/tokens.dart';
import 'l10n/gen/app_localizations.dart';
import 'recent_recordings_page.dart';
import 'session.dart';

class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key, required this.session});

  final Session session;

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  bool _permDenied = false;
  bool _btOff = false;

  Session get session => widget.session;

  Future<void> _scan() async {
    setState(() {
      _permDenied = false;
      _btOff = false;
    });

    // 权限在前：Android 12+ 未授权时 adapterStateNow 恒为 unknown，
    // 先查蓝牙会永远误报「蓝牙未开启」。
    final granted = await BlePermissions.ensureGranted();
    if (!granted) {
      setState(() => _permDenied = true);
      session.log(session.L.permDenied, LogKind.error);
      return;
    }

    // 适配器状态可能短暂为 unknown/turningOn，等一个确定态（2s 兜底）。
    var state = FlutterBluePlus.adapterStateNow;
    if (state != BluetoothAdapterState.on &&
        state != BluetoothAdapterState.off) {
      try {
        state = await FlutterBluePlus.adapterState
            .where((s) =>
                s == BluetoothAdapterState.on ||
                s == BluetoothAdapterState.off)
            .first
            .timeout(const Duration(seconds: 2));
      } catch (_) {}
    }
    if (state != BluetoothAdapterState.on) {
      setState(() => _btOff = true);
      return;
    }

    try {
      await session.startScan();
    } catch (e) {
      session.log(session.L.scanFailed('$e'), LogKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (_, _) => session.connected
          ? _Dashboard(session: session)
          : _ScanView(
              session: session,
              onScan: _scan,
              permDenied: _permDenied,
              btOff: _btOff,
              onRetry: _scan,
              onOpenSettings: BlePermissions.openAppSettings,
              // 近期录音是本地数据，未连接也展示；作为列表尾部一起滚动，
              // 不占固定底栏（否则条目多时会挤压扫描按钮和设备列表）。
              // ListView 自带横向 20 内边距，这里只补上边距即可与附近设备列表对齐。
              recent: session.recentRecordings.isNotEmpty
                  ? _RecentRecordings(
                      session: session,
                      padding: const EdgeInsets.only(top: 24),
                    )
                  : null,
            ),
    );
  }
}

// ---------------- 扫描（未连接） ----------------

class _ScanView extends StatelessWidget {
  const _ScanView({
    required this.session,
    required this.onScan,
    required this.permDenied,
    required this.btOff,
    required this.onRetry,
    required this.onOpenSettings,
    this.recent,
  });

  final Session session;
  final Future<void> Function() onScan;
  final bool permDenied;
  final bool btOff;
  final VoidCallback onRetry;
  final Future<void> Function() onOpenSettings;

  /// 列表尾部附加内容（近期录音区）。
  final Widget? recent;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        const SizedBox(height: 24),
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              color: AppColors.fill,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.mic, color: AppColors.primary, size: 34),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          l10n.findTitle,
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontSize: 23, fontWeight: FontWeight.w700, color: AppColors.ink,
              letterSpacing: -0.4),
        ),
        const SizedBox(height: 6),
        Text(
          l10n.findSubtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.muted, fontSize: 14),
        ),
        const SizedBox(height: 24),
        if (btOff) ...[
          _noticeCard(
            icon: Icons.bluetooth_disabled,
            color: AppColors.warning,
            title: l10n.bluetoothOffTitle,
            hint: l10n.bluetoothOffHint,
            actions: [
              OutlinedButton(
                onPressed: onRetry,
                child: Text(l10n.retry),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        if (permDenied) ...[
          _noticeCard(
            icon: Icons.location_off_outlined,
            color: AppColors.danger,
            title: l10n.permissionTitle,
            hint: l10n.permissionHint,
            actions: [
              FilledButton(
                onPressed: () => onOpenSettings(),
                child: Text(l10n.openSettings),
              ),
              OutlinedButton(
                onPressed: onRetry,
                child: Text(l10n.retry),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        FilledButton.icon(
          onPressed: session.scanning ? session.stopScan : onScan,
          icon: session.scanning
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.radar),
          label:
              Text(session.scanning ? l10n.stopScan : l10n.scan),
        ),
        if (session.scanning) ...[
          const SizedBox(height: 10),
          Center(
            child: Text(
              l10n.scanningHint,
              style: const TextStyle(color: AppColors.muted, fontSize: 13),
            ),
          ),
        ],
        if (session.lastDeviceName != null) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: session.scanning ? null : session.reconnect,
            icon: const Icon(Icons.history, size: 20),
            label: Text(l10n.reconnect(session.lastDeviceName!)),
          ),
        ],
        if (session.results.isNotEmpty) ...[
          const SizedBox(height: 28),
          Text(
            l10n.nearbyDevices,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.muted,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                for (var i = 0; i < session.results.length; i++)
                  _scanTile(context, session.results[i],
                      i == session.results.length - 1),
              ],
            ),
          ),
        ],
        ?recent,
      ],
    );
  }

  /// 扫描前置条件不满足时的提示卡（蓝牙关 / 权限拒）。
  Widget _noticeCard({
    required IconData icon,
    required Color color,
    required String title,
    required String hint,
    required List<Widget> actions,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 8),
                Text(title,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink)),
              ],
            ),
            const SizedBox(height: 6),
            Text(hint,
                style: const TextStyle(
                    color: AppColors.muted, fontSize: 13, height: 1.5)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: actions),
          ],
        ),
      ),
    );
  }

  Widget _scanTile(BuildContext context, ScanResult r, bool last) {
    final l10n = AppLocalizations.of(context)!;
    final name = r.device.platformName.isEmpty
        ? l10n.unnamedDevice
        : r.device.platformName;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => session.connect(r),
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
              child: const Icon(Icons.mic_none, color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, color: AppColors.ink)),
                  const SizedBox(height: 2),
                  Text(r.device.remoteId.str,
                      style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.fill,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('${r.rssi} dBm',
                  style: const TextStyle(fontSize: 11, color: AppColors.muted)),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: AppColors.borderStrong),
          ],
        ),
      ),
    );
  }
}

// ---------------- 已连接仪表盘 ----------------

class _Dashboard extends StatelessWidget {
  const _Dashboard({required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        _recordCard(context),
        if (session.recentRecordings.isNotEmpty) ...[
          const SizedBox(height: 16),
          _RecentRecordings(session: session, padding: EdgeInsets.zero),
        ],
      ],
    );
  }

  Widget _recordCard(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final recording = session.recording;
    final paused = session.paused;

    // 双编码：文字 + 颜色同时表达状态，不只靠颜色区分。
    final (statusText, statusColor, statusIcon) = !recording
        ? (l10n.ready, AppColors.muted, Icons.radio_button_checked)
        : paused
            ? (l10n.pausedStatus, AppColors.warning, Icons.pause_circle)
            : (l10n.recordingStatus, AppColors.danger,
                Icons.fiber_manual_record);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(statusIcon, color: statusColor, size: 18),
                const SizedBox(width: 8),
                Text(statusText,
                    style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 14)),
                const Spacer(),
                Text(
                  recording ? _clock(session.recordSeconds) : '00:00',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                    letterSpacing: -0.3,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // 单主 CTA：空闲=开始录音 / 录制中=停止并保存（欧美惯例：每屏一个主操作）。
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: recording ? session.stopRecord : session.startRecord,
                icon: recording
                    ? const Icon(Icons.stop, size: 18)
                    : const Icon(Icons.fiber_manual_record, size: 18),
                label: Text(recording ? l10n.stopAndSave : l10n.recordButton),
              ),
            ),
            if (recording) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed:
                      paused ? session.resumeRecord : session.pauseRecord,
                  icon: Icon(paused ? Icons.play_arrow : Icons.pause, size: 18),
                  label: Text(paused ? l10n.resume : l10n.pause),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _clock(int sec) {
  final m = sec ~/ 60;
  final s = sec % 60;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

// ---------------- 近期录音（本地保存，点击进音频详情页播放） ----------------

class _RecentRecordings extends StatelessWidget {
  const _RecentRecordings({required this.session, this.padding});

  final Session session;

  /// 外边距：首页仪表盘内紧贴录音卡（zero），扫描页下方用默认值。
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final recent = session.recentRecordings.take(5).toList();
    final hasMore = session.recentRecordings.length > 5;
    return Padding(
      padding: padding ?? const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(l10n.recentTitle,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.muted)),
              const Spacer(),
              if (hasMore)
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 32),
                    textStyle: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => RecentRecordingsPage(session: session),
                      )),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(l10n.moreButton),
                      const Icon(Icons.chevron_right, size: 16),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                for (var i = 0; i < recent.length; i++)
                  RecentRecordingTile(
                    session: session,
                    rec: recent[i],
                    trailing:
                        const Icon(Icons.chevron_right, color: AppColors.borderStrong),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
