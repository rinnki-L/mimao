/// 首页发现推荐端点——EchoMusicNext `crates/echo-api/src/module/home_discover.rs`
/// 的翻译（docs/architecture.md §4.3：`music/api/` ← module，一端点一文件）。
///
/// clientver 20809 + 无账号设备快照：旧版本/lite 请求会静默返回空列表
/// （上游注释）。song 条目映射成完整曲目，其余 item_type 原样保留。
library;

import 'dart:typed_data';

import 'package:mimao/music/api/everyday_recommend.dart';
import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/discovery_models.dart';
import 'package:mimao/music/models/music_models.dart';

/// home_discover.rs `default_page_size`；page_size=0 时也选这一批。
const int kugouHomeDiscoverDefaultPageSize = 4;

/// 首页发现推荐输入（home_discover.rs `Query`）。
class HomeDiscoverQuery {
  const HomeDiscoverQuery({this.pageSize = kugouHomeDiscoverDefaultPageSize});

  final int pageSize;

  void validate() {
    // Rust 侧是 u32：负数不可表示；Dart 侧显式拒绝，避免静默传 0 语义。
    if (pageSize < 0) {
      throw const KugouApiException('input', '首页发现分页大小无效');
    }
  }
}

/// POST /homediscoverrec/v1/client/home_discover_rec（网关；无 x-router）。
Future<MusicDiscoverRecommendations> fetchHomeDiscover(
  MusicSession session,
  HomeDiscoverQuery query,
) async {
  query.validate();
  final identity = await session.ensureDevice();
  // A zero page size selects the default batch of four（上游注释）。
  final pageSize = query.pageSize == 0
      ? kugouHomeDiscoverDefaultPageSize
      : query.pageSize;
  final response = await session.client.sendEndpoint(
    identity,
    KugouEndpoint(
      origin: KugouOrigin.gateway,
      path: '/homediscoverrec/v1/client/home_discover_rec',
      method: 'POST',
      params: <String, String>{
        'module_key': 'home_discover_rec',
        'module_id': '1',
        'area_code': '1',
        'platform': 'android',
        'userid': identity.userId.toString(),
        // This client version avoids silently empty responses from older or
        // lite requests（上游注释）。
        'clientver': '20809',
      },
      // serde_json BTreeMap：键序按字典序落盘（签名覆盖请求体字节）。
      body: encodeJsonBody(<String, Object?>{
        'go_ky_extra': <Object?>[
          <String, String>{'key': 'network', 'val': '2'},
          <String, String>{'key': 'play_mode', 'val': '2'},
          <String, String>{'key': 'no_mv_ret', 'val': '1'},
        ],
        'pagesize': pageSize,
        'recall_type': 'song',
        'support': 'only_song',
        'today_play_num': 0,
        'userid': identity.userId,
      }),
    ),
  );
  return _convertHomeDiscover(response.bytes);
}

/// 本模块从 song_info 平铺消费的键（home_discover.rs `SONG_INFO_KEYS`）；
/// trans_param 经自己的嵌套路径丢弃，剩余供应商键（cid 等）进 provider_extension。
const List<String> _homeDiscoverSongInfoKeys = <String>[
  'mixsongid',
  'album_audio_id',
  'audio_id',
  'album_name',
  'album_cover',
  'ori_album_id',
  'songname',
  'author_name',
  'privilege',
  'pay_type',
  'fail_process',
  'has_obbligato',
  'hash_128',
  'hash_320',
  'hash_flac',
  'filesize_128',
  'filesize_320',
  'filesize_flac',
  'timelength_128',
  'timelength_320',
  'timelength_flac',
];

/// wire 解析（home_discover.rs `convert`）。
MusicDiscoverRecommendations _convertHomeDiscover(Uint8List bytes) {
  final envelope = decodeDiscoveryEnvelope(bytes, errorCodeKey: 'errcode');
  ensureBusinessSuccess(envelope.status, envelope.errorCode, context: '首页发现');
  // data: Option<Data> + optional → 缺省/null/非 object → 默认空（不报 decode）。
  final data = wireMap(envelope.data);
  final items = data == null
      ? const <Object?>[]
      : wireList(data['items'], 'items');
  final mapped = <MusicDiscoverItem>[];
  final unmapped = <Object?>[];
  for (final raw in items) {
    final item = wireMap(raw);
    final songInfoRaw = item?['song_info'];
    // (Some("song"), Some(info)) if info.is_object() 才映射；其余原样保留。
    if (item == null || item['item_type'] != 'song' || songInfoRaw is! Map) {
      unmapped.add(raw);
      continue;
    }
    mapped.add(
      _convertItem(item, wireMap(songInfoRaw) ?? const <String, Object?>{}),
    );
  }
  return MusicDiscoverRecommendations(items: mapped, unmappedItems: unmapped);
}

MusicDiscoverItem _convertItem(
  Map<String, Object?> item,
  Map<String, Object?> info,
) {
  // song_info 是 object 语义，但进入本函数前已确认是 object。
  final trans = discoveryConvertTransParam(info['trans_param']);
  final resources = List.of(trans.resources);
  // 128/320/flac 三档无条件入表；timelength_* wire 上就是毫秒，原样透传。
  for (final (quality, hash, size, durationMs)
      in <(String, String, int?, int?)>[
        (
          '128',
          wireText(info['hash_128']),
          discoveryOptionalUnsigned(info['filesize_128']),
          discoveryOptionalUnsigned(info['timelength_128']),
        ),
        (
          '320',
          wireText(info['hash_320']),
          discoveryOptionalUnsigned(info['filesize_320']),
          discoveryOptionalUnsigned(info['timelength_320']),
        ),
        (
          'flac',
          wireText(info['hash_flac']),
          discoveryOptionalUnsigned(info['filesize_flac']),
          discoveryOptionalUnsigned(info['timelength_flac']),
        ),
      ]) {
    resources.add(
      MusicDiscoveryAudioResource(
        quality: quality,
        // 上游 hash: Some(hash)：空串也入表。
        hash: hash,
        sizeBytes: size,
        durationMs: durationMs,
      ),
    );
  }

  // id 优先 mixsongid，其次数字 album_audio_id；ori_album_id 是本响应的专辑 id。
  final mixsongid = wireText(info['mixsongid']);
  final albumAudioId = discoveryOptionalUnsigned(info['album_audio_id']);
  final id = mixsongid.isEmpty ? (albumAudioId?.toString() ?? '') : mixsongid;
  final hash = wireText(info['hash_128']).isEmpty
      ? wireText(info['hash_320'])
      : wireText(info['hash_128']);
  final authorName = wireText(info['author_name']);
  final artists = authorName.isEmpty
      ? const <MusicDiscoveryArtistDetail>[]
      : <MusicDiscoveryArtistDetail>[
          MusicDiscoveryArtistDetail(name: authorName),
        ];
  final albumName = wireText(info['album_name']);
  final hasObbligato = discoveryOptionalUnsigned32(info['has_obbligato']);

  final summary = MusicDiscoverySongSummary(
    id: id,
    hash: hash,
    title: wireText(info['songname']),
    artists: <MusicArtistRef>[
      for (final artist in artists)
        MusicArtistRef(id: artist.id, name: artist.name),
    ],
    albumId: discoveryOptionalUnsigned(info['ori_album_id'])?.toString() ?? '',
    albumTitle: albumName.isEmpty ? null : albumName,
    durationMs:
        discoveryOptionalUnsigned(info['timelength_128']) ??
        discoveryOptionalUnsigned(info['timelength_320']),
    coverUrl: coverUrl(wireText(info['album_cover'])),
    privilege: discoveryOptionalUnsigned32(info['privilege']),
  );
  final metadata = MusicDiscoverySongMetadata(
    audioId: discoveryOptionalUnsigned(info['audio_id']),
    originalTitle: null,
    officialTitle: null,
    titleSuffix: null,
    albumAudioRemark: '',
    sourceFileName: '',
    language: trans.language,
    publishedAt: null,
    publicationCode: null,
    originalityCode: trans.rights.originalityCode,
    // has_obbligato.and_then(numeric::boolean)：0/1 → bool，其它未知。
    hasAccompaniment: hasObbligato == 0
        ? false
        : hasObbligato == 1
        ? true
        : null,
    accompanimentCode: hasObbligato,
    relatedGoodsExtension: null,
    providerExtension: _providerExtension(info),
    paymentType: discoveryOptionalUnsigned32(info['pay_type']),
    failureCode: discoveryOptionalUnsigned32(info['fail_process']),
    oldCopyrightCode: null,
    rights: trans.rights,
    resources: resources,
    videos: const <MusicDiscoveryVideoReference>[],
    tags: const <MusicDiscoverySongTag>[],
    ipTags: const <MusicDiscoverySongTag>[],
    recommendation: const MusicDiscoveryRecommendationText(
      headline: '',
      detail: '',
      rankLabel: null,
    ),
    ranking: null,
    artists: artists,
    relatedVersions: const <MusicDiscoveryRelatedVersion>[],
  );
  final extra = wireMap(item['extra']);
  final startTime = extra == null ? '' : wireText(extra['start_time']);
  return MusicDiscoverItem(
    itemId: wireText(item['item_id']),
    algPath: wireText(item['alg_path']),
    // extra.start_time 非空才保留（开播语义上游未验证）。
    startTime: startTime.isEmpty ? null : startTime,
    song: MusicDiscoverySong(song: summary, metadata: metadata),
  );
}

/// home_discover.rs `provider_extension`：丢弃 song_info 平铺消费键与
/// trans_param 的 CONSUMED 键，剩余非空才保留（供应商原样数据）。
Object? _providerExtension(Map<String, Object?> info) {
  final raw = Map<String, Object?>.of(info);
  dropDiscoveryConsumedKeys(
    raw,
    'trans_param',
    kugouDiscoveryTransConsumedKeys,
  );
  dropDiscoveryConsumedKeys(raw, '', _homeDiscoverSongInfoKeys);
  return raw.isEmpty ? null : raw;
}
