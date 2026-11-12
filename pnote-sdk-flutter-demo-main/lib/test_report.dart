import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

String formatTestDuration(Duration duration) {
  String pad(int value) => value.toString().padLeft(2, '0');
  return '${pad(duration.inHours)}:${pad(duration.inMinutes % 60)}:'
      '${pad(duration.inSeconds % 60)}';
}

String formatTestTimestamp(DateTime time) {
  String pad(int value) => value.toString().padLeft(2, '0');
  return '${time.year}-${pad(time.month)}-${pad(time.day)} '
      '${pad(time.hour)}:${pad(time.minute)}:${pad(time.second)}';
}

String formatTestRate(int bytes, Duration duration) {
  final rate = duration.inMicroseconds <= 0
      ? 0.0
      : bytes * Duration.microsecondsPerSecond / duration.inMicroseconds / 1024;
  return '${rate.toStringAsFixed(1)}KB/s';
}

class TestReportStore extends ChangeNotifier {
  TestReportStore({
    Future<Directory> Function()? directory,
    File Function(String)? fileFactory,
  }) : _directory = directory ?? getApplicationDocumentsDirectory,
       _fileFactory = fileFactory ?? File.new;

  final Future<Directory> Function() _directory;
  final File Function(String) _fileFactory;
  final List<String> _unsaved = [];
  Future<void> _pending = Future<void>.value();
  Object? _lastError;
  bool _disposed = false;
  int? _retryOffset;

  Object? get lastError => _lastError;

  Future<File> _file() async {
    final root = await _directory();
    final reports = Directory('${root.path}/test_reports');
    await reports.create(recursive: true);
    return _fileFactory('${reports.path}/自动化测试报告.txt');
  }

  void append(String text) {
    _unsaved.add(text);
    _enqueue();
  }

  Future<void> _enqueue() {
    _pending = _pending
        .then((_) async {
          if (_unsaved.isEmpty) return;
          final count = _unsaved.length;
          final text = _unsaved.take(count).join();
          final file = await _file();
          final handle = await file.open(mode: FileMode.append);
          try {
            final offset = _retryOffset ??= await handle.length();
            await handle.truncate(offset);
            await handle.setPosition(offset);
            await handle.writeString(text);
            await handle.flush();
            await handle.close();
          } catch (_) {
            try {
              await handle.close();
            } on FileSystemException {
              // Recovery truncates to the original offset on the next retry.
            }
            rethrow;
          }
          _retryOffset = null;
          _unsaved.removeRange(0, count);
          _lastError = null;
        })
        .catchError((Object error) {
          _lastError = error;
        })
        .whenComplete(() {
          if (!_disposed) notifyListeners();
        });
    return _pending;
  }

  Future<File?> fileForSharing() async {
    await _enqueue();
    if (_lastError case final error?) throw error;
    final file = await _file();
    return await file.exists() && await file.length() > 0 ? file : null;
  }

  Future<void> clear() async {
    await _pending;
    final file = await _file();
    if (await file.exists()) await file.delete();
    _unsaved.clear();
    _retryOffset = null;
    _lastError = null;
    if (!_disposed) notifyListeners();
  }

  Future<File> copyForSharing(String path) {
    final copy = _pending.then((_) async {
      if (_lastError case final error?) throw error;
      return (await _file()).copy(path);
    });
    // Copy failures propagate to the caller without poisoning later writes.
    _pending = copy.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return copy;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
