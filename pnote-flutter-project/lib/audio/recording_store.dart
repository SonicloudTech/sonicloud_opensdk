import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'opus_bootstrap.dart';
import 'wav.dart';

/// 录音文件本地存储：
/// - 设备下载的 .opus 直接落 `recordings/`；
/// - App 端实时录音落 `recordings/app/`（与设备文件区分）；
/// 播放前一律懒转换为 .wav。
class RecordingStore {
  RecordingStore._();

  static final RecordingStore instance = RecordingStore._();

  Directory? _dir;
  Directory? _appDir;

  Future<Directory> get _recordingsDir async {
    if (_dir != null) return _dir!;
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/recordings');
    await dir.create(recursive: true);
    _dir = dir;
    return dir;
  }

  Future<Directory> get _appRecordingsDir async {
    if (_appDir != null) return _appDir!;
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/recordings/app');
    await dir.create(recursive: true);
    _appDir = dir;
    return dir;
  }

  Future<File> opusFile(String name) async =>
      File('${(await _recordingsDir).path}/$name');

  Future<File> wavFile(String name) async =>
      File('${(await _recordingsDir).path}/${name.replaceAll('.opus', '')}.wav');

  Future<bool> hasOpus(String name) async =>
      (await opusFile(name)).existsSync();

  Future<File> appOpusFile(String name) async =>
      File('${(await _appRecordingsDir).path}/$name');

  Future<File> appWavFile(String name) async =>
      File('${(await _appRecordingsDir).path}/${name.replaceAll('.opus', '')}.wav');

  /// App 录音的转写文本（与 .opus 同名 .txt，停录时写入）。
  Future<File> appTranscriptFile(String name) async =>
      File('${(await _appRecordingsDir).path}/${name.replaceAll('.opus', '')}.txt');

  /// AI 纪要任务 ID（提交成功即落盘，失败重进不重复提交、同任务不重复计费）。
  Future<File> appTaskIdFile(String name) async =>
      File('${(await _appRecordingsDir).path}/${name.replaceAll('.opus', '')}.taskid');

  /// AI 纪要正文（Markdown）。
  Future<File> appSummaryFile(String name) async =>
      File('${(await _appRecordingsDir).path}/${name.replaceAll('.opus', '')}.summary.md');

  /// App 录音列表（recordings/app 内 .opus，按修改时间倒序）。
  Future<List<File>> listAppOpus() async => _listOpus(await _appRecordingsDir);

  /// 设备下载文件列表（recordings 根目录 .opus，按修改时间倒序）。
  Future<List<File>> listDownloadedOpus() async =>
      _listOpus(await _recordingsDir);

  Future<List<File>> _listOpus(Directory dir) {
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.opus'))
        .toList()
      ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return Future.value(files);
  }

  /// 删除该录音的本地缓存（opus + wav），仅设备下载文件用。
  Future<void> remove(String name) async {
    for (final f in [await opusFile(name), await wavFile(name)]) {
      try {
        if (await f.exists()) await f.delete();
      } catch (e) {
        debugPrint('[STORE] 删除缓存失败 $name: $e');
      }
    }
  }

  /// 删除一条 App 自录（opus + wav + 转写 txt + AI taskid/纪要）。
  Future<void> removeApp(String name) async {
    for (final f in [
      await appOpusFile(name),
      await appWavFile(name),
      await appTranscriptFile(name),
      await appTaskIdFile(name),
      await appSummaryFile(name),
    ]) {
      try {
        if (await f.exists()) await f.delete();
      } catch (e) {
        debugPrint('[STORE] 删除缓存失败 $name: $e');
      }
    }
  }

  Future<File> toWav(String name) async =>
      _opusToWav(await opusFile(name), await wavFile(name));

  Future<File> appToWav(String name) async =>
      _opusToWav(await appOpusFile(name), await appWavFile(name));

  /// opus（40B 定长帧）→ WAV。坏帧跳过，不中断整段转换。
  Future<File> _opusToWav(File opus, File wav) async {
    if (await wav.exists()) return wav;

    await ensureOpusInitialized();
    final decoder = createPenDecoder();
    try {
      final bytes = await opus.readAsBytes();
      final pcm = BytesBuilder();
      for (var i = 0; i + kOpusFrameSize <= bytes.length; i += kOpusFrameSize) {
        final out = decodePenFrame(
            decoder, Uint8List.sublistView(bytes, i, i + kOpusFrameSize));
        if (out != null) pcm.add(out);
      }
      await wav.writeAsBytes(
          encodeWav(pcm.takeBytes(), sampleRate: kOpusSampleRate));
      return wav;
    } finally {
      decoder.destroy();
    }
  }
}
