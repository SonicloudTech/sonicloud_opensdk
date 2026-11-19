import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soni_sdk_demo/demo_test_page.dart';
import 'package:soni_sdk_demo/ota_automation/ota_automation_module.dart';
import 'package:soni_sdk_demo/ota_automation/ota_automation_runner.dart';
import 'package:soni_sdk_demo/provider_record_pen.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;
  const channel = MethodChannel('com.soni.soni_sdk_demo/recordPen');
  const events = MethodChannel('com.soni.soni_sdk_demo/eventChannel');
  const device = {'name': 'C08', 'address': 'bk-device', 'productType': 198};
  const first = (path: '/tmp/first.bin', version: '1.0.1');
  const second = (path: '/tmp/second.rbl', version: '1.0.2');
  final calls = <MethodCall>[];
  final served = <String>[];
  late RecordPenProvider provider;
  late OtaAutomationRunner runner;
  late StringBuffer report;
  var stops = 0;
  Future<String> Function(File)? startHttp;

  Future<void> flush(WidgetTester tester, [Duration? duration]) async {
    await tester.pump(duration);
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

  Future<void> connect(WidgetTester tester, [int type = 198]) => emit(tester, {
    'cmd': 2,
    'data': {...device, 'productType': type, 'connect_state': true},
  });
  Future<void> wifi(WidgetTester tester, int state) => emit(tester, {
    'cmd': 12,
    'state': 0,
    'data': {'wifi_state': state},
  });
  Future<void> bk(
    WidgetTester tester,
    Object type,
    Object value, {
    int cmd = 41,
    int state = 0,
  }) => emit(tester, {
    'cmd': cmd,
    'state': state,
    'data': {'type': type, 'value': value},
  });

  void bkTest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      calls.clear();
      served.clear();
      stops = 0;
      startHttp = null;
      report = StringBuffer();
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      messenger.setMockMethodCallHandler(events, (_) async => null);
      provider = RecordPenProvider();
      await provider.init();
      runner = OtaAutomationRunner(
        provider,
        isBk: true,
        startBkHttp: (file) async {
          served.add(file.path);
          if (startHttp != null) return startHttp!(file);
          return 'http://192.168.1.2:8080/firmware.bin';
        },
        stopBkHttp: () async {
          stops++;
        },
        onReport: report.write,
      );
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

  Future<void> begin(WidgetTester tester, {int attempts = 1}) async {
    await connect(tester);
    unawaited(runner.start(attempts: attempts, first: first, second: second));
    await flush(tester, const Duration(seconds: 2));
    expect(
      calls.where((call) => call.method == 'getDeviceWiFiState'),
      isNotEmpty,
    );
  }

  Future<void> send(WidgetTester tester, String current) async {
    await wifi(tester, 2);
    await bk(tester, '01', current);
    await flush(tester, const Duration(seconds: 2));
    expect(calls.where((call) => call.method == 'setBK_UPGRADEHD'), isNotEmpty);
  }

  bkTest('supports exactly the models with BK OTA controls', (tester) async {
    expect(runner.canStart, isFalse);
    for (final type in [198, 199, 200, 201, 202]) {
      await connect(tester, type);
      expect(runner.canStart, isTrue);
    }
    for (final type in [3, 40, 48, 64, 65, 66]) {
      await connect(tester, type);
      expect(runner.canStart, isFalse);
    }
  });

  const authKeys = {
    201: '0xa23942310bdc269c3b64d71a6531f5b79f1d02c77851861205a7b6d727bd0928',
    202: '0xae4b1e65f7ba1282d2060876d324253c95e9475307b4e9e14f9a708dcc54b250',
  };
  Future<void> auth(
    WidgetTester tester, {
    int state = 0,
    Object? result = '0',
  }) async {
    await emit(tester, {
      'cmd': 31,
      'state': state,
      'data': {if (result != null) 'authkey_state': result},
    });
    if (state == 0 && int.tryParse('$result') == 0) {
      await flush(tester, const Duration(seconds: 2));
    }
  }

  Future<void> beginAuth(
    WidgetTester tester,
    int type, {
    int attempts = 1,
  }) async {
    await connect(tester, type);
    unawaited(runner.start(attempts: attempts, first: first, second: second));
    await flush(tester);
  }

  void expectNoOtaCommands() {
    expect(
      calls.where(
        (call) => const {
          'getDeviceWiFiState',
          'getBKHDVersion',
          'setBK_UPGRADEHD',
        }.contains(call.method),
      ),
      isEmpty,
    );
    expect(served, isEmpty);
  }

  for (final type in [201, 202]) {
    bkTest(
      'type $type authenticates with the default key before Wi-Fi or OTA',
      (tester) async {
        await beginAuth(tester, type);
        expect(
          calls
              .where((call) => call.method == 'authkeyConnect')
              .single
              .arguments,
          {'authkey': authKeys[type]},
        );
        expectNoOtaCommands();
        await auth(tester);
        expect(
          calls.where((call) => call.method == 'getDeviceWiFiState'),
          hasLength(1),
        );
        await send(tester, '1.0.0');
        await bk(tester, '10', 0);
        await flush(tester, const Duration(seconds: 2));
        await bk(tester, '01', first.version);
        expect(runner.completed, 1);
        expect(runner.failureCount, 0);
        expect(
          calls.where((call) => call.method == 'authkeyConnect'),
          hasLength(1),
        );
      },
    );
  }

  for (final response in [
    (state: 0, result: '1'),
    (state: 1, result: '0'),
    (state: 0, result: null),
  ]) {
    bkTest('failed or incomplete authentication $response never unlocks OTA', (
      tester,
    ) async {
      await beginAuth(tester, 201);
      await auth(tester, state: response.state, result: response.result);
      expect(runner.failureCount, 1);
      expect(runner.isRunning, isFalse);
      expect(runner.lastFailure, contains('认证失败'));
      expectNoOtaCommands();
    });
  }

  bkTest('authentication timeout fails without issuing unauthed commands', (
    tester,
  ) async {
    await beginAuth(tester, 202);
    await flush(tester, const Duration(seconds: 9));
    expect(runner.completed, 0);
    expectNoOtaCommands();
    await flush(tester, const Duration(seconds: 1));
    expect(runner.failureCount, 1);
    expect(runner.lastFailure, contains('认证超时'));
    expectNoOtaCommands();
  });

  bkTest('late authentication after interruption cannot start OTA', (
    tester,
  ) async {
    await beginAuth(tester, 201);
    final interrupted = runner.interrupt();
    await flush(tester);
    await interrupted;
    await auth(tester);
    expect(runner.completed, 0);
    expect(runner.failureCount, 0);
    expectNoOtaCommands();
  });

  bkTest(
    'a Bluetooth restart authenticates again before verifying the new BK version',
    (tester) async {
      await beginAuth(tester, 202);
      await auth(tester);
      await send(tester, '1.0.0');
      await bk(tester, '10', 0);
      await emit(tester, {
        'cmd': 2,
        'data': {'connect_state': false, 'address': ''},
      });
      await flush(tester, const Duration(seconds: 2));
      await emit(tester, {
        'cmd': 1,
        'state': 0,
        'data': {...device, 'productType': 202},
      });
      await flush(tester, const Duration(seconds: 5));
      await connect(tester, 202);
      await flush(tester, const Duration(seconds: 2));
      await flush(tester, const Duration(seconds: 2));
      expect(
        calls.where((call) => call.method == 'authkeyConnect'),
        hasLength(2),
      );
      expect(
        calls.where((call) => call.method == 'getBKHDVersion'),
        hasLength(1),
      );
      await auth(tester);
      await flush(tester, const Duration(seconds: 2));
      expect(
        calls.where((call) => call.method == 'getBKHDVersion'),
        hasLength(2),
      );
      await bk(tester, '01', first.version);
      expect(runner.failureCount, 0);
      expect(runner.isRunning, isFalse);
    },
  );

  bkTest(
    'rejected reauthentication ends the round without reading an unauthenticated version',
    (tester) async {
      await beginAuth(tester, 201);
      await auth(tester);
      await send(tester, '1.0.0');
      await bk(tester, '10', 0);
      await emit(tester, {
        'cmd': 2,
        'data': {'connect_state': false, 'address': ''},
      });
      await flush(tester, const Duration(seconds: 2));
      await emit(tester, {
        'cmd': 1,
        'state': 0,
        'data': {...device, 'productType': 201},
      });
      await flush(tester, const Duration(seconds: 5));
      await connect(tester, 201);
      await flush(tester, const Duration(seconds: 2));
      await flush(tester, const Duration(seconds: 2));
      await auth(tester, result: '1');
      expect(runner.failureCount, 1);
      expect(runner.lastFailure, contains('认证失败'));
      expect(
        calls.where((call) => call.method == 'getBKHDVersion'),
        hasLength(1),
      );
      expect(runner.isRunning, isFalse);
    },
  );

  bkTest(
    'a disconnected authentication session cannot authorize the next connection',
    (tester) async {
      await beginAuth(tester, 201, attempts: 2);
      await emit(tester, {
        'cmd': 2,
        'data': {'connect_state': false, 'address': ''},
      });
      await flush(tester);
      expect(runner.failureCount, 1);
      await auth(tester);
      expectNoOtaCommands();
      await emit(tester, {
        'cmd': 1,
        'state': 0,
        'data': {...device, 'productType': 201},
      });
      await flush(tester, const Duration(seconds: 5));
      await connect(tester, 201);
      await flush(tester, const Duration(seconds: 2));
      expect(
        calls.where((call) => call.method == 'authkeyConnect'),
        hasLength(2),
      );
      expectNoOtaCommands();
      await auth(tester);
      await send(tester, '1.0.0');
      await bk(tester, '10', 0);
      await flush(tester, const Duration(seconds: 2));
      await bk(tester, '01', first.version);
      expect(runner.isRunning, isFalse);
      expect(runner.completed, 2);
      expect(runner.failureCount, 1);
    },
  );

  bkTest('version inputs preserve letters and request a text keyboard', (
    tester,
  ) async {
    await connect(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BkOtaAutomationModule(provider: provider, runner: runner),
        ),
      ),
    );
    for (final slot in [1, 2]) {
      final field = find.widgetWithText(TextFormField, '固件版本$slot');
      final input = tester.widget<TextField>(
        find.descendant(of: field, matching: find.byType(TextField)),
      );
      expect(input.keyboardType, TextInputType.text);
      expect(input.autocorrect, isFalse);
      expect(input.enableSuggestions, isFalse);
      await tester.enterText(field, 'V1.0.${slot}a-RC');
      expect(input.controller!.text, 'V1.0.${slot}a-RC');
    }
  });

  bkTest(
    'checks Wi-Fi, alternates files, serves HTTP and verifies each BK version',
    (tester) async {
      await begin(tester, attempts: 2);
      await wifi(tester, 0);
      expect(
        calls.where((call) => call.method == 'quickConnectDeviceWiFi'),
        hasLength(1),
      );
      expect(served, isEmpty);
      await wifi(tester, 4);
      expect(served, isEmpty);
      await send(tester, '1.0.1');
      expect(served, [second.path]);
      expect(
        calls.where((call) => call.method == 'setBK_UPGRADEHD').last.arguments,
        {'url': 'http://192.168.1.2:8080/firmware.bin'},
      );
      await bk(tester, '08', 0);
      await bk(tester, '09', 100);
      expect(runner.completed, 0);
      await bk(tester, '0A', 0);
      await flush(tester, const Duration(seconds: 2));
      await bk(tester, '01', '1.0.2');
      expect(runner.completed, 1);
      await send(tester, '1.0.2');
      await bk(tester, 8, '00', cmd: 40);
      await bk(tester, 10, '0', cmd: 40);
      await flush(tester, const Duration(seconds: 2));
      await bk(tester, 1, '1.0.1', cmd: 40);
      expect(runner.isRunning, isFalse);
      expect(runner.completed, 2);
      expect(runner.failureCount, 0);
      expect(served, [second.path, first.path]);
      expect(stops, greaterThanOrEqualTo(2));
      expect(report.toString(), contains('BK OTA自动化测试 - 重复2次'));
      expect(report.toString(), contains('成功 2 次，失败 0 次'));
      expect(calls.where((call) => call.method == 'authkeyConnect'), isEmpty);
    },
  );

  bkTest('rejects a URL failure and releases the HTTP server', (tester) async {
    await begin(tester);
    await send(tester, '1.0.1');
    await bk(tester, '08', '1');
    expect(runner.failureCount, 1);
    expect(runner.isRunning, isFalse);
    expect(stops, greaterThan(0));
    runner.clearResults();
    expect(runner.completed, 0);
    expect(runner.lastFailure, isNull);
  });

  bkTest(
    'Android decimal string verification types advance to version validation',
    (tester) async {
      await begin(tester);
      await send(tester, '1.0.0');
      await bk(tester, '10', '00');
      await flush(tester, const Duration(seconds: 2));
      await bk(tester, '01', first.version);
      expect(runner.completed, 1);
      expect(runner.failureCount, 0);
      expect(runner.isRunning, isFalse);
    },
  );

  bkTest('a file verification failure cannot count as a successful upgrade', (
    tester,
  ) async {
    await begin(tester);
    await send(tester, '1.0.0');
    await bk(tester, '09', 100);
    await bk(tester, '10', 1);
    expect(runner.failureCount, 1);
    expect(runner.failureCounts.keys.single, contains('文件验证失败'));
    expect(stops, greaterThan(0));
  });

  bkTest('unrelated BK version replies cannot fail a firmware download', (
    tester,
  ) async {
    await begin(tester);
    await send(tester, '1.0.0');
    await emit(tester, {
      'cmd': 40,
      'state': 1,
      'data': {'log': 'raw BK log'},
    });
    await bk(tester, '01', 'old version error', state: 1);
    expect(runner.isRunning, isTrue);
    expect(runner.failureCount, 0);
    await bk(tester, '0A', 0);
    await flush(tester, const Duration(seconds: 2));
    await bk(tester, '01', first.version);
    expect(runner.failureCount, 0);
    expect(runner.completed, 1);
  });

  bkTest(
    'a connected phone on the hotspot alone is not a ready TCP connection',
    (tester) async {
      await begin(tester);
      await wifi(tester, 4);
      await flush(tester, const Duration(seconds: 3));
      expect(
        calls.where((call) => call.method == 'quickConnectDeviceWiFi'),
        hasLength(1),
      );
      await flush(tester, const Duration(seconds: 35));
      expect(runner.failureCount, 1);
      expect(served, isEmpty);
      expect(calls.where((call) => call.method == 'setBK_UPGRADEHD'), isEmpty);
    },
  );

  bkTest('finishing download without verification times out after 20 seconds', (
    tester,
  ) async {
    await begin(tester);
    await send(tester, '1.0.0');
    await bk(tester, '09', 100);
    await flush(tester, const Duration(seconds: 19));
    expect(runner.completed, 0);
    await bk(tester, '09', 100);
    await flush(tester, const Duration(seconds: 1));
    expect(runner.failureCount, 1);
    expect(runner.lastFailure, contains('文件验证超时'));
    expect(stops, greaterThan(0));
  });

  bkTest(
    'reconnects Bluetooth after a verified upgrade before checking the version',
    (tester) async {
      await begin(tester);
      await send(tester, '1.0.0');
      await bk(tester, '0A', 0);
      await emit(tester, {
        'cmd': 2,
        'data': {'connect_state': false, 'address': ''},
      });
      await flush(tester, const Duration(seconds: 2));
      await emit(tester, {'cmd': 1, 'state': 0, 'data': device});
      await flush(tester, const Duration(seconds: 5));
      await connect(tester);
      await flush(tester, const Duration(seconds: 2));
      await flush(tester, const Duration(seconds: 2));
      await bk(tester, '01', '1.0.1');
      expect(runner.completed, 1);
      expect(runner.failureCount, 0);
    },
  );

  bkTest('old post-upgrade versions are polled until verification times out', (
    tester,
  ) async {
    await begin(tester);
    await send(tester, '1.0.0');
    await bk(tester, '0A', 0);
    await flush(tester, const Duration(seconds: 2));
    await bk(tester, '01', '1.0.0');
    expect(runner.completed, 0);
    await flush(tester, const Duration(seconds: 60));
    expect(runner.failureCount, 1);
    expect(runner.lastFailure, contains('校验固件版本超时'));
  });

  bkTest('interrupt releases HTTP without counting a failed round', (
    tester,
  ) async {
    await begin(tester);
    await send(tester, '1.0.1');
    final interrupted = runner.interrupt();
    await flush(tester);
    await interrupted;
    expect(runner.failureCount, 0);
    expect(runner.completed, 0);
    expect(stops, greaterThan(0));
    expect(report.toString(), contains('结果：中断'));
  });

  bkTest(
    'interrupting an HTTP startup prevents late URL sends and cleans up after startup',
    (tester) async {
      final release = Completer<String>();
      startHttp = (_) => release.future;
      await begin(tester);
      await wifi(tester, 2);
      await bk(tester, '01', '1.0.0');
      await flush(tester, const Duration(seconds: 2));
      expect(served, [first.path]);
      final interrupted = runner.interrupt();
      await flush(tester);
      await interrupted;
      expect(runner.isBusy, isTrue);
      expect(runner.canStart, isFalse);
      expect(calls.where((call) => call.method == 'setBK_UPGRADEHD'), isEmpty);
      final previousStops = stops;
      release.complete('http://192.168.1.2/late.bin');
      await flush(tester);
      expect(runner.isBusy, isFalse);
      expect(stops, greaterThan(previousStops));
      expect(calls.where((call) => call.method == 'setBK_UPGRADEHD'), isEmpty);
      expect(runner.failureCount, 0);
    },
  );

  bkTest(
    'a timed out HTTP startup stops remaining rounds until cleanup completes',
    (tester) async {
      final release = Completer<String>();
      startHttp = (_) => release.future;
      await begin(tester, attempts: 2);
      await wifi(tester, 2);
      await bk(tester, '01', '1.0.0');
      await flush(tester, const Duration(seconds: 2));
      await flush(tester, const Duration(minutes: 5));
      expect(runner.failureCount, 1);
      expect(runner.isRunning, isFalse);
      expect(runner.isBusy, isTrue);
      release.complete('http://192.168.1.2/late.bin');
      await flush(tester);
      expect(runner.isBusy, isFalse);
      expect(served, hasLength(1));
      expect(calls.where((call) => call.method == 'setBK_UPGRADEHD'), isEmpty);
    },
  );

  bkTest(
    'BK file picking validates extensions and runs using both staged firmware files',
    (tester) async {
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('soni-bk-pick-'),
      ))!;
      const paths = MethodChannel('plugins.flutter.io/path_provider');
      const picker = MethodChannel('miguelruivo.flutter.plugins.filepicker');
      var nextName = 'invalid.ufw';
      final selections = <MethodCall>[];
      for (final name in ['invalid.ufw', 'bin', 'first.bin', 'second.rbl']) {
        await tester.runAsync(
          () => File('${directory.path}/$name').writeAsBytes([1, 2, 3]),
        );
      }
      messenger.setMockMethodCallHandler(paths, (_) async => directory.path);
      messenger.setMockMethodCallHandler(picker, (call) async {
        selections.add(call);
        return [
          {'name': nextName, 'path': '${directory.path}/$nextName', 'size': 3},
        ];
      });
      try {
        await connect(tester);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: BkOtaAutomationModule(provider: provider, runner: runner),
            ),
          ),
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, '固件版本1'),
          first.version,
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, '固件版本2'),
          second.version,
        );
        await tester.tap(find.text('启动测试'));
        await flush(tester);
        expect(find.text('请选择两份固件文件'), findsOneWidget);
        Future<void> select(int slot) async {
          final button = tester.widget<TextButton>(
            find.widgetWithText(TextButton, '固件文件$slot'),
          );
          await tester.runAsync(() async => button.onPressed!());
          for (var frame = 0; frame < 100; frame++) {
            await flush(tester);
            if (tester
                    .widget<TextButton>(find.byType(TextButton).at(slot - 1))
                    .onPressed !=
                null) {
              return;
            }
          }
          fail('文件选择未完成');
        }

        await select(1);
        expect(find.text('固件文件1'), findsOneWidget);
        nextName = 'bin';
        await select(1);
        expect(find.text('固件文件1'), findsOneWidget);
        nextName = 'first.bin';
        await select(1);
        nextName = 'second.rbl';
        await select(2);
        expect(find.text('1 · first.bin'), findsOneWidget);
        expect(find.text('2 · second.rbl'), findsOneWidget);
        expect(selections.last.arguments['allowedExtensions'], ['bin', 'rbl']);
        await tester.tap(find.text('启动测试'));
        await flush(tester, const Duration(seconds: 2));
        await send(tester, first.version);
        expect(served.single, endsWith('/firmware.rbl'));
        expect(await tester.runAsync(() => File(served.single).readAsBytes()), [
          1,
          2,
          3,
        ]);
        final interrupted = runner.interrupt();
        await flush(tester);
        await interrupted;
        expect(runner.failureCount, 0);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await flush(tester);
        messenger.setMockMethodCallHandler(paths, null);
        messenger.setMockMethodCallHandler(picker, null);
        await tester.runAsync(() async {
          final deadline = DateTime.now().add(const Duration(seconds: 5));
          while ((await directory.list().toList()).any(
            (entry) =>
                entry is Directory &&
                entry.path.split('/').last.startsWith('soni_ota_test_'),
          )) {
            if (DateTime.now().isAfter(deadline)) fail('OTA临时固件未释放');
            await Future<void>.delayed(Duration.zero);
          }
          await directory.delete(recursive: true);
        });
      }
    },
  );

  bkTest(
    'changing targets while awaiting Wi-Fi never serves or sends firmware',
    (tester) async {
      await begin(tester);
      await connect(tester, 201);
      // The same address is still the same target; use a distinct address below.
      await emit(tester, {
        'cmd': 2,
        'data': {...device, 'address': 'other', 'connect_state': true},
      });
      await wifi(tester, 2);
      expect(runner.failureCount, 1);
      expect(served, isEmpty);
    },
  );

  bkTest('BK card matches the OTA form and locks other tests while running', (
    tester,
  ) async {
    await connect(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DemoTestPage(provider: provider, bkRunner: runner),
        ),
      ),
    );
    expect(find.text('BK OTA自动化测试'), findsOneWidget);
    final module = find.byType(BkOtaAutomationModule);
    expect(
      find.descendant(of: module, matching: find.text('固件文件1')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: module, matching: find.text('固件文件2')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: module, matching: find.byType(TextFormField)),
      findsNWidgets(3),
    );
    unawaited(runner.start(attempts: 1, first: first, second: second));
    await flush(tester);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '清空报告'))
          .onPressed,
      isNull,
    );
    final connectButton = find.descendant(
      of: find.byType(Scaffold).last,
      matching: find.byKey(const ValueKey('bluetooth-test-attempts')),
    );
    expect(tester.widget<TextField>(connectButton).enabled, isFalse);
    final interrupted = runner.interrupt();
    await flush(tester);
    await interrupted;
    expect(runner.isRunning, isFalse);
    await tester.pumpWidget(const SizedBox());
  });
}
