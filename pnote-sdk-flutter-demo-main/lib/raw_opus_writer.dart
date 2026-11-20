import 'dart:io';
import 'dart:typed_data';

/// Saves SDK audio bytes unchanged. Calls must be serialized by the caller.
class RawOpusWriter {
  RawOpusWriter(this.file);

  final File file;
  late final File _pending = File('${file.path}.part');
  final BytesBuilder _buffer = BytesBuilder();
  RandomAccessFile? _writer;
  Future<void>? _closing;
  int _bytes = 0;

  Future<void> add(List<int> data) async {
    if (_closing != null) throw StateError('Raw Opus writer is closed');
    _buffer.add(data);
    _bytes += data.length;
    if (_buffer.length >= 64 * 1024) await _writeBuffer();
  }

  Future<void> _writeBuffer() async {
    _writer ??= await _pending.open(mode: FileMode.write);
    await _writer!.writeFrom(_buffer.takeBytes());
  }

  Future<void> close({bool save = true}) => _closing ??= _finish(save);

  Future<void> _finish(bool save) async {
    try {
      try {
        if (save && _bytes > 0) {
          await _writeBuffer();
          await _writer!.flush();
        }
      } finally {
        await _writer?.close();
      }
      if (save && _bytes > 0) await _pending.rename(file.path);
    } finally {
      _buffer.clear();
      if (await _pending.exists()) await _pending.delete();
    }
  }
}
