import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soni_sdk_demo/provider_record_pen.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;
  const channel = MethodChannel('com.soni.soni_sdk_demo/recordPen');
  const events = MethodChannel('com.soni.soni_sdk_demo/eventChannel');
  final calls = <MethodCall>[];

  Future<void> emit(WidgetTester tester, Map<String, dynamic> event) async {
    await messenger.handlePlatformMessage(
      events.name,
      const StandardMethodCodec().encodeSuccessEnvelope(jsonEncode(event)),
      (_) {},
    );
    await tester.pump();
  }

  Map<String, dynamic> connection(String address, [dynamic state = 'true']) => {
    'cmd': 2,
    'data': {'connect_state': state, 'name': 'CB08', 'address': address},
  };

  Future<void> loadFiles(
    WidgetTester tester,
    RecordPenProvider provider,
  ) async {
    await emit(tester, {
      'cmd': 4,
      'finish': 1,
      'data': [
        {'name': 'a.opus', 'size': 40, 'time': 1},
        {'name': 'b.opus', 'size': 80, 'time': 2},
      ],
    });
    provider.setTransFileName('b.opus');
  }

  void connectionTest(
    String name,
    Future<void> Function(WidgetTester, RecordPenProvider) body,
  ) {
    testWidgets(name, (tester) async {
      calls.clear();
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      messenger.setMockMethodCallHandler(events, (call) async => null);
      final provider = RecordPenProvider();
      try {
        await provider.init();
        await tester.pump();
        await body(tester, provider);
      } finally {
        provider.stopAutoConnect();
        // Drain connection initialization and reconnect timers in fake time.
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

  connectionTest('iOS empty address uses the selected device among equal names', (
    tester,
    provider,
  ) async {
    for (final address in ['device-a', 'device-b']) {
      await emit(tester, {
        'cmd': 1,
        'state': 0,
        'data': {'name': 'CB08', 'address': address, 'productType': 48},
      });
    }
    await provider.connect(provider.discoveredDevices.last);
    await emit(tester, {
      'cmd': 2,
      'data': {'connect_state': '1', 'name': 'CB08', 'address': ''},
    });
    expect(provider.deviceInfo?['address'], 'device-b');
    expect(provider.deviceType, 48);
    await loadFiles(tester, provider);
    await emit(tester, connection('device-b'));
    expect(provider.recordFileNames, ['a.opus', 'b.opus']);
    expect(provider.transFileName, 'b.opus');
  });

  connectionTest('same-device success preserves files and selection', (
    tester,
    provider,
  ) async {
    await emit(tester, connection('C8:47:8C:44:D6:D2'));
    await loadFiles(tester, provider);
    calls.clear();
    for (final state in ['true', true, '1', 1]) {
      await emit(tester, connection('c8:47:8c:44:d6:d2', state));
      expect(provider.recordFileNames, ['a.opus', 'b.opus']);
      expect(provider.transFileName, 'b.opus');
      expect(provider.isConnected, isTrue);
    }
    expect(calls.where((call) => call.method == 'stopSearch'), isEmpty);
  });

  for (final (state, address) in <(Object, String?)>[
    (0, 'null'),
    ('0', null),
    (false, 'device-a'),
    ('false', ''),
  ]) {
    connectionTest('disconnect ${state.runtimeType}:$state/${address ?? "missing"} immediately clears device selection caches', (
      tester,
      provider,
    ) async {
      for (final address in ['device-a', 'device-b']) {
        await emit(tester, {
          'cmd': 1, 'state': 0,
          'data': {'name': 'CB08', 'address': address, 'productType': 48},
        });
      }
      await provider.connect(provider.discoveredDevices.first);
      await emit(tester, connection('device-a'));
      await loadFiles(tester, provider);
      expect(provider.discoveredDevices, hasLength(2));
      final snapshots = <List<Object?>>[];
      void observeDisconnect() {
        if (!provider.isConnected) {
          snapshots.add([
            provider.discoveredDevices.length,
            provider.deviceMap,
            provider.deviceName,
            provider.deviceAddress,
          ]);
        }
      }
      provider.addListener(observeDisconnect);
      try {
        await emit(tester, {
          'cmd': 2,
          'data': {'connect_state': state, if (address != null) 'address': address},
        });
        expect(provider.isConnected, isFalse);
        expect(provider.deviceInfo, isNull);
        expect(provider.discoveredDevices, isEmpty);
        expect(provider.deviceMap, isNull);
        expect(provider.deviceName, isEmpty);
        expect(provider.deviceAddress, isEmpty);
        expect(provider.recordFiles, isEmpty);
        expect(provider.transFileName, isEmpty);
        expect(snapshots, isNotEmpty);
        expect(snapshots, everyElement([0, null, '', '']));
      } finally {
        provider.removeListener(observeDisconnect);
      }
      await provider.startSearch();
      await emit(tester, {
        'cmd': 1, 'state': 0,
        'data': {'name': 'New pen', 'address': 'device-c', 'productType': 202},
      });
      expect(provider.discoveredDevices.single['address'], 'device-c');
    });
  }

  connectionTest('disconnect does not scan after five seconds and manual search still works', (
    tester,
    provider,
  ) async {
    await emit(tester, connection('device-a'));
    await emit(tester, connection('device-a', 'false'));
    await tester.pump(const Duration(seconds: 6));
    expect(calls.where((call) => call.method == 'startSearch'), isEmpty);
    await provider.startSearch();
    expect(calls.where((call) => call.method == 'startSearch'), hasLength(1));
  });

  connectionTest('unexpected disconnect stops SDK reconnect and rejects its later scan results', (
    tester,
    provider,
  ) async {
    await emit(tester, {
      'cmd': 1, 'state': 0,
      'data': {'name': 'CB08', 'address': 'device-a', 'productType': 48},
    });
    await provider.connect(provider.discoveredDevices.single);
    await emit(tester, connection('device-a'));
    calls.clear();
    await emit(tester, connection('device-a', false));
    expect(calls.where((call) => call.method == 'close'), hasLength(1));
    expect(calls.where((call) => call.method == 'stopSearch'), hasLength(1));
    await emit(tester, connection('device-a', false));
    expect(calls.where((call) => call.method == 'close'), hasLength(1));
    await tester.pump(const Duration(seconds: 6));
    await emit(tester, {
      'cmd': 1, 'state': 0,
      'data': {'name': 'CB08', 'address': 'device-a', 'productType': 48},
    });
    await emit(tester, {'cmd': 6, 'data': {'cbc': 80}});
    expect(provider.isConnected, isFalse);
    expect(provider.deviceInfo, isNull);
    expect(provider.discoveredDevices, isEmpty);
    expect(provider.deviceMap, isNull);
    expect(provider.cbc, '-1');
    expect(calls.where((call) => call.method == 'startSearch'), isEmpty);
    await provider.startSearch();
    await emit(tester, {
      'cmd': 1, 'state': 0,
      'data': {'name': 'New pen', 'address': 'device-b', 'productType': 202},
    });
    expect(provider.discoveredDevices.single['address'], 'device-b');
  });

  connectionTest('manual disconnect is not sent to the SDK a second time', (
    tester,
    provider,
  ) async {
    await emit(tester, connection('device-a'));
    calls.clear();
    await provider.closeConnect();
    await emit(tester, connection('device-a', false));
    expect(calls.where((call) => call.method == 'close'), hasLength(1));
    expect(calls.where((call) => call.method == 'stopSearch'), hasLength(1));
    expect(provider.isConnected, isFalse);
  });

  connectionTest('SDK disconnect cleanup precedes explicit scans and duplicate callbacks do not stop them', (
    tester,
    provider,
  ) async {
    await emit(tester, connection('device-a'));
    calls.clear();
    var requested = false;
    void scanAfterDisconnect() {
      if (!provider.isConnected && !requested) {
        requested = true;
        provider.startSearch();
      }
    }
    provider.addListener(scanAfterDisconnect);
    try {
      await emit(tester, connection('device-a', false));
      expect(calls.map((call) => call.method), ['close', 'stopSearch', 'startSearch']);
      await emit(tester, {
        'cmd': 1, 'state': 0,
        'data': {'name': 'New pen', 'address': 'device-b'},
      });
      await emit(tester, connection('device-a', false));
      expect(calls.map((call) => call.method), ['close', 'stopSearch', 'startSearch']);
      expect(provider.discoveredDevices.single['address'], 'device-b');
    } finally {
      provider.removeListener(scanAfterDisconnect);
    }
  });

  connectionTest('disconnect cancels delayed initialization of the old connection', (
    tester,
    provider,
  ) async {
    await emit(tester, connection('device-a'));
    calls.clear();
    await emit(tester, connection('device-a', false));
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 100));
    expect(calls.where((call) => const {
      'syncTime', 'getCBC', 'getSN',
    }.contains(call.method)), isEmpty);
  });

  connectionTest('successful connection syncs time before authentication', (
    tester,
    provider,
  ) async {
    await emit(tester, connection('device-a'));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    final sent = calls.where((call) => call.method == 'syncTime').single;
    expect(sent.arguments, isNull);
  });

  connectionTest('successful authentication syncs time', (
    tester,
    provider,
  ) async {
    await emit(tester, connection('device-a'));
    for (final zero in [0, '0']) {
      calls.clear();
      await emit(tester, {
        'cmd': 31,
        'state': zero,
        'data': {'authkey_state': zero},
      });
      expect(calls.single.method, 'syncTime');
      expect(calls.single.arguments, isNull);
    }
  });

  connectionTest('failed or malformed authentication never sends time', (
    tester,
    provider,
  ) async {
    await emit(tester, connection('device-a'));
    calls.clear();
    for (final event in [
      {'cmd': 31, 'state': 0, 'data': {'authkey_state': '1'}},
      {'cmd': 31, 'state': 1, 'data': {'authkey_state': '0'}},
      {'cmd': 31, 'state': 0, 'data': <String, dynamic>{}},
      {'cmd': 31, 'state': 0, 'data': null},
      {'cmd': 31, 'data': {'authkey_state': '0'}},
      {'cmd': 32, 'state': 0, 'data': {'authkey_state': '0'}},
      {'cmd': 33, 'state': 0, 'data': {'authkey_state': '0'}},
    ]) {
      await emit(tester, event);
    }
    await emit(tester, connection('device-a', false));
    await emit(tester, {
      'cmd': 31, 'state': 0, 'data': {'authkey_state': '0'},
    });
    expect(calls.where((call) => call.method == 'syncTime'), isEmpty);
  });

  for (final type in [201, 202, 48, 199, null]) {
    connectionTest('manual time sync calls syncTime for type $type', (
      tester,
      provider,
    ) async {
      await emit(tester, {
        'cmd': 2,
        'data': {
          'connect_state': '1',
          'name': 'pen',
          'address': 'device-a',
          if (type != null) 'productType': type,
        },
      });
      calls.clear();
      await provider.asyncNowTime();
      expect(calls.single.method, 'syncTime');
      expect(calls.single.arguments, isNull);
    });
  }

  connectionTest('different devices with the same name still clear files', (
    tester,
    provider,
  ) async {
    await emit(tester, connection('device-a'));
    await loadFiles(tester, provider);
    await emit(tester, connection('device-b'));
    expect(provider.recordFiles, isEmpty);
    expect(provider.transFileName, isEmpty);
  });

  connectionTest('a real reconnect is not suppressed by battery updates', (
    tester,
    provider,
  ) async {
    await emit(tester, connection('device-a'));
    await loadFiles(tester, provider);
    await emit(tester, connection('device-a', 'false'));
    expect(provider.recordFiles, isEmpty);
    await loadFiles(tester, provider);
    await emit(tester, {
      'cmd': 6,
      'data': {'cbc': 86},
    });
    await emit(tester, connection('device-a'));
    expect(provider.recordFiles, isEmpty);
    expect(provider.transFileName, isEmpty);
  });

  connectionTest('explicit list refresh still clears the old list', (
    tester,
    provider,
  ) async {
    await emit(tester, connection('device-a'));
    await loadFiles(tester, provider);
    await provider.getRecordFileList();
    expect(provider.recordFiles, isEmpty);
    expect(provider.transFileName, isEmpty);
    expect(calls.last.method, 'getRecordFileList');
  });
}
