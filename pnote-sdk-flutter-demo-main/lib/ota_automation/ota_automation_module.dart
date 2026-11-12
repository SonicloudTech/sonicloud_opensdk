import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../provider_record_pen.dart';
import 'ota_automation_runner.dart';

typedef _SelectedFirmware = ({String name, File file});

class OtaAutomationModule extends StatefulWidget {
  const OtaAutomationModule({super.key, required this.provider, this.runner, this.enabled = true});

  final RecordPenProvider provider;
  final OtaAutomationRunner? runner;
  final bool enabled;

  @override
  State<OtaAutomationModule> createState() => _OtaAutomationModuleState();
}

class _OtaAutomationModuleState extends State<OtaAutomationModule> {
  final _formKey = GlobalKey<FormState>();
  final _attempts = TextEditingController(text: '1');
  final _versions = [TextEditingController(), TextEditingController()];
  final _firmware = List<_SelectedFirmware?>.filled(2, null);
  late final OtaAutomationRunner _runner;
  Future<void>? _activeRun;
  bool _picking = false;

  @override
  void initState() {
    super.initState();
    _runner = widget.runner ?? OtaAutomationRunner(widget.provider);
  }

  Future<void> _selectFirmware(int index) async {
    if (_picking || _runner.isRunning) return;
    setState(() => _picking = true);
    Directory? staging;
    try {
      final result = await FilePicker.pickFiles(
        type: Platform.isIOS ? FileType.any : FileType.custom,
        allowedExtensions: Platform.isIOS ? null : ['ufw'],
      );
      if (!mounted || result == null || result.files.isEmpty) return;
      final picked = result.files.single;
      final path = picked.path;
      if (!picked.name.toLowerCase().endsWith('.ufw') || path == null) {
        throw const FormatException('请选择可读取的 .ufw 固件文件');
      }
      final temporary = await getTemporaryDirectory();
      staging = await temporary.createTemp('soni_ota_test_');
      final file = await File(path).copy('${staging.path}/firmware.ufw');
      if (await file.length() == 0) throw const FormatException('固件文件为空');
      if (!mounted) return;
      final previous = _firmware[index];
      setState(() => _firmware[index] = (name: picked.name, file: file));
      staging = null;
      await _removeDirectory(previous?.file.parent);
    } catch (error) {
      _showMessage('选择固件失败：$error');
    } finally {
      await _removeDirectory(staging);
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _removeDirectory(Directory? directory) async {
    if (directory == null) return;
    try {
      await directory.delete(recursive: true);
    } on FileSystemException {
      // 系统可能已经清理临时目录。
    }
  }

  Future<void> _start() async {
    if (_picking || !_runner.canStart || !widget.enabled) return;
    if (!_formKey.currentState!.validate()) return;
    final first = _firmware[0];
    final second = _firmware[1];
    if (first == null || second == null) {
      _showMessage('请选择两份固件文件');
      return;
    }
    final run = _runner.start(
      attempts: int.parse(_attempts.text.trim()),
      first: (path: first.file.path, version: _versions[0].text.trim()),
      second: (path: second.file.path, version: _versions[1].text.trim()),
    );
    _activeRun = run;
    try {
      await run;
    } catch (error) {
      _showMessage('启动测试失败：$error');
    } finally {
      _activeRun = null;
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    if (widget.runner == null) _runner.dispose();
    _attempts.dispose();
    for (final version in _versions) {
      version.dispose();
    }
    unawaited(_releaseFirmware(_activeRun));
    super.dispose();
  }

  Future<void> _releaseFirmware(Future<void>? activeRun) async {
    try {
      await activeRun;
    } finally {
      for (final firmware in _firmware) {
        await _removeDirectory(firmware?.file.parent);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _runner,
      builder: (context, _) {
        if (_runner.device?.type != OtaAutomationRunner.supportedDeviceType &&
            !_runner.isRunning) {
          return const SizedBox.shrink();
        }
        final locked = _runner.isRunning || _picking || !widget.enabled;
        final theme = Theme.of(context);
        return Form(
          key: _formKey,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFFF5F7FB),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE2E6F0)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 6,
                children: [
                  Text('杰理OTA自动化测试', style: theme.textTheme.labelLarge),
                  Row(
                    spacing: 6,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _attempts,
                          enabled: !locked,
                          keyboardType: TextInputType.number,
                          style: theme.textTheme.bodySmall,
                          decoration: _compactInput('测试次数'),
                          validator: (value) =>
                              (int.tryParse(value?.trim() ?? '') ?? 0) > 0
                              ? null
                              : '请输入正整数',
                        ),
                      ),
                      Expanded(
                        child: Text(
                          '失败次数 ${_runner.failureCount}',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      Expanded(child: _runButton(locked)),
                    ],
                  ),
                  for (var index = 0; index < _firmware.length; index++)
                    _firmwareFields(index, locked),
                  if (_runner.upgradeDirection case final direction?)
                    Text('升级方向 $direction', style: theme.textTheme.bodySmall),
                  if (_runner.isRunning || _runner.completed > 0)
                    Text(
                      '${_runner.status} · 已完成 ${_runner.completed} 次',
                      style: theme.textTheme.bodySmall,
                    ),
                  for (final entry in _runner.failureCounts.entries)
                    Text(
                      '${entry.key}：${entry.value} 次',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  if (_runner.lastFailure case final failure?)
                    Text(
                      failure,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  InputDecoration _compactInput(String label) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(fontSize: 11),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
  );

  Widget _runButton(bool locked) {
    return FilledButton(
      onPressed: _runner.isRunning
          ? (_runner.stopRequested ? null : _runner.stopAfterCurrentAttempt)
          : (_runner.canStart && !locked ? _start : null),
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 32),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      ),
      child: Text(
        _runner.isRunning ? (_runner.stopRequested ? '停止中' : '本轮后停止') : '启动测试',
      ),
    );
  }

  Widget _firmwareFields(int index, bool locked) {
    final slot = index + 1;
    final name = _firmware[index]?.name;
    return Row(
      spacing: 6,
      children: [
        Expanded(
          flex: 3,
          child: TextButton(
            onPressed: locked ? null : () => _selectFirmware(index),
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            ),
            child: Text(
              name == null ? '固件文件$slot' : '$slot · $name',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        Expanded(
          flex: 2,
          child: TextFormField(
            controller: _versions[index],
            enabled: !locked,
            style: Theme.of(context).textTheme.bodySmall,
            decoration: _compactInput('固件版本$slot'),
            validator: (value) =>
                (value?.trim().isEmpty ?? true) ? '请输入版本' : null,
          ),
        ),
      ],
    );
  }
}
