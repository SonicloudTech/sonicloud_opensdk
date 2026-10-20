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
