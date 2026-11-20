/// 歌词下载端点测试：请求装配（lyrics 主机 + 6 个端点参数）+ status=200
/// 判定、contenttype 三档、4MB 预算、decode_envelope 恢复与输入校验。
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/lyric.dart';
import 'package:mimao/music/api/lyric_api.dart';
import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/client/kugou_identity.dart';

import '../capture_adapter.dart';

/// 假会话：ensureDevice 直接返回给定身份，不联网、不落盘。
MusicSession _session(KugouClient client, KugouIdentity identity) =>
    MusicSession(
      client: client,
      ensureDevice: () async => identity,
      loadIdentity: () async => identity,
      saveIdentity: (_) async {},
    );

const MusicLyricDownloadQuery _query = MusicLyricDownloadQuery(
  id: 'lyric-id-1',
  accesskey: 'ak123',
);

Future<void> _expectKind(
  Future<Object?> future,
  String kind, {
  int? code,
  String? message,
  String? reason,
}) async {
  await expectLater(
    future,
    throwsA(
      predicate(
        (Object e) =>
            e is KugouApiException &&
            e.kind == kind &&
            (code == null || e.code == code) &&
            (message == null || e.message == message),
      ),
    ),
    reason: reason,
  );
}

void main() {
  test('请求装配：GET lyrics.kugou.com/download，6 个端点参数 + 普通签名', () async {
    final adapter = CaptureAdapter(
      jsonBytes(
        '{"status":200,"error_code":0,"contenttype":1,"content":"bGlyYw"}',
      ),
    );
    final client = KugouClient(dio: Dio()..httpClientAdapter = adapter);
    // 注册过的设备 + 账号身份：普通签名路径会带账号字段与真 dfid。
    final identity = KugouIdentity(
      userId: 42,
      token: 'tok',
      t1: '',
      mid: 'midX',
      dfid: 'realDfid009',
      uuid: '-',
      guid: 'guidX',
      mac: '02:00:00:00:00:00',
      deviceName: '',
      renderFingerprint: '',
    );

    final lyric = await fetchLyricDownload(_session(client, identity), _query);

    expect(lyric.format, 'lrc');
    expect(adapter.requests, hasLength(1));
    final request = adapter.requests.single;
    expect(request.method, 'GET');
    expect(
      '${adapter.captured.uri}'.startsWith('https://lyrics.kugou.com/download'),
      isTrue,
    );
    // 6 个端点参数（ver/client/id/accesskey/fmt/charset）。
    expect(request.query['ver'], '1');
    expect(request.query['client'], 'android');
    expect(request.query['id'], 'lyric-id-1');
    expect(request.query['accesskey'], 'ak123');
    expect(request.query['fmt'], 'krc');
    expect(request.query['charset'], 'utf8');
    // 普通签名请求路径：保留设备默认参数与账号字段 + Android 签名。
    expect(request.query['signature'], isNotNull);
    expect(request.query['appid'], '3116');
    expect(request.query['dfid'], 'realDfid009');
    expect(request.query['mid'], 'midX');
    expect(request.query['userid'], '42');
    expect(request.headers.containsKey('x-router'), isFalse);
  });

  test('成功三档：contenttype 0/1/2 → krc/lrc/text，content 原样透传', () async {
    final adapter = CaptureAdapter(jsonBytes('{}'))
      ..responses.addAll(<Uint8List>[
        jsonBytes(
          '{"status":200,"error_code":0,"contenttype":0,"content":"encoded-krc"}',
        ),
        jsonBytes(
          '{"status":200,"error_code":0,"contenttype":1,"content":"encoded-lrc"}',
        ),
        jsonBytes(
          '{"status":"200","error_code":"0","contenttype":"2","content":123}',
        ),
      ]);
    final client = KugouClient(dio: Dio()..httpClientAdapter = adapter);
    final session = _session(client, KugouIdentity.anonymous());
    final expected = <String>['krc', 'lrc', 'text'];
    final expectedContent = <String>['encoded-krc', 'encoded-lrc', '123'];
    for (var index = 0; index < 3; index++) {
      final lyric = await fetchLyricDownload(session, _query);
      expect(lyric.format, expected[index], reason: 'index=$index');
      expect(lyric.encoding, 'base64');
      expect(lyric.content, expectedContent[index], reason: 'index=$index');
    }
  });

  test('成功判定不是 status=1：status=1 且 error_code=0 → business', () async {
    final adapter = CaptureAdapter(
      jsonBytes('{"status":1,"error_code":0,"contenttype":0,"content":"x"}'),
    );
    final client = KugouClient(dio: Dio()..httpClientAdapter = adapter);
    await _expectKind(
      fetchLyricDownload(_session(client, KugouIdentity.anonymous()), _query),
      'business',
      code: 0,
      message: '歌词获取失败',
    );
  });

  test('业务失败：status=0 error_code=3102 → business 带码', () async {
    final adapter = CaptureAdapter(
      jsonBytes('{"status":0,"error_code":3102,"contenttype":0}'),
    );
    final client = KugouClient(dio: Dio()..httpClientAdapter = adapter);
    await _expectKind(
      fetchLyricDownload(_session(client, KugouIdentity.anonymous()), _query),
      'business',
      code: 3102,
    );
  });

  test('contenttype 3 → unsupported；contenttype 非标量 → decode', () async {
    final unsupported = CaptureAdapter(
      jsonBytes('{"status":200,"error_code":0,"contenttype":3}'),
    );
    await _expectKind(
      fetchLyricDownload(
        _session(
          KugouClient(dio: Dio()..httpClientAdapter = unsupported),
          KugouIdentity.anonymous(),
        ),
        _query,
      ),
      'unsupported',
      message: '暂不支持此歌词编码',
    );

    final notScalar = CaptureAdapter(
      jsonBytes('{"status":200,"error_code":0,"contenttype":true}'),
    );
    await _expectKind(
      fetchLyricDownload(
        _session(
          KugouClient(dio: Dio()..httpClientAdapter = notScalar),
          KugouIdentity.anonymous(),
        ),
        _query,
      ),
      'decode',
    );
  });

  test('4MB 预算：content 字节数超限 → limit；恰好 4MB 通过', () async {
    const overLimit = 4 * 1024 * 1024 + 1;
    final adapter = CaptureAdapter(
      jsonBytes(
        '{"status":200,"error_code":0,"contenttype":0,"content":"${'A' * overLimit}"}',
      ),
    );
    await _expectKind(
      fetchLyricDownload(
        _session(
          KugouClient(dio: Dio()..httpClientAdapter = adapter),
          KugouIdentity.anonymous(),
        ),
        _query,
      ),
      'limit',
      message: '接口资源超过解码内存预算',
    );

    const boundary = 4 * 1024 * 1024;
    final okAdapter = CaptureAdapter(
      jsonBytes(
        '{"status":200,"error_code":0,"contenttype":0,"content":"${'A' * boundary}"}',
      ),
    );
    final lyric = await fetchLyricDownload(
      _session(
        KugouClient(dio: Dio()..httpClientAdapter = okAdapter),
        KugouIdentity.anonymous(),
      ),
      _query,
    );
    expect(lyric.format, 'krc');
    expect(lyric.content.length, boundary);
  });

  test('decode_envelope 恢复：结构坏但有业务码 → business；无码 → decode', () async {
    // contenttype 缺失 + error_code=700 → 恢复 business(700)。
    final recoverable = CaptureAdapter(
      jsonBytes('{"status":0,"error_code":700}'),
    );
    await _expectKind(
      fetchLyricDownload(
        _session(
          KugouClient(dio: Dio()..httpClientAdapter = recoverable),
          KugouIdentity.anonymous(),
        ),
        _query,
      ),
      'business',
      code: 700,
    );
    // status=0 且 error_code 不可解 → business(0)。
    final rejected = CaptureAdapter(
      jsonBytes('{"status":0,"error_code":true}'),
    );
    await _expectKind(
      fetchLyricDownload(
        _session(
          KugouClient(dio: Dio()..httpClientAdapter = rejected),
          KugouIdentity.anonymous(),
        ),
        _query,
      ),
      'business',
      code: 0,
    );
    // 无业务码可恢复 → decode。
    final plain = CaptureAdapter(jsonBytes('{"status":200}'));
    await _expectKind(
      fetchLyricDownload(
        _session(
          KugouClient(dio: Dio()..httpClientAdapter = plain),
          KugouIdentity.anonymous(),
        ),
        _query,
      ),
      'decode',
    );
    // 非 JSON 信封 → decode。
    final binary = CaptureAdapter(Uint8List.fromList(<int>[0x00, 0x01]));
    await _expectKind(
      fetchLyricDownload(
        _session(
          KugouClient(dio: Dio()..httpClientAdapter = binary),
          KugouIdentity.anonymous(),
        ),
        _query,
      ),
      'decode',
    );
  });

  test('登录过期（error_code=20018 / msg 文本）→ authentication', () async {
    for (final body in <String>[
      '{"status":0,"error_code":20018}',
      '{"status":0,"msg":"用户登录已过期，请重新登录"}',
    ]) {
      final adapter = CaptureAdapter(jsonBytes(body));
      await _expectKind(
        fetchLyricDownload(
          _session(
            KugouClient(dio: Dio()..httpClientAdapter = adapter),
            KugouIdentity.anonymous(),
          ),
          _query,
        ),
        'authentication',
        reason: body,
      );
    }
  });

  test('content 的 text 宽容：缺省 → 空串；bool/对象 → 空串（不抛）', () async {
    for (final body in <String>[
      '{"status":200,"error_code":0,"contenttype":2}',
      '{"status":200,"error_code":0,"contenttype":2,"content":false}',
      '{"status":200,"error_code":0,"contenttype":2,"content":{"raw":1}}',
    ]) {
      final adapter = CaptureAdapter(jsonBytes(body));
      final lyric = await fetchLyricDownload(
        _session(
          KugouClient(dio: Dio()..httpClientAdapter = adapter),
          KugouIdentity.anonymous(),
        ),
        _query,
      );
      expect(lyric.content, '', reason: body);
      expect(lyric.format, 'text');
    }
  });

  test('input 校验：id / accesskey 为空 → 歌词标识不完整，且不发请求', () async {
    final adapter = CaptureAdapter(jsonBytes('{"status":200,"error_code":0}'));
    final client = KugouClient(dio: Dio()..httpClientAdapter = adapter);
    final session = _session(client, KugouIdentity.anonymous());
    await _expectKind(
      fetchLyricDownload(
        session,
        const MusicLyricDownloadQuery(id: '', accesskey: 'ak123'),
      ),
      'input',
      message: '歌词标识不完整',
    );
    await _expectKind(
      fetchLyricDownload(
        session,
        const MusicLyricDownloadQuery(id: 'lyric-id-1', accesskey: ''),
      ),
      'input',
      message: '歌词标识不完整',
    );
    expect(adapter.requests, isEmpty);
  });

  test('组接口委托：KugouLyricApi.downloadLyric 与端点函数同链路', () async {
    final adapter = CaptureAdapter(
      jsonBytes(
        '{"status":200,"error_code":0,"contenttype":0,"content":"a2Rj"}',
      ),
    );
    final client = KugouClient(dio: Dio()..httpClientAdapter = adapter);
    final api = KugouLyricApi(_session(client, KugouIdentity.anonymous()));

    final lyric = await api.downloadLyric(_query);

    expect(lyric.format, 'krc');
    expect(lyric.encoding, 'base64');
    expect(lyric.content, 'a2Rj');
    expect(adapter.requests, hasLength(1));
  });
}
