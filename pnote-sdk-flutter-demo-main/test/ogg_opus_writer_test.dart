import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:soni_sdk_demo/ogg_opus_writer.dart';

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('soni-ogg-test-');
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test(
    'Ogg Opus preserves packets with valid headers, CRC and duration',
    () async {
      final file = File('${directory.path}/audio.ogg');
      final writer = OggOpusWriter(file.openWrite());
      final silence = Uint8List.fromList([0xf8, 0xff, 0xfe]);
      for (var i = 0; i < 123; i++) {
        await writer.addPacket(silence);
      }
      await writer.close();
      final pages = _readPages(await file.readAsBytes());
      expect(pages.first.flags, 2);
      expect(pages.first.body, [
        ...ascii.encode('OpusHead'),
        1,
        1,
        0,
        0,
        0x80,
        0x3e,
        0,
        0,
        0,
        0,
        0,
      ]);
      expect(ascii.decode(pages[1].body.sublist(0, 8)), 'OpusTags');
      expect(pages[1].granule, 0);
      expect(pages.last.flags, 4);
      expect(pages.last.granule, 118080);
      expect(pages.skip(2).map((p) => p.granule), [48000, 96000, 118080]);
      final packets = pages.skip(2).expand((page) => page.packets).toList();
      expect(packets, hasLength(123));
      for (final packet in packets) {
        expect(packet, silence);
      }
      expect(writer.durationSeconds, closeTo(2.46, 0.00001));
      await writer.close();
      await expectLater(writer.addPacket(silence), throwsStateError);
    },
  );

  test(
    'packet duration follows TOC instead of assuming 20 milliseconds',
    () async {
      final file = File('${directory.path}/durations.ogg');
      final writer = OggOpusWriter(file.openWrite());
      // SILK 10/60ms, hybrid 20ms, CELT 2.5ms, then two and three CELT frames.
      for (final packet in [
        [0x00],
        [0x18],
        [0x68],
        [0x80],
        [0x81],
        [0x83, 3],
      ]) {
        await writer.addPacket(Uint8List.fromList(packet));
      }
      await writer.close();
      expect(_readPages(await file.readAsBytes()).last.granule, 5040);
    },
  );

  test(
    '255-byte packet boundaries and a full final page remain intact',
    () async {
      final file = File('${directory.path}/boundaries.ogg');
      final writer = OggOpusWriter(file.openWrite());
      final packet = Uint8List(255)..[0] = 0xf8;
      for (var i = 0; i < 50; i++) {
        await writer.addPacket(packet);
      }
      await writer.close();
      final pages = _readPages(await file.readAsBytes());
      expect(pages, hasLength(3));
      expect(pages.last.flags, 4);
      expect(pages.last.granule, 48000);
      expect(pages.last.packets, hasLength(50));
      expect(pages.last.packets.last, packet);
    },
  );

  test(
    'buffered Ogg writes wait for the consumer in bounded batches',
    () async {
      final consumer = _PausedConsumer();
      final writer = OggOpusWriter(IOSink(consumer));
      var completed = false;
      final writing = () async {
        for (var i = 0; i < 3000; i++) {
          await writer.addPacket(Uint8List(40)..[0] = 0xf8);
        }
        await writer.close();
        completed = true;
      }();
      await consumer.started.future;
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);
      consumer.release.complete();
      await writing;
      expect(consumer.chunkSizes.length, lessThan(5));
      expect(consumer.chunkSizes.every((size) => size < 70 * 1024), isTrue);
    },
  );

  test(
    'malformed packet durations fail without corrupting the next packet',
    () async {
      final file = File('${directory.path}/invalid.ogg');
      final writer = OggOpusWriter(file.openWrite());
      for (final packet in [
        <int>[],
        [0x83],
        [0x83, 0],
        [0x1b, 3],
      ]) {
        await expectLater(
          writer.addPacket(Uint8List.fromList(packet)),
          throwsFormatException,
        );
      }
      await writer.addPacket(Uint8List.fromList([0xf8, 0xff, 0xfe]));
      await writer.close();
      expect(_readPages(await file.readAsBytes()).last.granule, 960);
    },
  );
}

class _Page {
  _Page(this.flags, this.granule, this.body, this.packets);
  final int flags;
  final int granule;
  final Uint8List body;
  final List<Uint8List> packets;
}

List<_Page> _readPages(Uint8List bytes) {
  final pages = <_Page>[];
  int? serial;
  var offset = 0;
  while (offset < bytes.length) {
    expect(ascii.decode(bytes.sublist(offset, offset + 4)), 'OggS');
    expect(bytes[offset + 4], 0);
    final data = ByteData.sublistView(bytes, offset);
    final segmentCount = bytes[offset + 26];
    final segments = bytes.sublist(offset + 27, offset + 27 + segmentCount);
    final bodyStart = offset + 27 + segmentCount;
    final bodyLength = segments.fold<int>(0, (sum, size) => sum + size);
    final end = bodyStart + bodyLength;
    expect(data.getUint32(18, Endian.little), pages.length);
    serial ??= data.getUint32(14, Endian.little);
    expect(data.getUint32(14, Endian.little), serial);
    // Independent bit-by-bit CRC verification, rather than the writer's table.
    var crc = 0;
    for (var i = offset; i < end; i++) {
      final value = i >= offset + 22 && i < offset + 26 ? 0 : bytes[i];
      crc ^= value << 24;
      for (var bit = 0; bit < 8; bit++) {
        crc =
            ((crc << 1) ^ ((crc & 0x80000000) != 0 ? 0x04c11db7 : 0)) &
            0xffffffff;
      }
    }
    expect(data.getUint32(22, Endian.little), crc);
    final packets = <Uint8List>[];
    var packetStart = bodyStart;
    var cursor = bodyStart;
    for (final size in segments) {
      cursor += size;
      if (size < 255) {
        packets.add(Uint8List.sublistView(bytes, packetStart, cursor));
        packetStart = cursor;
      }
    }
    expect(packetStart, end);
    pages.add(
      _Page(
        bytes[offset + 5],
        data.getInt64(6, Endian.little),
        Uint8List.sublistView(bytes, bodyStart, end),
        packets,
      ),
    );
    offset = end;
  }
  return pages;
}

class _PausedConsumer implements StreamConsumer<List<int>> {
  final started = Completer<void>();
  final release = Completer<void>();
  final chunkSizes = <int>[];

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      chunkSizes.add(chunk.length);
      if (!started.isCompleted) started.complete();
      await release.future;
    }
  }

  @override
  Future<void> close() async {}
}
