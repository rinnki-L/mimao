/// AI 免费畅听推荐测试：数字分页请求体、十档音质资源、作者回退、
/// provider_extension 键保留/丢弃、身份回退链与错误分支。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/ai_recommend_song.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/client/kugou_identity.dart';

import '../capture_adapter.dart';
import 'fake_session.dart';

String aiWire({Object? cardInfo, Object? list}) => jsonEncode(<String, Object?>{
  'status': 1,
  'errcode': 0,
  'data': <String, Object?>{
    'card_info':
        cardInfo ?? <String, Object?>{'card_title': '免费畅听', 'card_id': 3},
    'list': list ?? <Object?>[_aiSong()],
  },
});

Map<String, Object?> _aiSong() => <String, Object?>{
  'mixsongid': '999',
  'album_audio_id': '888',
  'audio_id': 7,
  'songname': 'AI歌',
  'author_name': '兜底歌手',
  'filename': 'fn',
  'ori_audio_name': '原名',
  'official_songname': '官方名',
  'suffix_audio_name': '副名',
  'publish_date': '2021-01-01',
  'language': '国语',
  'is_publish': 1,
  'is_original': 1,
  'album_info': <String, Object?>{
    'album_id': '66',
    'album_name': '专辑',
    'sizable_cover': 'http://imge.kugou.com/{size}/al.png',
    'album_extra': 'keep',
  },
  'authors': <Object?>[
    <String, Object?>{
      'author_id': 100,
      'author_name': '歌手A',
      'is_publish': 2,
      'sizable_avatar': 'http://av/{size}/a.png',
    },
  ],
  'album_audio_remark': '保留',
  'audio_info': <String, Object?>{
    'hash': 'HMAIN',
    'hash_128': 'H128',
    'hash_320': 'H320',
    'hash_flac': 'HFLAC',
    'hash_high': 'HHI',
    'hash_super': 'HSUP',
    'hash_dolby_448': 'HD448',
    'hash_dolby_640': 'HD640',
    'hash_dolby_768': 'HD768',
    'hash_multichannel': 'HMC',
    'hash_vinylrecord': 'HVIN',
    'filesize_128': 1,
    'filesize_320': 2,
    'filesize_flac': 3,
    'filesize_high': 4,
    'filesize_super': 5,
    'filesize_dolby_448': 6,
    'filesize_dolby_640': 7,
    'filesize_dolby_768': 8,
    'filesize_multichannel': 9,
    'filesize_vinylrecord': 10,
    'timelength': 240000,
    'timelength_128': 240000,
    'timelength_320': 240000,
    'timelength_flac': 240000,
    'timelength_high': 240000,
    'timelength_super': 240000,
    'privilege': 8,
    'privilege_128': 9,
    'privilege_320': 10,
    'privilege_flac': 11,
    'privilege_high': 12,
    'privilege_super': 13,
    'bitrate': 128,
    'bitrate_flac': 900,
    'bitrate_high': 1400,
    'bitrate_super': 1900,
    'bitrate_dolby_448': 448,
    'bitrate_dolby_640': 640,
    'bitrate_dolby_768': 768,
    'bitrate_multichannel': 480,
    'bitrate_vinylrecord': 990,
    'extname': 'mp3',
    'extname_super': 'vil',
    'pay_type': 1,
    'fail_process': 0,
    'old_cpy': 2,
    'audio_id': 77,
    'trans_param': <String, Object?>{
      'audio_privilege': 8,
      'language': '粤语',
      'cid': 'keep-cid',
    },
    'extra_audio_key': 'keep',
  },
};

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

  test('请求装配：POST/无 x-router/数字分页请求体（字符串值会 20010）', () async {
    adapter.bytes = jsonBytes(aiWire());
    final result = await fetchAiRecommendSongs(session);
    expect(result.songs, hasLength(1));

    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(
      request.path,
      'https://gateway.kugou.com/concepts/v1/ai/recommend_song',
    );
    expect(request.headers['x-router'], isNull);
    // 上游 params 为空 BTreeMap：无 userid 等端点参数（默认注入只带账号态 userid）。
    expect(request.query.containsKey('userid'), isFalse);
    // BTreeMap 键序 + 数值型分页。
    expect(request.bodyText, '{"apiver":2,"page":1,"pagesize":30,"source":2}');
  });

  test('解码：卡片头/摘要/十档音质/作者头像/元数据回退', () async {
    adapter.bytes = jsonBytes(aiWire());
    final result = await fetchAiRecommendSongs(session);

    expect(result.cardInfo?.cardTitle, '免费畅听');
    expect(result.cardInfo?.cardId, 3);

    final song = result.songs.single;
    final summary = song.song;
    expect(summary.id, '999', reason: '身份优先级：mixsongid');
    expect(summary.hash, 'HMAIN');
    expect(summary.title, 'AI歌');
    expect(summary.albumId, '66');
    expect(summary.albumTitle, '专辑');
    expect(summary.durationMs, 240000, reason: '顶层 timelength');
    expect(summary.coverUrl, 'http://imge.kugou.com/240/al.png');
    expect(summary.privilege, 8, reason: 'privilege 优先于 privilege_128');

    final metadata = song.metadata;
    expect(metadata.audioId, 7, reason: '顶层 audio_id 优先');
    expect(metadata.originalTitle, '原名');
    expect(metadata.officialTitle, '官方名');
    expect(metadata.titleSuffix, '副名');
    expect(metadata.sourceFileName, 'fn');
    expect(metadata.language, '国语', reason: '顶层 language 非空优先');
    expect(metadata.publishedAt, '2021-01-01');
    expect(metadata.publicationCode, 1);
    expect(metadata.originalityCode, 1);
    expect(metadata.paymentType, 1);
    expect(metadata.failureCode, 0);
    expect(metadata.oldCopyrightCode, 2);
    expect(metadata.hasAccompaniment, isNull);

    final artist = metadata.artists.single;
    expect(artist.id, 100);
    expect(artist.avatarUrl, 'http://av/240/a.png');
    expect(artist.publicationCode, 2);

    final qualities = metadata.resources.map((r) => r.quality).toList();
    expect(qualities, <String>[
      '128',
      '320',
      'flac',
      'high',
      'super',
      'dolby_448',
      'dolby_640',
      'dolby_768',
      'multichannel',
      'vinylrecord',
    ]);
    expect(metadata.resources[0].bitRateBps, 128000);
    expect(metadata.resources[0].extension, 'mp3');
    expect(metadata.resources[0].privilege, 9);
    expect(metadata.resources[1].privilege, 10);
    expect(metadata.resources[1].bitRateBps, isNull);
    expect(metadata.resources[2].bitRateBps, 900000);
    expect(metadata.resources[3].bitRateBps, 1400000);
    expect(
      metadata.resources[4].extension,
      'vil',
      reason: 'super 档 extname_super',
    );
    expect(metadata.resources[4].bitRateBps, 1900000);
    expect(metadata.resources[5].bitRateBps, 448000);
    expect(metadata.resources[9].hash, 'HVIN');

    expect(metadata.rights.audioPrivilege, 8);
  });

  test('provider_extension：已消费键丢弃、未映射键保留（含 album_audio_remark）', () async {
    adapter.bytes = jsonBytes(aiWire());
    final result = await fetchAiRecommendSongs(session);
    final extension =
        result.songs.single.metadata.providerExtension! as Map<String, Object?>;

    expect(
      extension['album_audio_remark'],
      '保留',
      reason: 'ai 模块未消费该键（fm 才消费），应留在扩展',
    );
    // 顶层消费键已丢。
    expect(extension.containsKey('mixsongid'), isFalse);
    expect(extension.containsKey('authors'), isFalse);
    expect(extension.containsKey('language'), isFalse);
    // album_info 整体消费键已丢，未映射键保留。
    final album = extension['album_info']! as Map<String, Object?>;
    expect(album['album_extra'], 'keep');
    expect(album.containsKey('album_id'), isFalse);
    // audio_info 平铺消费键已丢、未映射键保留；trans_param 只丢 CONSUMED 键。
    final audio = extension['audio_info']! as Map<String, Object?>;
    expect(audio['extra_audio_key'], 'keep');
    expect(audio.containsKey('hash'), isFalse);
    expect(audio.containsKey('privilege_128'), isFalse);
    final trans = audio['trans_param']! as Map<String, Object?>;
    // CONSUMED_KEYS 连 language 一起消费，trans_param 只剩未映射键。
    expect(trans, <String, Object?>{'cid': 'keep-cid'});
  });

  test(
    '回退链：authors 空 → author_name 兜底；mixsongid → album_audio_id → hash',
    () async {
      final fallbackSong = _aiSong()
        ..remove('mixsongid')
        ..remove('authors');
      (fallbackSong['audio_info']! as Map<String, Object?>).remove('hash');
      adapter.bytes = jsonBytes(aiWire(list: <Object?>[fallbackSong]));
      final result = await fetchAiRecommendSongs(session);

      final song = result.songs.single;
      expect(song.song.id, '888', reason: 'mixsongid 缺省回退 album_audio_id');
      expect(song.song.hash, 'H128', reason: 'audio hash 缺省回退 hash_128');
      final artist = song.metadata.artists.single;
      expect(artist.name, '兜底歌手');
      expect(artist.id, isNull);
      expect(artist.avatarUrl, isNull);
      expect(song.song.artistText, '兜底歌手');

      // album_audio_id 也缺省 → 音频 hash 作主键。
      // album_audio_id 也缺省 → 音频 hash 作主键（id 链不含 hash_128）。
      final hashSong = _aiSong()
        ..remove('mixsongid')
        ..remove('album_audio_id');
      adapter.bytes = jsonBytes(aiWire(list: <Object?>[hashSong]));
      final hashResult = await fetchAiRecommendSongs(session);
      expect(hashResult.songs.single.song.id, 'HMAIN');
    },
  );

  test('边界：audio_info/album_info 非 object → 默认；data 缺省 → 空表', () async {
    // song_info 缺 album_info → 专辑名空 → albumTitle null；audio_info 缺省
    // → 十档资源仍无条件入表（hash 为空串）。
    adapter.bytes = jsonBytes(
      '{"status":1,"errcode":0,"data":{"card_info":null,"list":[{"mixsongid":"1"}]}}',
    );
    final result = await fetchAiRecommendSongs(session);
    expect(result.cardInfo, isNull);
    final song = result.songs.single;
    expect(song.song.albumTitle, isNull);
    expect(
      song.metadata.resources.map((r) => r.quality).toList(),
      hasLength(10),
    );
    expect(song.metadata.resources.first.hash, '');

    adapter.bytes = jsonBytes('{"status":1,"errcode":0}');
    final empty = await fetchAiRecommendSongs(session);
    expect(empty.songs, isEmpty);
    expect(empty.cardInfo, isNull);
  });

  test('解码失败：list 元素非 object → decode', () async {
    adapter.bytes = jsonBytes('{"status":1,"errcode":0,"data":{"list":[5]}}');
    await expectLater(
      fetchAiRecommendSongs(session),
      throwsA(predicate((Object e) => '$e'.contains('decode'))),
    );
  });

  test(
    'errcode 键上的 20018 是 business；error_code 键上的 20018 是 authentication',
    () async {
      adapter.bytes = jsonBytes('{"status":1,"errcode":20018}');
      await expectLater(
        fetchAiRecommendSongs(session),
        throwsA(
          predicate(
            (Object e) =>
                e is KugouApiException &&
                e.kind == 'business' &&
                e.code == 20018,
          ),
        ),
      );

      adapter.bytes = jsonBytes('{"status":1,"errcode":0,"error_code":20018}');
      await expectLater(
        fetchAiRecommendSongs(session),
        throwsA(
          predicate(
            (Object e) => e is KugouApiException && e.kind == 'authentication',
          ),
        ),
      );
    },
  );

  test('status=0 → business', () async {
    adapter.bytes = jsonBytes('{"status":0,"errcode":9}');
    await expectLater(
      fetchAiRecommendSongs(session),
      throwsA(
        predicate(
          (Object e) =>
              e is KugouApiException && e.kind == 'business' && e.code == 9,
        ),
      ),
    );
  });
}
