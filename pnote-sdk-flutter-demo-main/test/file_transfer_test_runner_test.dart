import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soni_sdk_demo/demo_theme.dart';
import 'package:soni_sdk_demo/file_transfer_test/file_transfer_test_module.dart';
import 'package:soni_sdk_demo/file_transfer_test/file_transfer_test_runner.dart';
import 'package:soni_sdk_demo/provider_record_pen.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;
  const channel = MethodChannel('com.soni.soni_sdk_demo/recordPen');
  const events = MethodChannel('com.soni.soni_sdk_demo/eventChannel');
  final calls = <MethodCall>[];
  var report = StringBuffer();

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

  Future<void> list(WidgetTester tester) => emit(tester, {
    'cmd': 4,
    'state': '0',
    'finish': 1,
    'data': [
      {'name': 'a.opus', 'size': 2048, 'time': 1},
      {'name': 'b.opus', 'size': 4096, 'time': 2},
    ],
  });

  Future<void> result(WidgetTester tester, String name, int state) =>
      emit(tester, {
        'cmd': 5,
        'state': 0,
        'data': {'name': name, 'record_file_state': state},
      });

  Future<void> audio(WidgetTester tester, int bytes) async {
    await messenger.handlePlatformMessage(
      events.name,
      const StandardMethodCodec().encodeSuccessEnvelope({
        'audioType': AudioDataType.file,
        'audio': Uint8List(bytes),
      }),
      (_) {},
    );
    await flush(tester);
  }

  Iterable<MethodCall> transfers() =>
      calls.where((call) => call.method == 'startGetFile');

  void transferTest(
    String name,
    Future<void> Function(
      WidgetTester,
      RecordPenProvider,
      FileTransferTestRunner,
    )
    body, {
    int type = 48,
    bool nameOnly = false,
  }) {
    testWidgets(name, (tester) async {
      calls.clear();
      report = StringBuffer();
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'getPhoneInfo') {
          return {
            'model': 'Google Pixel 9',
            'systemName': 'Android',
            'systemVersion': '16',
          };
        }
        return null;
      });
      messenger.setMockMethodCallHandler(events, (_) async => null);
      final provider = RecordPenProvider();
      await provider.init();
      final runner = FileTransferTestRunner(provider, onReport: report.write);
      try {
        await emit(tester, {
          'cmd': 2,
          'data': {
            'connect_state': 1,
            'name': 'Pen',
            if (!nameOnly) 'address': 'test-device',
            'productType': type,
          },
        });
        await body(tester, provider, runner);
      } finally {
        runner.dispose();
        provider.stopAutoConnect();
        await tester.pump(const Duration(seconds: 5));
        await tester.pump(const Duration(milliseconds: 100));
        binding.removeObserver(provider);
        provider.dispose();
        await provider.streamController.close();
        messenger.setMockMethodCallHandler(channel, null);
        messenger.setMockMethodCallHandler(events, null);
      }
    });
  }

  for (final fileName in <String?>[null, 'a.opus']) {
    transferTest(
      '${fileName ?? "all files"} waits two seconds between transfers',
      (tester, provider, runner) async {
        final run = runner.start(fileName: fileName, repetitions: 2);
        await list(tester);
        expect(transfers(), hasLength(1));
        await audio(tester, 2048);
        await result(tester, 'a.opus', 0);
        await flush(tester, const Duration(milliseconds: 1999));
        expect(transfers(), hasLength(1));
        expect(runner.isRunning, isTrue);
        await flush(tester, const Duration(milliseconds: 1));
        expect(transfers(), hasLength(2));
        final nextName = fileName ?? 'b.opus';
        await audio(tester, fileName == null ? 4096 : 2048);
        await result(tester, nextName, 0);
        await run;
        expect(runner.isRunning, isFalse);
        expect(runner.successes, 2);
      },
    );
  }

  transferTest('interrupt cancels the interval before the next transfer', (
    tester,
    provider,
    runner,
  ) async {
    final run = runner.start(fileName: 'a.opus', repetitions: 2);
    await list(tester);
    await audio(tester, 2048);
    await result(tester, 'a.opus', 0);
    final stopping = runner.interrupt();
    await flush(tester);
    expect(runner.isRunning, isFalse);
    await stopping;
    await run;
    await flush(tester, const Duration(seconds: 2));
    expect(transfers(), hasLength(1));
    expect(runner.failureCount, 0);
    expect(provider.audioDecodeAndStoreEnabled, isTrue);
  });

  for (final type in [1, 48, 202, 999]) {
    transferTest(
      'type $type transfers all files sequentially without decoding',
      (tester, provider, runner) async {
        final run = runner.start();
        await flush(tester);
        expect(provider.audioDecodeAndStoreEnabled, isFalse);
        await list(tester);
        expect(transfers().single.arguments, {
          'fileName': 'a.opus',
          'offset': 0,
        });
        await result(tester, 'unrelated.opus', 0);
        expect(runner.completed, 0);
        await messenger.handlePlatformMessage(
          events.name,
          const StandardMethodCodec().encodeSuccessEnvelope({
            'audioType': AudioDataType.file,
            'audio': Uint8List(2048),
          }),
          (_) {},
        );
        await flush(tester);
        expect(provider.audioReceivedBytes(AudioDataType.file), 2048);
        await result(tester, 'a.opus', 0);
        await flush(tester, const Duration(seconds: 2));
        expect(transfers().last.arguments['fileName'], 'b.opus');
        await audio(tester, 4096);
        await result(tester, 'b.opus', 0);
        await run;
        expect(runner.completed, 2);
        expect(runner.successes, 2);
        expect(provider.audioDecodeAndStoreEnabled, isTrue);
        expect(report.toString(), startsWith('\n\n（'));
        expect(
          report.toString(),
          contains('） 手机：Google Pixel 9 · 系统：Android 16\n'),
        );
        expect(report.toString(), contains('全部文件传输测试\n'));
        expect(report.toString(), contains('文件总大小：6.0KB'));
        expect(report.toString(), contains('1/2 结果：成功'));
        expect(report.toString(), contains('2/2 结果：成功'));
        expect(report.toString(), contains('累计接收：6.0KB'));
        expect(report.toString(), contains('总耗时：'));
      },
      type: type,
      nameOnly: type == 1,
    );
  }

  transferTest(
    'completed transfers fail size validation and report exact received and target bytes',
    (tester, provider, runner) async {
      final run = runner.start(fileName: 'a.opus', repetitions: 3);
      await list(tester);
      for (final count in [888, 2048, 2050]) {
        if (count != 888) await flush(tester, const Duration(seconds: 2));
        await messenger.handlePlatformMessage(events.name,
          const StandardMethodCodec().encodeSuccessEnvelope({
            'audioType': AudioDataType.file, 'audio': Uint8List(count),
          }), (_) {});
        await flush(tester);
        await result(tester, 'a.opus', 0);
      }
      await run;
      expect(runner.successes, 1);
      expect(runner.failureCounts, {'文件大小不一致': 2});
      expect(report.toString(), contains('收到：888/目标：2048'));
      expect(report.toString(), contains('收到：2048/目标：2048'));
      expect(report.toString(), contains('收到：2050/目标：2048'));
      expect(report.toString(), contains('1/3 结果：失败 失败原因：文件大小不一致'));
      expect(report.toString(), contains('2/3 结果：成功'));
    },
  );

  transferTest(
    'unknown file sizes are reported as unverified instead of successful empty files',
    (tester, provider, runner) async {
      final run = runner.start(fileName: 'a.opus');
      await emit(tester, {
        'cmd': 4, 'state': 0, 'finish': 1,
        'data': [{'name': 'a.opus', 'time': 1}],
      });
      await result(tester, 'a.opus', 0);
      await run;
      expect(runner.successes, 0);
      expect(runner.failureCounts, {'无法校验文件大小': 1});
      expect(report.toString(), contains('收到：0/目标：未知'));
      expect(report.toString(), contains('文件大小未校验'));
    },
  );

  transferTest(
    'a zero-byte file passes size validation without data packets',
    (tester, provider, runner) async {
      final run = runner.start(fileName: 'a.opus');
      await emit(tester, {
        'cmd': 4, 'state': 0, 'finish': 1,
        'data': [{'name': 'a.opus', 'size': 0, 'time': 0}],
      });
      await result(tester, 'a.opus', 0);
      await run;
      expect(runner.successes, 1);
      expect(runner.failureCounts, isEmpty);
      expect(report.toString(), contains('收到：0/目标：0'));
      expect(report.toString(), contains('文件大小校验通过'));
    },
  );

  transferTest(
    'single-file button only transfers the selected file after list changes',
    (tester, provider, runner) async {
      final refresh = runner.refreshFiles();
      await list(tester);
      await refresh;
      await tester.pumpWidget(MaterialApp(
        theme: createDemoTheme(),
        home: Scaffold(body: FileTransferTestModule(provider: provider, runner: runner)),
      ));
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(provider.recordFiles.first.displayLabel).last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '3');
      await tester.tap(find.text('单文件重复传输测试'));
      await flush(tester);
      await emit(tester, {
        'cmd': 4, 'state': '0', 'finish': 0,
        'data': [{'name': 'b.opus', 'size': 4096, 'time': 2}],
      });
      await list(tester);
      for (var index = 0; index < 3; index++) {
        if (index > 0) await flush(tester, const Duration(seconds: 2));
        expect(transfers().last.arguments['fileName'], 'a.opus');
        await audio(tester, 2048);
        await result(tester, 'a.opus', 0);
      }
      expect(transfers().map((call) => call.arguments['fileName']),
          ['a.opus', 'a.opus', 'a.opus']);
      expect(runner.total, 3);
      expect(report.toString(), contains('单文件重复传输测试 - 重复3次 - a.opus'));
      expect(report.toString(), isNot(contains('全部文件传输测试')));
      await tester.pumpWidget(const SizedBox());
    },
  );

  transferTest(
    'clearing transfer results resets history and keeps the selected files available',
    (tester, provider, runner) async {
      final run = runner.start(fileName: 'a.opus', repetitions: 2);
      await list(tester);
      await result(tester, 'a.opus', 1);
      await flush(tester, const Duration(seconds: 2));
      await audio(tester, 2048);
      await result(tester, 'a.opus', 0);
      await run;
      expect(runner.completed, 2);
      expect(runner.failureCount, 1);
      runner.clearResults();
      expect(runner.completed, 0);
      expect(runner.total, 0);
      expect(runner.successes, 0);
      expect(runner.failureCounts, isEmpty);
      expect(runner.status, '等待开始');
      expect(runner.speedSummary, '当前 --，最低 --，最高 --');
      expect(runner.averageRate, '--');
      expect(runner.files.map((file) => file.name), ['a.opus', 'b.opus']);
      expect(runner.canStart, isTrue);
    },
  );

  transferTest(
    'repeated transfers use the requested count and group failures',
    (tester, provider, runner) async {
      final run = runner.start(fileName: 'a.opus', repetitions: 3);
      await list(tester);
      await result(tester, 'a.opus', 1);
      await flush(tester, const Duration(seconds: 2));
      await result(tester, 'a.opus', 1);
      await flush(tester, const Duration(seconds: 2));
      await audio(tester, 2048);
      await result(tester, 'a.opus', 0);
      await run;
      expect(transfers(), hasLength(3));
      expect(
        transfers().map((call) => call.arguments['offset']),
        everyElement(0),
      );
      expect(runner.completed, 3);
      expect(runner.successes, 1);
      expect(runner.failureCounts, {'文件不存在': 2});
      expect(report.toString(), contains('单文件重复传输测试 - 重复3次 - a.opus - 2.0KB'));
      expect(report.toString(), contains('1/3 结果：失败 失败原因：文件不存在'));
      expect(report.toString(), contains('3/3 结果：成功'));
      expect(report.toString(), contains('平均速度：'));
      expect(report.toString(), contains('最高速度：'));
      expect(report.toString(), contains('最低速度：'));
    },
  );

  transferTest('interrupt stops the active transfer and restores storage', (
    tester,
    provider,
    runner,
  ) async {
    final run = runner.start(fileName: 'a.opus', repetitions: 3);
    await list(tester);
    final stopping = runner.interrupt();
    await flush(tester);
    expect(calls.where((call) => call.method == 'stopGetFile'), hasLength(1));
    await result(tester, 'a.opus', 3);
    await stopping;
    await run;
    expect(transfers(), hasLength(1));
    expect(runner.failureCount, 0);
    expect(provider.audioDecodeAndStoreEnabled, isTrue);
    expect(report.toString(), contains('1/3 结果：中断'));
  });

  transferTest('interrupt prevents a queued transfer from starting later', (
    tester,
    provider,
    runner,
  ) async {
    final release = Completer<void>();
    final delayed = FileTransferTestRunner(
      provider,
      onReport: report.write,
      startTransfer: (name, canSend) async {
        await release.future;
        if (canSend()) await provider.sendFileFromPenToPhoneWithOffset(name, 0);
      },
    );
    try {
      await audio(tester, 1234);
      final run = delayed.start(fileName: 'a.opus', repetitions: 2);
      await list(tester);
      final stopping = delayed.interrupt();
      await flush(tester);
      release.complete();
      await stopping;
      await run;
      expect(transfers(), isEmpty);
      expect(delayed.failureCount, 0);
      expect(report.toString(), contains('收到：0/目标：2048'));
      expect(provider.audioDecodeAndStoreEnabled, isTrue);
    } finally {
      if (!release.isCompleted) release.complete();
      delayed.dispose();
    }
  });

  transferTest('an unknown stop reply requires the disconnect fallback', (
    tester,
    provider,
    runner,
  ) async {
    final run = runner.start(fileName: 'a.opus', repetitions: 2);
    await list(tester);
    final stopping = runner.interrupt();
    await flush(tester);
    await result(tester, 'a.opus', 99);
    await flush(tester, const Duration(seconds: 4));
    expect(calls.where((call) => call.method == 'close'), isEmpty);
    await flush(tester, const Duration(seconds: 1));
    await stopping;
    await run;
    expect(calls.where((call) => call.method == 'close'), hasLength(1));
    expect(provider.audioDecodeAndStoreEnabled, isTrue);
  });

  transferTest(
    'disconnect ends the run but retains the file snapshot and statistics',
    (tester, provider, runner) async {
      final run = runner.start();
      await list(tester);
      await audio(tester, 2048);
      await result(tester, 'a.opus', 0);
      await emit(tester, {
        'cmd': 2,
        'data': {'connect_state': 0, 'address': 'null'},
      });
      await run;
      expect(runner.files.map((file) => file.name), ['a.opus', 'b.opus']);
      expect(runner.successes, 1);
      expect(runner.failureCount, 1);
      expect(provider.audioDecodeAndStoreEnabled, isTrue);
    },
  );
}
