import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pnote_demo_app/main.dart';

void main() {
  testWidgets('app renders bottom navigation (en default)', (tester) async {
    await tester.pumpWidget(const PnoteDemoApp());

    expect(find.text('Devices'), findsOneWidget);
    expect(find.text('Recordings'), findsOneWidget);
    expect(find.text('Activity'), findsOneWidget);
    expect(find.text('Find your recorder'), findsOneWidget);
  });

  testWidgets('language menu switches to Chinese', (tester) async {
    await tester.pumpWidget(const PnoteDemoApp());

    await tester.tap(find.byIcon(Icons.language));
    await tester.pumpAndSettle();

    await tester.tap(find.text('中文').last);
    await tester.pumpAndSettle();

    expect(find.text('设备'), findsOneWidget);
    expect(find.text('录音文件'), findsOneWidget);
    expect(find.text('动态'), findsOneWidget);
    expect(find.text('查找你的录音笔'), findsOneWidget);
    expect(find.text('跟随系统'), findsNothing);
  });
}
