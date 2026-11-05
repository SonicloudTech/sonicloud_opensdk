import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soni_sdk_demo/demo_home_tabs.dart';
import 'package:soni_sdk_demo/demo_theme.dart';

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
        home: const DemoHomeTabs(device: TextField()),
      ),
    );

    expect(find.text('设备'), findsOneWidget);
    expect(find.text('测试'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), '保留设备页输入');

    await tester.tap(find.text('测试'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.text('设备'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('保留设备页输入'), findsOneWidget);
  });
}
