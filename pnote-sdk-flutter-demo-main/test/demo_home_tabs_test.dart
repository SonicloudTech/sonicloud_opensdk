import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soni_sdk_demo/demo_home_tabs.dart';
import 'package:soni_sdk_demo/demo_test_page.dart';
import 'package:soni_sdk_demo/ota_automation/ota_automation_module.dart';
import 'package:soni_sdk_demo/demo_theme.dart';
import 'package:soni_sdk_demo/provider_record_pen.dart';

void main() {
  for (final bottomPadding in [0.0, 34.0]) {
    testWidgets(
      'keyboard keeps bottom tabs fixed with safe area $bottomPadding',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        tester.view.viewPadding = FakeViewPadding(bottom: bottomPadding);
        tester.view.padding = FakeViewPadding(bottom: bottomPadding);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        addTearDown(tester.view.resetViewPadding);
        addTearDown(tester.view.resetPadding);
        await tester.pumpWidget(
          MaterialApp(
            theme: createDemoTheme(),
            home: const DemoHomeTabs(device: SizedBox.expand()),
          ),
        );
        final tabPosition = tester.getCenter(find.text('设备'));
        final page = find.byType(IndexedStack);
        final pageBottom = tester.getBottomRight(page).dy;

        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        tester.view.padding = const FakeViewPadding();
        await tester.pumpAndSettle();
        expect(tester.getCenter(find.text('设备')), tabPosition);
        expect(tester.getBottomRight(page).dy, lessThan(pageBottom));
        expect(tester.getBottomRight(page).dy, lessThanOrEqualTo(544));

        tester.view.viewInsets = const FakeViewPadding();
        tester.view.padding = FakeViewPadding(bottom: bottomPadding);
        await tester.pumpAndSettle();
        expect(tester.getCenter(find.text('设备')), tabPosition);
        expect(tester.getBottomRight(page).dy, pageBottom);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'page keeps its app bar and drawer access after tab layout changes',
    (tester) async {
      final scaffoldKey = GlobalKey<ScaffoldState>();
      await tester.pumpWidget(
        MaterialApp(
          theme: createDemoTheme(),
          home: DemoHomeTabs(
            scaffoldKey: scaffoldKey,
            appBar: AppBar(title: const Text('SDK Demo')),
            endDrawer: const Drawer(child: Text('BK OTA')),
            device: const TextField(),
          ),
        ),
      );
      expect(find.text('SDK Demo'), findsOneWidget);
      scaffoldKey.currentState!.openEndDrawer();
      await tester.pumpAndSettle();
      expect(find.text('BK OTA'), findsOneWidget);
      expect(scaffoldKey.currentState!.isEndDrawerOpen, isTrue);
    },
  );

  testWidgets('bottom tabs switch pages and preserve device input', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: createDemoTheme(),
        home: const DemoHomeTabs(
          device: TextField(),
          testPage: Text('杰理OTA自动化测试'),
        ),
      ),
    );

    expect(find.text('设备'), findsOneWidget);
    expect(find.text('测试'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), '保留设备页输入');

    await tester.tap(find.text('测试'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(find.text('杰理OTA自动化测试'), findsOneWidget);

    await tester.tap(find.text('设备'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('保留设备页输入'), findsOneWidget);
  });

  testWidgets('OTA module keeps its form after the device disconnects', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final binding = tester.binding;
    final messenger = binding.defaultBinaryMessenger;
    const channel = MethodChannel('com.soni.soni_sdk_demo/recordPen');
    const events = MethodChannel('com.soni.soni_sdk_demo/eventChannel');
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    messenger.setMockMethodCallHandler(events, (_) async => null);
    final provider = RecordPenProvider();
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
      messenger.setMockMethodCallHandler(events, null);
      binding.removeObserver(provider);
      provider.dispose();
      return provider.streamController.close();
    });
    await provider.init();

    Future<void> emitConnection(int? type) async {
      await messenger.handlePlatformMessage(
        events.name,
        const StandardMethodCodec().encodeSuccessEnvelope(
          jsonEncode({
            'cmd': 2,
            'data': {
              'connect_state': type == null ? '0' : '1',
              'name': 'CB08',
              'address': type == null ? 'null' : 'AA:BB:CC:00:00:48',
              if (type != null) 'productType': type,
            },
          }),
        ),
        (_) {},
      );
      await tester.pump();
    }

    await tester.pumpWidget(
      MaterialApp(
        theme: createDemoTheme(),
        home: DemoHomeTabs(
          device: const SizedBox.expand(),
          testPage: DemoTestPage(provider: provider),
        ),
      ),
    );
    await tester.tap(find.text('测试'));
    await tester.pumpAndSettle();
    expect(find.text('杰理OTA自动化测试'), findsNothing);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('文件传输测试'), findsOneWidget);
    expect(find.text('全部文件传输测试'), findsOneWidget);
    expect(find.text('单文件重复传输测试'), findsOneWidget);
    await emitConnection(30);
    expect(find.text('杰理OTA自动化测试'), findsNothing);
    expect(find.text('文件传输测试'), findsOneWidget);

    await emitConnection(48);
    expect(find.text('杰理OTA自动化测试'), findsOneWidget);
    expect(find.text('48 · CB08'), findsOneWidget);
    final reportShare = find.text('分享报告');
    expect(reportShare, findsOneWidget);
    expect(find.text('清空报告'), findsOneWidget);
    expect(tester.getCenter(reportShare).dy, closeTo(tester.getCenter(find.text('48 · CB08')).dy, 1));
    expect(find.descendant(of: find.byType(OtaAutomationModule), matching: find.text('48 · CB08')), findsNothing);
    expect(find.text('测试次数'), findsOneWidget);
    expect(find.text('失败次数 0'), findsOneWidget);
    for (final slot in [1, 2]) {
      final file = find.widgetWithText(TextButton, '固件文件$slot');
      final version = find.widgetWithText(TextFormField, '固件版本$slot');
      expect(file, findsOneWidget);
      expect(version, findsOneWidget);
      expect(tester.getCenter(file).dy, closeTo(tester.getCenter(version).dy, 1));
    }
    final start = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '启动测试'),
    );
    expect(start.onPressed, isNotNull);
    expect(tester.takeException(), isNull);

    await tester.enterText(find.byType(TextFormField).first, '12');
    await emitConnection(null);
    expect(find.text('杰理OTA自动化测试'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, '启动测试'))
          .onPressed,
      isNull,
    );
    await emitConnection(48);
    expect(find.text('12'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('leaving the test tab waits for interruption confirmation', (
    tester,
  ) async {
    var decision = Completer<bool>();
    await tester.pumpWidget(MaterialApp(
      home: DemoHomeTabs(
        device: const Text('设备内容'),
        testPage: const Text('测试内容'),
        onLeaveTest: () => decision.future,
      ),
    ));
    await tester.tap(find.text('测试'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设备'));
    await tester.pumpAndSettle();
    expect(find.text('测试内容'), findsOneWidget);
    decision.complete(false);
    await tester.pumpAndSettle();
    expect(find.text('测试内容'), findsOneWidget);

    decision = Completer<bool>();
    await tester.tap(find.text('设备'));
    await tester.pump();
    decision.complete(true);
    await tester.pumpAndSettle();
    expect(find.text('设备内容'), findsOneWidget);
  });
}
