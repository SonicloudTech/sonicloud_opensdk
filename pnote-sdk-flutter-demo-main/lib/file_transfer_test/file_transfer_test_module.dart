import 'package:flutter/material.dart';

import '../provider_record_pen.dart';
import 'file_transfer_test_runner.dart';

class FileTransferTestModule extends StatefulWidget {
  const FileTransferTestModule({
    super.key,
    required this.provider,
    required this.runner,
    this.enabled = true,
  });

  final RecordPenProvider provider;
  final FileTransferTestRunner runner;
  final bool enabled;

  @override
  State<FileTransferTestModule> createState() => _FileTransferTestModuleState();
}

class _FileTransferTestModuleState extends State<FileTransferTestModule> {
  final _repetitions = TextEditingController(text: '1');
  String? _selectedFile;

  @override
  void dispose() {
    _repetitions.dispose();
    super.dispose();
  }

  Future<void> _perform(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('文件传输测试失败：$error')));
    }
  }

  Future<void> _startRepeated() async {
    final repetitions = int.tryParse(_repetitions.text.trim());
    if (_selectedFile == null || repetitions == null || repetitions < 1) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请选择文件并填写正整数重复次数')));
      return;
    }
    await _perform(
      () => widget.runner.start(
        fileName: _selectedFile,
        repetitions: repetitions,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.runner, widget.provider]),
      builder: (context, _) {
        final runner = widget.runner;
        final files = runner.files;
        if (!files.any((file) => file.name == _selectedFile)) {
          _selectedFile = files.isEmpty || runner.isBusy ? null : files.last.name;
        }
        final locked = runner.isBusy || !widget.enabled;
        final canStart = runner.canStart && widget.enabled;
        final theme = Theme.of(context);
        return DecoratedBox(
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
                Text('文件传输测试', style: theme.textTheme.labelLarge),
                Row(
                  spacing: 6,
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextButton(
                        onPressed: canStart
                            ? () => _perform(runner.refreshFiles)
                            : null,
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 32),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                        ),
                        child: const Text('获取文件列表'),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: FilledButton(
                        onPressed: canStart
                            ? () => _perform(() => runner.start())
                            : null,
                        style: _testButtonStyle(),
                        child: const Text('全部文件传输测试'),
                      ),
                    ),
                  ],
                ),
                DropdownButtonFormField<String>(
                  value: _selectedFile,
                  isExpanded: true,
                  isDense: true,
                  menuMaxHeight: 240,
                  style: theme.textTheme.bodySmall,
                  decoration: _compactInput('选择重复传输的文件（${files.length}）'),
                  selectedItemBuilder: (context) => [
                    for (final file in files.reversed)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Text(
                            file.displayLabel,
                            maxLines: 1,
                            softWrap: false,
                          ),
                        ),
                      ),
                  ],
                  items: [
                    for (final file in files.reversed)
                      DropdownMenuItem(
                        value: file.name,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Text(
                            file.displayLabel,
                            maxLines: 1,
                            softWrap: false,
                          ),
                        ),
                      ),
                  ],
                  onChanged: locked
                      ? null
                      : (value) => setState(() => _selectedFile = value),
                ),
                Row(
                  spacing: 6,
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _repetitions,
                        enabled: !locked,
                        keyboardType: TextInputType.number,
                        style: theme.textTheme.bodySmall,
                        decoration: _compactInput('重复次数'),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: FilledButton(
                        onPressed: canStart && _selectedFile != null
                            ? _startRepeated
                            : null,
                        style: _testButtonStyle(),
                        child: const Text('单文件重复传输测试'),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 1, color: Color(0xFFE2E6F0)),
                Row(
                  spacing: 6,
                  children: [
                    Expanded(
                      child: Text(
                        '成功 ${runner.successes} 次 · 失败 ${runner.failureCount} 次',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    if (runner.isRunning)
                      TextButton(
                        onPressed: runner.interrupt,
                        style: TextButton.styleFrom(
                          foregroundColor: theme.colorScheme.error,
                          minimumSize: const Size(0, 28),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                        ),
                        child: const Text('中断测试'),
                      ),
                  ],
                ),
                Text(
                  '${runner.status} · 已完成 ${runner.completed}/${runner.total} 次',
                  style: theme.textTheme.bodySmall,
                ),
                Text(
                  '传输速度 ${runner.speedSummary}',
                  style: theme.textTheme.bodySmall,
                ),
                Text(
                  '平均速度 ${runner.averageRate}',
                  style: theme.textTheme.bodySmall,
                ),
                for (final entry in runner.failureCounts.entries)
                  Text(
                    '${entry.key}：${entry.value} 次',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
              ],
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

  ButtonStyle _testButtonStyle() => FilledButton.styleFrom(
    minimumSize: const Size(0, 32),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
  );
}
