import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soni_sdk_demo/demo_log_header.dart';
import 'package:soni_sdk_demo/demo_theme.dart';

void main() {
  testWidgets(
    'log header actions sit between title and count and stay usable',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final messenger = tester.binding.defaultBinaryMessenger;
      String? clipboard;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map)['text'] as String;
        }
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      });
      var autoScroll = false;
      final logs = ['第一行', '第二行'];
      await tester.pumpWidget(
        MaterialApp(
        theme: createDemoTheme(),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => DemoLogHeader(
                lineCount: logs.length,
                autoScroll: autoScroll,
                onAutoScrollChanged: (value) =>
                    setState(() => autoScroll = value),
                onClear: () => setState(logs.clear),
                onCopy: () =>
                    Clipboard.setData(ClipboardData(text: logs.join('\n'))),
              ),
            ),
          ),
        ),
      );

      final labels = ['日志', '自动滚底', '清屏', '复制log', '2 行'];
      for (var i = 1; i < labels.length; i++) {
        expect(
          tester.getCenter(find.text(labels[i])).dx,
          greaterThan(tester.getCenter(find.text(labels[i - 1])).dx),
        );
      }
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      await tester.tap(find.text('复制log'));
      await tester.pump();
      expect(clipboard, '第一行\n第二行');
      await tester.tap(find.text('清屏'));
      await tester.pump();
      expect(find.text('0 行'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
