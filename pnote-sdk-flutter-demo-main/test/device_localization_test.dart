import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:soni_sdk_demo/demo_function_panel.dart';
import 'package:soni_sdk_demo/demo_home_tabs.dart';
import 'package:soni_sdk_demo/demo_log_header.dart';
import 'package:soni_sdk_demo/device_localizations.dart';
import 'package:soni_sdk_demo/provider_record_pen.dart';
import 'package:soni_sdk_demo/service_bluetooth.dart';

void main() {
  test('English setting errors translate device parameter validation', () async {
    const strings = DeviceLocalizations(isEnglish: true);
    final provider = RecordPenProvider();
    addTearDown(() async {
      TestWidgetsFlutterBinding.ensureInitialized().removeObserver(provider);
      provider.dispose();
      await provider.streamController.close();
    });
    for (final (action, title, expected)
        in <(Future<void> Function(), String, String)>[
          (
            () => provider.setSendFileTimeInterval(12),
            'Transfer interval',
            'Transfer interval failed: Transfer interval must be 13–255 ms',
          ),
          (
            () => RecordPenBluetoothService().setWifiPassword('123'),
            'Set hotspot password',
            'Set hotspot password failed: Hotspot password must contain 8–16 characters',
          ),
        ]) {
      Object? failure;
      try {
        await action();
      } catch (error) {
        failure = error;
      }
      expect(failure, isA<FormatException>());
      expect(strings.settingFailed(title, failure!), expected);
    }
  });

  testWidgets('language changes device controls while preserving page state', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final provider = RecordPenProvider();
    addTearDown(() async {
      tester.binding.removeObserver(provider);
      provider.dispose();
      await provider.streamController.close();
    });
    var strings = const DeviceLocalizations();
    var autoScroll = true;
    var copied = false;
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) => DemoHomeTabs(
              deviceLabel: strings.device,
              appBar: AppBar(
                title: const Text('SoniSDKDemo V4.0.3'),
                actions: [
                  TextButton(
                    onPressed: () => setState(() {
                      strings = DeviceLocalizations(
                        isEnglish: !strings.isEnglish,
                      );
                    }),
                    child: Text(strings.switchLanguage),
                  ),
                ],
              ),
              testPage: const Text('文件传输测试'),
              device: SingleChildScrollView(
                child: Column(
                  children: [
                    DemoLogHeader(
                      strings: strings,
                      lineCount: 2,
                      autoScroll: autoScroll,
                      onAutoScrollChanged: (value) =>
                          setState(() => autoScroll = value),
                      onClear: () {},
                      onCopy: () => copied = true,
                    ),
                    DemoFunctionPanel(
                      strings: strings,
                      fileSelector: const TextField(),
                      deviceSelector: Text(strings.selectDevice(1)),
                      functionBuilder: (_) => const SizedBox(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'keep-input');
    await tester.tap(find.text('切换英文'));
    await tester.pumpAndSettle();
    expect(find.text('切换中文'), findsOneWidget);
    expect(find.text('Device'), findsOneWidget);
    expect(find.text('Select device (1)'), findsOneWidget);
    expect(find.text('Log'), findsOneWidget);
    expect(find.text('2 lines'), findsOneWidget);
    expect(find.text('keep-input'), findsOneWidget);
    await tester.ensureVisible(find.text('Copy log'));
    await tester.tap(find.text('Copy log'));
    expect(copied, isTrue);
    await tester.ensureVisible(find.byType(Switch));
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(autoScroll, isFalse);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('测试'));
    await tester.pumpAndSettle();
    expect(find.text('文件传输测试'), findsOneWidget);
    await tester.tap(find.text('Device'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('切换中文'));
    await tester.pumpAndSettle();
    expect(find.text('日志'), findsOneWidget);
    expect(find.text('设备'), findsOneWidget);
    expect(find.text('keep-input'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('connected device descriptions use the selected language', (
    tester,
  ) async {
    final messenger = tester.binding.defaultBinaryMessenger;
    const channel = MethodChannel('com.soni.soni_sdk_demo/recordPen');
    const events = MethodChannel('com.soni.soni_sdk_demo/eventChannel');
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    messenger.setMockMethodCallHandler(events, (_) async => null);
    final provider = RecordPenProvider();
    addTearDown(() async {
      messenger.setMockMethodCallHandler(channel, null);
      messenger.setMockMethodCallHandler(events, null);
      tester.binding.removeObserver(provider);
      provider.dispose();
      await provider.streamController.close();
    });
    await provider.init();

    Future<void> connect(int? type) async {
      await messenger.handlePlatformMessage(
        events.name,
        const StandardMethodCodec().encodeSuccessEnvelope(
          jsonEncode({
            'cmd': 2,
            'data': {
              'connect_state': '1',
              'name': 'Soni',
              'address': 'device-$type',
              if (type != null) 'productType': type,
            },
          }),
        ),
        (_) {},
      );
      await tester.pump();
    }

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const MaterialApp(
          home: Scaffold(
            body: DemoFunctionPanel(
              strings: DeviceLocalizations(isEnglish: true),
              fileSelector: SizedBox(),
              deviceSelector: SizedBox(),
              functionBuilder: _emptyFunction,
            ),
          ),
        ),
      ),
    );
    await connect(null);
    expect(find.text('Other'), findsOneWidget);
    expect(find.text('Unknown'), findsOneWidget);
    await connect(48);
    expect(find.text('JL01 (new 7911)'), findsOneWidget);
    expect(find.text('48'), findsOneWidget);
    expect(find.text('Soni'), findsOneWidget);
    for (final type in [64, 65, 66]) {
      await connect(type);
      expect(find.text(type == 66 ? 'JL02 (AOC 7012)' : 'JL02 (Aigo 7012)'), findsOneWidget);
      expect(find.text('$type'), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
  });
}

Widget _emptyFunction(int _) => const SizedBox();
