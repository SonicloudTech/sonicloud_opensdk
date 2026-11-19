import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soni_sdk_demo/service_bk_http.dart';

class _RealHttpOverrides extends HttpOverrides {}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  late Directory directory;
  final servers = <BkUpgradeHttpServer>[];

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('soni-bk-http-');
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      paths,
      (_) async => directory.path,
    );
  });
  tearDown(() async {
    for (final server in servers) {
      await server.stop();
    }
    servers.clear();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(paths, null);
    await directory.delete(recursive: true);
  });

  Future<List<int>> download(String url, {int? expectedLength}) =>
      HttpOverrides.runWithHttpOverrides(() async {
        final client = HttpClient();
        try {
          final request = await client.getUrl(
            Uri.parse(url).replace(host: '127.0.0.1'),
          );
          final response = await request.close();
          expect(response.statusCode, HttpStatus.ok);
          if (expectedLength != null) {
            expect(response.contentLength, expectedLength);
          }
          return response.fold<List<int>>(
            [],
            (bytes, chunk) => bytes..addAll(chunk),
          );
        } finally {
          client.close(force: true);
        }
      }, _RealHttpOverrides());

  test(
    'serves an encoded filename with an actual port and Content-Length',
    () async {
      final file = await File(
        '${directory.path}/固件 update.bin',
      ).writeAsBytes([0, 1, 2, 255]);
      final server = BkUpgradeHttpServer(listenPort: 0);
      servers.add(server);
      final url = await server.start(firmwareFile: file);
      expect(Uri.parse(url).port, greaterThan(0));
      expect(url, contains('%20'));
      expect(await download(url, expectedLength: 4), [0, 1, 2, 255]);
      await server.stop();
      expect(server.isRunning, isFalse);
      expect(server.servingUrl, isNull);
    },
  );

  test(
    'independent HTTP servers cannot overwrite each others cached firmware',
    () async {
      final firstDirectory = await Directory(
        '${directory.path}/first',
      ).create();
      final secondDirectory = await Directory(
        '${directory.path}/second',
      ).create();
      final first = await File(
        '${firstDirectory.path}/firmware.bin',
      ).writeAsBytes([1, 2, 3]);
      final second = await File(
        '${secondDirectory.path}/firmware.bin',
      ).writeAsBytes([4, 5]);
      final firstServer = BkUpgradeHttpServer(listenPort: 0);
      final secondServer = BkUpgradeHttpServer(listenPort: 0);
      servers.addAll([firstServer, secondServer]);
      final firstUrl = await firstServer.start(firmwareFile: first);
      final secondUrl = await secondServer.start(firmwareFile: second);
      expect(await download(firstUrl, expectedLength: 3), [1, 2, 3]);
      expect(await download(secondUrl, expectedLength: 2), [4, 5]);
    },
  );
}
