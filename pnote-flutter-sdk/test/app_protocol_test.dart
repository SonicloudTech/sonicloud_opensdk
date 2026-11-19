import 'dart:convert';
import 'dart:typed_data';

import 'package:pnote_flutter_sdk/pnote_flutter_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppCodec 生成 app 侧 JSON', () {
    test('电量 cmd=6 → {"cbc":"95"}', () {
      final json = AppCodec.encode(
        AppCodec.battery(const BatteryInfo(percent: 95, charging: false)),
      );
      final m = jsonDecode(json) as Map<String, dynamic>;
      expect(m['cmd'], '6');
      expect(m['state'], '0');
      expect((m['data'] as Map)['cbc'], '95');
    });

    test('电量充电中 → cbc=110', () {
      final json = AppCodec.encode(
        AppCodec.battery(const BatteryInfo(percent: 100, charging: true)),
      );
      final data = (jsonDecode(json) as Map)['data'] as Map;
      expect(data['cbc'], '110');
    });

    test('容量 cmd=13 → residueSpace/totalSpace', () {
      final json = AppCodec.encode(
        AppCodec.capacity(const Capacity(freeKb: 1024, totalKb: 8192)),
      );
      final m = jsonDecode(json) as Map<String, dynamic>;
      expect(m['cmd'], '13');
      expect((m['data'] as Map)['residueSpace'], '1024');
      expect((m['data'] as Map)['totalSpace'], '8192');
    });

    test('版本 cmd=17', () {
      final m = jsonDecode(AppCodec.encode(AppCodec.version('1.2.23'))) as Map;
      expect(m['cmd'], '17');
      expect((m['data'] as Map)['version'], '1.2.23');
    });

    test('SN cmd=7（用 MAC 代替）', () {
      final m = jsonDecode(AppCodec.encode(AppCodec.sn('D1:A1:C4:00:01:24')))
          as Map;
      expect(m['cmd'], '7');
      expect((m['data'] as Map)['sn'], 'D1:A1:C4:00:01:24');
    });

    test('物理按键 cmd=8', () {
      final m = jsonDecode(AppCodec.encode(AppCodec.keyEvent(1))) as Map;
      expect(m['cmd'], '8');
      expect((m['data'] as Map)['event'], '1');
    });

    test('录音状态 cmd=9：recording→1, idle→2', () {
      final rec = jsonDecode(
              AppCodec.encode(AppCodec.recordStateReply(RecordState.recording)))
          as Map;
      expect((rec['data'] as Map)['recordState'], '1');
      final idle = jsonDecode(
              AppCodec.encode(AppCodec.recordStateReply(RecordState.idle)))
          as Map;
      expect((idle['data'] as Map)['recordState'], '2');
    });

    test('文件列表 cmd=4：data 为数组 + finish', () {
      // 真机格式：大端字段 + 变长名字(以 '.' 结尾)
      final params = Uint8List.fromList([
        0, 0, 0, 1, // count=1 大端
        0, 0, 0, 60, // duration=60 大端
        0, 0, 16, 0, // size=4096 大端
        ...'note20251231121212.'.codeUnits, // 名字以 '.' 结尾
      ]);
      final files = FileList.parse(params);
      final m = jsonDecode(AppCodec.encode(AppCodec.fileList(files))) as Map;
      expect(m['cmd'], '4');
      expect(m['finish'], '1');
      final arr = m['data'] as List;
      expect(arr.length, 1);
      expect((arr[0] as Map)['time'], '60');
      expect((arr[0] as Map)['size'], '4096');
      expect((arr[0] as Map)['name'], 'note20251231121212.opus');
    });
  });
}
