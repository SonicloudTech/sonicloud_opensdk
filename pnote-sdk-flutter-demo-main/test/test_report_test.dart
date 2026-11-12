import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:soni_sdk_demo/test_report.dart';

void main() {
  test('clearing removes saved and pending report content before new tests', () async {
    final directory = await Directory.systemTemp.createTemp('soni-clear-');
    addTearDown(() => directory.delete(recursive: true));
    final report = TestReportStore(directory: () async => directory);
    report.append('旧测试结果\n');
    await report.fileForSharing();
    report.append('清空前的最后结果\n');
    await report.clear();
    expect(await report.fileForSharing(), isNull);
    report.append('新的测试结果\n');
    final file = await report.fileForSharing();
    expect(await file!.readAsString(), '新的测试结果\n');
    report.dispose();
  });

  test('report snapshots serialize before later completion rows', () async {
    final directory = await Directory.systemTemp.createTemp('soni-snapshot-');
    addTearDown(() => directory.delete(recursive: true));
    final report = TestReportStore(directory: () async => directory);
    report.append('第一轮：成功\n');
    await report.fileForSharing();
    final copy = report.copyForSharing('${directory.path}/snapshot.txt');
    report.append('第二轮：成功\n');
    final snapshot = await copy;
    expect(await snapshot.readAsString(), '第一轮：成功\n');
    final live = await report.fileForSharing();
    expect(await live!.readAsString(), '第一轮：成功\n第二轮：成功\n');
    report.dispose();
  });

  for (final phase in ['write', 'flush', 'close']) {
    test('a failed $phase retries without partial or duplicate rows', () async {
      final directory = await Directory.systemTemp.createTemp('soni-write-');
      addTearDown(() => directory.delete(recursive: true));
      var fail = false;
      final report = TestReportStore(
        directory: () async => directory,
        fileFactory: (path) =>
            fail ? _FailingFile(File(path), phase) : File(path),
      );
      report.append('已有结果\n');
      await report.fileForSharing();
      fail = true;
      report.append('完整的新结果\n');
      await expectLater(
        report.fileForSharing(),
        throwsA(isA<FileSystemException>()),
      );
      fail = false;
      report.append('下一轮\n');
      final file = await report.fileForSharing();
      expect(await file!.readAsString(), '已有结果\n完整的新结果\n下一轮\n');
      report.dispose();
    });
  }

  test('reports append in order and survive reopening the store', () async {
    final directory = await Directory.systemTemp.createTemp('soni-report-');
    addTearDown(() => directory.delete(recursive: true));
    final report = TestReportStore(directory: () async => directory);
    report.append('\n\n（2026-11-11 15:30:00）\n单次传输测试\n');
    report.append('1/2 结果：成功\n');
    final file = await report.fileForSharing();
    expect(await file!.readAsString(), contains('单次传输测试\n1/2 结果：成功\n'));
    report.dispose();
    final reopened = TestReportStore(directory: () async => directory);
    reopened.append('2/2 结果：失败 失败原因：断开\n');
    final second = await reopened.fileForSharing();
    expect(second!.path, file.path);
    expect(
      await second.readAsString(),
      endsWith('1/2 结果：成功\n2/2 结果：失败 失败原因：断开\n'),
    );
    reopened.dispose();
  });

  test(
    'failed report writes retain text and retry without duplicates',
    () async {
      final directory = await Directory.systemTemp.createTemp('soni-report-');
      addTearDown(() => directory.delete(recursive: true));
      var fail = true;
      final report = TestReportStore(
        directory: () async {
          if (fail) throw const FileSystemException('磁盘不可用');
          return directory;
        },
      );
      report.append('第一轮\n');
      await expectLater(
        report.fileForSharing(),
        throwsA(isA<FileSystemException>()),
      );
      expect(report.lastError, isNotNull);
      fail = false;
      report.append('第二轮\n');
      final file = await report.fileForSharing();
      expect(await file!.readAsString(), '第一轮\n第二轮\n');
      expect(report.lastError, isNull);
      report.dispose();
    },
  );

  test('report time and rate use elapsed hours and real bytes', () {
    expect(
      formatTestDuration(const Duration(hours: 27, minutes: 2, seconds: 5)),
      '27:02:05',
    );
    expect(formatTestRate(3072000, const Duration(seconds: 5)), '600.0KB/s');
    expect(formatTestRate(0, Duration.zero), '0.0KB/s');
    expect(
      formatTestTimestamp(DateTime(2026, 11, 11, 15, 2, 5)),
      '2026-11-11 15:02:05',
    );
  });
}

class _FailingFile extends Fake implements File {
  _FailingFile(this.file, this.phase);
  final File file;
  final String phase;

  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) async =>
      _FailingWriter(await file.open(mode: mode), phase);
}

class _FailingWriter extends Fake implements RandomAccessFile {
  _FailingWriter(this.file, this.phase);
  final RandomAccessFile file;
  final String phase;

  @override
  Future<int> length() => file.length();

  @override
  Future<RandomAccessFile> truncate(int length) => file.truncate(length);

  @override
  Future<RandomAccessFile> setPosition(int position) =>
      file.setPosition(position);

  @override
  Future<RandomAccessFile> writeString(
    String string, {
    Encoding encoding = utf8,
  }) async {
    await file.writeString(
      phase == 'write' ? string.substring(0, 2) : string,
      encoding: encoding,
    );
    if (phase == 'write') throw const FileSystemException('写入中断');
    return this;
  }

  @override
  Future<RandomAccessFile> flush() async {
    await file.flush();
    if (phase == 'flush') throw const FileSystemException('flush 失败');
    return this;
  }

  @override
  Future<void> close() async {
    await file.close();
    if (phase == 'close') throw const FileSystemException('关闭失败');
  }
}
