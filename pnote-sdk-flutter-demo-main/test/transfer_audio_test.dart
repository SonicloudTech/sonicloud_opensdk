import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:soni_sdk_demo/main.dart';
import 'package:soni_sdk_demo/wave_write.dart';

void main() {
  test('a new transfer waits until the previous sink has flushed', () async {
    final queue = AudioTaskQueue();
    final consumer = _PausedConsumer();
    final sink = IOSink(consumer);
    sink.add([1, 2, 3, 4]);
    final finishing = queue.run(() async {
      await sink.flush();
      await sink.close();
    });
    await consumer.started.future;

    var restarted = false;
    final restarting = queue.run(() async {
      await sink.close();
      restarted = true;
    });
    await Future<void>.delayed(Duration.zero);
    expect(restarted, isFalse);

    consumer.release.complete();
    await Future.wait([finishing, restarting]);
    expect(restarted, isTrue);
    expect(consumer.bytes, [1, 2, 3, 4]);
  });

  test('pending audio writes finish before closing and restarting', () async {
    final queue = AudioTaskQueue();
    final release = Completer<void>();
    final events = <String>[];
    final writing = queue.run(() async {
      await release.future;
      events.add('last frame');
    });
    final finishing = queue.run(() async => events.add('finish'));
    final restarting = queue.run(() async => events.add('restart'));
    release.complete();
    await Future.wait([writing, finishing, restarting]);
    expect(events, ['last frame', 'finish', 'restart']);
  });

  test('a failed audio operation does not block the next transfer', () async {
    final queue = AudioTaskQueue();
    final failure = StateError('write failed');
    final failed = queue.run(() async => throw failure);
    final expectation = expectLater(failed, throwsA(same(failure)));
    var restarted = false;
    await queue.run(() async => restarted = true);
    await expectation;
    expect(restarted, isTrue);
  });

  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('soni-wav-test-');
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test('WAV keeps the PCM bytes and the existing audio format', () async {
    final pcm = File('${directory.path}/audio.pcm');
    await pcm.writeAsBytes([0, 128, 255, 127]);
    final wav = File('${directory.path}/audio.wav');

    await WavWriter.writeWavFile(filePath: wav.path, pcmFile: pcm);

    final bytes = await wav.readAsBytes();
    expect(bytes.length, 48);
    expect(bytes.sublist(0, 4), [82, 73, 70, 70]);
    expect(bytes.sublist(8, 12), [87, 65, 86, 69]);
    final header = ByteData.sublistView(bytes);
    expect(header.getUint32(4, Endian.little), 40);
    expect(header.getUint16(20, Endian.little), 1);
    expect(header.getUint16(22, Endian.little), 1);
    expect(header.getUint32(24, Endian.little), 16000);
    expect(header.getUint32(28, Endian.little), 32000);
    expect(header.getUint16(32, Endian.little), 2);
    expect(header.getUint16(34, Endian.little), 16);
    expect(bytes.sublist(36, 40), [100, 97, 116, 97]);
    expect(header.getUint32(40, Endian.little), 4);
    expect(bytes.sublist(44), [0, 128, 255, 127]);
  });

  test('large PCM is streamed without reading the whole file', () async {
    const length = 362897280;
    final pcm = _StreamingPcm(length);
    final wav = File('${directory.path}/large.wav');

    await WavWriter.writeWavFile(filePath: wav.path, pcmFile: pcm);

    expect(await wav.length(), length + 44);
    final reader = await wav.open();
    try {
      final header = ByteData.sublistView(await reader.read(44));
      expect(header.getUint32(4, Endian.little), length + 36);
      expect(header.getUint32(40, Endian.little), length);
      await reader.setPosition(length + 43);
      expect(await reader.readByte(), 127);
    } finally {
      await reader.close();
    }
  });
}

class _PausedConsumer implements StreamConsumer<List<int>> {
  final started = Completer<void>();
  final release = Completer<void>();
  final bytes = <int>[];

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    started.complete();
    await release.future;
    await for (final chunk in stream) {
      bytes.addAll(chunk);
    }
  }

  @override
  Future<void> close() async {}
}

class _StreamingPcm extends Fake implements File {
  _StreamingPcm(this.size);

  final int size;

  @override
  Future<int> length() async => size;

  @override
  Future<Uint8List> readAsBytes() async {
    throw StateError('PCM must not be read into memory as a whole');
  }

  @override
  Stream<Uint8List> openRead([int? start, int? end]) async* {
    final chunk = Uint8List(64 * 1024)..fillRange(0, 64 * 1024, 127);
    for (var offset = 0; offset < size; offset += chunk.length) {
      final remaining = size - offset;
      yield remaining < chunk.length
          ? Uint8List.sublistView(chunk, 0, remaining)
          : chunk;
    }
  }
}
