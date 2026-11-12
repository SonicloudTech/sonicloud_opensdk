import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soni_sdk_demo/ogg_opus_writer.dart';
import 'package:soni_sdk_demo/service_audio_export.dart';
import 'package:soni_sdk_demo/service_file_share.dart';
import 'package:soni_sdk_demo/wave_write.dart';

void main() {
  final messenger =
      TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger;
  const channel = MethodChannel('com.soni.soni_sdk_demo/recordPen');

  test('only completed audio is offered for export', () async {
    final directory = await Directory.systemTemp.createTemp('soni-audio-test-');
    addTearDown(() => directory.delete(recursive: true));
    final ogg = File('${directory.path}/record_play.ogg');
    await OggOpusWriter(ogg.openWrite()).close();
    expect(await AudioFileExporter.isSaved(ogg), isFalse);

    final writer = OggOpusWriter(ogg.openWrite());
    await writer.addPacket(Uint8List.fromList([0xf8, 0xff, 0xfe]));
    await writer.close();
    expect(await AudioFileExporter.isSaved(ogg), isTrue);
    final oggBytes = await ogg.readAsBytes();
    await ogg.writeAsBytes(oggBytes.sublist(0, oggBytes.length - 1));
    expect(await AudioFileExporter.isSaved(ogg), isFalse);

    final wav = File('${directory.path}/transfer_play.wav');
    final pcm = await File('${directory.path}/audio.pcm').writeAsBytes([]);
    await WavWriter.writeWavFile(filePath: wav.path, pcmFile: pcm);
    expect(await AudioFileExporter.isSaved(wav), isFalse);
    await pcm.writeAsBytes([0, 128, 255, 127]);
    await WavWriter.writeWavFile(filePath: wav.path, pcmFile: pcm);
    expect(await AudioFileExporter.isSaved(wav), isTrue);
    final wavBytes = await wav.readAsBytes();
    await wav.writeAsBytes(wavBytes.sublist(0, wavBytes.length - 1));
    expect(await AudioFileExporter.isSaved(wav), isFalse);
  });

  test(
    'export keeps a stable copy while the next recording is saved',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'soni-audio-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final original = await File(
        '${directory.path}/record_play.ogg',
      ).writeAsBytes([1, 2, 3]);
      late File snapshot;

      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'shareFile');
        expect(call.arguments['mimeType'], 'audio/ogg');
        snapshot = File(call.arguments['path'] as String);
        expect(snapshot.uri.pathSegments.last, 'record_play.ogg');
        await original.writeAsBytes([4, 5, 6]);
        expect(await snapshot.readAsBytes(), [1, 2, 3]);
        return true;
      });

      expect(await FileSharer.share(original, directory), isTrue);
      expect(await snapshot.exists(), isTrue);
      expect(await original.readAsBytes(), [4, 5, 6]);
    },
  );

  test('text shares use text/plain and remove snapshots on launch failure', () async {
    final directory = await Directory.systemTemp.createTemp('soni-share-test-');
    addTearDown(() => directory.delete(recursive: true));
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final source = await File('${directory.path}/report.txt').writeAsString('测试结果');
    late File snapshot;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'shareFile');
      expect(call.arguments['mimeType'], 'text/plain');
      snapshot = File(call.arguments['path'] as String);
      expect(await snapshot.readAsString(), '测试结果');
      throw PlatformException(code: 'SHARE_FAILED');
    });
    await expectLater(FileSharer.share(source, directory), throwsA(isA<PlatformException>()));
    expect(await snapshot.exists(), isFalse);
    expect(await source.exists(), isTrue);
  });
}
