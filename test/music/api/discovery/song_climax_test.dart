/// 歌曲高潮测试：GET 装配（data 参数/kg-* 头/climax 主机）、hash 校验、
/// 十进制串毫秒解码、空条目/非法元素容忍、status-only 成功判定。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/song_climax.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/client/kugou_identity.dart';

import '../capture_adapter.dart';
import 'fake_session.dart';

const String kHash32 = '0123456789abcdef0123456789ABCDEF';

void main() {
  late CaptureAdapter adapter;
  late KugouClient client;
  late KugouIdentity identity;
  late MusicSession session;

  setUp(() {
    adapter = CaptureAdapter(Uint8List(0));
    client = KugouClient(dio: Dio()..httpClientAdapter = adapter);
    identity = anonymousIdentity();
    session = fakeMusicSession(client, identity);
  });

  test('请求装配：GET/climax 主机/data 紧凑 JSON/kg-* 固定头', () async {
    adapter.bytes = jsonBytes(climaxWire());
    final segments = await fetchSongClimax(session, kHash32);
    expect(segments, hasLength(2));

    final request = adapter.requests.single;
    expect(request.method, 'GET');
    expect(
      request.path,
      'https://expendablekmrcdn.kugou.com/v1/audio_climax/audio',
    );
    expect(request.query['data'], '[{"hash":"$kHash32"}]');
    expect(request.headers['kg-rc'], '1');
    expect(request.headers['kg-thash'], '5d816a0');
    expect(request.headers['kg-rec'], '1');
    expect(request.headers['kg-rf'], 'B9EDA08A64250DEFFBCADDEE00F8F25F');
    expect(request.headers['x-router'], isNull);
  });

  test('input：hash 非法（长度/字符集）→ input，且不发请求', () async {
    for (final hash in <String>['', 'a' * 31, 'a' * 33, 'z' * 32]) {
      await expectLater(
        fetchSongClimax(session, hash),
        throwsA(
          predicate((Object e) => e is KugouApiException && e.kind == 'input'),
        ),
      );
    }
    expect(adapter.requests, isEmpty);
    // 大小写混合十六进制合法。
    expect(kugouValidSongHash('ABCDEF0123456789abcdef0123456789'), isTrue);
  });

  test('解码：十进制串/数字毫秒、全空条目不入表', () async {
    adapter.bytes = jsonBytes(
      '{"status":1,"error_code":0,"data":['
      '{"start_time":"1000","end_time":"2000","hash":"ABC"},'
      '{"start_time":3000},'
      '{}]}',
    );
    final segments = await fetchSongClimax(session, kHash32);
    expect(segments, hasLength(2));
    expect(segments[0].startMs, 1000);
    expect(segments[0].endMs, 2000);
    expect(segments[0].hash, 'ABC');
    expect(segments[1].startMs, 3000);
    expect(segments[1].endMs, isNull);
    expect(segments[1].hash, isNull);
  });

  test('边界：data 缺省/null/非数组/非法元素/全空 → 空表（不报错）', () async {
    for (final wire in <String>[
      '{"status":1,"error_code":0}',
      '{"status":1,"error_code":0,"data":null}',
      '{"status":1,"error_code":0,"data":5}',
      '{"status":1,"error_code":0,"data":[]}',
      '{"status":1,"error_code":0,"data":[5]}',
      '{"status":1,"error_code":0,"data":[{"start_time":" 100"}]}',
      '{"status":1,"error_code":0,"data":[{}]}',
    ]) {
      adapter.bytes = jsonBytes(wire);
      final segments = await fetchSongClimax(session, kHash32);
      expect(segments, isEmpty, reason: wire);
    }
    // " 100" 带空白 → Milliseconds 解析失败（u64::from_str 不容忍空白）。
    // hash 为数字 → 文本宽容成 '123'。
    adapter.bytes = jsonBytes(
      '{"status":1,"error_code":0,"data":[{"hash":123}]}',
    );
    final numericHash = await fetchSongClimax(session, kHash32);
    expect(numericHash.single.hash, '123');
  });

  test(
    '业务判定只看 status：status=0 → business；status=1 error_code=7 → 成功',
    () async {
      adapter.bytes = jsonBytes('{"status":0,"error_code":9}');
      await expectLater(
        fetchSongClimax(session, kHash32),
        throwsA(
          predicate(
            (Object e) =>
                e is KugouApiException && e.kind == 'business' && e.code == 9,
          ),
        ),
      );

      adapter.bytes = jsonBytes(
        '{"status":1,"error_code":7,"data":[{"start_time":1}]}',
      );
      final segments = await fetchSongClimax(session, kHash32);
      expect(segments.single.startMs, 1);
    },
  );
}

/// 最小可信 wire：两个带值条目 + 一个全空条目。
String climaxWire() => jsonEncode(<String, Object?>{
  'status': 1,
  'error_code': 0,
  'data': <Object?>[
    <String, Object?>{'start_time': '1000', 'end_time': '2000', 'hash': 'ABC'},
    <String, Object?>{'start_time': 3000},
    <String, Object?>{},
  ],
});
