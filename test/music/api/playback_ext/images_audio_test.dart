/// 歌曲关联歌手图片端点测试（images_audio.rs）：入参校验（1..100/1..50/32 位
/// hex/filename 字节数）、clearDefaults 装配（data JSON 精确签名/id_or_zero）、
/// 嵌套数组解码（分组保序/https 升级/optional_map 宽容）、信封分支。
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/images_audio.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import 'package:mimao/music/client/signature.dart';
import 'package:mimao/music/models/playback_ext_models.dart';

import '../capture_adapter.dart';
import 'fake_session.dart';

const String kHash = '0123456789abcdef0123456789abcdef';

String imagesWire({
  int status = 1,
  int errorCode = 0,
  Object? data = const <Object?>[],
}) => jsonEncode(<String, Object?>{
  'status': status,
  'error_code': errorCode,
  'data': data,
});

Map<String, Object?> artistWire({
  Object? authorId = 6076,
  Object? authorName = '周杰伦',
  Object? isPublish = 1,
  Object? resHash = kHash,
  Object? avatar = 'http://imge.kugou.com/kugouicon/{size}/a.png',
  Object? sizableAvatar = 'http://imge.kugou.com/kugouicon/{size}/a.png',
  Object? audioPublishDate = '2008-10-15',
  Object? imgs = const <String, Object?>{
    '1': <Object?>[
      <String, Object?>{
        'id': '991',
        'file_hash': kHash,
        'sizable_portrait': 'http://imge.kugou.com/portrait/{size}/p.png',
        'filename': 'p.png',
        'publish_time': '2025-01-01',
        'source': 3,
      },
    ],
    '2': <Object?>[],
    '3': null,
  },
}) => <String, Object?>{
  if (authorId != null) 'author_id': authorId,
  if (authorName != null) 'author_name': authorName,
  if (isPublish != null) 'is_publish': isPublish,
  if (resHash != null) 'res_hash': resHash,
  if (avatar != null) 'avatar': avatar,
  if (sizableAvatar != null) 'sizable_avatar': sizableAvatar,
  if (audioPublishDate != null) 'audio_publish_date': audioPublishDate,
  'imgs': imgs,
};

void main() {
  late CaptureAdapter adapter;
  late KugouClient client;
  late KugouIdentity identity;

  setUp(() {
    adapter = CaptureAdapter(jsonBytes(imagesWire()));
    client = KugouClient(dio: Dio()..httpClientAdapter = adapter);
    identity = KugouIdentity.anonymous();
  });

  Future<List<List<MusicAuthorImages>>> fetch(ImagesAudioQuery query) =>
      fetchImagesAudio(fakePlaybackSession(client, identity), query);

  test('input：空/超 100/count 越界/非法 hash/filename 超 16384 字节 → 参数无效', () async {
    for (final query in <ImagesAudioQuery>[
      const ImagesAudioQuery(resources: <ImagesAudioResource>[]),
      ImagesAudioQuery(
        resources: List.generate(
          101,
          (_) => const ImagesAudioResource(hash: kHash),
        ),
      ),
      const ImagesAudioQuery(
        resources: <ImagesAudioResource>[ImagesAudioResource(hash: kHash)],
        count: 0,
      ),
      const ImagesAudioQuery(
        resources: <ImagesAudioResource>[ImagesAudioResource(hash: kHash)],
        count: 51,
      ),
      const ImagesAudioQuery(
        resources: <ImagesAudioResource>[ImagesAudioResource(hash: 'short')],
      ),
      ImagesAudioQuery(
        resources: <ImagesAudioResource>[
          ImagesAudioResource(hash: kHash, filename: 'x' * 16385),
        ],
      ),
      ImagesAudioQuery(
        resources: <ImagesAudioResource>[
          // 3 字节/字 × 5462 = 16386 字节。
          ImagesAudioResource(hash: kHash, filename: '中' * 5462),
        ],
      ),
    ]) {
      await expectLater(
        fetch(query),
        throwsA(
          predicate(
            (Object e) =>
                e is KugouApiException &&
                e.kind == 'input' &&
                e.message.contains('歌曲图片查询参数无效'),
          ),
        ),
      );
    }
    // 边界合法：count=1/50、filename 恰好 16384 字节、大写 hash。
    for (final query in <ImagesAudioQuery>[
      const ImagesAudioQuery(
        resources: <ImagesAudioResource>[ImagesAudioResource(hash: kHash)],
        count: 1,
      ),
      const ImagesAudioQuery(
        resources: <ImagesAudioResource>[ImagesAudioResource(hash: kHash)],
        count: 50,
      ),
      ImagesAudioQuery(
        resources: <ImagesAudioResource>[
          ImagesAudioResource(hash: kHash, filename: 'x' * 16384),
        ],
      ),
      const ImagesAudioQuery(
        resources: <ImagesAudioResource>[
          ImagesAudioResource(hash: 'ABCDEF0123456789ABCDEF0123456789'),
        ],
      ),
    ]) {
      await expectLater(fetch(query), completes);
    }
  });

  test(
    '请求装配：GET ArtistImages 主机/clearDefaults/data JSON 精确签名/id_or_zero',
    () async {
      await fetch(
        ImagesAudioQuery(
          resources: <ImagesAudioResource>[
            const ImagesAudioResource(hash: kHash),
            const ImagesAudioResource(
              audioId: 730888,
              hash: kHash,
              albumAudioId: 339415062,
              filename: 'a.mp3',
            ),
          ],
          count: 8,
        ),
      );

      final captured = adapter.requests.single;
      expect(captured.method, 'GET');
      expect(
        captured.path,
        'https://expendablekmr.kugou.com/v2/author_image/audio',
      );
      final query = captured.query;
      // 端点参数（data 序列化保持声明序；0 → 数字 0，非 0 → 十进制字符串）。
      expect(query['appid'], '3116');
      expect(query['clientver'], '11440');
      expect(query['count'], '8');
      expect(
        query['data'],
        jsonEncode(<Object?>[
          <String, Object?>{
            'audio_id': 0,
            'hash': kHash,
            'album_audio_id': 0,
            'filename': '',
          },
          <String, Object?>{
            'audio_id': '730888',
            'hash': kHash,
            'album_audio_id': '339415062',
            'filename': 'a.mp3',
          },
        ]),
      );
      expect(query['isCdn'], '1');
      expect(query['publish_time'], '1');
      expect(query['show_authors'], '1');
      // request_audio_images：clear_defaults=true——默认字段一个都不注入。
      for (final key in const <String>[
        'dfid',
        'mid',
        'clienttime',
        'token',
        'userid',
        'uuid',
      ]) {
        expect(
          query.containsKey(key),
          isFalse,
          reason: 'clearDefaults 不注入 $key',
        );
      }
      final unsigned = <String, String>{...query}..remove('signature');
      expect(
        query['signature'],
        kugouSignatureAndroid(unsigned, const <int>[]),
      );
      // 固定头仍在（send_endpoint 恒定头），但 clienttime 头随默认清空缺席。
      expect(captured.headers['dfid'], identity.dfid);
      expect(captured.headers['mid'], identity.mid);
      expect(captured.headers['clienttime'], isNull);
      expect(captured.headers['x-router'], isNull);
      expect(captured.headers['User-Agent'], kugouDefaultUserAgent);
    },
  );

  test('解码：外层分组保序（含空组）；author_id 数字 → 文本；https 升级；imgs 宽容', () async {
    adapter.bytes = jsonBytes(
      imagesWire(
        data: <Object?>[
          <Object?>[artistWire()],
          <Object?>[],
          <Object?>[
            artistWire(
              authorId: '42',
              avatar: 'ftp://imge.kugou.com/a.png',
              sizableAvatar: 'https://imge.kugou.com/s/{size}/a.png',
              imgs: <String, Object?>{
                '1': <Object?>[
                  <String, Object?>{'sizable_portrait': 'https://ok/p.png'},
                  'garbage-row',
                ],
                '4': 'garbage-category',
              },
            ),
          ],
        ],
      ),
    );
    final groups = await fetch(
      const ImagesAudioQuery(
        resources: <ImagesAudioResource>[ImagesAudioResource(hash: kHash)],
      ),
    );
    expect(groups, hasLength(3));
    expect(groups[1], isEmpty, reason: '空组原样保留');

    final first = groups[0].single;
    expect(first.artistId, '6076');
    expect(first.name, '周杰伦');
    expect(first.publishStatus, 1);
    expect(first.resourceHash, kHash);
    // avatar 原样保留（可能是 {size} 模板）；avatar_url 升级 https。
    expect(first.avatar, 'http://imge.kugou.com/kugouicon/{size}/a.png');
    expect(first.avatarUrl, 'https://imge.kugou.com/kugouicon/{size}/a.png');
    expect(first.audioPublishDate, '2008-10-15');
    expect(first.images, hasLength(3));
    expect(first.images['1'], hasLength(1));
    expect(first.images['1']!.single.id, '991');
    // 写真 url：http → https，{size} 模板原样保留（不走 cover_url 替换）。
    expect(
      first.images['1']!.single.url,
      'https://imge.kugou.com/portrait/{size}/p.png',
    );
    expect(first.images['1']!.single.source, 3);
    expect(first.images['2'], isEmpty);
    expect(first.images['3'], isEmpty, reason: 'null 类别 → None → 空列表');

    final third = groups[2].single;
    expect(third.artistId, '42', reason: 'optional<String>：字符串原样');
    expect(third.avatar, 'ftp://imge.kugou.com/a.png');
    // 非 http 前缀且非 https → null（image_url 拒绝 ftp）。
    expect(third.avatarUrl, 'https://imge.kugou.com/s/{size}/a.png');
    // 类别内垃圾行 → 整条类别 None → 空表；垃圾类别值 → None → 空表。
    expect(third.images['1'], isEmpty);
    expect(third.images['4'], isEmpty);
  });

  test(
    '分支：status!=1 → business 带码；恢复分支；行/组非 object → decode；20018 认证',
    () async {
      adapter.bytes = jsonBytes(
        imagesWire(status: 0, errorCode: 30005, data: <Object?>[]),
      );
      await expectLater(
        fetch(
          const ImagesAudioQuery(
            resources: <ImagesAudioResource>[ImagesAudioResource(hash: kHash)],
          ),
        ),
        throwsA(
          predicate(
            (Object e) =>
                e is KugouApiException &&
                e.kind == 'business' &&
                e.code == 30005,
          ),
        ),
      );
      // 恢复：status 缺失但 error_code 非零 → business。
      adapter.bytes = jsonBytes(
        jsonEncode(<String, Object?>{'error_code': 30021}),
      );
      await expectLater(
        fetch(
          const ImagesAudioQuery(
            resources: <ImagesAudioResource>[ImagesAudioResource(hash: kHash)],
          ),
        ),
        throwsA(
          predicate(
            (Object e) =>
                e is KugouApiException &&
                e.kind == 'business' &&
                e.code == 30021,
          ),
        ),
      );
      // error_code 必填缺失 → decode。
      adapter.bytes = jsonBytes(
        jsonEncode(<String, Object?>{'status': 1, 'data': []}),
      );
      await expectLater(
        fetch(
          const ImagesAudioQuery(
            resources: <ImagesAudioResource>[ImagesAudioResource(hash: kHash)],
          ),
        ),
        throwsA(predicate((Object e) => '$e'.contains('decode'))),
      );
      // 歌手行非 object → 结构失败 → decode。
      adapter.bytes = jsonBytes(
        imagesWire(
          data: <Object?>[
            <Object?>['garbage'],
          ],
        ),
      );
      await expectLater(
        fetch(
          const ImagesAudioQuery(
            resources: <ImagesAudioResource>[ImagesAudioResource(hash: kHash)],
          ),
        ),
        throwsA(predicate((Object e) => '$e'.contains('decode'))),
      );
      // 20018 → authentication。
      adapter.bytes = jsonBytes(
        jsonEncode(<String, Object?>{
          'status': 1,
          'error_code': 20018,
          'data': [],
        }),
      );
      await expectLater(
        fetch(
          const ImagesAudioQuery(
            resources: <ImagesAudioResource>[ImagesAudioResource(hash: kHash)],
          ),
        ),
        throwsA(
          predicate(
            (Object e) =>
                e is KugouApiException &&
                e.kind == 'authentication' &&
                e.code == 20018,
          ),
        ),
      );
      // 非 JSON → decode。
      adapter.bytes = jsonBytes('not-json');
      await expectLater(
        fetch(
          const ImagesAudioQuery(
            resources: <ImagesAudioResource>[ImagesAudioResource(hash: kHash)],
          ),
        ),
        throwsA(predicate((Object e) => '$e'.contains('decode'))),
      );
    },
  );
}
