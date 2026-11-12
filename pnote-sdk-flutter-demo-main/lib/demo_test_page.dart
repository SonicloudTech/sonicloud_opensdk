import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'file_transfer_test/file_transfer_test_module.dart';
import 'file_transfer_test/file_transfer_test_runner.dart';
import 'ota_automation/ota_automation_module.dart';
import 'ota_automation/ota_automation_runner.dart';
import 'provider_record_pen.dart';
import 'service_file_share.dart';
import 'test_report.dart';

class DemoTestPage extends StatefulWidget {
  const DemoTestPage({
    super.key,
    required this.provider,
    this.runner,
    this.transferRunner,
    this.reportStore,
  });

  final RecordPenProvider provider;
  final OtaAutomationRunner? runner;
  final FileTransferTestRunner? transferRunner;
  final TestReportStore? reportStore;

  @override
  State<DemoTestPage> createState() => _DemoTestPageState();
}

class _DemoTestPageState extends State<DemoTestPage> {
  late final OtaAutomationRunner _ota;
  late final FileTransferTestRunner _transfer;
  late final TestReportStore _reports;
  bool _sharing = false;
  bool _clearing = false;

  @override
  void initState() {
    super.initState();
    _reports = widget.reportStore ?? TestReportStore();
    _ota =
        widget.runner ??
        OtaAutomationRunner(
          widget.provider,
          canStartTest: () => !_transfer.isBusy,
          onReport: _reports.append,
        );
    _transfer =
        widget.transferRunner ??
        FileTransferTestRunner(
          widget.provider,
          canStartTest: () => !_ota.isRunning,
          onReport: _reports.append,
        );
  }

  @override
  void dispose() {
    if (widget.runner == null) _ota.dispose();
    if (widget.transferRunner == null) _transfer.dispose();
    if (widget.reportStore == null) _reports.dispose();
    super.dispose();
  }

  Future<void> _shareReport() async {
    if (_sharing || _clearing) return;
    setState(() => _sharing = true);
    try {
      final file = await _reports.fileForSharing();
      if (!mounted) return;
      if (file == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('暂无测试报告，请先启动测试')),
        );
        return;
      }
      await FileSharer.share(
        file,
        await getTemporaryDirectory(),
        copySource: _reports.copyForSharing,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('分享测试报告失败：$error')),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _clearReport() async {
    if (_clearing || _sharing || _ota.isRunning || _transfer.isBusy) return;
    setState(() => _clearing = true);
    try {
      await _reports.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('测试报告已清空')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('清空测试报告失败：$error')),
      );
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  String get _deviceLabel {
    final info = widget.provider.deviceInfo;
    if (info != null) {
      return '${widget.provider.deviceType ?? "--"} · ${info['name'] ?? "--"}';
    }
    final device = _ota.device;
    return device == null ? '未连接设备' : '${device.type ?? "--"} · ${device.name}';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_ota, _transfer, widget.provider, _reports]),
      builder: (context, _) => SingleChildScrollView(
        padding: const EdgeInsets.all(8),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 8,
          children: [
            Row(
              spacing: 8,
              children: [
                Expanded(
                  child: Text(
                    _deviceLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                TextButton(
                  onPressed: _clearing || _sharing || _ota.isRunning || _transfer.isBusy
                      ? null
                      : _clearReport,
                  child: const Text('清空报告'),
                ),
                TextButton.icon(
                  onPressed: _sharing || _clearing ? null : _shareReport,
                  icon: const Icon(Icons.share, size: 16),
                  label: const Text('分享报告'),
                ),
              ],
            ),
            if (_reports.lastError != null)
              Text(
                '测试报告保存失败，待重试：${_reports.lastError}',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            FileTransferTestModule(
              provider: widget.provider,
              runner: _transfer,
              enabled: !_ota.isRunning && !_clearing,
            ),
            OtaAutomationModule(
              provider: widget.provider,
              runner: _ota,
              enabled: !_transfer.isBusy && !_clearing,
            ),
          ],
        ),
      ),
    );
  }
}
