import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'logger.dart';

/// App 本地 HTTP 服务，供 BK 设备下载固件。
/// 固件来自用户通过文件管理选择的本地文件。
class BkUpgradeHttpServer {
  BkUpgradeHttpServer._();

  static final BkUpgradeHttpServer instance = BkUpgradeHttpServer._();

  static const int port = 8080;

  HttpServer? _server;
  File? _firmwareFile;
  String _serveFileName = 'update.bin';

  bool get isRunning => _server != null;

  String? get servingUrl => _servingUrl;
  String? _servingUrl;

  String? get firmwarePath => _firmwareFile?.path;

  /// 启动服务，[firmwareFile] 为手机上已选中的固件文件。
  Future<String> start({required File firmwareFile}) async {
    await stop();

    if (!await firmwareFile.exists()) {
      throw StateError('固件文件不存在: ${firmwareFile.path}');
    }

    // 统一拷到临时目录，避免 content:// / 权限受限路径读失败
    _firmwareFile = await _copyToCache(firmwareFile);
    _serveFileName = p.basename(_firmwareFile!.path);
    if (_serveFileName.isEmpty) {
      _serveFileName = 'update.bin';
    }

    final localIp = await _resolveLocalIpv4();
    if (localIp == null) {
      throw StateError('未获取到局域网 IP，请先连接设备 WiFi / 热点');
    }

    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    final encodedName = Uri.encodeComponent(_serveFileName);
    _servingUrl = 'http://$localIp:$port/$encodedName';
    Log.f('BK HTTP 已启动: $_servingUrl  file=${_firmwareFile!.path}');

    _server!.listen((request) async {
      try {
        await _handleRequest(request);
      } catch (e, st) {
        Log.e('BK HTTP 处理异常: $e\n$st');
        try {
          request.response.statusCode = HttpStatus.internalServerError;
          await request.response.close();
        } catch (_) {}
      }
    });

    return _servingUrl!;
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _servingUrl = null;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final path = request.uri.path;
    final reqName = request.uri.pathSegments.isEmpty
        ? ''
        : request.uri.pathSegments.last;
    final matched = path == '/' ||
        reqName == _serveFileName ||
        path == '/$_serveFileName' ||
        path.endsWith('/$_serveFileName') ||
        reqName.toLowerCase().endsWith('.bin') ||
        reqName.toLowerCase().endsWith('.rbl');

    if (request.method == 'GET' && matched) {
      final file = _firmwareFile;
      if (file == null || !await file.exists()) {
        request.response.statusCode = HttpStatus.notFound;
        request.response.write('firmware missing');
        await request.response.close();
        return;
      }

      final bytes = await file.readAsBytes();
      request.response.statusCode = HttpStatus.ok;
      request.response.headers.contentType = ContentType(
        'application',
        'octet-stream',
      );
      request.response.headers.contentLength = bytes.length;
      request.response.headers.set(
        'Content-Disposition',
        'attachment; filename="$_serveFileName"',
      );
      request.response.add(bytes);
      await request.response.close();
      Log.d('BK HTTP 已响应固件下载: ${bytes.length} bytes');
      return;
    }

    request.response.statusCode = HttpStatus.notFound;
    request.response.write('Not Found');
    await request.response.close();
  }

  Future<File> _copyToCache(File source) async {
    final dir = await getTemporaryDirectory();
    final name = p.basename(source.path);
    final safeName = name.isEmpty ? 'update.bin' : name;
    final dest = File('${dir.path}/bk_fw_$safeName');
    await source.copy(dest.path);
    Log.d('固件已拷贝到缓存: ${source.path} -> ${dest.path} (${await dest.length()} bytes)');
    return dest;
  }

  /// 优先选常见局域网网段的 IPv4。
  Future<String?> _resolveLocalIpv4() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLinkLocal: false,
    );

    final candidates = <String>[];
    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        if (addr.isLoopback) continue;
        candidates.add(addr.address);
      }
    }
    if (candidates.isEmpty) return null;

    String? prefer(bool Function(String ip) test) {
      for (final ip in candidates) {
        if (test(ip)) return ip;
      }
      return null;
    }

    return prefer((ip) => ip.startsWith('192.168.')) ??
        prefer((ip) => ip.startsWith('10.')) ??
        prefer((ip) => ip.startsWith('172.')) ??
        candidates.first;
  }
}
