import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soni_sdk_demo/device_localizations.dart';
import 'package:soni_sdk_demo/file_transfer_size_check.dart';
import 'package:soni_sdk_demo/provider_record_pen.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;
  const channel = MethodChannel('com.soni.soni_sdk_demo/recordPen');
  const events = MethodChannel('com.soni.soni_sdk_demo/eventChannel');

  Future<void> emit(WidgetTester tester, Object event) async {
    await messenger.handlePlatformMessage(
      events.name,
      const StandardMethodCodec().encodeSuccessEnvelope(event),
      (_) {},
    );
    await tester.pump();
  }

  void sizeTest(
    String name,
    Future<void> Function(
      WidgetTester,
      RecordPenProvider,
      List<FileTransferSizeCheck>,
    )
    body,
  ) {
    testWidgets(name, (tester) async {
      messenger.setMockMethodCallHandler(channel, (_) async => null);
      messenger.setMockMethodCallHandler(events, (_) async => null);
      final provider = RecordPenProvider();
      final checks = <FileTransferSizeCheck>[];
      final subscription = provider.streamController.stream.listen((event) {
        if (event[RecordPenProvider.fileTransferSizeKey]
            case final FileTransferSizeCheck check) {
          checks.add(check);
        }
      });
      try {
        await provider.init();
        await body(tester, provider, checks);
      } finally {
        binding.removeObserver(provider);
        provider.dispose();
        await tester.runAsync(() async {
          await subscription.cancel();
          await provider.streamController.close();
        });
        messenger.setMockMethodCallHandler(channel, null);
        messenger.setMockMethodCallHandler(events, null);
      }
    });
  }

  Future<void> files(WidgetTester tester, [Object? size = 888]) => emit(
    tester,
    jsonEncode({
      'cmd': 4,
      'finish': 1,
      'data': [
        {'name': 'a.opus', if (size != null) 'size': size, 'time': 1},
      ],
    }),
  );

  Future<void> audio(
    WidgetTester tester,
    int bytes, [
    String type = AudioDataType.file,
  ]) => emit(tester, {'audioType': type, 'audio': Uint8List(bytes)});

  Future<void> finish(
    WidgetTester tester, [
    String? name = 'a.opus',
    int state = 0,
  ]) => emit(
    tester,
    jsonEncode({
      'cmd': 5,
      'state': 0,
      'data': {if (name != null) 'name': name, 'record_file_state': state},
    }),
  );

  for (final storage in [true, false]) {
    sizeTest(
      'size checks count raw bytes with storage $storage and preserve the target snapshot',
      (tester, provider, checks) async {
        await files(tester);
        provider.setAudioDecodeAndStoreEnabled(storage);
        await provider.sendFileFromPenToPhoneWithOffset('a.opus', 0);
        await provider.getRecordFileList();
        await audio(tester, 400);
        await audio(tester, 999, AudioDataType.record);
        await audio(tester, 488);
        await finish(tester);
        expect(checks, hasLength(1));
        expect(checks.single.receivedBytes, 888);
        expect(checks.single.expectedBytes, 888);
        expect(checks.single.matches, isTrue);
        expect(
          const DeviceLocalizations().fileSizeCheck(checks.single),
          contains('收到：888/目标：888'),
        );
        await finish(tester);
        expect(checks, hasLength(1));
      },
    );
  }

  sizeTest(
    'short and oversized transfers fail and repeated transfers reset the byte count',
    (tester, provider, checks) async {
      await files(tester, 999);
      for (final count in [888, 1000]) {
        await provider.sendFileFromPenToPhoneWithOffset('a.opus', 0);
        await audio(tester, count);
        await finish(tester, 'other.opus');
        expect(checks.length, count == 888 ? 0 : 1);
        await finish(tester, null);
        expect(checks.last.receivedBytes, count);
        expect(checks.last.expectedBytes, 999);
        expect(checks.last.matches, isFalse);
        expect(
          const DeviceLocalizations().fileSizeCheck(checks.last),
          contains('校验失败'),
        );
      }
    },
  );

  sizeTest(
    'missing sizes are not treated as empty files and zero-byte files are valid',
    (tester, provider, checks) async {
      for (final size in [null, -1, 0]) {
        await provider.getRecordFileList();
        await files(tester, size);
        await provider.sendFileFromPenToPhoneWithOffset('a.opus', 0);
        await finish(tester);
        expect(checks.last.expectedBytes, size == 0 ? 0 : null);
        expect(checks.last.matches, size == 0 ? true : null);
      }
    },
  );

  sizeTest('resumed transfers compare against the remaining original bytes', (
    tester,
    provider,
    checks,
  ) async {
    await files(tester);
    await provider.sendFileFromPenToPhoneWithOffset('a.opus', 400);
    await audio(tester, 488);
    await finish(tester);
    expect(checks.single.receivedBytes, 488);
    expect(checks.single.expectedBytes, 488);
    expect(checks.single.matches, isTrue);
  });

  sizeTest('stopped transfers do not produce a successful completion check', (
    tester,
    provider,
    checks,
  ) async {
    await files(tester);
    await provider.sendFileFromPenToPhoneWithOffset('a.opus', 0);
    await audio(tester, 400);
    await finish(tester, 'a.opus', 3);
    await finish(tester);
    expect(checks, isEmpty);
  });
}
