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

  test(
    'device reset reaches native code and propagates native errors',
    () async {
      final provider = RecordPenProvider();
      try {
        await provider.resetDevice();
        expect(calls.single.method, 'resetDevice');
        expect(calls.single.arguments, isNull);

        messenger.setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(
            code: 'RESET_FAILED',
            message: '设备重置调用失败',
          );
        });
        await expectLater(
          provider.resetDevice(),
          throwsA(
            isA<PlatformException>().having(
              (error) => error.code,
              'code',
              'RESET_FAILED',
            ),
          ),
        );
      } finally {
        binding.removeObserver(provider);
        provider.dispose();
        await provider.streamController.close();
      }
    },
  );

  test('cmd 35 reports device reset results in the page event stream', () async {
    const events = MethodChannel('com.soni.soni_sdk_demo/eventChannel');
    messenger.setMockMethodCallHandler(events, (call) async => null);
    final provider = RecordPenProvider();
    final received = <Map<String, dynamic>>[];
    final subscription = provider.streamController.stream.listen(received.add);
    try {
      await provider.init();
      await Future<void>.delayed(Duration.zero);
      final cases = [
        {'cmd': '35', 'value': '0', 'text': '成功'},
        {'cmd': 35, 'value': 0, 'text': '成功'},
        {'cmd': '35', 'value': '1', 'text': '失败'},
        {'cmd': 35, 'value': 1, 'text': '失败'},
        {'cmd': '35', 'value': '2', 'text': '结果未知(2)'},
        {'cmd': 35, 'value': null, 'text': '结果未知(null)'},
      ];
      for (final item in cases) {
        received.clear();
        final event = {
          'cmd': item['cmd'],
          'state': '0',
          'data': {'reset_device_state': item['value']},
        };
        await messenger.handlePlatformMessage(
          events.name,
          const StandardMethodCodec().encodeSuccessEnvelope(jsonEncode(event)),
          (_) {},
        );
        await Future<void>.delayed(Duration.zero);
        expect(received, [event, {'重置设备': item['text']}]);
      }
    } finally {
      await subscription.cancel();
      binding.removeObserver(provider);
      provider.dispose();
      await provider.streamController.close();
      messenger.setMockMethodCallHandler(events, null);
    }
  });

  test(
    'heartbeat events reply and report the device settings results',
    () async {
      const events = MethodChannel('com.soni.soni_sdk_demo/eventChannel');
      messenger.setMockMethodCallHandler(events, (_) async => null);
      final provider = RecordPenProvider();
      final received = <Map<String, dynamic>>[];
      final subscription = provider.streamController.stream.listen(
        received.add,
      );

      Future<void> emit(Object cmd, Map<String, dynamic> data) async {
        await messenger.handlePlatformMessage(
          events.name,
          const StandardMethodCodec().encodeSuccessEnvelope(
            jsonEncode({'cmd': cmd, 'state': '0', 'data': data}),
          ),
          (_) {},
        );
        await Future<void>.delayed(Duration.zero);
      }

      try {
        await provider.init();
        await Future<void>.delayed(Duration.zero);
        calls.clear();

        await emit('101', {});
        expect(calls.map((call) => call.method), ['sendBackHeartbeatData']);
        provider.heartbeatReplyEnabled = false;
        await emit(101, {});

        await emit('100', {'offline_transfer_interval_state': '0'});
        await emit(100, {'offline_transfer_interval_state': '1'});
        expect(provider.deviceHeartbeatEnabled, isTrue);
        await provider.setHeartbeatDataState(true);
        expect(provider.isHeartbeatSettingPending, isTrue);
        expect(provider.deviceHeartbeatEnabled, isTrue);
        await emit('102', {'heartbeat_state': '00'});
        expect(provider.isHeartbeatSettingPending, isFalse);
        expect(provider.deviceHeartbeatEnabled, isTrue);
        await provider.setHeartbeatDataState(false);
        expect(provider.deviceHeartbeatEnabled, isTrue);
        await emit(102, {'heartbeat_state': '01'});
        expect(provider.isHeartbeatSettingPending, isFalse);
        expect(provider.deviceHeartbeatEnabled, isFalse);
        expect(received.where((event) => !event.containsKey('cmd')), [
          {'heartbeatLog': '收到设备心跳（0x32）'},
          {'heartbeatLog': '已发送心跳回复（0x33）'},
          {'heartbeatLog': '收到设备心跳（0x32），自动回复已关闭'},
          {'设置传输间隔': '成功'},
          {'设置传输间隔': '失败'},
          {'heartbeatLog': '设置开启设备心跳（0x34）'},
          {'heartbeatLog': '收到设备心跳开关应答（0x35），设备当前为开启'},
          {'heartbeatLog': '设置关闭设备心跳（0x34）'},
          {'heartbeatLog': '收到设备心跳开关应答（0x35），设备当前为关闭'},
        ]);
        expect(calls.map((call) => call.method), [
          'sendBackHeartbeatData',
          'setHeartbeatDataState',
          'setHeartbeatDataState',
        ]);
        expect(calls.skip(1).map((call) => call.arguments), [
          {'state': 1},
          {'state': 0},
        ]);

        await provider.setHeartbeatDataState(true);
        await emit(102, {'heartbeat_state': '01'});
        expect(provider.deviceHeartbeatEnabled, isFalse);
        expect(provider.isHeartbeatSettingPending, isFalse);
        expect(received.last, {
          'heartbeatLog': '收到设备心跳开关应答（0x35），设置失败，设备当前为关闭',
        });
        await emit(102, {'heartbeat_state': 0});
        expect(provider.deviceHeartbeatEnabled, isTrue);
        await provider.setHeartbeatDataState(false);
        await emit(102, {'heartbeat_state': '02'});
        expect(provider.deviceHeartbeatEnabled, isTrue);
        expect(provider.isHeartbeatSettingPending, isFalse);

        await emit(2, {'connect_state': '0', 'address': 'null'});
        expect(provider.deviceHeartbeatEnabled, isTrue);
      } finally {
        await subscription.cancel();
        binding.removeObserver(provider);
        provider.dispose();
        await provider.streamController.close();
        messenger.setMockMethodCallHandler(events, null);
      }
    },
  );

  test('transfer interval passes valid SDK arguments', () async {
    final provider = RecordPenProvider();
    try {
      await provider.setSendFileTimeInterval(13);
      await provider.setSendFileTimeInterval(255);

      for (final interval in [12, 256]) {
        await expectLater(
          provider.setSendFileTimeInterval(interval),
          throwsFormatException,
        );
      }
      expect(calls.map((call) => call.method), [
        'sendFileTimeInterval',
        'sendFileTimeInterval',
      ]);
      expect(calls.map((call) => call.arguments), [
        {'interval': 13},
        {'interval': 255},
      ]);
    } finally {
      binding.removeObserver(provider);
      provider.dispose();
      await provider.streamController.close();
    }
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
