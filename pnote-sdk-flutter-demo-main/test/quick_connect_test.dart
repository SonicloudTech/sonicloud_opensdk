import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soni_sdk_demo/provider_record_pen.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.soni.soni_sdk_demo/recordPen');

  test('quick connection sends an empty string for an open hotspot', () async {
    final calls = <MethodCall>[];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    final provider = RecordPenProvider();
    try {
      await provider.quickConnectDeviceWiFi();
      expect(calls.single.method, 'quickConnectDeviceWiFi');
      expect(calls.single.arguments, {'password': ''});
    } finally {
      binding.removeObserver(provider);
      provider.dispose();
      await provider.streamController.close();
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    }
  });
}
