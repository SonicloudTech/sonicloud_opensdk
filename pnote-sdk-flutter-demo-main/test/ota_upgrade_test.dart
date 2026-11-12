import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soni_sdk_demo/provider_record_pen.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;
  const channel = MethodChannel('com.soni.soni_sdk_demo/recordPen');
  const events = MethodChannel('com.soni.soni_sdk_demo/eventChannel');
  const firmwarePath = '/tmp/update.ufw';
  final calls = <MethodCall>[];

  Future<void> emit(Map<String, dynamic> event) async {
    messenger.handlePlatformMessage(
      events.name,
      const StandardMethodCodec().encodeSuccessEnvelope(jsonEncode(event)),
      null,
    );
    await Future<void>.delayed(Duration.zero);
  }

  void otaTest(String name, Future<void> Function(RecordPenProvider) body) {
    test(name, () async {
      calls.clear();
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      messenger.setMockMethodCallHandler(events, (call) async => null);
      final provider = RecordPenProvider();
      try {
        await provider.init();
        await Future<void>.delayed(Duration.zero);
        calls.clear();
        await body(provider);
      } finally {
        binding.removeObserver(provider);
        provider.dispose();
        await provider.streamController.close();
        messenger.setMockMethodCallHandler(channel, null);
        messenger.setMockMethodCallHandler(events, null);
      }
    });
  }

  for (final prepareState in ['0', 0, '3', 3]) {
    otaTest(
      'OTA waits for approval $prepareState (${prepareState.runtimeType})',
      (provider) async {
        final upgrade = provider.requestAndSendOtaFile(firmwarePath);
        await Future<void>.delayed(Duration.zero);
        expect(calls.map((call) => call.method), ['requestDeviceGotoOtaMode']);

        await emit({
          'cmd': '18',
          'state': '0',
          'data': {'versionCode': '0001'},
        });
        expect(calls, hasLength(1));

        final approval = {
          'cmd': 19,
          'state': prepareState is String ? '0' : 0,
          'data': {'prepareState': prepareState},
        };
        final approvalStatus = provider.streamController.stream.firstWhere(
          (event) => event.containsKey('是否可以升级'),
        );
        final upgradeCompleted = expectLater(upgrade, completes);
        await emit(approval);
        await upgradeCompleted;
        expect(await approvalStatus, {'是否可以升级': '可以'});
        await emit(approval);
        expect(calls.map((call) => call.method), [
          'requestDeviceGotoOtaMode',
          'sendOtaFile',
        ]);
        expect(calls.last.arguments, {'filePath': firmwarePath});
      },
    );
  }

  final failures = [
    {
      'state': '0',
      'data': {'prepareState': '1'},
    },
    {
      'state': 0,
      'data': {'prepareState': 2},
    },
    {
      'state': '1',
      'data': {'prepareState': '0'},
    },
    {'state': '0', 'data': <String, dynamic>{}},
    {'state': '0', 'data': null},
  ];
  for (var index = 0; index < failures.length; index++) {
    otaTest('OTA rejects unsuccessful or incomplete approval $index', (
      provider,
    ) async {
      final result = expectLater(
        provider.requestAndSendOtaFile(firmwarePath),
        throwsStateError,
      );
      await Future<void>.delayed(Duration.zero);
      await emit({'cmd': '19', ...failures[index]});
      await result;
      expect(calls.map((call) => call.method), ['requestDeviceGotoOtaMode']);
    });
  }

  otaTest('OTA timeout ignores late approval and allows a fresh request', (
    provider,
  ) async {
    final result = expectLater(
      provider.requestAndSendOtaFile(
        firmwarePath,
        timeout: const Duration(seconds: 1),
      ),
      throwsA(isA<TimeoutException>()),
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(const Duration(seconds: 1));
    await result;
    final approval = {
      'cmd': '19',
      'state': '0',
      'data': {'prepareState': '0'},
    };
    await emit(approval);
    expect(calls, hasLength(1));

    final retry = provider.requestAndSendOtaFile(firmwarePath);
    await Future<void>.delayed(Duration.zero);
    await emit(approval);
    await retry;
    expect(calls.map((call) => call.method), [
      'requestDeviceGotoOtaMode',
      'requestDeviceGotoOtaMode',
      'sendOtaFile',
    ]);
  });

  otaTest('OTA native request failure never sends firmware', (provider) async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      throw PlatformException(code: 'REQUEST_FAILED');
    });
    final result = expectLater(
      provider.requestAndSendOtaFile(firmwarePath),
      throwsA(isA<PlatformException>()),
    );
    await Future<void>.delayed(Duration.zero);
    await result;
    await emit({
      'cmd': '19',
      'state': '0',
      'data': {'prepareState': '0'},
    });
    expect(calls.map((call) => call.method), ['requestDeviceGotoOtaMode']);
  });

  otaTest('cancelling OTA ignores late approval and allows the next request', (
    provider,
  ) async {
    final cancelled = expectLater(
      provider.requestAndSendOtaFile(firmwarePath),
      throwsStateError,
    );
    await Future<void>.delayed(Duration.zero);
    await provider.cancelOtaTransfer();
    await cancelled;
    final approval = {'cmd': 19, 'state': 0, 'data': {'prepareState': 3}};
    await emit(approval);
    expect(calls.where((call) => call.method == 'sendOtaFile'), isEmpty);
    final next = provider.requestAndSendOtaFile(firmwarePath);
    await emit(approval);
    await next;
    expect(calls.where((call) => call.method == 'sendOtaFile'), hasLength(1));
  });

  otaTest('overlapping OTA requests cannot use the same approval', (
    provider,
  ) async {
    final manual = provider.requestAndSendOtaFile(firmwarePath);
    await expectLater(
      provider.requestAndSendOtaFile(firmwarePath),
      throwsStateError,
    );
    await emit({
      'cmd': 19,
      'state': 0,
      'data': {'prepareState': 3},
    });
    await manual;
    await expectLater(
      provider.requestAndSendOtaFile(firmwarePath),
      throwsStateError,
    );

    await emit({
      'cmd': 21,
      'state': 0,
      'data': {'receiveState': 0},
    });
    final retry = provider.requestAndSendOtaFile(firmwarePath);
    await emit({'cmd': 19, 'state': 0, 'data': {'prepareState': 3}});
    await retry;
    expect(calls.map((call) => call.method), [
      'requestDeviceGotoOtaMode',
      'sendOtaFile',
      'requestDeviceGotoOtaMode',
      'sendOtaFile',
    ]);
  });
}
