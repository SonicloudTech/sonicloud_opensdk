import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:soni_sdk_demo/demo_function_panel.dart';
import 'package:soni_sdk_demo/provider_record_pen.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;
  const channel = MethodChannel('com.soni.soni_sdk_demo/recordPen');
  const events = MethodChannel('com.soni.soni_sdk_demo/eventChannel');
  const common = [
    7,
    8,
    9,
    10,
    12,
    14,
    15,
    16,
    11,
    20,
    21,
    22,
    24,
    27,
    28,
    31,
    32,
    29,
    30,
    17,
    33,
    34,
    23,
    25,
  ];

  Future<void> emit(WidgetTester tester, Map<String, dynamic> event) async {
    await messenger.handlePlatformMessage(
      events.name,
      const StandardMethodCodec().encodeSuccessEnvelope(jsonEncode(event)),
      (_) {},
    );
    await tester.pump();
  }

  void panelTest(
    String name,
    Future<void> Function(WidgetTester, RecordPenProvider) body,
  ) {
    testWidgets(name, (tester) async {
      messenger.setMockMethodCallHandler(channel, (_) async => null);
      messenger.setMockMethodCallHandler(events, (_) async => null);
      final provider = RecordPenProvider();
      try {
        await provider.init();
        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: provider,
            child: MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: DemoFunctionPanel(
                    fileSelector: const Text('文件选择'),
                    deviceSelector: const Text('设备选择 / 连接'),
                    functionBuilder: (id) =>
                        TextButton(onPressed: () {}, child: Text('DEMO-$id')),
                  ),
                ),
              ),
            ),
          ),
        );
        await body(tester, provider);
      } finally {
        provider.stopAutoConnect();
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 5));
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 50));
        binding.removeObserver(provider);
        provider.dispose();
        await provider.streamController.close();
        messenger.setMockMethodCallHandler(channel, null);
        messenger.setMockMethodCallHandler(events, null);
      }
    });
  }

  List<int> visibleFunctions(WidgetTester tester) => tester
      .widgetList<Text>(find.byType(Text))
      .map((widget) => widget.data ?? '')
      .where((text) => text.startsWith('DEMO-'))
      .map((text) => int.parse(text.substring(5)))
      .toList();

  panelTest('disconnected devices show only the documented common rows', (
    tester,
    provider,
  ) async {
    expect(visibleFunctions(tester), common);
    expect(find.text('文件选择'), findsOneWidget);
    expect(find.text('设备选择 / 连接'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('DEMO-7')).dy,
      tester.getTopLeft(find.text('DEMO-10')).dy,
    );
    expect(
      tester.getTopLeft(find.text('DEMO-12')).dy,
      greaterThan(tester.getTopLeft(find.text('DEMO-7')).dy),
    );
  });

  Finder deviceTitle(int type) =>
      find.ancestor(of: find.text('$type'), matching: find.byType(Wrap));

  void expectTitle(WidgetTester tester, int type, String model, String name) {
    final title = deviceTitle(type);
    expect(title, findsOneWidget);
    expect(
      tester
          .widgetList<Text>(
            find.descendant(of: title, matching: find.byType(Text)),
          )
          .map((text) => text.data),
      ['$type', model, name],
    );
  }

  const devices = {
    1: ('CB08', [35, 36, 37, 38, 26, 18, 19, 53, 54]),
    3: ('CB08', [39, 40, 42, 41, 43, 44, 45, 52, 53, 54, 55, 56]),
    4: ('CB08', [39, 40, 42, 41, 43, 44, 45, 52, 53, 54, 55, 56]),
    5: ('D10', [48, 51, 50, 49, 5, 47]),
    198: ('C08-FB', [39, 40, 42, 41, 43, 5, 47, 57]),
    199: ('C08-DX', [39, 40, 42, 41, 43, 44, 45, 5, 47, 6, 57]),
    200: ('C08-AI', [39, 40, 42, 41, 43, 44, 45, 57]),
    201: ('L09', [2, 39, 40, 42, 41, 43, 44, 45, 5, 47, 46, 13, 3, 4, 57]),
    202: ('C10', [2, 39, 40, 42, 41, 43, 44, 45, 5, 47, 46, 57, 3, 4]),
    999: ('其他', [39, 40, 42, 41, 43, 44, 45, 52, 55, 56]),
  };

  for (final entry in devices.entries) {
    panelTest('type ${entry.key} shows its controls and clears on disconnect', (
      tester,
      provider,
    ) async {
      final address = 'device-${entry.key}';
      await emit(tester, {
        'cmd': 1,
        'state': '0',
        'data': {
          'name': 'Soni',
          'address': address,
          'productType': entry.key.isEven ? '${entry.key}' : entry.key,
        },
      });
      final device = provider.discoveredDevices.single;
      await provider.connect(device);
      // The connection callback has no productType: retain the scan metadata.
      await emit(tester, {
        'cmd': 2,
        'data': {'connect_state': '1', 'name': 'Soni', 'address': address},
      });
      expect(visibleFunctions(tester), [...common, ...entry.value.$2]);
      expectTitle(tester, entry.key, entry.value.$1, 'Soni');
      if (entry.key == 3 || entry.key == 4) {
        expect(
          tester.getTopLeft(find.text('DEMO-55')).dy,
          tester.getTopLeft(find.text('DEMO-56')).dy,
        );
      }
      await emit(tester, {
        'cmd': 2,
        'data': {'connect_state': '0', 'name': 'Soni', 'address': address},
      });
      expect(visibleFunctions(tester), common);
      expect(deviceTitle(entry.key), findsNothing);
      // Late battery notifications must not restore the old device controls.
      await emit(tester, {
        'cmd': 6,
        'data': {'cbc': 80},
      });
      expect(visibleFunctions(tester), common);
    });
  }

  panelTest('switching devices does not reuse the previous device type', (
    tester,
    provider,
  ) async {
    await provider.connect({
      'name': 'L09',
      'address': 'old',
      'productType': '201',
    });
    await emit(tester, {
      'cmd': 2,
      'data': {'connect_state': true, 'name': 'L09', 'address': 'old'},
    });
    expect(find.text('DEMO-13'), findsOneWidget);
    await emit(tester, {
      'cmd': 2,
      'data': {'connect_state': true, 'name': 'Unknown', 'address': 'new'},
    });
    expect(visibleFunctions(tester), [
      ...common,
      39,
      40,
      42,
      41,
      43,
      44,
      45,
      52,
      55,
      56,
    ]);
    expect(find.text('其他'), findsOneWidget);
    expect(find.text('DEMO-13'), findsNothing);
    await emit(tester, {
      'cmd': 2,
      'data': {
        'connect_state': true,
        'name': 'C10',
        'address': 'new',
        'type': 202,
      },
    });
    expectTitle(tester, 202, 'C10', 'C10');
    expect(find.text('DEMO-13'), findsNothing);
    expect(find.text('DEMO-2'), findsOneWidget);
  });

  panelTest('duplicate connection callbacks retain the current type', (
    tester,
    provider,
  ) async {
    await emit(tester, {
      'cmd': 2,
      'data': {
        'connect_state': true,
        'name': 'C10',
        'address': 'device',
        'type': 202,
      },
    });
    expectTitle(tester, 202, 'C10', 'C10');
    await emit(tester, {
      'cmd': 2,
      'data': {'connect_state': true, 'name': 'C10', 'address': 'device'},
    });
    expectTitle(tester, 202, 'C10', 'C10');
    await emit(tester, {
      'cmd': 2,
      'data': {'connect_state': false, 'name': 'C10', 'address': 'null'},
    });
    expect(visibleFunctions(tester), common);
    await emit(tester, {
      'cmd': 6,
      'data': {'cbc': 80},
    });
    expect(visibleFunctions(tester), common);
  });

  panelTest('later scan results can supply a missing product type', (
    tester,
    provider,
  ) async {
    for (final data in [
      {'name': 'Soni', 'address': 'device'},
      {'name': 'Soni', 'address': 'device', 'productType': 198},
    ]) {
      await emit(tester, {'cmd': 1, 'state': 0, 'data': data});
    }
    expect(provider.discoveredDevices, hasLength(1));
    await provider.connect(provider.discoveredDevices.single);
    await emit(tester, {
      'cmd': 2,
      'data': {'connect_state': true, 'name': 'Soni', 'address': 'device'},
    });
    expectTitle(tester, 198, 'C08-FB', 'Soni');
    expect(find.text('DEMO-57'), findsOneWidget);
    expect(find.text('DEMO-2'), findsNothing);
  });
}
