import 'dart:io';

import 'package:flutter/services.dart';

class FileSharer {
  static const _channel = MethodChannel('com.soni.soni_sdk_demo/recordPen');

  static Future<bool> share(
    File source,
    Directory temporaryDirectory, {
    Future<File> Function(String)? copySource,
    bool uniqueName = false,
  }) async {
    final root = Directory('${temporaryDirectory.path}/shared_files');
    await root.create(recursive: true);
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    await for (final entry in root.list()) {
      if (entry is Directory &&
          (await entry.stat()).modified.isBefore(cutoff)) {
        try {
          await entry.delete(recursive: true);
        } on FileSystemException {
          // A stale cache must not prevent sharing a new file.
        }
      }
    }
    final staging = await root.createTemp('share-');
    var shared = false;
    try {
      var name = source.uri.pathSegments.last;
      if (uniqueName) {
        final dot = name.lastIndexOf('.');
        final stem = dot < 0 ? name : name.substring(0, dot);
        final extension = dot < 0 ? '' : name.substring(dot);
        final time = DateTime.now().toIso8601String()
            .replaceAll(RegExp(r'[-:.]'), '').replaceFirst('T', '_');
        final token = staging.uri.pathSegments
            .where((part) => part.isNotEmpty).last.substring('share-'.length);
        // 本地存储按文件名展示报告，导出时区分新旧快照。
        name = '${stem}_${time}_$token$extension';
      }
      final snapshot = await (copySource ?? source.copy)(
        '${staging.path}/$name',
      );
      final mimeType = switch (source.path.toLowerCase().split('.').last) {
        'txt' => 'text/plain',
        'wav' => 'audio/wav',
        'ogg' => 'audio/ogg',
        _ => 'application/octet-stream',
      };
      shared =
          await _channel.invokeMethod<bool>('shareFile', {
            'path': snapshot.path,
            'mimeType': mimeType,
          }) ??
          false;
      return shared;
    } finally {
      // Messaging apps can read the URI after Android's chooser has closed.
      if (!shared && await staging.exists()) {
        await staging.delete(recursive: true);
      }
    }
  }
}
