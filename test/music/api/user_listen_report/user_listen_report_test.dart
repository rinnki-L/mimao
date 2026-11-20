/// 听歌上报协议测试：握手装配/解密、事件文本与加密复算、信封语义、input 校验。
///
/// 全部离线：CaptureAdapter 多响应 + 假 MusicSession + 固定时钟/随机源；
/// 签名与 AES 密文在测试侧按协议逐字复算。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/user_listen_report.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import 'package:mimao/music/models/user_listen_report_models.dart';

import '../capture_adapter.dart';
import 'listen_report_fixtures.dart';

String md5Text(String value) => md5.convert(utf8.encode(value)).toString();

String md5Bytes(List<int> value) => md5.convert(value).toString();

Matcher throwsKugou(String kind, String message, {int? code}) => throwsA(
  isA<KugouApiException>()
      .having((error) => error.kind, 'kind', kind)
      .having((error) => error.message, 'message', message)
      .having((error) => error.code, 'code', code),
);

Matcher throwsKind(String kind) => throwsA(
  isA<KugouApiException>().having((error) => error.kind, 'kind', kind),
);

int indexOfSeq(List<int> haystack, List<int> needle, int start) {
  for (var index = start; index <= haystack.length - needle.length; index++) {
    var matched = true;
    for (var offset = 0; offset < needle.length; offset++) {
      if (haystack[index + offset] != needle[offset]) {
        matched = false;
        break;
      }
    }
    if (matched) return index;
  }
  return -1;
}

/// 解出的 POST 事件载荷：plain 长度（= length 参数）+ header 文本 + fields 文本。
class DecodedPost {
  const DecodedPost(this.plainLength, this.header, this.fields);

  final int plainLength;
  final String header;
  final String fields;
}

/// 解密 /v2/post 请求体：AES（md5(uuid+clienttime+seed+serverstr)）→
/// zlib → header 文本 + zlib(fields)。
DecodedPost decodePostedEvent(
  CapturedRequest post,
  String uuid,
  int clienttime,
) {
  final body = post.data! as Uint8List;
  final cipherKey = utf8.encode(
    md5Text('$uuid$clienttime$listenReportEntropyHex$fixtureServerstr'),
  );
  final packed = aesCbcPkcs7Decrypt(body, cipherKey, aesIv(uuid));
  final plain = ZLibDecoder().convert(packed);
  final first = indexOfSeq(plain, const <int>[13, 10], 0);
  final second = indexOfSeq(plain, const <int>[13, 10], first + 2);
  final header = utf8.decode(plain.sublist(0, second + 2));
  final fields = utf8.decode(ZLibDecoder().convert(plain.sublist(second + 2)));
  return DecodedPost(plain.length, header, fields);
}

String expectedStartFields(int song, String uuid) =>
    'type_id=20431&action=play&fo3=3878,4320,4326,5747,5749,7229,7289,7863'
    '&spt=0&sty=手动&mixsongid=$song&source=46&ivar1=1&fo=/专辑播放页'
    '&mid=1234567890&uuid=$uuid&ss1=1&ss2=1&sys=9&mod=EchoMusicNext'
    '&channelid=18&ip=0.0.0.0&net=1&ver=10597&gitversion=7aa8a76'
    '&time=$listenReportMilliseconds&userid=42'
    '&ss3=${md5Text(listenReportEntropyHex)}';

String expectedEndFields(int song, int duration, bool completed, String uuid) {
  final state = completed ? '完整播放' : '中断播放';
  return 'type_id=4&action=play&fo3=3878,4320,4326,5747,5749,7229,7289,7863'
      '&duration=$duration&svar3=0&svar2=0&fo=我的音乐/主态/自建歌单/RU'
      '&sty=手动&state=$state&mixsongid=$song&source=46&ivar3=0&type=1'
      '&fs=1.0&ivar1=1&mid=1234567890&uuid=$uuid&ss1=1&ss2=1'
      '&sys=9&mod=EchoMusicNext&channelid=18&ip=0.0.0.0&net=1&ver=10597'
      '&gitversion=7aa8a76&time=$listenReportMilliseconds&userid=42'
      '&ss3=${md5Text(listenReportEntropyHex)}';
}

String expectedHeader(String fields, String uuid) =>
    '4\t1\t$uuid\t0\t3116\t10597\t18\t9\tEchoMusicNext'
    '\t$uuid\t1234567890\t0\t$kugouHeaderZeroBlock\r\n'
    '${utf8.encode(fields).length}\t10048\t0\t$listenReportSeconds\t1\t42\t0\t0\r\n';

/// 用自定义会话明文构造 /v2/gen 响应。
Uint8List genResponseWithSessionJson(String sessionJson) => jsonBytes(
  '{"status":1,"errcode":0,"data":"${base64Encode(aesCbcPkcs7Encrypt(utf8.encode(sessionJson), aesKey(listenReportEntropyHex), aesIv(listenReportUuid)))}"}',
);

void main() {
  late CaptureAdapter adapter;
  late KugouClient client;
  late KugouIdentity identity;
  late MusicSession session;
  late SequenceRandom random;
  late MusicListenReportSessionCache cache;

  setUp(() {
    adapter = CaptureAdapter(postOkResponse());
    client = KugouClient(dio: Dio()..httpClientAdapter = adapter);
    identity = listenReportIdentity();
    session = fakeListenReportSession(identity, client);
    random = SequenceRandom(listenReportEntropy);
    cache = MusicListenReportSessionCache();
  });

  void useIdentity(KugouIdentity value) {
    identity = value;
    session = fakeListenReportSession(value, client);
  }

  /// 重置缓存（信封分支用新缓存，互不串扰）。
  void freshCache() {
    cache = MusicListenReportSessionCache();
  }

  Future<MusicListenReportAcceptance> report(MusicListenReportQuery query) =>
      fetchListenReport(
        session,
        query,
        cache: cache,
        clock: listenReportClock,
        random: random,
      );

  MusicListenReportQuery startQuery({int song = 42}) => MusicListenReportQuery(
    event: MusicListenReportEvent.start,
    mixsongid: song,
  );

  MusicListenReportQuery endQuery({
    int song = 42,
    int? duration = 4250,
    bool completed = false,
  }) => MusicListenReportQuery(
    event: MusicListenReportEvent.end,
    mixsongid: song,
    durationMs: duration,
    completed: completed,
  );

  test('握手两步请求装配：URL/params/body/UA/签名逐字复算', () async {
    installHappyPath(adapter, listenReportEntropyHex, listenReportUuid);
    final acceptance = await report(startQuery());
    expect(acceptance.accepted, isTrue);

    expect(adapter.requests.length, 3);

    // 第一步 /v3/qrydid：POST，JSON body 字段序 machine/mid/uuid/wh。
    final qrydid = adapter.requests[0];
    expect(qrydid.method, 'POST');
    expect(qrydid.path, 'http://d.kugou.com/v3/qrydid');
    expect(qrydid.query['_t'], '$listenReportSeconds');
    expect(qrydid.query['appid'], 'and02');
    final body = qrydid.data! as Uint8List;
    expect(
      utf8.decode(body),
      '{"machine":"EchoMusicNext","mid":"1234567890",'
      '"uuid":"$listenReportUuid","wh":[1920,1080]}',
    );
    // sign = md5("_t<秒>appidand02pbKC7zn{4U*ydo2M1Rir" + body 字节)。
    expect(
      qrydid.query['sign'],
      md5Bytes(<int>[
        ...utf8.encode(
          '_t${listenReportSeconds}appidand02pbKC7zn{4U*ydo2M1Rir',
        ),
        ...body,
      ]),
    );
    // /v3/qrydid 不带 KG-Rec/UA（request_cscc 分支）；POST 是 octet-stream。
    expect(qrydid.headers.containsKey('KG-Rec'), isFalse);
    expect(qrydid.headers.containsKey('User-Agent'), isFalse);
    expect(qrydid.headers['Content-Type'], 'application/octet-stream');

    // 第二步 /v2/gen：GET，KG-Rec + CsccGen UA。
    final gen = adapter.requests[1];
    expect(gen.method, 'GET');
    expect(gen.path, 'http://d.kugou.com/v2/gen');
    expect(gen.query['_t'], '$listenReportSeconds');
    expect(gen.query['appid'], '3116');
    final portrait = gen.query['s']!;
    expect(
      gen.query['sign'],
      md5Text(
        '_t${listenReportSeconds}appid3116s$portrait$kugouListenReportAppKey',
      ),
    );
    expect(gen.headers['KG-Rec'], '1');
    expect(gen.headers['User-Agent'], kugouListenReportGenUserAgent);
    expect(gen.headers.containsKey('Content-Type'), isFalse);
    // RSA PKCS#1 v1.5 输出 128 字节；明文文本单独对拍。
    expect(base64Decode(portrait).length, 128);
    expect(
      listenReportPortraitText(
        uuid: listenReportUuid,
        seed: listenReportEntropyHex,
        milliseconds: listenReportMilliseconds,
        deviceId: fixtureDeviceId,
      ),
      '$listenReportUuid\t$listenReportEntropyHex\t'
      '$listenReportMilliseconds\t$fixtureDeviceId',
    );
  });

  test('握手响应解密传导：post cookie 与事件密钥取自会话三件套', () async {
    installHappyPath(adapter, listenReportEntropyHex, listenReportUuid);
    await report(startQuery());

    final post = adapter.requests[2];
    expect(post.path, 'http://d.kugou.com/v2/post');
    expect(post.method, 'POST');
    // cookie 参数来自 /v2/gen 解密出的 SessionData.cookie。
    expect(post.query['cookie'], fixtureCookie);
    expect(post.headers['KG-Rec'], '1');
    expect(post.headers['User-Agent'], kugouListenReportPostUserAgent);
    expect(post.headers['Content-Type'], 'application/octet-stream');
    // 事件密钥 = md5(uuid + clienttime + seed + serverstr)：解密成功即证明
    // clienttime/serverstr/seed 与 fixture 三件套一致。
    final decoded = decodePostedEvent(
      post,
      listenReportUuid,
      fixtureClienttime,
    );
    expect(decoded.fields, isNotEmpty);
    expect(decoded.header, isNotEmpty);
  });

  test('clienttime 为数字字符串时精确解析并参与密钥', () async {
    installHappyPath(adapter, listenReportEntropyHex, listenReportUuid);
    adapter.responses[1] = genResponseWithSessionJson(
      '{"cookie":"str-cookie","clienttime":"456","serverstr":"$fixtureServerstr"}',
    );
    await report(startQuery());

    final post = adapter.requests[2];
    expect(post.query['cookie'], 'str-cookie');
    // 用 456（而非默认 123）作密钥成分应可解密。
    final body = post.data! as Uint8List;
    final cipherKey = utf8.encode(
      md5Text('${listenReportUuid}456$listenReportEntropyHex$fixtureServerstr'),
    );
    final packed = aesCbcPkcs7Decrypt(body, cipherKey, aesIv(listenReportUuid));
    expect(ZLibDecoder().convert(packed), isNotEmpty);
  });

  test('start 事件：header/fields 文本、zlib 内容、length 与 sign 复算', () async {
    installHappyPath(adapter, listenReportEntropyHex, listenReportUuid);
    await report(startQuery(song: 42));

    final post = adapter.requests[2];
    final decoded = decodePostedEvent(
      post,
      listenReportUuid,
      fixtureClienttime,
    );
    final fields = expectedStartFields(42, listenReportUuid);
    expect(decoded.fields, fields);
    expect(decoded.header, expectedHeader(fields, listenReportUuid));
    // length 参数 = 明文（header + zlib(fields)）字节长度。
    expect(int.parse(post.query['length']!), decoded.plainLength);
    // sign = md5(BTreeMap 序拼接的 key+value + APPKEY + 密文字节)。
    final body = post.data! as Uint8List;
    final query = post.query;
    final joined =
        '_t${query['_t']}appid${query['appid']}cookie${query['cookie']}'
        'length${query['length']}';
    expect(query['_t'], '$listenReportSeconds');
    expect(query['appid'], '3116');
    expect(
      query['sign'],
      md5Bytes(<int>[
        ...utf8.encode('$joined$kugouListenReportAppKey'),
        ...body,
      ]),
    );
  });

  test('end 事件：duration/state 文本（中断播放/完整播放/时长 0）', () async {
    installHappyPath(adapter, listenReportEntropyHex, listenReportUuid);
    await report(endQuery(song: 5288783, duration: 4250, completed: false));
    await report(endQuery(song: 5288783, duration: 9000, completed: true));

    final interrupted = decodePostedEvent(
      adapter.requests[2],
      listenReportUuid,
      fixtureClienttime,
    );
    expect(
      interrupted.fields,
      expectedEndFields(5288783, 4250, false, listenReportUuid),
    );
    expect(
      interrupted.header,
      expectedHeader(
        expectedEndFields(5288783, 4250, false, listenReportUuid),
        listenReportUuid,
      ),
    );
    final completed = decodePostedEvent(
      adapter.requests[3],
      listenReportUuid,
      fixtureClienttime,
    );
    expect(
      completed.fields,
      expectedEndFields(5288783, 9000, true, listenReportUuid),
    );
    expect(
      completed.header,
      expectedHeader(
        expectedEndFields(5288783, 9000, true, listenReportUuid),
        listenReportUuid,
      ),
    );
    // 会话仍缓存：第三次 end(duration=0) 只发 1 个请求（Rust 只要求 Some）。
    final before = adapter.requests.length;
    await report(endQuery(song: 1, duration: 0));
    expect(adapter.requests.length, before + 1);
    final zero = decodePostedEvent(
      adapter.requests.last,
      listenReportUuid,
      fixtureClienttime,
    );
    expect(zero.fields, expectedEndFields(1, 0, false, listenReportUuid));
  });

  test('uuid 归一化：显式 uuid 去连字符后进入 body/fields，guid 不参与', () async {
    useIdentity(
      copyIdentity(
        listenReportIdentity(),
        uuid: '0011-2233-4455-6677-8899-aabbccddeeff',
      ),
    );
    installHappyPath(adapter, listenReportEntropyHex, listenReportUuid);
    await report(startQuery());

    final body = adapter.requests[0].data! as Uint8List;
    expect(utf8.decode(body), contains('"uuid":"$listenReportUuid"'));
    final decoded = decodePostedEvent(
      adapter.requests[2],
      listenReportUuid,
      fixtureClienttime,
    );
    expect(decoded.fields, contains('uuid=$listenReportUuid'));
    expect(decoded.header, contains(listenReportUuid));
  });

  test('uuid 为 - 时回退 guid（宿主带连字符，CSCC 用裸 32 位）', () async {
    // listenReportIdentity 默认 uuid='-'；guid 去连字符即 listenReportUuid。
    installHappyPath(adapter, listenReportEntropyHex, listenReportUuid);
    await report(startQuery());
    final body = adapter.requests[0].data! as Uint8List;
    expect(utf8.decode(body), contains('"uuid":"$listenReportUuid"'));
    expect(utf8.decode(body), isNot(contains('-')));
  });

  test('input：uuid 不足/超过 32 位或含非字母数字', () async {
    final cases = <(String, KugouIdentity)>[
      (
        'guid 短',
        copyIdentity(listenReportIdentity(), guid: '0011223344556677889'),
      ),
      (
        'uuid 33 位',
        copyIdentity(
          listenReportIdentity(),
          uuid: '00112233445566778899aabbccddeefff',
        ),
      ),
      (
        'uuid 去分隔符后不足 32',
        copyIdentity(
          listenReportIdentity(),
          uuid: '00112233-4455-6677-8899-aabbccddeef',
        ),
      ),
      (
        'uuid 含非字母数字',
        copyIdentity(
          listenReportIdentity(),
          uuid: '00112233445566778899aabbccddeef#',
        ),
      ),
    ];
    for (final (name, value) in cases) {
      useIdentity(value);
      await expectLater(
        report(startQuery()),
        throwsKugou('input', '听歌上报身份或事件不完整'),
      );
      expect(adapter.requests, isEmpty, reason: name);
    }
  });

  test('input：身份或事件不完整（匿名/缺 token/缺 mid/mixsongid=0/end 缺时长）', () async {
    final cases = <(String, KugouIdentity, MusicListenReportQuery)>[
      (
        '匿名',
        copyIdentity(listenReportIdentity(), userId: 0, token: ''),
        startQuery(),
      ),
      (
        '缺 token',
        copyIdentity(listenReportIdentity(), token: ''),
        startQuery(),
      ),
      ('缺 mid', copyIdentity(listenReportIdentity(), mid: ''), startQuery()),
      ('mixsongid=0', listenReportIdentity(), startQuery(song: 0)),
      ('end 缺 duration', listenReportIdentity(), endQuery(duration: null)),
    ];
    for (final (name, value, query) in cases) {
      useIdentity(value);
      await expectLater(report(query), throwsKugou('input', '听歌上报身份或事件不完整'));
      expect(adapter.requests, isEmpty, reason: name);
    }
  });

  test('input：设备资料无效（空/控制字符/&/超 128 字符）', () async {
    final cases = <(String, KugouIdentity)>[
      ('空 deviceName', copyIdentity(listenReportIdentity(), deviceName: '')),
      (
        '控制字符 U+0001',
        copyIdentity(listenReportIdentity(), deviceName: 'Echo\u0001Next'),
      ),
      (
        '控制字符 U+007F',
        copyIdentity(listenReportIdentity(), deviceName: 'Echo\u007F'),
      ),
      ('含 &', copyIdentity(listenReportIdentity(), deviceName: 'Echo&Next')),
      ('mid 含 &', copyIdentity(listenReportIdentity(), mid: '12&45')),
      ('129 字符', copyIdentity(listenReportIdentity(), deviceName: '中' * 129)),
    ];
    for (final (name, value) in cases) {
      useIdentity(value);
      await expectLater(
        report(startQuery()),
        throwsKugou('input', '听歌上报设备资料无效'),
      );
      expect(adapter.requests, isEmpty, reason: name);
    }
  });

  test('deviceName 恰 128 字符通过（字符数语义，非 UTF-16 码元）', () async {
    useIdentity(copyIdentity(listenReportIdentity(), deviceName: '中' * 128));
    installHappyPath(adapter, listenReportEntropyHex, listenReportUuid);
    final acceptance = await report(startQuery());
    expect(acceptance.accepted, isTrue);
    expect(adapter.requests.length, 3);
    // BMP 中文每字 1 个 UTF-16 码元 / 3 字节 UTF-8：128 字符 = 384 字节。
    final body = adapter.requests[0].data! as Uint8List;
    expect(utf8.decode(body), contains('"machine":"${'中' * 128}"'));
  });

  test('业务失败：status=0 / errcode 非 0（error_code 优先）/ 数字字符串宽容', () async {
    final cases = <(String, int?)>[
      ('{"status":0,"errcode":1203}', 1203),
      ('{"status":0}', null),
      ('{"status":1,"errcode":1203}', 1203),
      ('{"status":0,"error_code":0,"errcode":1203}', 1203),
      ('{"status":1,"errcode":0,"error_code":7}', 7),
      ('{"status":"0","errcode":0}', null),
    ];
    for (final (body, code) in cases) {
      freshCache();
      installHappyPath(
        adapter,
        listenReportEntropyHex,
        listenReportUuid,
        post: jsonBytes(body),
      );
      await expectLater(
        report(startQuery()),
        throwsKugou('business', '音乐服务拒绝了上报', code: code),
      );
    }
  });

  test('信封宽容：status 不可解析时按缺失处理（上游 optional 语义）', () async {
    installHappyPath(
      adapter,
      listenReportEntropyHex,
      listenReportUuid,
      post: jsonBytes('{"status":true,"errcode":0}'),
    );
    final acceptance = await report(startQuery());
    expect(acceptance.accepted, isTrue);
  });

  test('登录过期：error_code=20018 或 msg 文本 → authentication', () async {
    final cases = <(String, int?)>[
      ('{"error_code":20018}', 20018),
      ('{"error_code":"20018"}', 20018),
      ('{"msg":"用户登录已过期，请重新登录"}', null),
    ];
    for (final (body, code) in cases) {
      freshCache();
      installHappyPath(
        adapter,
        listenReportEntropyHex,
        listenReportUuid,
        post: jsonBytes(body),
      );
      await expectLater(
        report(startQuery()),
        throwsKugou('authentication', '登录已过期，请重新登录酷狗账号', code: code),
      );
    }
  });

  test('decode：响应非 JSON / 非 object', () async {
    for (final (body, message) in <(String, String)>[
      ('not json', '响应不是合法 JSON'),
      ('[1,2]', '响应信封不是 JSON object'),
    ]) {
      freshCache();
      installHappyPath(
        adapter,
        listenReportEntropyHex,
        listenReportUuid,
        post: jsonBytes(body),
      );
      await expectLater(report(startQuery()), throwsKugou('decode', message));
    }
  });

  test('decode：gen data 不是合法 base64 / 不是标量文本', () async {
    adapter.bytes = postOkResponse();
    adapter.responses
      ..add(qrydidOkResponse())
      ..add(jsonBytes('{"status":1,"errcode":0,"data":"not+base64!"}'))
      ..add(qrydidOkResponse())
      ..add(jsonBytes('{"status":1,"errcode":0,"data":{"cookie":"c"}}'));
    await expectLater(
      report(startQuery()),
      throwsKugou('decode', '上报会话密文不是合法 base64'),
    );
    await expectLater(
      report(startQuery()),
      throwsKugou('decode', '响应字段 data 不是标量文本'),
    );
    expect(adapter.requests.length, 4);
  });

  test('decode：会话明文缺字段 / 空值 / 非标量 clienttime', () async {
    adapter.bytes = postOkResponse();
    final cases = <(String, String)>[
      ('缺 serverstr', '{"cookie":"c","clienttime":1}'),
      ('cookie 空', '{"cookie":"","clienttime":1,"serverstr":"s"}'),
      ('clienttime 非标量', '{"cookie":"c","clienttime":true,"serverstr":"s"}'),
      ('clienttime 缺失', '{"cookie":"c","serverstr":"s"}'),
    ];
    for (final (_, sessionJson) in cases) {
      adapter.responses
        ..add(qrydidOkResponse())
        ..add(genResponseWithSessionJson(sessionJson));
    }
    for (final (name, _) in cases) {
      await expectLater(
        report(startQuery()),
        throwsKind('decode'),
        reason: name,
      );
    }
    expect(adapter.requests.length, cases.length * 2);
  });

  test('decode：qrydid data 缺 deviceid / deviceid 空 / data 非 object', () async {
    adapter.bytes = postOkResponse();
    final cases = <(String, String)>[
      ('deviceid 空', '{"status":1,"errcode":0,"data":{"deviceid":""}}'),
      ('缺 deviceid', '{"status":1,"errcode":0,"data":{}}'),
      ('data 非 object', '{"status":1,"errcode":0,"data":5}'),
      ('data 缺失', '{"status":1,"errcode":0}'),
      ('deviceid 非标量', '{"status":1,"errcode":0,"data":{"deviceid":true}}'),
    ];
    for (final (_, body) in cases) {
      adapter.responses.add(jsonBytes(body));
    }
    for (final (name, _) in cases) {
      await expectLater(
        report(startQuery()),
        throwsKind('decode'),
        reason: name,
      );
    }
    expect(adapter.requests.length, cases.length);
  });
}
