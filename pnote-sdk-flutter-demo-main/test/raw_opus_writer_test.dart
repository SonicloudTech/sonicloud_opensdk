import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:soni_sdk_demo/raw_opus_writer.dart';
import 'package:soni_sdk_demo/service_audio_export.dart';

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('soni-raw-opus-');
  });
  tearDown(() => directory.delete(recursive: true));

  test(
    'raw export preserves received bytes without headers or padding',
    () async {
      final file = File('${directory.path}/record_raw.opus');
      final writer = RawOpusWriter(file);
      await writer.add([1, 2, 3]);
      await writer.add(List.filled(65536, 4));
      await writer.add(List.generate(43, (index) => index));
      expect(await AudioFileExporter.isSaved(file), isFalse);
      await writer.close();
      expect(await file.readAsBytes(), [
        1,
        2,
        3,
        ...List.filled(65536, 4),
        ...List.generate(43, (i) => i),
      ]);
      expect(await AudioFileExporter.isSaved(file), isTrue);
      expect(await File('${file.path}.part').exists(), isFalse);
      await writer.close();
      await expectLater(writer.add([4]), throwsStateError);
    },
  );

  test(
    'discarding a partial recording keeps the previous completed file',
    () async {
      final file = await File(
        '${directory.path}/record_raw.opus',
      ).writeAsBytes([9]);
      final writer = RawOpusWriter(file);
      await writer.add([1, 2, 3]);
      await writer.close(save: false);
      expect(await file.readAsBytes(), [9]);
      expect(await File('${file.path}.part').exists(), isFalse);
    },
  );

  test('an empty recording is not offered for sharing', () async {
    final file = File('${directory.path}/record_raw.opus');
    await RawOpusWriter(file).close();
    expect(await AudioFileExporter.isSaved(file), isFalse);
  });
}
