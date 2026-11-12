import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soni_sdk_demo/ota_automation/ota_automation_runner.dart';
import 'package:soni_sdk_demo/provider_record_pen.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;
  const channel = MethodChannel('com.soni.soni_sdk_demo/recordPen');
  const events = MethodChannel('com.soni.soni_sdk_demo/eventChannel');
  const first = (path: '/tmp/first.ufw', version: '1.0.1');
  const second = (path: '/tmp/second.ufw', version: '1.0.2');
  const address = 'AA:BB:CC:00:00:48';
  const otherAddress = 'AA:BB:CC:00:00:30';
  const device = {'name': 'Test pen', 'address': address, 'productType': 48};
  final calls = <MethodCall>[];
  var report = StringBuffer();

  Future<void> flush(WidgetTester tester, [Duration? elapsed]) async {
    await tester.pump(elapsed);
    // Stream cancellation can complete in the root zone, outside fake time.
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

  Future<void> connect(
    WidgetTester tester, [
    Map<String, dynamic> info = device,
  ]) => emit(tester, {
    'cmd': 2,
    'data': {...info, 'connect_state': true},
  });

  Future<void> disconnect(
    WidgetTester tester, [
    String disconnectedAddress = 'null',
  ]) => emit(tester, {
    'cmd': '2',
    'data': {'connect_state': '0', 'address': disconnectedAddress},
  });

  Future<void> wifi(WidgetTester tester, int state) => emit(tester, {
    'cmd': 12,
    'state': 0,
    'data': {'wifi_state': state},
  });

  Future<void> approve(WidgetTester tester) => emit(tester, {
    'cmd': 19,
    'state': '0',
    'data': {'prepareState': 3},
  });

  Future<void> receive(WidgetTester tester) => emit(tester, {
    'cmd': '21',
    'state': 0,
    'data': {'receiveState': '0'},
  });

  Future<void> progress(WidgetTester tester, int sent) => emit(tester, {
    'cmd': '20',
    'state': '0',
    'data': {'progress': '$sent', 'total': '1257792'},
  });

  Future<void> version(WidgetTester tester, String value) async {
    await flush(tester, const Duration(seconds: 2));
    await emit(tester, {
      'cmd': 17,
      'state': '0',
      'data': {'version': value},
    });
    await flush(tester, const Duration(seconds: 2));
  }

  Iterable<MethodCall> sent() =>
      calls.where((call) => call.method == 'sendOtaFile');

  void automationTest(
    String name,
    Future<void> Function(WidgetTester, OtaAutomationRunner) body,
  ) {
    testWidgets(name, (tester) async {
      calls.clear();
      report = StringBuffer();
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      messenger.setMockMethodCallHandler(events, (_) async => null);
      final provider = RecordPenProvider();
      await provider.init();
      final runner = OtaAutomationRunner(provider, onReport: report.write);
      try {
        await body(tester, runner);
      } finally {
        runner.dispose();
        provider.stopAutoConnect();
        await tester.pump(const Duration(seconds: 5));
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 50));
        binding.removeObserver(provider);
        provider.dispose();
        await provider.streamController.close();
        messenger.setMockMethodCallHandler(channel, null);
        messenger.setMockMethodCallHandler(events, null);
      }
    });
  }

  automationTest('iOS empty connection address retains scanned device identity', (
    tester,
    runner,
  ) async {
    await emit(tester, {'cmd': 1, 'state': 0, 'data': device});
    await emit(tester, {
      'cmd': 2,
      'data': {'connect_state': '1', 'name': device['name'], 'address': ''},
    });
    expect(runner.device?.address, address);
    expect(runner.device?.type, 48);
    expect(runner.canStart, isTrue);
    await disconnect(tester, '');
    expect(runner.canStart, isFalse);
  });

  automationTest('captures the connected device and starts only for type 48', (
    tester,
    runner,
  ) async {
    await connect(tester, {...device, 'productType': '30'});
    expect(runner.device?.type, 30);
    expect(runner.canStart, isFalse);
    await connect(tester);
    expect(runner.device?.address, address);
    expect(runner.canStart, isTrue);
    await disconnect(tester);
    expect(runner.device?.address, address);
    expect(runner.canStart, isFalse);
  });

  automationTest('chooses the first different firmware from a fresh version', (
    tester,
    runner,
  ) async {
    await connect(tester);
    final run = runner.start(attempts: 4, first: first, second: second);
    await flush(tester, const Duration(seconds: 2));

    var attempt = 0;
    for (final (currentVersion, reportedVersion) in [
      ('1.0.1', '1.0.0'),
      ('1.0.0', '1.0.1'),
      ('1.0.1', '1.0.2'),
      ('1.0.2', '1.0.1'),
    ]) {
      attempt++;
      expect(
        calls.where((call) => call.method == 'getDeviceVersion'),
        hasLength(attempt * 2 - 1),
      );
      expect(
        calls.where((call) => call.method == 'requestDeviceGotoOtaMode'),
        hasLength(attempt - 1),
      );
      expect(runner.upgradeDirection, isNull);
      await version(tester, currentVersion);
      final targetVersion = currentVersion == first.version
          ? second.version
          : first.version;
      final direction = '$currentVersion → $targetVersion';
      expect(runner.upgradeDirection, direction);
      await approve(tester);
      expect(
        sent(),
        hasLength(attempt),
        reason: '${runner.status} ${runner.lastFailure} $calls',
      );
      final versionQueries = calls
          .where((call) => call.method == 'getDeviceVersion')
          .length;
      await progress(tester, 1257792);
      await receive(tester);
      expect(runner.status, contains('重连'));
      await version(tester, '1.0.1');
      expect(
        calls.where((call) => call.method == 'getDeviceVersion'),
        hasLength(versionQueries),
      );
      await disconnect(tester, address);
      expect(runner.upgradeDirection, direction);
      final connects = calls.where((call) => call.method == 'connect').length;
      await emit(tester, {
        'cmd': 1,
        'state': '0',
        'data': {...device, 'address': otherAddress},
      });
      expect(
        calls.where((call) => call.method == 'connect'),
        hasLength(connects),
      );
      await emit(tester, {'cmd': 1, 'state': '0', 'data': device});
      expect(calls.where((call) => call.method == 'connect'), hasLength(connects));
      await flush(tester, const Duration(seconds: 4));
      expect(calls.where((call) => call.method == 'connect'), hasLength(connects));
      await flush(tester, const Duration(seconds: 1));
      expect(calls.where((call) => call.method == 'connect').last.arguments, {
        'name': 'Test pen',
        'address': address,
      });
      if (reportedVersion == '1.0.0') {
        await tester.pump(const Duration(seconds: 7));
        await emit(tester, {'cmd': 1, 'state': '0', 'data': device});
        expect(
          calls.where((call) => call.method == 'connect'),
          hasLength(connects + 1),
        );
        await disconnect(tester, address);
        await emit(tester, {'cmd': 1, 'state': '0', 'data': device});
        await flush(tester, const Duration(seconds: 5));
        expect(
          calls.where((call) => call.method == 'connect'),
          hasLength(connects + 2),
        );
      }
      await connect(tester);
      await flush(tester, const Duration(seconds: 2));
      expect(
        calls.where((call) => call.method == 'getDeviceVersion'),
        hasLength(versionQueries + 1),
      );
      await version(tester, reportedVersion);
    }

    await run;
    expect(sent().map((call) => call.arguments['filePath']), [
      second.path,
      first.path,
      second.path,
      first.path,
    ]);
    expect(runner.completed, 4);
    expect(report.toString(), contains(RegExp(r'1/4 结果：失败[^\n]*升级方向：1.0.1 → 1.0.2')));
    expect(report.toString(), contains('2/4 结果：成功 升级方向：1.0.0 → 1.0.1'));
    expect(report.toString(), contains('4/4 结果：成功 升级方向：1.0.2 → 1.0.1'));
    expect(runner.failureCount, 1);
    expect(runner.upgradeDirection, '1.0.2 → 1.0.1');
  });

  automationTest('verification times out 20 seconds after the final progress', (
    tester,
    runner,
  ) async {
    await connect(tester);
    final run = runner.start(attempts: 2, first: first, second: second);
    await version(tester, '1.0.0');
    await approve(tester);
    expect(sent(), hasLength(1));
    await progress(tester, 100);
    await flush(tester, const Duration(minutes: 4, seconds: 59));
    expect(runner.completed, 0);

    await progress(tester, 1257792);
    await disconnect(tester, address);
    await flush(tester, const Duration(seconds: 19));
    expect(runner.completed, 0);
    await progress(tester, 1257792);
    await flush(tester, const Duration(seconds: 1));
    expect(runner.completed, 1);
    expect(runner.failureCount, 1);
    expect(runner.lastFailure, contains('文件验证超时'));

    await emit(tester, {'cmd': 1, 'state': '0', 'data': device});
    await flush(tester, const Duration(seconds: 5));
    await connect(tester);
    await version(tester, '1.0.0');
    await approve(tester);
    expect(sent(), hasLength(2));
    await flush(tester, const Duration(minutes: 5));
    await run;
    expect(runner.failureCount, 2);
    expect(runner.lastFailure, contains('等待固件发送完成超时'));
  });

  automationTest('waits before querying and sending and can interrupt a reconnect', (
    tester,
    runner,
  ) async {
    await connect(tester);
    final run = runner.start(attempts: 2, first: first, second: second);
    await flush(tester, const Duration(seconds: 1));
    expect(calls.where((call) => call.method == 'getDeviceVersion'), isEmpty);
    await flush(tester, const Duration(seconds: 1));
    expect(calls.where((call) => call.method == 'getDeviceVersion'), hasLength(1));
    await emit(tester, {
      'cmd': 17,
      'state': 0,
      'data': {'version': '1.0.0'},
    });
    await flush(tester, const Duration(seconds: 1));
    expect(calls.where((call) => call.method == 'requestDeviceGotoOtaMode'), isEmpty);
    await flush(tester, const Duration(seconds: 1));
    expect(calls.where((call) => call.method == 'requestDeviceGotoOtaMode'), hasLength(1));
    await approve(tester);
    await receive(tester);
    await disconnect(tester, address);
    await emit(tester, {'cmd': 1, 'state': '0', 'data': device});
    final interruption = runner.interrupt();
    await flush(tester);
    await interruption;
    await run;
    await flush(tester, const Duration(seconds: 5));
    expect(calls.where((call) => call.method == 'connect'), isEmpty);
    expect(runner.isRunning, isFalse);
    expect(runner.failureCount, 0);
    expect(runner.failureCounts, isEmpty);
    expect(report.toString(), contains('1/2 结果：中断'));
  });

  automationTest('interrupt aborts a Bluetooth connection already in progress', (
    tester,
    runner,
  ) async {
    await connect(tester);
    final run = runner.start(attempts: 1, first: first, second: second);
    await version(tester, '1.0.0');
    await approve(tester);
    await receive(tester);
    await disconnect(tester, address);
    await emit(tester, {'cmd': 1, 'state': '0', 'data': device});
    await flush(tester, const Duration(seconds: 5));
    expect(calls.where((call) => call.method == 'connect'), hasLength(1));
    final interruption = runner.interrupt();
    await flush(tester);
    await interruption;
    await run;
    expect(calls.where((call) => call.method == 'close'), hasLength(1));
    expect(runner.failureCount, 0);
  });

  automationTest('a reconnect timeout ignores a suspended connect callback', (
    tester,
    runner,
  ) async {
    await connect(tester);
    final run = runner.start(attempts: 1, first: first, second: second);
    await version(tester, '1.0.0');
    await approve(tester);
    await receive(tester);
    await disconnect(tester, address);
    final release = Completer<void>();
    var stops = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'stopSearch' && ++stops == 2) await release.future;
      return null;
    });
    await emit(tester, {'cmd': 1, 'state': '0', 'data': device});
    await flush(tester, const Duration(seconds: 5));
    await flush(tester, const Duration(seconds: 25));
    await run;
    release.complete();
    await flush(tester);
    expect(calls.where((call) => call.method == 'connect'), isEmpty);
    expect(runner.failureCount, 1);
  });

  automationTest('does not upgrade when both firmwares match the device', (
    tester,
    runner,
  ) async {
    await connect(tester);
    final run = runner.start(
      attempts: 1,
      first: first,
      second: (path: second.path, version: first.version),
    );
    await version(tester, first.version);
    await run;
    expect(
      calls.where((call) => call.method == 'requestDeviceGotoOtaMode'),
      isEmpty,
    );
    expect(runner.failureCount, 1);
    expect(runner.lastFailure, contains('与两份固件版本一致'));
    expect(report.toString(), contains('1/1 结果：失败 失败原因：当前版本与两份固件版本一致'));
    expect(report.toString(), contains('总耗时：'));
    expect(runner.upgradeDirection, isNull);
  });

  automationTest('counts a failure when the device cannot reconnect in 30s', (
    tester,
    runner,
  ) async {
    await connect(tester);
    final run = runner.start(attempts: 1, first: first, second: second);
    await tester.pump();
    await version(tester, '1.0.0');
    await approve(tester);
    await receive(tester);
    await disconnect(tester);
    await tester.pump(const Duration(seconds: 29));
    expect(runner.isRunning, isTrue);
    await flush(tester, const Duration(seconds: 1));
    expect(runner.isRunning, isFalse, reason: runner.status);
    await run;
    expect(runner.failureCount, 1);
    expect(
      calls.where((call) => call.method == 'getDeviceVersion'),
      hasLength(1),
    );
  });

  automationTest('retries denied preparation without dropping the connection', (
    tester,
    runner,
  ) async {
    await connect(tester);
    final run = runner.start(attempts: 2, first: first, second: second);
    await tester.pump();
    for (var attempt = 1; attempt <= 2; attempt++) {
      await version(tester, '1.0.0');
      expect(
        calls.where((call) => call.method == 'requestDeviceGotoOtaMode'),
        hasLength(attempt),
      );
      await emit(tester, {
        'cmd': 19,
        'state': 0,
        'data': {'prepareState': 1},
      });
      expect(calls.where((call) => call.method == 'close'), isEmpty);
    }
    await run;
    expect(runner.failureCount, 2);
    expect(sent(), isEmpty);
    expect(runner.failureCounts, {
      '不能进入升级状态，请检查 SD 卡或内存空间': 2,
    });
  });

  automationTest('waits for TCP and avoids sending after the target changes', (
    tester,
    runner,
  ) async {
    await connect(tester);
    final run = runner.start(attempts: 3, first: first, second: second);
    await tester.pump();
    await version(tester, '1.0.0');
    await emit(tester, {
      'cmd': 19,
      'state': 0,
      'data': {'prepareState': 2},
    });
    await wifi(tester, 0);
    await wifi(tester, 4);
    expect(
      calls.where((call) => call.method == 'quickConnectDeviceWiFi'),
      hasLength(1),
    );
    expect(
      calls.where((call) => call.method == 'requestDeviceGotoOtaMode'),
      hasLength(1),
    );
    await wifi(tester, 2);
    expect(
      calls.where((call) => call.method == 'requestDeviceGotoOtaMode'),
      hasLength(2),
    );
    await connect(tester, {...device, 'address': otherAddress});
    await approve(tester);
    await run;
    expect(sent(), isEmpty);
    expect(runner.completed, 1);
    expect(runner.failureCount, 1);
  });
}
