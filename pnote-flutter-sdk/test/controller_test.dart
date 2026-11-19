import 'dart:async';
import 'dart:typed_data';

import 'package:pnote_flutter_sdk/src/pen/audio_pen_controller.dart';
import 'package:pnote_flutter_sdk/src/pen/commands.dart';
import 'package:pnote_flutter_sdk/src/pen/frame.dart';
import 'package:pnote_flutter_sdk/src/pen/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_transport.dart';

void main() {
  late FakeTransport transport;
  late AudioPenController controller;

  setUp(() {
    transport = FakeTransport();
    controller = AudioPenController(transport);
    controller.start();
  });

  test('getBattery 发指令并解析回包', () async {
    final future = controller.getBattery();
    // 给事件循环一拍，让请求帧先发出
    await Future<void>.delayed(Duration.zero);
    transport.deviceSend(DataType.control, ControlCmd.replyBattery, [88]);

    final battery = await future;
    expect(battery.percent, 88);

    // 验证发出过 getBattery 指令帧
    final reqFrame = FrameCodec.decode(transport.sent.first)!.frame;
    expect(reqFrame.dataType, DataType.control);
    expect(reqFrame.cmd, ControlCmd.getBattery);
  });

  test('收到设备帧后自动回 ACK', () async {
    transport.deviceSend(DataType.control, ControlCmd.deviceMode, [0x02]);
    await Future<void>.delayed(Duration.zero);

    // sent 中应包含一个 ACK 帧（dataType=3，无 cmd，seq=0）
    final ackFrames = transport.sent
        .map((b) => FrameCodec.decode(b)!.frame)
        .where((f) => f.dataType == DataType.ack && f.payload.isEmpty);
    expect(ackFrames, isNotEmpty);
    expect(ackFrames.first.seq, 0);
  });

  test('deviceMode 帧分发到 statusStream', () async {
    final modeFuture = controller.statusStream.first;
    transport.deviceSend(DataType.control, ControlCmd.deviceMode, [0x02]);
    final mode = await modeFuture;
    expect(mode.recording, true);
  });

  test('请求超时抛 TimeoutException', () async {
    final c = AudioPenController(transport,
        responseTimeout: const Duration(milliseconds: 50));
    c.start();
    expect(c.getVersion(), throwsA(isA<TimeoutException>()));
  });

  // 录音指令对齐 iOS 端（DATA_AUDIO 通道），fire-and-forget。
  group('录音指令走 audio 通道（对齐 iOS）', () {
    List<Frame> sentFrames() =>
        transport.sent.map((b) => FrameCodec.decode(b)!.frame).toList();

    test('开始录音 → 01 00', () async {
      final ok = await controller.startRecord();
      expect(ok, true);
      final f = sentFrames().last;
      expect(f.dataType, DataType.realtime); // 0x01
      expect(f.cmd, AudioCmd.startRecord); // 0x00
      expect(f.params, isEmpty);
    });

    test('停止录音 → 01 02，连发两次', () async {
      final ok = await controller.stopRecord();
      expect(ok, true);
      final stops = sentFrames()
          .where((f) =>
              f.dataType == DataType.realtime && f.cmd == AudioCmd.stopRecord)
          .toList();
      expect(stops.length, 2);
    });

    test('暂停录音 → 01 03 01', () async {
      await controller.pauseRecord();
      final f = sentFrames().last;
      expect(f.dataType, DataType.realtime);
      expect(f.cmd, AudioCmd.pausePlay); // 0x03
      expect(f.params, [AudioCmd.pauseFlag]); // 0x01
    });

    test('继续录音 → 01 03 00', () async {
      await controller.resumeRecord();
      final f = sentFrames().last;
      expect(f.dataType, DataType.realtime);
      expect(f.cmd, AudioCmd.pausePlay); // 0x03
      expect(f.params, [AudioCmd.resumeFlag]); // 0x00
    });
  });

  // 接收：设备端物理暂停/继续（audio AUDIO_PAUSE_PLAY_BY_DEVICE=0x04）。
  group('接收设备端暂停/继续（对齐 iOS）', () {
    test('flag=1 暂停 → state 2', () async {
      final future = controller.deviceRecordStream.first;
      transport.deviceSend(
          DataType.realtime, AudioCmd.pausePlayByDevice, [1]);
      expect(await future, 2);
    });

    test('flag=0 继续 → state 3', () async {
      final future = controller.deviceRecordStream.first;
      transport.deviceSend(
          DataType.realtime, AudioCmd.pausePlayByDevice, [0]);
      expect(await future, 3);
    });

    test('flag=2 停止 → state 0', () async {
      final future = controller.deviceRecordStream.first;
      transport.deviceSend(
          DataType.realtime, AudioCmd.pausePlayByDevice, [2]);
      expect(await future, 0);
    });
  });

  // 接收：物理按键帧（key/DATA_TYPE_BTN=0x03）分发到 keyEventStream。
  test('物理按键帧分发到 keyEventStream', () async {
    final future = controller.keyEventStream.first;
    transport.deviceSend(DataType.key, KeyCmd.keyStartRecord, const []);
    final f = await future;
    expect(f.dataType, DataType.key);
    expect(f.cmd, KeyCmd.keyStartRecord); // 1
  });

  // 文件列表多帧累积（cmd=1 多帧 + cmd=18 收尾）。
  test('文件列表：多帧 cmd=1 累积，cmd=18 收尾', () async {
    final future = controller.getFileList();
    await Future<void>.delayed(Duration.zero);

    // 大端字段 + 变长名字(以 '.' 结尾，无填充)，与真机一致。
    List<int> be4(int v) =>
        [(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];
    Uint8List record(int time, int size, String name) {
      // 名字以 '.' 结尾（设备真实格式）。
      return Uint8List.fromList(
          [...be4(time), ...be4(size), ...'$name.'.codeUnits]);
    }
    transport.deviceSend(DataType.file, FileCmd.replyFileList,
        [...[0, 0, 0, 1], ...record(60, 4096, 'note20250101120000')]);
    transport.deviceSend(DataType.file, FileCmd.replyFileList,
        [...[0, 0, 0, 1], ...record(90, 8192, 'call20250101130000')]);
    // 结束帧（cmd=18，无 params）。
    transport.deviceSend(DataType.file, FileCmd.fileListDone, const []);

    final files = await future;
    expect(files.length, 2);
    expect(files[0].durationSec, 60);
    expect(files[0].sizeBytes, 4096);
    expect(files[0].name, 'note20250101120000.opus');
    expect(files[0].isCall, false);
    expect(files[1].durationSec, 90);
    expect(files[1].sizeBytes, 8192);
    expect(files[1].name, 'call20250101130000.opus');
    expect(files[1].isCall, true);
  });

  // 文件下载（设备主动推流：cmd=3 文件名 / cmd=4 数据 / cmd=5 结束）。
  test('文件下载：收齐 cmd=4 数据，cmd=5(0) 完成', () async {
    final doneFuture = controller.downloadFile('note20250101.opus');
    await Future<void>.delayed(Duration.zero); // 让请求帧先发出

    // 验证请求帧：file/requestFile + offset(小端0) + name
    final req = FrameCodec.decode(transport.sent.first)!.frame;
    expect(req.dataType, DataType.file);
    expect(req.cmd, FileCmd.requestFile);
    expect(req.params.sublist(0, 4), [0, 0, 0, 0]); // offset 小端
    expect(String.fromCharCodes(req.params.sublist(4)), 'note20250101.opus');

    // 收集数据流
    final chunks = <int>[];
    final dataSub = controller.fileDataStream.listen(chunks.addAll);
    final progress = <int>[];
    final progSub = controller.downloadProgressStream.listen(progress.add);

    // 设备推流
    transport.deviceSend(DataType.file, FileCmd.fileStart,
        'note20250101.opus'.codeUnits);
    transport.deviceSend(DataType.file, FileCmd.fileData, [1, 2, 3]);
    transport.deviceSend(DataType.file, FileCmd.fileData, [4, 5]);
    transport.deviceSend(DataType.file, FileCmd.fileEnd, [0]); // 完成

    final result = await doneFuture;
    expect(result.success, true);
    expect(result.endCode, FileEndCode.completed);
    expect(result.fileName, 'note20250101.opus');
    expect(result.receivedBytes, 5);
    expect(chunks, [1, 2, 3, 4, 5]);
    expect(progress, [3, 5]);
    await dataSub.cancel();
    await progSub.cancel();
  });

  test('文件下载：cmd=5(2) offset 过大 → 失败', () async {
    final doneFuture = controller.downloadFile('x.opus');
    await Future<void>.delayed(Duration.zero);
    transport.deviceSend(DataType.file, FileCmd.fileEnd, [2]);
    final result = await doneFuture;
    expect(result.success, false);
    expect(result.endCode, FileEndCode.offsetTooLarge);
  });

  test('终止下载：发出 cmd=7', () async {
    await controller.abortDownload();
    final last = transport.sent.map((b) => FrameCodec.decode(b)!.frame).last;
    expect(last.dataType, DataType.file);
    expect(last.cmd, FileCmd.abortImport);
  });

  // 删除文件（cmd=8 请求，设备回 cmd=13：1B 0成功/1失败）。
  test('删除文件：cmd=8 请求(4B padding+name)，cmd=13(0) 成功', () async {
    final future = controller.delFileData('note20250101.opus');
    await Future<void>.delayed(Duration.zero); // 让请求帧先发出

    final req = FrameCodec.decode(transport.sent.first)!.frame;
    expect(req.dataType, DataType.file);
    expect(req.cmd, FileCmd.deleteFiles); // 8
    expect(req.params.sublist(0, 4), [0, 0, 0, 0]); // padding（对齐 iOS 布局）
    expect(String.fromCharCodes(req.params.sublist(4)), 'note20250101.opus');

    transport.deviceSend(DataType.file, FileCmd.replyDeleteFiles, [0]); // 成功
    expect(await future, true);
  });

  test('删除文件：cmd=13(1) 失败', () async {
    final future = controller.delFileData('x.opus');
    await Future<void>.delayed(Duration.zero);
    transport.deviceSend(DataType.file, FileCmd.replyDeleteFiles, [1]); // 失败
    expect(await future, false);
  });

  // 分段下载（cmd=12 请求，body=offset(LE)+end(LE)+name；回包仍走 cmd=3/4/5）。
  test('分段下载：cmd=12 请求 body=offset(LE)+end(LE)+name', () async {
    final doneFuture =
        controller.downloadFile('note.opus', offset: 10, end: 20);
    await Future<void>.delayed(Duration.zero);

    final req = FrameCodec.decode(transport.sent.first)!.frame;
    expect(req.dataType, DataType.file);
    expect(req.cmd, FileCmd.requestFileByFromToEnd); // 12
    expect(req.params.sublist(0, 4), [10, 0, 0, 0]); // offset=10 小端
    expect(req.params.sublist(4, 8), [20, 0, 0, 0]); // end=20 小端
    expect(String.fromCharCodes(req.params.sublist(8)), 'note.opus');

    // 设备推流（与普通下载相同的 cmd=3/4/5）
    transport.deviceSend(
        DataType.file, FileCmd.fileStart, 'note.opus'.codeUnits);
    transport.deviceSend(DataType.file, FileCmd.fileData, [1, 2]);
    transport.deviceSend(DataType.file, FileCmd.fileEnd, [0]);

    final result = await doneFuture;
    expect(result.success, true);
    expect(result.receivedBytes, 2);
  });

  // 实时录音音频流（audio AUDIO_DATA，cmd=0x01）：_streaming 门控。
  group('实时录音音频流 recordDataStream', () {
    test('录音开始后 opus 帧透传，参数原样', () async {
      await controller.startRecord(); // 置门控
      final future = controller.recordDataStream.first;
      transport.deviceSend(DataType.realtime, AudioCmd.data, [9, 9, 9]);
      final bytes = await future;
      expect(bytes, [9, 9, 9]);
    });

    test('未开流（未开始录音）时丢弃', () async {
      var received = false;
      final sub = controller.recordDataStream.listen((_) => received = true);
      transport.deviceSend(DataType.realtime, AudioCmd.data, [1]);
      await Future<void>.delayed(Duration.zero);
      expect(received, false);
      await sub.cancel();
    });

    test('停止录音后丢弃（门控复位）', () async {
      await controller.startRecord();
      await controller.stopRecord(); // 门控复位
      var received = false;
      final sub = controller.recordDataStream.listen((_) => received = true);
      transport.deviceSend(DataType.realtime, AudioCmd.data, [1]);
      await Future<void>.delayed(Duration.zero);
      expect(received, false);
      await sub.cancel();
    });
  });

  tearDown(() async {
    await controller.dispose();
  });
}
