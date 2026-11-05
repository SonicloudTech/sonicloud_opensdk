import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soni_sdk_demo/log_clipboard.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  test('logs within the copy budget keep all lines unchanged', () {
    expect(LogClipboard.split('首行\n末行', maxBytes: 13), ['首行\n末行']);
    expect(LogClipboard.split(''), isEmpty);
  });

  test('long logs split without losing text or breaking Unicode', () {
    const text = 'abc中😀\n最后一行';
    final parts = LogClipboard.split(text, maxBytes: 7);
    expect(parts, ['abc中', '😀\n', '最后', '一行']);
    expect(parts.join(), text);
    expect(parts.every((part) => utf8.encode(part).length <= 7), isTrue);
  });

  test('a single oversized line is fully available across copy parts', () {
    final text = '中😀' * 100000;
    final parts = LogClipboard.split(text);
    expect(parts.length, greaterThan(1));
    expect(parts.join(), text);
    expect(
      parts.every((part) => utf8.encode(part).length <= LogClipboard.maxBytes),
      isTrue,
    );
  });

  test(
    'copy only succeeds when the clipboard contains the complete text',
    () async {
      String? clipboard;
      var truncate = false;
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            final text = (call.arguments as Map)['text'] as String;
            clipboard = truncate ? text.substring(0, 2) : text;
          }
          if (call.method == 'Clipboard.getData') {
            return {'text': clipboard};
          }
          return null;
        },
      );
      addTearDown(() {
        binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      });

      expect(await LogClipboard.copy('首行\n末行😀'), isTrue);
      truncate = true;
      expect(await LogClipboard.copy('首行\n末行😀'), isFalse);
    },
  );

  test('clipboard write failures are returned to the caller', () async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => throw PlatformException(code: 'clipboard_failed'),
    );
    addTearDown(() {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });
    await expectLater(
      LogClipboard.copy('日志'),
      throwsA(isA<PlatformException>()),
    );
  });
}
