import 'package:flutter/material.dart';

import '../provider_record_pen.dart';
import 'bluetooth_connection_test_runner.dart';

class BluetoothConnectionTestModule extends StatefulWidget {
  const BluetoothConnectionTestModule({
    super.key,
    required this.provider,
    required this.runner,
    this.enabled = true,
  });

  final RecordPenProvider provider;
  final BluetoothConnectionTestRunner runner;
  final bool enabled;

  @override
  State<BluetoothConnectionTestModule> createState() =>
      _BluetoothConnectionTestModuleState();
}

class _BluetoothConnectionTestModuleState
    extends State<BluetoothConnectionTestModule> {
  final _attempts = TextEditingController(text: '1');
  final _interval = TextEditingController(text: '2');
  final _disconnectDelay = TextEditingController(text: '0');

  @override
  void dispose() {
    _attempts.dispose();
    _interval.dispose();
    _disconnectDelay.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final attempts = int.tryParse(_attempts.text.trim());
    final seconds = int.tryParse(_interval.text.trim());
    if (attempts == null || attempts < 1 || seconds == null || seconds < 0) {
      _showMessage('请输入正整数测试次数和非负整数重连间隔');
      return;
    }
    final disconnectSeconds = int.tryParse(_disconnectDelay.text.trim());
    if (disconnectSeconds == null || disconnectSeconds < 0) {
      _showMessage('请输入非负整数断链延迟');
      return;
    }
    try {
      await widget.runner.start(
        attempts: attempts,
        reconnectInterval: Duration(seconds: seconds),
        disconnectDelay: Duration(seconds: disconnectSeconds),
      );
    } catch (error) {
      _showMessage('蓝牙连接测试失败：$error');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.runner, widget.provider]),
      builder: (context, _) {
        final runner = widget.runner;
        final locked = runner.isRunning || !widget.enabled;
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
                Text('设备蓝牙连接测试', style: theme.textTheme.labelLarge),
                Row(
                  spacing: 6,
                  children: [
                    Expanded(
                      child: TextField(
                        key: const ValueKey('bluetooth-test-attempts'),
                        controller: _attempts,
                        enabled: !locked,
                        keyboardType: TextInputType.number,
                        style: theme.textTheme.bodySmall,
                        decoration: _compactInput('测试次数'),
                      ),
                    ),
                    FilledButton(
                      onPressed: !locked && runner.canStart ? _start : null,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 32),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 4,
                        ),
                      ),
                      child: const Text('启动测试'),
                    ),
                  ],
                ),
                Row(
                  spacing: 6,
                  children: [
                    Expanded(
                      child: TextField(
                        key: const ValueKey('bluetooth-disconnect-delay'),
                        controller: _disconnectDelay,
                        enabled: !locked,
                        keyboardType: TextInputType.number,
                        style: theme.textTheme.bodySmall,
                        decoration: _compactInput('连接后断链延迟（秒）'),
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        key: const ValueKey('bluetooth-reconnect-interval'),
                        controller: _interval,
                        enabled: !locked,
                        keyboardType: TextInputType.number,
                        style: theme.textTheme.bodySmall,
                        decoration: _compactInput('断链后重连间隔（秒）'),
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
}
