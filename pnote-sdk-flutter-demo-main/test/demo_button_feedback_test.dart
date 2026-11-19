import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soni_sdk_demo/demo_theme.dart';

void main() {
  const feedback = ValueKey('demo-button-feedback');

  for (final kind in ['filled', 'text', 'icon']) {
    testWidgets(
      'iOS $kind buttons briefly change color without delaying actions',
      (tester) async {
        var presses = 0;
        late Widget button;
        switch (kind) {
          case 'text':
            button = TextButton(
              onPressed: () => presses++,
              child: const Text('操作'),
            );
          case 'icon':
            button = IconButton(
              onPressed: () => presses++,
              icon: const Icon(Icons.play_arrow),
            );
          default:
            button = FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => presses++,
              child: const Text('操作'),
            );
        }
        await tester.pumpWidget(
          MaterialApp(
            theme: createDemoTheme().copyWith(platform: TargetPlatform.iOS),
            home: Scaffold(body: Center(child: button)),
          ),
        );
        final target = find.byWidget(button);
        await tester.tap(target);
        await tester.pump();
        expect(presses, 1);
        expect(
          find.descendant(of: target, matching: find.byKey(feedback)),
          findsOneWidget,
        );
        await tester.pump(const Duration(milliseconds: 150));
        expect(find.byKey(feedback), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.byKey(feedback), findsNothing);
        expect(presses, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'rapid presses are not blocked and disabled buttons do not flash',
    (tester) async {
      var presses = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: createDemoTheme(),
          home: Scaffold(
            body: Column(
              children: [
                FilledButton(
                  onPressed: () => presses++,
                  child: const Text('操作'),
                ),
                const TextButton(onPressed: null, child: Text('禁用')),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.text('禁用'));
      await tester.pump();
      expect(find.byKey(feedback), findsNothing);
      await tester.tap(find.text('操作'));
      await tester.pump(const Duration(milliseconds: 150));
      await tester.tap(find.text('操作'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(presses, 2);
      expect(find.byKey(feedback), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull);
    },
  );
}
