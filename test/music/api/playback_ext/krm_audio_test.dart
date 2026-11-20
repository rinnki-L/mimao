/// 歌曲资料补全端点测试（krm_audio.rs）：批量 ID 校验（1..100/非 0/去重）、
/// 请求装配（router/KG-TID/body 键序）、50 实体顺序分块合并、SongInformation
/// 解码（album_info 回退/extra 可选/__status 跳过）与信封分支。
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/krm_audio.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import 'package:mimao/music/client/signature.dart';
import 'package:mimao/music/models/playback_ext_models.dart';

import '../capture_adapter.dart';
import 'fake_session.dart';

/// krm 信封（krm_audio.rs `Wire`：data 缺省 null，无 list 的空对象宽容）。
String krmWire({
  int status = 1,
  int errorCode = 0,
  Object? data = const <Object?>[],
}) => jsonEncode(<String, Object?>{
  'status': status,
  'error_code': errorCode,
  if (data != null) 'data': data,
});

Map<String, Object?> recordWire({
  Object? albumAudioId = 339415062,
  String albumId = '14421203',
  Object? songname = '稻香',
  String baseAlbumName = '魔杰座',
  String language = '国语',
  String publishDate = '2008-10-15',
  Object? albumInfo = const <String, Object?>{
    'album_name': '魔杰座（专辑资料）',
    'cover': 'http://imge.kugou.com/{size}/c.png',
    'publish_date': '2008-10-14',
  },
  List<Object?> authors = const <Object?>[
    <String, Object?>{
      'base': <String, Object?>{
        'author_id': 6076,
        'author_name': '周杰伦',
        'avatar': 'http://imge.kugou.com/{size}/avatar.png',
        'is_publish': 1,
      },
    },
  ],
  Object? extra = const <String, Object?>{
    'composer': '周杰伦',
    'lyrics': '方文山',
    'bpm': 115,
    'bpm_type': '1',
    'bpm_desc': '快(BPM 115)',
  },
}) => <String, Object?>{
  'base': <String, Object?>{
    'album_audio_id': albumAudioId,
    'album_id': albumId,
    'songname': songname,
    'album_name': baseAlbumName,
    'language': language,
    'publish_date': publishDate,
  },
  if (albumInfo != null) 'album_info': albumInfo,
  'authors': authors,
  if (extra != null) 'extra': extra,
};

void main() {
  late CaptureAdapter adapter;
  late KugouClient client;
  late KugouIdentity identity;

  setUp(() {
    adapter = CaptureAdapter(jsonBytes(krmWire()));
    client = KugouClient(dio: Dio()..httpClientAdapter = adapter);
    identity = KugouIdentity.anonymous();
  });

  Future<List<MusicSongPresentation>> fetch(KrmAudioQuery query) =>
      fetchKrmAudio(fakePlaybackSession(client, identity), query);

  test('input：空/超 100/含 0/负数/重复 → 批量ID无效；边界 100 合法', () async {
    for (final ids in <List<int>>[
      <int>[],
      List.generate(101, (i) => i + 1),
      <int>[0, 1],
      <int>[-1],
      <int>[5, 5],
    ]) {
      await expectLater(
        fetch(KrmAudioQuery(albumAudioIds: ids)),
        throwsA(
          predicate(
            (Object e) =>
                e is KugouApiException &&
                e.kind == 'input' &&
                e.message.contains('歌曲资料批量ID无效'),
          ),
        ),
      );
    }
    await expectLater(
      fetch(KrmAudioQuery(albumAudioIds: List.generate(100, (i) => i + 1))),
      completes,
    );
  });

  test(
    '请求装配：POST /kmr/v2/audio + openapi.kugou.com router + KG-TID/body 键序',
    () async {
      await fetch(const KrmAudioQuery(albumAudioIds: <int>[339415062, 730888]));

      final captured = adapter.requests.single;
      expect(captured.method, 'POST');
      expect(captured.path, 'https://gateway.kugou.com/kmr/v2/audio');
      expect(captured.headers['x-router'], 'openapi.kugou.com');
      expect(captured.headers['KG-TID'], '238');
      expect(captured.headers['Content-Type'], 'application/json');
      // body 键序 = serde_json::json! 声明序：data（entity_id 数值）→ fields。
      expect(
        captured.bodyText,
        jsonEncode(<String, Object?>{
          'data': <Object?>[
            <String, Object?>{'entity_id': 339415062},
            <String, Object?>{'entity_id': 730888},
          ],
          'fields': 'album_info,base,authors.base,extra',
        }),
      );
      // 普通签名请求：默认字段 + Android 签名（覆盖 body 字节）。
      final query = captured.query;
      expect(query['appid'], '3116');
      expect(query['dfid'], identity.dfid);
      expect(query['uuid'], '-');
      final unsigned = <String, String>{...query}..remove('signature');
      expect(
        query['signature'],
        kugouSignatureAndroid(unsigned, utf8.encode(captured.bodyText)),
      );
    },
  );

  test('分块：100 个 id → 50+50 两次顺序请求并按序合并；51 → 50+1', () async {
    final ids = List<int>.generate(100, (i) => i + 1);
    adapter.responses.add(
      jsonBytes(
        krmWire(
          data: <Object?>[
            recordWire(albumAudioId: 1, songname: 'chunk-1'),
            recordWire(albumAudioId: 2, songname: 'chunk-2'),
          ],
        ),
      ),
    );
    adapter.responses.add(
      jsonBytes(
        krmWire(
          data: <Object?>[recordWire(albumAudioId: 3, songname: 'chunk-3')],
        ),
      ),
    );
    final merged = await fetch(KrmAudioQuery(albumAudioIds: ids));
    expect(adapter.requests, hasLength(2));
    // 每块 50 个 entity_id，第二块 51..100。
    final first =
        jsonDecode(adapter.requests[0].bodyText) as Map<String, Object?>;
    final second =
        jsonDecode(adapter.requests[1].bodyText) as Map<String, Object?>;
    expect(
      (first['data']! as List<Object?>)
          .map((row) => (row! as Map<String, Object?>)['entity_id'])
          .toList(),
      List<int>.generate(50, (i) => i + 1),
    );
    expect(
      (second['data']! as List<Object?>)
          .map((row) => (row! as Map<String, Object?>)['entity_id'])
          .toList(),
      List<int>.generate(50, (i) => i + 51),
    );
    // 合并顺序 = 请求顺序。
    expect(merged.map((p) => p.title).toList(), <String>[
      'chunk-1',
      'chunk-2',
      'chunk-3',
    ]);

    // 51 个 id：第二块只有 1 个实体。
    adapter.requests.clear();
    adapter.responses.clear();
    adapter.responses.add(jsonBytes(krmWire()));
    adapter.responses.add(jsonBytes(krmWire()));
    await fetch(
      KrmAudioQuery(albumAudioIds: List<int>.generate(51, (i) => i + 1)),
    );
    final secondBody =
        jsonDecode(adapter.requests[1].bodyText) as Map<String, Object?>;
    expect((secondBody['data']! as List<Object?>), hasLength(1));
  });

  test('解码：SongInformation 全量（album_info 优先/cover {size}/词曲/BPM）', () async {
    adapter.bytes = jsonBytes(krmWire(data: <Object?>[recordWire()]));
    final songs = await fetch(const KrmAudioQuery(albumAudioIds: <int>[1]));
    expect(songs, hasLength(1));
    final song = songs.single;
    expect(song.id, '339415062', reason: 'album_audio_id 数字 → 文本');
    expect(song.title, '稻香');
    expect(song.albumId, '14421203');
    expect(song.albumTitle, '魔杰座（专辑资料）', reason: 'album_info 优先于 base');
    expect(song.coverUrl, 'http://imge.kugou.com/240/c.png');
    expect(song.artists, hasLength(1));
    expect(song.artists.single.id, 6076);
    expect(song.artists.single.name, '周杰伦');
    expect(
      song.artists.single.avatarUrl,
      'http://imge.kugou.com/240/avatar.png',
    );
    expect(song.artists.single.publicationCode, 1);

    final info = song.information;
    expect(info.publishedAt, '2008-10-15');
    expect(info.albumPublishedAt, '2008-10-14');
    expect(info.language, '国语');
    expect(info.lyricist, '方文山');
    expect(info.composer, '周杰伦');
    expect(info.bpm, 115.0);
    expect(info.tempoCode, '1');
    expect(info.tempoDescription, '快(BPM 115)');
  });

  test('解码：album_info/extra 缺失 → 回退 base；authors 空；数字文本宽容', () async {
    adapter.bytes = jsonBytes(
      krmWire(
        data: <Object?>[
          recordWire(albumInfo: null, extra: null, authors: const <Object?>[]),
        ],
      ),
    );
    final song = (await fetch(
      const KrmAudioQuery(albumAudioIds: <int>[1]),
    )).single;
    expect(song.albumTitle, '魔杰座', reason: '回退 base.album_name');
    expect(song.coverUrl, '', reason: 'album_info 缺失 → 封面空串');
    expect(song.information.albumPublishedAt, isNull);
    expect(song.information.bpm, isNull);
    expect(song.information.lyricist, isNull);
    expect(song.information.composer, isNull);
    expect(song.artists, isEmpty);

    // text/optional 宽容：bool songname → 空串；bpm 数字字符串 → 数值。
    adapter.bytes = jsonBytes(
      krmWire(
        data: <Object?>[
          recordWire(
            songname: true,
            extra: <String, Object?>{'bpm': '115.5', 'lyrics': true},
          ),
        ],
      ),
    );
    final tolerant = (await fetch(
      const KrmAudioQuery(albumAudioIds: <int>[1]),
    )).single;
    expect(tolerant.title, '');
    expect(tolerant.information.bpm, 115.5);
    expect(tolerant.information.lyricist, isNull);
  });

  test('分支：__status=1 无 base 跳过；带 base 照常解码；非法 __status → 空默认行', () async {
    adapter.bytes = jsonBytes(
      krmWire(
        data: <Object?>[
          <String, Object?>{'__status': 1},
          // 字符串 "1" 同样按 u32 精确解析 → 跳过。
          <String, Object?>{'__status': '1'},
          <String, Object?>{
            '__status': 1,
            'base': <String, Object?>{'album_audio_id': 9, 'songname': '保留'},
          },
          // bool 不是 u32 → 非 1 → 不跳过 → base 缺省解码成空默认行。
          <String, Object?>{'__status': true},
        ],
      ),
    );
    final songs = await fetch(const KrmAudioQuery(albumAudioIds: <int>[1]));
    expect(songs, hasLength(2));
    expect(songs[0].title, '保留');
    expect(songs[0].id, '9');
    // base 缺省（response::object）→ 空默认行。
    expect(songs[1].id, '');
    expect(songs[1].title, '');
    expect(songs[1].coverUrl, '');
  });

  test('分支：业务失败带码；20018 认证；data 非数组/行非 object → decode', () async {
    adapter.bytes = jsonBytes(krmWire(status: 0, errorCode: 20010));
    await expectLater(
      fetch(const KrmAudioQuery(albumAudioIds: <int>[1])),
      throwsA(
        predicate(
          (Object e) =>
              e is KugouApiException && e.kind == 'business' && e.code == 20010,
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
      fetch(const KrmAudioQuery(albumAudioIds: <int>[1])),
      throwsA(
        predicate(
          (Object e) =>
              e is KugouApiException &&
              e.kind == 'authentication' &&
              e.code == 20018,
        ),
      ),
    );
    // data 缺省 null → 空结果（成功确认）。
    adapter.bytes = jsonBytes(krmWire(data: null));
    expect(await fetch(const KrmAudioQuery(albumAudioIds: <int>[1])), isEmpty);
    // data 非数组（{} 或字符串）→ decode（无 list 宽容）。
    adapter.bytes = jsonBytes(krmWire(data: <String, Object?>{}));
    await expectLater(
      fetch(const KrmAudioQuery(albumAudioIds: <int>[1])),
      throwsA(predicate((Object e) => '$e'.contains('decode'))),
    );
    adapter.bytes = jsonBytes(krmWire(data: 'garbage'));
    await expectLater(
      fetch(const KrmAudioQuery(albumAudioIds: <int>[1])),
      throwsA(predicate((Object e) => '$e'.contains('decode'))),
    );
    // 行非 object → decode。
    adapter.bytes = jsonBytes(krmWire(data: <Object?>[42]));
    await expectLater(
      fetch(const KrmAudioQuery(albumAudioIds: <int>[1])),
      throwsA(predicate((Object e) => '$e'.contains('decode'))),
    );
    // 非 JSON → decode。
    adapter.bytes = jsonBytes('not-json');
    await expectLater(
      fetch(const KrmAudioQuery(albumAudioIds: <int>[1])),
      throwsA(predicate((Object e) => '$e'.contains('decode'))),
    );
  });
}
