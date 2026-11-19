import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soni_sdk_demo/test_report.dart';

void main() {
  final messenger =
      TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger;
  const channel = MethodChannel('com.soni.soni_sdk_demo/recordPen');

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  for (final failure in ['missing', 'platform', 'empty']) {
    test(
      '$failure phone information does not prevent a report header',
      () async {
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (failure == 'missing') throw MissingPluginException();
          if (failure == 'platform') {
            throw PlatformException(code: 'unavailable');
          }
          return {'model': ' ', 'systemName': '', 'systemVersion': ''};
        });
        expect(
          await formatTestStartHeader(DateTime(2026, 11, 14, 15, 2, 5)),
          '\n\n（2026-11-14 15:02:05） 手机：未知 · 系统：未知\n',
        );
      },
    );
  }
}
