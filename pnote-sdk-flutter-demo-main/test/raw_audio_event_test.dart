import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soni_sdk_demo/provider_record_pen.dart';

void main() {
  testWidgets('raw audio retains bytes before decoder frame splitting', (
    tester,
  ) async {
    final binding = tester.binding;
    final messenger = binding.defaultBinaryMessenger;
    const channel = MethodChannel('com.soni.soni_sdk_demo/recordPen');
    const events = MethodChannel('com.soni.soni_sdk_demo/eventChannel');
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    messenger.setMockMethodCallHandler(events, (_) async => null);
    final provider = RecordPenProvider();
    final received = <Map<String, dynamic>>[];
    final subscription = provider.streamController.stream.listen(received.add);
    try {
      await provider.init();
      for (final type in [AudioDataType.record, AudioDataType.file]) {
        received.clear();
        final bytes = Uint8List.fromList(List.generate(43, (i) => i));
        await messenger.handlePlatformMessage(
          events.name,
          const StandardMethodCodec().encodeSuccessEnvelope({
            'audioType': type,
            'audio': bytes,
          }),
          (_) {},
        );
        await tester.pump();
        expect(received.first['audioType'], type);
        expect(received.first['rawAudio'], bytes);
        expect(received.last['audio'], bytes.sublist(0, 40));
      }
      received.clear();
      provider.setAudioDecodeAndStoreEnabled(false);
      await messenger.handlePlatformMessage(
        events.name,
        const StandardMethodCodec().encodeSuccessEnvelope({
          'audioType': AudioDataType.file,
          'audio': Uint8List(40),
        }),
        (_) {},
      );
      await tester.pump();
      expect(received, isEmpty);
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
