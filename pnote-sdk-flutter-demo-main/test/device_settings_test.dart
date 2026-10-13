import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soni_sdk_demo/provider_record_pen.dart';
import 'package:soni_sdk_demo/service_bluetooth.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.soni.soni_sdk_demo/recordPen');
  final messenger = binding.defaultBinaryMessenger;
  final service = RecordPenBluetoothService();
  final calls = <MethodCall>[];

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

  test('AuthKey changes pass the original hex string to the SDK', () async {
    final bytes = List.generate(32, (index) => index * 8);
    final hex = bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    final values = [hex, '0x$hex', '  0X${hex.toUpperCase()}\n'];
    for (final value in values) {
      await service.resetAuthkey(value);
    }
    for (final call in calls) {
      expect(call.method, 'resetAuthkey');
      expect(call.arguments['authkey'], isA<String>());
    }
    expect(calls.map((call) => call.arguments['authkey']), values);
  });

  test('AuthKey input is passed unchanged for SDK validation', () async {
    final values = ['', '0x', 'aa' * 31, 'aa' * 33, 'gg' * 32];
    for (final value in values) {
      await service.resetAuthkey(value);
    }
    expect(calls.map((call) => call.arguments['authkey']), values);
  });

  test('factory reset and hotspot password use their SDK commands', () async {
    await service.unbondAuthkey();
    await service.setWifiPassword('12345678');
    expect(calls[0].method, 'unbondAuthkey');
    expect(calls[1].method, 'setWifiPassword');
    expect(calls[1].arguments['password'], '12345678');
    calls.clear();
    for (final value in ['', '1234567', '1' * 17]) {
      await expectLater(service.setWifiPassword(value), throwsFormatException);
    }
    expect(calls, isEmpty);
  });

  test('setting errors propagate to the page', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'SETTING_FAILED');
    });
    for (final operation in [
      () => service.resetAuthkey('aa' * 32),
      service.unbondAuthkey,
      () => service.setWifiPassword('12345678'),
    ]) {
      await expectLater(operation(), throwsA(isA<PlatformException>()));
    }
  });

  test(
    'Wi-Fi password connection uses WPA and normal connection stays open',
    () async {
      const eventChannel = MethodChannel('com.soni.soni_sdk_demo/eventChannel');
      const wifiChannel = MethodChannel('wifi_iot');
      final wifiCalls = <MethodCall>[];
      messenger.setMockMethodCallHandler(eventChannel, (call) async => null);
      messenger.setMockMethodCallHandler(wifiChannel, (call) async {
        wifiCalls.add(call);
        return true;
      });
      final provider = RecordPenProvider();
      try {
        await provider.init();
        await Future<void>.delayed(Duration.zero);
        await messenger.handlePlatformMessage(
          eventChannel.name,
          const StandardMethodCodec().encodeSuccessEnvelope(
            jsonEncode({
              'cmd': 12,
              'data': {'wifi_state': 0, 'wifiName': 'SoniDemo'},
            }),
          ),
          (_) {},
        );
        expect(provider.wifiName, 'SoniDemo');

        await provider.connectDeviceWiFi(password: '87654321');
        await provider.connectDeviceWiFi();

        final connections = wifiCalls
            .where((call) => call.method == 'connect')
            .toList();
        expect(connections, hasLength(2));
        expect(connections[0].arguments['ssid'], 'SoniDemo');
        expect(connections[0].arguments['password'], '87654321');
        expect(connections[0].arguments['security'], 'WPA');
        expect(connections[1].arguments['password'], isNull);
        expect(connections[1].arguments['security'], 'NONE');
        expect(
          calls.where((call) => call.method == 'connectDeviceWiFi'),
          hasLength(2),
        );
      } finally {
        binding.removeObserver(provider);
        provider.dispose();
        await provider.streamController.close();
        messenger.setMockMethodCallHandler(eventChannel, null);
        messenger.setMockMethodCallHandler(wifiChannel, null);
      }
    },
  );
}
