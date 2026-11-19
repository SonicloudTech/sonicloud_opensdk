import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soni_sdk_demo/bluetooth_connection_test/bluetooth_connection_test_runner.dart';
import 'package:soni_sdk_demo/bluetooth_connection_test/bluetooth_connection_test_module.dart';
import 'package:soni_sdk_demo/provider_record_pen.dart';
import 'package:soni_sdk_demo/demo_test_page.dart';
import 'package:soni_sdk_demo/file_transfer_test/file_transfer_test_module.dart';
import 'package:soni_sdk_demo/ota_automation/ota_automation_module.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;
  const channel = MethodChannel('com.soni.soni_sdk_demo/recordPen');
  const events = MethodChannel('com.soni.soni_sdk_demo/eventChannel');
  const device = {'name': 'Test pen', 'address': 'AA:BB:48', 'productType': 48};
  final calls = <MethodCall>[];
  late RecordPenProvider provider;
  late BluetoothConnectionTestRunner runner;
  late StringBuffer report;

  Future<void> flush(WidgetTester tester, [Duration? elapsed]) async {
    await tester.pump(elapsed);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }

  Future<void> emit(WidgetTester tester, Map<String, dynamic> event) async {
    await messenger.handlePlatformMessage(
      events.name,
      const StandardMethodCodec().encodeSuccessEnvelope(jsonEncode(event)),
      (_) {},
    );
    await flush(tester);
  }

  Future<void> connect(WidgetTester tester, [String address = 'AA:BB:48']) =>
      emit(tester, {
        'cmd': 2,
        'data': {...device, 'address': address, 'connect_state': true},
      });

  Future<void> disconnect(WidgetTester tester) => emit(tester, {
    'cmd': 2,
    'data': {'connect_state': '0', 'address': ''},
  });

  Future<void> scan(WidgetTester tester, [String address = 'AA:BB:48']) =>
      emit(tester, {
        'cmd': 1,
        'state': 0,
        'data': {...device, 'address': address},
      });

  void connectionTest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      calls.clear();
      report = StringBuffer();
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      messenger.setMockMethodCallHandler(events, (_) async => null);
      provider = RecordPenProvider();
      await provider.init();
      runner = BluetoothConnectionTestRunner(provider, onReport: report.write);
      try {
        await body(tester);
      } finally {
        await tester.pumpWidget(const SizedBox());
        runner.dispose();
        provider.stopAutoConnect();
        await flush(tester, const Duration(seconds: 5));
        await flush(tester, const Duration(milliseconds: 50));
        await flush(tester, const Duration(milliseconds: 50));
        binding.removeObserver(provider);
        provider.dispose();
        await provider.streamController.close();
        messenger.setMockMethodCallHandler(channel, null);
        messenger.setMockMethodCallHandler(events, null);
      }
    });
  }

  connectionTest(
    'waits from the disconnect callback and reconnects only the target',
    (tester) async {
      expect(runner.canStart, isFalse);
      await connect(tester);
      final run = runner.start(
        attempts: 2,
        reconnectInterval: const Duration(seconds: 3),
      );
      await flush(tester);
      expect(runner.isRunning, isTrue);
      expect(calls.where((call) => call.method == 'close'), hasLength(1));
      await flush(tester, const Duration(seconds: 4));
      expect(calls.where((call) => call.method == 'startSearch'), isEmpty);
      for (var round = 1; round <= 2; round++) {
        await disconnect(tester);
        await flush(tester, const Duration(seconds: 2));
        expect(
          calls.where((call) => call.method == 'startSearch'),
          hasLength(round - 1),
        );
        await flush(tester, const Duration(seconds: 1));
        await scan(tester, 'other-address');
        expect(
          calls.where((call) => call.method == 'connect'),
          hasLength(round - 1),
        );
        await scan(tester);
        expect(calls.where((call) => call.method == 'connect').last.arguments, {
          'name': 'Test pen',
          'address': 'AA:BB:48',
        });
        expect(runner.completed, round - 1);
        await connect(tester, '');
        expect(runner.successes, round);
      }
      await run;
      expect(runner.completed, 2);
      expect(runner.failureCount, 0);
      expect(runner.isRunning, isFalse);
      expect(report.toString(), contains('设备蓝牙连接测试'));
      expect(report.toString(), contains('成功 2 次，失败 0 次'));
      runner.clearResults();
      expect(runner.completed, 0);
      expect(runner.total, 0);
      expect(runner.successes, 0);
      expect(runner.status, '等待开始');
    },
  );

  connectionTest(
    'counts failed callbacks and timeouts then continues the requested rounds',
    (tester) async {
      await connect(tester);
      final run = runner.start(attempts: 3, reconnectInterval: Duration.zero);
      await flush(tester);
      await disconnect(tester);
      await scan(tester);
      await disconnect(tester);
      expect(runner.failureCount, 1);
      await flush(tester);
      expect(runner.status, contains('扫描'));
      await flush(tester, const Duration(seconds: 30));
      expect(runner.failureCount, 2);
      await flush(tester);
      expect(runner.status, contains('扫描'));
      await scan(tester);
      await connect(tester);
      await run;
      expect(runner.completed, 3);
      expect(runner.successes, 1);
      expect(report.toString(), contains('成功 1 次，失败 2 次'));
      runner.clearResults();
      expect(runner.failureCount, 0);
    },
  );

  connectionTest('a disconnect timeout fails without starting a reconnect', (
    tester,
  ) async {
    await connect(tester);
    final run = runner.start(attempts: 1, reconnectInterval: Duration.zero);
    await flush(tester);
    await flush(tester, const Duration(seconds: 10));
    await run;
    expect(runner.completed, 1);
    expect(runner.failureCount, 1);
    expect(calls.where((call) => call.method == 'connect'), isEmpty);
    expect(calls.where((call) => call.method == 'startSearch'), isEmpty);
  });

  connectionTest('interrupt cancels the interval without recording a failure', (
    tester,
  ) async {
    await connect(tester);
    final run = runner.start(
      attempts: 10,
      reconnectInterval: const Duration(seconds: 5),
    );
    await flush(tester);
    await disconnect(tester);
    final interrupted = runner.interrupt();
    await flush(tester);
    await interrupted;
    await run;
    await flush(tester, const Duration(seconds: 10));
    expect(calls.where((call) => call.method == 'connect'), isEmpty);
    expect(calls.where((call) => call.method == 'startSearch'), isEmpty);
    expect(runner.completed, 0);
    expect(runner.failureCount, 0);
    expect(runner.status, '测试已中断');
    expect(report.toString(), contains('成功 0 次，失败 0 次，测试已中断'));
  });

  connectionTest('interrupt stops an active connection attempt', (
    tester,
  ) async {
    await connect(tester);
    final run = runner.start(attempts: 10, reconnectInterval: Duration.zero);
    await flush(tester);
    await disconnect(tester);
    await scan(tester);
    final closes = calls.where((call) => call.method == 'close').length;
    final interrupted = runner.interrupt();
    await flush(tester);
    await interrupted;
    await run;
    expect(
      calls.where((call) => call.method == 'close'),
      hasLength(closes + 1),
    );
    expect(runner.completed, 0);
    expect(runner.failureCount, 0);
  });

  connectionTest(
    'switching devices stops without disconnecting the new device',
    (tester) async {
      await connect(tester);
      final run = runner.start(attempts: 3, reconnectInterval: Duration.zero);
      await flush(tester);
      await disconnect(tester);
      await scan(tester);
      final closes = calls.where((call) => call.method == 'close').length;
      await connect(tester, 'other-address');
      await run;
      expect(runner.completed, 1);
      expect(runner.failureCount, 1);
      expect(calls.where((call) => call.method == 'close'), hasLength(closes));
      expect(provider.isConnected, isTrue);
    },
  );

  connectionTest(
    'module validates settings, locks inputs and interrupts the run',
    (tester) async {
      await connect(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BluetoothConnectionTestModule(
              provider: provider,
              runner: runner,
            ),
          ),
        ),
      );
      final attempts = find.byKey(const ValueKey('bluetooth-test-attempts'));
      final interval = find.byKey(
        const ValueKey('bluetooth-reconnect-interval'),
      );
      await tester.enterText(attempts, '0');
      await tester.tap(find.text('启动测试'));
      await flush(tester);
      expect(runner.isRunning, isFalse);
      expect(find.text('请输入正整数测试次数和非负整数重连间隔'), findsOneWidget);
      await tester.enterText(attempts, '3');
      await tester.enterText(interval, '-1');
      await tester.tap(find.text('启动测试'));
      await flush(tester);
      expect(runner.isRunning, isFalse);
      await tester.enterText(interval, '4');
      await tester.tap(find.text('启动测试'));
      await flush(tester);
      expect(runner.total, 3);
      expect(tester.widget<TextField>(attempts).enabled, isFalse);
      expect(tester.widget<TextField>(interval).enabled, isFalse);
      await disconnect(tester);
      await flush(tester, const Duration(seconds: 3));
      expect(calls.where((call) => call.method == 'startSearch'), isEmpty);
      await flush(tester, const Duration(seconds: 1));
      expect(calls.where((call) => call.method == 'startSearch'), hasLength(1));
      await tester.tap(find.text('中断测试'));
      await flush(tester);
      expect(runner.isRunning, isFalse);
      expect(runner.failureCount, 0);
      expect(find.text('成功 0 次 · 失败 0 次'), findsOneWidget);
      expect(tester.widget<TextField>(attempts).enabled, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  connectionTest(
    'configured disconnect delay applies initially and after each successful reconnect',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await connect(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BluetoothConnectionTestModule(
              provider: provider,
              runner: runner,
            ),
          ),
        ),
      );
      final delay = find.byKey(const ValueKey('bluetooth-disconnect-delay'));
      expect(delay, findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('bluetooth-test-attempts')),
        '2',
      );
      await tester.enterText(delay, '3');
      await tester.enterText(
        find.byKey(const ValueKey('bluetooth-reconnect-interval')),
        '2',
      );
      await tester.tap(find.text('启动测试'));
      await flush(tester);
      expect(tester.widget<TextField>(delay).enabled, isFalse);
      await flush(tester, const Duration(seconds: 2));
      expect(calls.where((call) => call.method == 'close'), isEmpty);
      await flush(tester, const Duration(seconds: 1));
      for (var round = 1; round <= 2; round++) {
        expect(calls.where((call) => call.method == 'close'), hasLength(round));
        await flush(tester, const Duration(seconds: 1));
        await disconnect(tester);
        await flush(tester, const Duration(seconds: 1));
        expect(
          calls.where((call) => call.method == 'startSearch'),
          hasLength(round - 1),
        );
        await flush(tester, const Duration(seconds: 1));
        await scan(tester);
        await connect(tester);
        expect(runner.successes, round - 1);
        await flush(tester, const Duration(seconds: 2));
        expect(runner.successes, round - 1);
        expect(calls.where((call) => call.method == 'close'), hasLength(round));
        await flush(tester, const Duration(seconds: 1));
        expect(runner.successes, round);
      }
      expect(runner.isRunning, isFalse);
      expect(runner.failureCount, 0);
      expect(provider.isConnected, isTrue);
      expect(report.toString(), contains('成功 2 次，失败 0 次'));
      expect(tester.takeException(), isNull);
    },
  );

  connectionTest('module rejects invalid disconnect delays before starting', (
    tester,
  ) async {
    await connect(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BluetoothConnectionTestModule(
            provider: provider,
            runner: runner,
          ),
        ),
      ),
    );
    final delay = find.byKey(const ValueKey('bluetooth-disconnect-delay'));
    expect(delay, findsOneWidget);
    for (final invalid in ['', '-1', '1.5']) {
      await tester.enterText(delay, invalid);
      await tester.tap(find.text('启动测试'));
      await flush(tester);
      expect(runner.isRunning, isFalse);
      expect(calls.where((call) => call.method == 'close'), isEmpty);
    }
  });

  connectionTest(
    'interrupt cancels the disconnect delay and preserves completed successes',
    (tester) async {
      await connect(tester);
      final run = runner.start(
        attempts: 3,
        reconnectInterval: Duration.zero,
        disconnectDelay: const Duration(seconds: 3),
      );
      await flush(tester);
      await flush(tester, const Duration(seconds: 3));
      await disconnect(tester);
      await scan(tester);
      await connect(tester);
      await flush(tester, const Duration(seconds: 3));
      expect(runner.successes, 1);
      await disconnect(tester);
      await scan(tester);
      await connect(tester);
      final interrupted = runner.interrupt();
      await flush(tester);
      await interrupted;
      await run;
      await flush(tester, const Duration(seconds: 5));
      expect(calls.where((call) => call.method == 'close'), hasLength(2));
      expect(runner.successes, 1);
      expect(runner.failureCount, 0);
      expect(provider.isConnected, isTrue);
      expect(runner.status, '测试已中断');
    },
  );

  connectionTest(
    'an unexpected initial disconnect counts a failure and continues after the reconnect interval',
    (tester) async {
      await connect(tester);
      final run = runner.start(
        attempts: 2,
        reconnectInterval: const Duration(seconds: 2),
        disconnectDelay: const Duration(seconds: 10),
      );
      await flush(tester);
      await flush(tester, const Duration(seconds: 3));
      await disconnect(tester);
      expect(runner.failureCount, 1);
      expect(runner.successes, 0);
      await flush(tester, const Duration(seconds: 1));
      expect(calls.where((call) => call.method == 'startSearch'), isEmpty);
      await flush(tester, const Duration(seconds: 1));
      expect(calls.where((call) => call.method == 'startSearch'), hasLength(1));
      await scan(tester);
      await connect(tester);
      expect(runner.successes, 0);
      await flush(tester, const Duration(seconds: 10));
      await run;
      expect(runner.successes, 1);
      expect(runner.failureCount, 1);
      expect(report.toString(), contains('成功 1 次，失败 1 次'));
    },
  );

  connectionTest(
    'the final reconnect fails if the device disconnects before the hold finishes',
    (tester) async {
      await connect(tester);
      final run = runner.start(
        attempts: 1,
        reconnectInterval: const Duration(seconds: 2),
        disconnectDelay: const Duration(seconds: 5),
      );
      await flush(tester);
      await flush(tester, const Duration(seconds: 5));
      await disconnect(tester);
      await flush(tester, const Duration(seconds: 2));
      await scan(tester);
      await connect(tester);
      expect(runner.successes, 0);
      expect(runner.isRunning, isTrue);
      await flush(tester, const Duration(seconds: 2));
      await disconnect(tester);
      await run;
      expect(runner.completed, 1);
      expect(runner.successes, 0);
      expect(runner.failureCount, 1);
      expect(report.toString(), contains('成功 0 次，失败 1 次'));
    },
  );

  connectionTest('module disables starting while another test is active', (
    tester,
  ) async {
    await connect(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BluetoothConnectionTestModule(
            provider: provider,
            runner: runner,
            enabled: false,
          ),
        ),
      ),
    );
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '启动测试'))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('bluetooth-test-attempts')),
          )
          .enabled,
      isFalse,
    );
  });

  connectionTest(
    'a timed out round never connects after a suspended stop completes',
    (tester) async {
      await connect(tester);
      final run = runner.start(attempts: 1, reconnectInterval: Duration.zero);
      await flush(tester);
      await disconnect(tester);
      final release = Completer<void>();
      var suspendNextStop = true;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'stopSearch' && suspendNextStop) {
          suspendNextStop = false;
          await release.future;
        }
        return null;
      });
      await scan(tester);
      expect(calls.where((call) => call.method == 'connect'), isEmpty);
      await flush(tester, const Duration(seconds: 30));
      await run;
      release.complete();
      await flush(tester);
      expect(calls.where((call) => call.method == 'connect'), isEmpty);
      expect(runner.failureCount, 1);
    },
  );

  connectionTest(
    'a connection timeout waits for the real close callback before the next round',
    (tester) async {
      await connect(tester);
      final run = runner.start(
        attempts: 2,
        reconnectInterval: const Duration(seconds: 2),
      );
      await flush(tester);
      await disconnect(tester);
      await flush(tester, const Duration(seconds: 2));
      await scan(tester);
      await flush(tester, const Duration(seconds: 30));
      await flush(tester);
      await flush(tester, const Duration(seconds: 2));
      expect(calls.where((call) => call.method == 'startSearch'), hasLength(1));
      await connect(tester);
      expect(runner.successes, 0);
      await disconnect(tester);
      await flush(tester);
      expect(runner.failureCount, 1);
      await flush(tester, const Duration(seconds: 1));
      expect(calls.where((call) => call.method == 'startSearch'), hasLength(1));
      await flush(tester, const Duration(seconds: 1));
      await scan(tester);
      await connect(tester);
      await run;
      expect(runner.completed, 2);
      expect(runner.successes, 1);
      expect(runner.failureCount, 1);
    },
  );

  connectionTest(
    'an unconfirmed cancellation stops instead of contaminating later rounds',
    (tester) async {
      await connect(tester);
      final run = runner.start(attempts: 3, reconnectInterval: Duration.zero);
      await flush(tester);
      await disconnect(tester);
      await scan(tester);
      await flush(tester, const Duration(seconds: 30));
      await flush(tester, const Duration(seconds: 10));
      await run;
      expect(runner.completed, 1);
      expect(runner.failureCount, 1);
      expect(runner.status, '断开连接未确认，测试已停止');
      expect(calls.where((call) => call.method == 'startSearch'), hasLength(1));
    },
  );

  connectionTest('disposing during the interval cancels all subsequent work', (
    tester,
  ) async {
    await connect(tester);
    final disposable = BluetoothConnectionTestRunner(provider);
    final run = disposable.start(
      attempts: 2,
      reconnectInterval: const Duration(seconds: 5),
    );
    await flush(tester);
    await disconnect(tester);
    disposable.dispose();
    await flush(tester);
    await run;
    await flush(tester, const Duration(seconds: 10));
    expect(calls.where((call) => call.method == 'startSearch'), isEmpty);
    expect(disposable.completed, 0);
  });

  connectionTest(
    'the test page locks other modules and report clearing during Bluetooth tests',
    (tester) async {
      await connect(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DemoTestPage(provider: provider, bluetoothRunner: runner),
          ),
        ),
      );
      final transfer = tester.widget<FileTransferTestModule>(
        find.byType(FileTransferTestModule),
      );
      final ota = tester.widget<OtaAutomationModule>(
        find.byType(OtaAutomationModule),
      );
      final run = runner.start(attempts: 1, reconnectInterval: Duration.zero);
      await flush(tester);
      expect(transfer.runner.canStart, isFalse);
      expect(ota.runner!.canStart, isFalse);
      expect(
        tester
            .widget<FileTransferTestModule>(find.byType(FileTransferTestModule))
            .enabled,
        isFalse,
      );
      expect(
        tester
            .widget<OtaAutomationModule>(find.byType(OtaAutomationModule))
            .enabled,
        isFalse,
      );
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '清空报告'))
            .onPressed,
        isNull,
      );
      final interrupted = runner.interrupt();
      await flush(tester);
      await interrupted;
      await run;
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '清空报告'))
            .onPressed,
        isNotNull,
      );
      final refresh = transfer.runner.refreshFiles();
      final rejectedRefresh = expectLater(refresh, throwsStateError);
      await flush(tester);
      expect(
        tester
            .widget<BluetoothConnectionTestModule>(
              find.byType(BluetoothConnectionTestModule),
            )
            .enabled,
        isFalse,
      );
      await transfer.runner.interrupt();
      await flush(tester);
      await rejectedRefresh;
      expect(tester.takeException(), isNull);
    },
  );

  connectionTest('rejects invalid settings and overlapping runs', (
    tester,
  ) async {
    await connect(tester);
    await expectLater(
      runner.start(attempts: 0, reconnectInterval: Duration.zero),
      throwsArgumentError,
    );
    await expectLater(
      runner.start(attempts: 1, reconnectInterval: const Duration(seconds: -1)),
      throwsArgumentError,
    );
    await expectLater(
      runner.start(
        attempts: 1,
        reconnectInterval: Duration.zero,
        disconnectDelay: const Duration(seconds: -1),
      ),
      throwsArgumentError,
    );
    expect(calls.where((call) => call.method == 'close'), isEmpty);
    final run = runner.start(attempts: 1, reconnectInterval: Duration.zero);
    await flush(tester);
    expect(runner.canStart, isFalse);
    expect(runner.clearResults, throwsStateError);
    await expectLater(
      runner.start(attempts: 1, reconnectInterval: Duration.zero),
      throwsStateError,
    );
    final interrupted = runner.interrupt();
    await flush(tester);
    await interrupted;
    await run;
  });
}
