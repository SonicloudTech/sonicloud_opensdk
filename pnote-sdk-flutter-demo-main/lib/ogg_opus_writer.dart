import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// Encapsulates device Opus packets without decoding or re-encoding audio.
/// Calls to addPacket and close must be serialized by the caller.
class OggOpusWriter {
  OggOpusWriter(this._sink, {int inputSampleRate = 16000}) {
    final head = Uint8List(19);
    head.setAll(0, ascii.encode('OpusHead'));
    head[8] = 1;
    head[9] = 1; // Mono, channel mapping family 0.
    // The device supplies no encoder-delay metadata. Keep every sample, as
    // the existing raw Opus -> PCM path does, rather than inventing pre-skip.
    ByteData.sublistView(head).setUint32(12, inputSampleRate, Endian.little);
    _appendPage(head, [head.length], 2, 0);

    final vendor = ascii.encode('Soni SDK Demo');
    final tags = Uint8List(16 + vendor.length);
    tags.setAll(0, ascii.encode('OpusTags'));
    ByteData.sublistView(tags).setUint32(8, vendor.length, Endian.little);
    tags.setAll(12, vendor);
    _appendPage(tags, [tags.length], 0, 0);
  }

  final IOSink _sink;
  final int _serial = Random().nextInt(0x7fffffff);
  final BytesBuilder _buffer = BytesBuilder(copy: false);
  final BytesBuilder _pageBody = BytesBuilder(copy: false);
  final List<int> _segments = [];
  int _sequence = 0;
  int _totalSamples = 0;
  int _pageSamples = 0;
  Future<void>? _closing;

  double get durationSeconds => _totalSamples / 48000;

  Future<void> addPacket(Uint8List packet) async {
    if (_closing != null) throw StateError('Ogg writer is closed');
    final samples = _packetSamples(packet);
    final segmentCount = packet.length ~/ 255 + 1;
    if (segmentCount > 255) {
      throw FormatException('Opus packet exceeds one Ogg page');
    }
    // Retain the final page until another packet arrives, so close can mark
    // the actual last audio page EOS, including an exactly full page.
    if (_segments.isNotEmpty &&
        (_pageSamples >= 48000 || _segments.length + segmentCount > 255)) {
      _emitAudioPage(0);
    }
    var remaining = packet.length;
    while (remaining >= 255) {
      _segments.add(255);
      remaining -= 255;
    }
    _segments.add(remaining);
    _pageBody.add(Uint8List.fromList(packet));
    _totalSamples += samples;
    _pageSamples += samples;
    if (_buffer.length >= 64 * 1024) {
      _sink.add(_buffer.takeBytes());
      // Await the consumer periodically to avoid an unbounded IOSink backlog.
      await _sink.flush();
    }
  }

  Future<void> close() => _closing ??= _finish();

  Future<void> _finish() async {
    try {
      _emitAudioPage(4);
      _sink.add(_buffer.takeBytes());
      await _sink.flush();
    } finally {
      await _sink.close();
    }
  }

  void _emitAudioPage(int flags) {
    _appendPage(
      _pageBody.takeBytes(),
      _segments,
      flags,
      _segments.isEmpty ? -1 : _totalSamples,
    );
    _segments.clear();
    _pageSamples = 0;
  }

  void _appendPage(Uint8List body, List<int> segments, int flags, int granule) {
    final page = Uint8List(27 + segments.length + body.length);
    page.setAll(0, ascii.encode('OggS'));
    page[5] = flags;
    final data = ByteData.sublistView(page);
    data.setInt64(6, granule, Endian.little);
    data.setUint32(14, _serial, Endian.little);
    data.setUint32(18, _sequence++, Endian.little);
    page[26] = segments.length;
    page.setAll(27, segments);
    page.setAll(27 + segments.length, body);
    var crc = 0;
    for (final value in page) {
      crc = ((crc << 8) ^ _crcTable[((crc >> 24) ^ value) & 255]) & 0xffffffff;
    }
    data.setUint32(22, crc, Endian.little);
    _buffer.add(page);
  }

  // Ogg Opus granule positions always use 48 kHz, including 16 kHz input.
  static int _packetSamples(Uint8List packet) {
    if (packet.isEmpty) throw FormatException('Empty Opus packet');
    final config = packet[0] >> 3;
    final int samplesPerFrame;
    if (config >= 16) {
      samplesPerFrame = 120 << (config & 3);
    } else if (config >= 12) {
      samplesPerFrame = 480 << (config & 1);
    } else {
      samplesPerFrame = const [480, 960, 1920, 2880][config & 3];
    }
    final code = packet[0] & 3;
    final int frames;
    if (code == 0) {
      frames = 1;
    } else if (code != 3) {
      frames = 2;
    } else {
      if (packet.length < 2) throw FormatException('Missing Opus frame count');
      frames = packet[1] & 63;
    }
    final samples = samplesPerFrame * frames;
    if (frames == 0 || samples > 5760) {
      throw FormatException('Invalid Opus packet duration');
    }
    return samples;
  }

  static final Uint32List _crcTable = Uint32List.fromList(
    List.generate(256, (value) {
      var crc = value << 24;
      for (var bit = 0; bit < 8; bit++) {
        crc =
            ((crc << 1) ^ ((crc & 0x80000000) != 0 ? 0x04c11db7 : 0)) &
            0xffffffff;
      }
      return crc;
    }),
  );
}
