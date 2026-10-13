import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soni_sdk_demo/service_bluetooth.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.soni.soni_sdk_demo/recordPen');
  const defaultAuthkey =
      '0xae4b1e65f7ba1282d2060876d324253c95e9475307b4e9e14f9a708dcc54b250';
  final service = RecordPenBluetoothService();
  final calls = <MethodCall>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('default AuthKey reaches the SDK as the original hex string', () async {
    await service.authkeyConnect(defaultAuthkey);

    expect(calls.single.method, 'authkeyConnect');
    expect(calls.single.arguments['authkey'], defaultAuthkey);
  });

  test('input is passed unchanged for SDK validation and conversion', () async {
    final values = [
      defaultAuthkey.substring(2),
      '  ${defaultAuthkey.toUpperCase()}\n',
      '00' * 31 + 'ff',
      '',
      '0x',
      'aa' * 31,
      'aa' * 33,
      'gg' * 32,
    ];
    for (final value in values) {
      await service.authkeyConnect(value);
    }

    expect(calls.map((call) => call.arguments['authkey']), values);
  });

  test('native errors propagate so the page can display the failure', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'AUTHKEY_FAILED');
    });

    await expectLater(
      service.authkeyConnect(defaultAuthkey),
      throwsA(isA<PlatformException>()),
    );
  });
}
