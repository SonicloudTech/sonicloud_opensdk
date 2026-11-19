import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soni_sdk_demo/demo_test_page.dart';
import 'package:soni_sdk_demo/bluetooth_connection_test/bluetooth_connection_test_runner.dart';
import 'package:soni_sdk_demo/demo_theme.dart';
import 'package:soni_sdk_demo/file_transfer_test/file_transfer_test_runner.dart';
import 'package:soni_sdk_demo/ota_automation/ota_automation_runner.dart';
import 'package:soni_sdk_demo/provider_record_pen.dart';
import 'package:soni_sdk_demo/test_report.dart';

void main() {
  testWidgets(
    'clear report removes all test histories before a single-file run',
    (tester) async {
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('soni-clear-page-'),
      ))!;
      final reports = TestReportStore(directory: () async => directory);
      final messenger = tester.binding.defaultBinaryMessenger;
      const channel = MethodChannel('com.soni.soni_sdk_demo/recordPen');
      const events = MethodChannel('com.soni.soni_sdk_demo/eventChannel');
      const paths = MethodChannel('plugins.flutter.io/path_provider');
      final transfers = <String>[];
      final sharedFiles = <File>[];
      final sharedTexts = <String>[];
      messenger.setMockMethodCallHandler(paths, (_) async => directory.path);
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'startGetFile') {
          transfers.add(call.arguments['fileName'] as String);
        }
        if (call.method == 'shareFile') {
          final snapshot = File(call.arguments['path'] as String);
          sharedFiles.add(snapshot);
          sharedTexts.add(snapshot.readAsStringSync());
          return true;
        }
        return null;
      });
      messenger.setMockMethodCallHandler(events, (_) async => null);
      final provider = RecordPenProvider();
      await provider.init();
      // Real file I/O must finish outside the widget test's fake clock.
      void append(String text) => Zone.root.run(() => reports.append(text));
      final ota = OtaAutomationRunner(provider, onReport: append);
      final bluetooth = BluetoothConnectionTestRunner(provider, onReport: append);
      final transfer = FileTransferTestRunner(
        provider,
        onReport: append,
      );

      Future<void> flush([Duration? duration]) async {
        await tester.pump(duration);
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump();
      }

      Future<void> share() async {
        final button = tester.widget<TextButton>(
          find.ancestor(
            of: find.text('分享报告'),
            matching: find.byWidgetPredicate((widget) => widget is TextButton),
          ),
        );
        await tester.runAsync(() async {
          await (button.onPressed! as Future<void> Function())();
        });
        await flush();
      }

      Future<void> emit(Map<String, dynamic> event) async {
        await messenger.handlePlatformMessage(
          events.name,
          const StandardMethodCodec().encodeSuccessEnvelope(jsonEncode(event)),
          (_) {},
        );
        await flush();
      }

      Future<void> files() => emit({
        'cmd': 4,
        'state': 0,
        'finish': 1,
        'data': [
          {'name': 'a.opus', 'size': 2048, 'time': 1},
          {'name': 'b.opus', 'size': 4096, 'time': 2},
        ],
      });

      Future<void> result(String name, int state) => emit({
        'cmd': 5,
        'state': 0,
        'data': {'name': name, 'record_file_state': state},
      });

      Future<void> audio(int bytes) async {
        await messenger.handlePlatformMessage(
          events.name,
          const StandardMethodCodec().encodeSuccessEnvelope({
            'audioType': AudioDataType.file,
            'audio': Uint8List(bytes),
          }),
          (_) {},
        );
        await flush();
      }

      try {
        await emit({
          'cmd': 2,
          'data': {
            'connect_state': 1,
            'name': 'Pen',
            'address': 'device',
            'productType': 48,
          },
        });
        final otaRun = ota.start(
          attempts: 1,
          first: (path: '/tmp/first.ufw', version: '1.0.1'),
          second: (path: '/tmp/second.ufw', version: '1.0.2'),
        );
        await flush(const Duration(seconds: 2));
        await emit({
          'cmd': 17,
          'state': 0,
          'data': {'version': '1.0.1'},
        });
        await flush(const Duration(seconds: 2));
        await emit({
          'cmd': 19,
          'state': 0,
          'data': {'prepareState': 1},
        });
        await otaRun;
        final allRun = transfer.start();
        await files();
        await result('a.opus', 1);
        await flush(const Duration(seconds: 2));
        await audio(4096);
        await result('b.opus', 0);
        await allRun;
        await tester.runAsync(reports.fileForSharing);
        expect(ota.failureCount, 1);
        expect(transfer.completed, 2);
        final bluetoothRun = bluetooth.start(attempts: 1, reconnectInterval: Duration.zero);
        await flush();
        await emit({'cmd': 2, 'data': {'connect_state': 0, 'address': ''}});
        await emit({'cmd': 1, 'state': 0, 'data': {'name': 'Pen', 'address': 'device', 'productType': 48}});
        await emit({'cmd': 2, 'data': {'connect_state': 1, 'name': 'Pen', 'address': 'device', 'productType': 48}});
        await bluetoothRun;
        expect(bluetooth.successes, 1);

        await tester.pumpWidget(
          MaterialApp(
            theme: createDemoTheme(),
            home: Scaffold(
              body: DemoTestPage(
                provider: provider,
                runner: ota,
                transferRunner: transfer,
                bluetoothRunner: bluetooth,
                reportStore: reports,
              ),
            ),
          ),
        );
        await share();
        expect(sharedTexts.single, contains('全部文件传输测试'));
        expect(sharedTexts.single, contains('杰理OTA自动化测试'));
        expect(sharedTexts.single, contains('设备蓝牙连接测试'));
        expect(sharedTexts.single, contains('成功 1 次，失败 0 次'));
        await tester.runAsync(() async {
          await tester.tap(find.text('清空报告'));
          expect(await reports.fileForSharing(), isNull);
        });
        await flush();
        expect(ota.completed, 0);
        expect(ota.failureCounts, isEmpty);
        expect(ota.lastFailure, isNull);
        expect(ota.upgradeDirection, isNull);
        expect(transfer.completed, 0);
        expect(transfer.successes, 0);
        expect(transfer.failureCounts, isEmpty);
        expect(bluetooth.completed, 0);
        expect(bluetooth.total, 0);
        expect(bluetooth.successes, 0);
        expect(bluetooth.failureCount, 0);
        expect(find.text('成功 0 次 · 失败 0 次'), findsNWidgets(2));
        expect(find.text('失败次数 0'), findsOneWidget);
        await share();
        expect(sharedFiles, hasLength(1));

        transfers.clear();
        await tester.tap(find.text('单文件重复传输测试'));
        await flush();
        await files();
        await audio(4096);
        await result('b.opus', 0);
        expect(transfers, ['b.opus']);
        final text = await tester.runAsync(() async {
          final file = await reports.fileForSharing();
          return file!.readAsString();
        });
        expect(text, contains('单文件重复传输测试 - 重复1次 - b.opus'));
        expect(text, isNot(contains('全部文件传输测试')));
        expect(text, isNot(contains('杰理OTA自动化测试')));
        expect(text, isNot(contains('设备蓝牙连接测试')));
        expect(text, isNot(contains('文件不存在')));
        await share();
        expect(sharedTexts, hasLength(2));
        expect(sharedTexts.last, text);
        expect(sharedTexts.last, isNot(sharedTexts.first));
        expect(sharedFiles.last.uri.pathSegments.last,
            isNot(sharedFiles.first.uri.pathSegments.last));
        expect(await tester.runAsync(sharedFiles.first.readAsString), sharedTexts.first);
        expect(sharedFiles.last.uri.pathSegments.last, startsWith('自动化测试报告_'));
        expect(sharedFiles.last.uri.pathSegments.last, endsWith('.txt'));

        await tester.tap(find.text('全部文件传输测试'));
        await flush();
        await files();
        await audio(2048);
        await result('a.opus', 0);
        await flush(const Duration(seconds: 2));
        await audio(4096);
        await result('b.opus', 0);
        await share();
        expect(sharedTexts, hasLength(3));
        expect(sharedTexts.last, startsWith(sharedTexts[1]));
        expect(sharedTexts.last, contains('全部文件传输测试'));
        expect(sharedTexts.last, isNot(contains('杰理OTA自动化测试')));
        expect(sharedFiles.map((file) => file.uri.pathSegments.last).toSet(), hasLength(3));
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        bluetooth.dispose();
        transfer.dispose();
        ota.dispose();
        provider.stopAutoConnect();
        await flush(const Duration(seconds: 5));
        await flush(const Duration(milliseconds: 50));
        await flush(const Duration(milliseconds: 50));
        tester.binding.removeObserver(provider);
        provider.dispose();
        await provider.streamController.close();
        reports.dispose();
        messenger.setMockMethodCallHandler(channel, null);
        messenger.setMockMethodCallHandler(events, null);
        messenger.setMockMethodCallHandler(paths, null);
        await tester.runAsync(() => directory.delete(recursive: true));
      }
    },
  );
}
