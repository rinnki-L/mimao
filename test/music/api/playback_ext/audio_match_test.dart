/// 听歌识曲端点测试（audio_match.rs）：PCM 校验（STANDARD base64/非空/≤160000/
/// 偶数长度）、请求装配（octet-stream + KuGou UA 固定头 + useid/fpid）、
/// 候选解码（SongSummary + CatalogSongFacts/资源回退链/confidence 排序）、
/// 信封与登录过期分支。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/audio_match.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import 'package:mimao/music/client/signature.dart';
import 'package:mimao/music/models/playback_ext_models.dart';

import '../capture_adapter.dart';
import 'fake_session.dart';

/// 固定测试时钟（fpid 断言用）。
final DateTime kTestNow = DateTime.fromMillisecondsSinceEpoch(
  1700000000123,
  isUtc: true,
);

/// 指定字节数的 PCM（int16 样本交替 1/-1；长度可为奇数以覆盖校验分支）。
Uint8List pcmBytes(int length) {
  final bytes = Uint8List(length);
  for (var i = 0; i + 1 < length; i += 2) {
    bytes[i] = 0x01;
    bytes[i + 1] = i % 4 == 0 ? 0x00 : 0xff;
  }
  return bytes;
}

AudioMatchQuery pcmQuery(Uint8List bytes) =>
    AudioMatchQuery(pcmBase64: base64Encode(bytes));

/// 识曲候选 wire（audio_match.rs `Candidate`）。
Map<String, Object?> candidateWire({
  Object? mixsongid = '339415062',
  Object? songname = '稻香',
  String singername = '周杰伦',
  String albumId = '14421203',
  String hashHit = 'SOMEHASHVALUE',
  String unionCover = 'http://imge.kugou.com/kugouicon/{size}/cover.jpg',
  Object? dist = 0.25,
  Object? privilege = 8,
  Object? isOriginal = 1,
  Object? timeoffset = 3500,
  Object? timelength128 = 265430,
  List<Object?> authors = const <Object?>[
    <String, Object?>{'author_id': 6076, 'author_name': '周杰伦'},
  ],
  List<Object?> album = const <Object?>[
    <String, Object?>{'albumid': '999', 'albumname': '其他专辑'},
    <String, Object?>{'albumid': '14421203', 'albumname': '魔杰座'},
  ],
  List<Object?> resPrivilege = const <Object?>[
    <String, Object?>{
      'type': 'audio',
      'pay_type': 3,
      'fail_process': 0,
      'old_cpy': 1,
      'trans_param': <String, Object?>{
        'qualitymap': <String, Object?>{'attr0': 0, 'attr1': 2, 'bits': '0101'},
        'cpy_attr0': 281629629091840,
        'is_original': 1,
        'hash_offset': <String, Object?>{
          'start_byte': 0,
          'end_byte': 65536,
          'start_ms': 0,
          'end_ms': 30000,
          'offset_hash': 'PREVIEWHASH',
        },
        'union_cover': 'http://imge.kugou.com/c/{size}/t.png',
        'ogg_128_hash': 'OGG128HASH',
        'ogg_128_filesize': 4096,
        'language': '国语',
        'cid': '42',
      },
    },
  ],
}) => <String, Object?>{
  'mixsongid': mixsongid,
  'songname': songname,
  'singername': singername,
  'album_id': albumId,
  'hash_hit': hashHit,
  'union_cover': unionCover,
  'PeakCount': 372,
  if (dist != null) 'dist': dist,
  if (privilege != null) 'privilege': privilege,
  if (isOriginal != null) 'is_original': isOriginal,
  if (timeoffset != null) 'timeoffset': timeoffset,
  'authors': authors,
  'album': album,
  'res_privilege': resPrivilege,
  'hash_128': 'HASH128',
  'filesize_128': 100,
  if (timelength128 != null) 'timelength_128': timelength128,
  'bitrate_128': 128,
  'hash_192': 'HASH192',
  'hash_320': 'HASH320',
  'filesize_320': 200,
  'hash_flac': 'HASHFLAC',
  'filesize_flac': 25325000,
  'hash_high': 'HASHHIGH',
  'timelength_high': 265430,
  'hash_super': 'HASHSUPER',
};

String matchWire({
  int status = 1,
  int errorCode = 0,
  Object? data = const <Object?>[],
}) => jsonEncode(<String, Object?>{
  'status': status,
  'error_code': errorCode,
  'data': data,
});

void main() {
  late CaptureAdapter adapter;
  late KugouClient client;
  late KugouIdentity identity;

  setUp(() {
    adapter = CaptureAdapter(jsonBytes(matchWire()));
    client = KugouClient(dio: Dio()..httpClientAdapter = adapter);
    identity = KugouIdentity.anonymous();
  });

  Future<List<MusicRecognitionMatch>> fetch(
    AudioMatchQuery query, {
    KugouIdentity? as,
  }) => fetchAudioMatch(
    fakePlaybackSession(client, as ?? identity),
    query,
    now: () => kTestNow,
  );

  test('input：非 canonical base64/非法字符 → 编码无效；空/超长/奇数 PCM → 单声道约束', () async {
    for (final pcm in const <String>[
      'QQ', // 长度非 4 倍数（缺 canonical padding）
      'A', // 同上
      '====', // 非法字符
      'A@==-20', // 非法字符
    ]) {
      await expectLater(
        fetch(AudioMatchQuery(pcmBase64: pcm)),
        throwsA(
          predicate(
            (Object e) =>
                e is KugouApiException &&
                e.kind == 'input' &&
                e.message.contains('识曲音频编码无效'),
          ),
        ),
      );
    }
    // 空 PCM：base64 合法解码成 0 字节 → 单声道约束错误。
    await expectLater(
      fetch(const AudioMatchQuery(pcmBase64: '')),
      throwsA(
        predicate((Object e) => e is KugouApiException && e.kind == 'input'),
      ),
    );
    await expectLater(
      fetch(pcmQuery(pcmBytes(160002))),
      throwsA(
        predicate(
          (Object e) =>
              e is KugouApiException && e.message.contains('十秒以内的单声道 PCM'),
        ),
      ),
    );
    await expectLater(
      fetch(pcmQuery(pcmBytes(160001))),
      throwsA(
        predicate(
          (Object e) =>
              e is KugouApiException && e.message.contains('十秒以内的单声道 PCM'),
        ),
      ),
    );
    // 边界合法：恰好 160000 字节且为偶数。
    adapter.bytes = jsonBytes(matchWire());
    await expectLater(fetch(pcmQuery(pcmBytes(160000))), completes);
  });

  test('请求装配：POST 网关路径/fpid=毫秒/useid/固定头/octet-stream body 原样字节', () async {
    final pcm = pcmBytes(48);
    await fetch(pcmQuery(pcm));

    final captured = adapter.requests.single;
    expect(captured.method, 'POST');
    expect(
      captured.path,
      'https://gateway.kugou.com/fingerprint.service/v1/music_trackid_mulit',
    );
    final query = captured.query;
    // 端点参数（useid 是上游原样键名拼写）。
    expect(query['fpid'], '1700000000123');
    expect(query['area_code'], '1');
    expect(query['include_unpublish'], '1');
    expect(query['useid'], '0');
    expect(query['multi_result'], '1');
    // 普通签名请求：注入 lite 默认字段 + token/userid 缺席（匿名）。
    expect(query['appid'], '3116');
    expect(query['clientver'], '11440');
    expect(query['dfid'], identity.dfid);
    expect(query['mid'], identity.mid);
    expect(query['uuid'], '-');
    expect(query.containsKey('token'), isFalse);
    expect(query.containsKey('userid'), isFalse);
    // Android 签名覆盖 PCM 原始字节。
    final unsigned = <String, String>{...query}..remove('signature');
    expect(query['signature'], kugouSignatureAndroid(unsigned, pcm));
    // 固定头：KuGou UA 覆盖默认 UA；octet-stream；kg-* 逐条透传；无 router。
    expect(captured.headers['User-Agent'], 'KuGou/11490 (Android)');
    expect(captured.headers['Content-Type'], 'application/octet-stream');
    expect(captured.headers['kg-rc'], '1');
    expect(captured.headers['kg-thash'], '5d816a0');
    expect(captured.headers['kg-rec'], '1');
    expect(captured.headers['kg-rf'], 'B9EDA08A64250DEFFBCADDEE00F8F25F');
    expect(captured.headers['dfid'], identity.dfid);
    expect(captured.headers['mid'], identity.mid);
    expect(captured.headers['clienttime'], query['clienttime']);
    expect(captured.headers['x-router'], isNull);
    // body 是原始 PCM 字节，不经任何编码。
    expect(captured.data, isA<Uint8List>());
    expect(Uint8List.fromList((captured.data! as List<int>)), pcm);
  });

  test('请求装配：带账号身份 → useid/token/userid 跟随身份', () async {
    final account = identity.withAccount(userId: 123, token: 'tok');
    await fetch(pcmQuery(pcmBytes(16)), as: account);
    final query = adapter.requests.single.query;
    expect(query['useid'], '123');
    expect(query['token'], 'tok');
    expect(query['userid'], '123');
  });

  test(
    '解码：候选保留 SongSummary + CatalogSongFacts（资源回退链/权益/trans_param）',
    () async {
      adapter.bytes = jsonBytes(matchWire(data: <Object?>[candidateWire()]));
      final matches = await fetch(pcmQuery(pcmBytes(16)));
      expect(matches, hasLength(1));
      final song = matches.single.song;
      expect(song.id, '339415062');
      expect(song.hash, 'SOMEHASHVALUE');
      expect(song.title, '稻香');
      expect(song.artists, hasLength(1));
      expect(song.artists.single.id, 6076);
      expect(song.artists.single.name, '周杰伦');
      expect(song.albumId, '14421203');
      // 专辑名取 album 列表里 albumid == 候选 album_id 的那行。
      expect(song.albumTitle, '魔杰座');
      expect(song.durationMs, 265430);
      expect(song.coverUrl, 'http://imge.kugou.com/kugouicon/240/cover.jpg');
      expect(song.privilege, 8);

      final facts = song.facts;
      expect(facts.paymentType, 3);
      expect(facts.failureCode, 0);
      expect(facts.oldCopyrightCode, 1);
      expect(facts.originalityCode, 1);
      // 资源：trans_param 的 ogg 先产出（extension=ogg），后接 128/192/320/flac/
      // high/super 等（只保留至少一个事实的档位）。
      final qualities = facts.resources.map((r) => r.quality).toList();
      expect(qualities, <String>[
        'ogg_128',
        'standard',
        '192',
        'higher',
        'flac',
        'hi_res',
        'master',
      ]);
      final ogg = facts.resources.first;
      expect(ogg.hash, 'OGG128HASH');
      expect(ogg.sizeBytes, 4096);
      expect(ogg.extension, 'ogg');
      final flac = facts.resources.firstWhere((r) => r.quality == 'flac');
      expect(flac.hash, 'HASHFLAC');
      expect(flac.sizeBytes, 25325000);
      expect(flac.extension, 'flac');
      final standard = facts.resources.firstWhere(
        (r) => r.quality == 'standard',
      );
      expect(standard.bitRateBps, 128000);
      expect(standard.extension, 'mp3');
      // 无 hash_ape/filesize_ape → ape 档不产出。
      expect(qualities.contains('ape'), isFalse);

      final rights = facts.rights!;
      expect(rights.qualityMap!.attr0, 0);
      expect(rights.qualityMap!.attr1, 2);
      expect(rights.qualityMap!.bits, '0101');
      expect(rights.copyrightAttributes, 281629629091840);
      expect(rights.originalityCode, 1);
      expect(rights.preview!.startByte, 0);
      expect(rights.preview!.endMs, 30000);
      expect(rights.coverUrl, 'http://imge.kugou.com/c/240/t.png');
      expect(rights.voiceAd, isNull);
      expect(rights.blockedApplications, isNull);

      expect(matches.single.distance, 0.25);
      expect(matches.single.confidence, 0.75);
      expect(matches.single.timeOffset, 3500);
    },
  );

  test(
    '解码：authors 缺省回退 singername；dist 缺失 → confidence null；conf 降序排序',
    () async {
      final noAuthors = candidateWire(
        authors: const <Object?>[],
        dist: null,
        mixsongid: '1',
      );
      final far = candidateWire(dist: 0.5, mixsongid: '2');
      final close = candidateWire(dist: '0', mixsongid: '3');
      adapter.bytes = jsonBytes(
        matchWire(data: <Object?>[noAuthors, far, close]),
      );
      final matches = await fetch(pcmQuery(pcmBytes(16)));
      // confidence = 1 - clamp(dist)：3→1.0、2→0.5、1→null 排最后。
      expect(matches.map((m) => m.song.id).toList(), <String>['3', '2', '1']);
      expect(matches[0].confidence, 1.0);
      expect(matches[2].confidence, isNull);
      expect(matches[2].distance, isNull);
      // authors 缺省 + singername 非空 → ArtistRef(id: null, name: singername)。
      expect(matches[2].song.artists.single.id, isNull);
      expect(matches[2].song.artists.single.name, '周杰伦');
      // 数字文本 dist 按字符串解析（text → parse）。
    },
  );

  test(
    '解码宽容：data 缺失/null/空 object → 空表；数字文本 mixsongid；bool text → 空串',
    () async {
      for (final wire in <String>[
        jsonEncode(<String, Object?>{'status': 1}),
        jsonEncode(<String, Object?>{
          'status': 1,
          'error_code': 0,
          'data': null,
        }),
        jsonEncode(<String, Object?>{
          'status': 1,
          'error_code': 0,
          'data': <String, Object?>{},
        }),
      ]) {
        adapter.bytes = jsonBytes(wire);
        final matches = await fetch(pcmQuery(pcmBytes(16)));
        expect(matches, isEmpty);
      }
      adapter.bytes = jsonBytes(
        matchWire(
          data: <Object?>[
            candidateWire(
              mixsongid: 339415062,
              songname: true,
              privilege: '8',
              timeoffset: true,
            ),
          ],
        ),
      );
      final matches = await fetch(pcmQuery(pcmBytes(16)));
      expect(matches.single.song.id, '339415062');
      expect(matches.single.song.title, '', reason: 'text 收到 bool → 空串');
      expect(matches.single.song.privilege, 8);
      expect(
        matches.single.timeOffset,
        isNull,
        reason: 'optional 收到 bool → null',
      );
    },
  );

  test(
    '分支：status!=1 → business 带码；20018/msg → authentication；候选行非 object → decode',
    () async {
      adapter.bytes = jsonBytes(
        matchWire(status: 0, errorCode: 30005, data: <Object?>[]),
      );
      await expectLater(
        fetch(pcmQuery(pcmBytes(16))),
        throwsA(
          predicate(
            (Object e) =>
                e is KugouApiException &&
                e.kind == 'business' &&
                e.code == 30005,
          ),
        ),
      );
      adapter.bytes = jsonBytes(
        jsonEncode(<String, Object?>{
          'status': 1,
          'error_code': 20018,
          'data': [],
        }),
      );
      await expectLater(
        fetch(pcmQuery(pcmBytes(16))),
        throwsA(
          predicate(
            (Object e) =>
                e is KugouApiException &&
                e.kind == 'authentication' &&
                e.code == 20018,
          ),
        ),
      );
      adapter.bytes = jsonBytes(
        jsonEncode(<String, Object?>{'status': 0, 'msg': '用户登录已过期，请重新登录'}),
      );
      await expectLater(
        fetch(pcmQuery(pcmBytes(16))),
        throwsA(
          predicate(
            (Object e) =>
                e is KugouApiException &&
                e.kind == 'authentication' &&
                e.code == null,
          ),
        ),
      );
      // status=1 先过，再逐行解码：标量行 → decode。
      adapter.bytes = jsonBytes(matchWire(data: <Object?>[42]));
      await expectLater(
        fetch(pcmQuery(pcmBytes(16))),
        throwsA(predicate((Object e) => '$e'.contains('decode'))),
      );
      // trans_param 非对象：候选整体 decode 失败（serde 严格）。
      adapter.bytes = jsonBytes(
        matchWire(
          data: <Object?>[
            candidateWire(
              resPrivilege: <Object?>[
                <String, Object?>{'type': 'audio', 'trans_param': 'garbage'},
              ],
            ),
          ],
        ),
      );
      await expectLater(
        fetch(pcmQuery(pcmBytes(16))),
        throwsA(predicate((Object e) => '$e'.contains('decode'))),
      );
      // 非 JSON → decode。
      adapter.bytes = jsonBytes('not-json');
      await expectLater(
        fetch(pcmQuery(pcmBytes(16))),
        throwsA(predicate((Object e) => '$e'.contains('decode'))),
      );
    },
  );

  test(
    '解码：无 audio 权益行 → 付款/失败事实全空 + 空 trans 默认；timelength_128 缺失 → duration null',
    () async {
      adapter.bytes = jsonBytes(
        matchWire(
          data: <Object?>[
            candidateWire(
              resPrivilege: <Object?>[
                <String, Object?>{'type': 'copyright', 'pay_type': 9},
              ],
              timelength128: null,
            ),
          ],
        ),
      );
      final matches = await fetch(pcmQuery(pcmBytes(16)));
      final facts = matches.single.song.facts;
      expect(facts.paymentType, isNull);
      expect(facts.failureCode, isNull);
      expect(facts.oldCopyrightCode, isNull);
      expect(facts.rights, isNotNull);
      expect(facts.rights!.preview, isNull);
      // 无 trans_param → 无 ogg 资源；候选行的 suffix 资源仍逐档产出。
      expect(facts.resources.map((r) => r.quality).toList(), <String>[
        'standard',
        '192',
        'higher',
        'flac',
        'hi_res',
        'master',
      ]);
      expect(matches.single.song.durationMs, isNull);
    },
  );
}
