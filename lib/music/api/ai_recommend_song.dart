/// AI 免费畅听推荐端点——EchoMusicNext
/// `crates/echo-api/src/module/ai_recommend_song.rs` 的翻译。
///
/// body 分页保持数字（字符串值会 20010，上游注释）；每档音质资源独立保留，
/// 未建模供应商键进 provider_extension。
library;

import 'dart:typed_data';

import 'package:mimao/music/api/everyday_recommend.dart';
import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/discovery_models.dart';
import 'package:mimao/music/models/music_models.dart';

/// POST /concepts/v1/ai/recommend_song（网关；无 x-router）。
Future<MusicFreeListenSongs> fetchAiRecommendSongs(MusicSession session) async {
  final identity = await session.ensureDevice();
  final response = await session.client.sendEndpoint(
    identity,
    KugouEndpoint(
      origin: KugouOrigin.gateway,
      path: '/concepts/v1/ai/recommend_song',
      method: 'POST',
      // Keep page and page size numeric; string values can return 20010
      // （上游注释）。键序对齐 serde_json BTreeMap。
      body: encodeJsonBody(const <String, Object?>{
        'apiver': 2,
        'page': 1,
        'pagesize': 30,
        'source': 2,
      }),
    ),
  );
  return _convertAiRecommendSongs(response.bytes);
}

/// 本模块平铺消费的顶层键（ai_recommend_song.rs `SONG_KEYS`）。
const List<String> _aiSongKeys = <String>[
  'mixsongid',
  'album_audio_id',
  'audio_id',
  'songname',
  'author_name',
  'filename',
  'ori_audio_name',
  'official_songname',
  'suffix_audio_name',
  'publish_date',
  'language',
  'is_publish',
  'is_original',
  'authors',
];

/// audio_info 平铺消费键（ai_recommend_song.rs `AUDIO_KEYS`）。
const List<String> _aiAudioKeys = <String>[
  'hash',
  'hash_128',
  'hash_320',
  'hash_flac',
  'hash_high',
  'hash_super',
  'hash_dolby_448',
  'hash_dolby_640',
  'hash_dolby_768',
  'hash_multichannel',
  'hash_vinylrecord',
  'filesize_128',
  'filesize_320',
  'filesize_flac',
  'filesize_high',
  'filesize_super',
  'filesize_dolby_448',
  'filesize_dolby_640',
  'filesize_dolby_768',
  'filesize_multichannel',
  'filesize_vinylrecord',
  'timelength',
  'timelength_128',
  'timelength_320',
  'timelength_flac',
  'timelength_high',
  'timelength_super',
  'timelength_dolby_448',
  'timelength_dolby_640',
  'timelength_dolby_768',
  'timelength_multichannel',
  'timelength_vinylrecord',
  'privilege',
  'privilege_128',
  'privilege_320',
  'privilege_flac',
  'privilege_high',
  'privilege_super',
  'privilege_dolby_448',
  'privilege_dolby_640',
  'privilege_dolby_768',
  'privilege_multichannel',
  'privilege_vinylrecord',
  'bitrate',
  'bitrate_flac',
  'bitrate_high',
  'bitrate_super',
  'bitrate_dolby_448',
  'bitrate_dolby_640',
  'bitrate_dolby_768',
  'bitrate_multichannel',
  'bitrate_vinylrecord',
  'pay_type',
  'fail_process',
  'old_cpy',
  'extname',
  'extname_super',
  'audio_id',
];

/// wire 解析（ai_recommend_song.rs `convert`）。
MusicFreeListenSongs _convertAiRecommendSongs(Uint8List bytes) {
  final envelope = decodeDiscoveryEnvelope(bytes, errorCodeKey: 'errcode');
  ensureBusinessSuccess(envelope.status, envelope.errorCode, context: 'AI 推荐');
  // data: Option<Data> + optional → 缺省/null/非 object → 默认空（不报 decode）。
  final data = wireMap(envelope.data);
  final cardInfo = data == null ? null : _cardInfo(data['card_info']);
  final list = data == null
      ? const <Object?>[]
      : wireList(data['list'], 'list');
  final songs = <MusicDiscoverySong>[];
  for (final raw in list) {
    final wire = wireMap(raw);
    if (wire == null) {
      throw const KugouApiException('decode', 'AI 推荐歌曲项不是 object');
    }
    songs.add(_convertAiSong(wire));
  }
  return MusicFreeListenSongs(songs: songs, cardInfo: cardInfo);
}

/// card_info：Option + optional → 缺省/null/非 object → null。
MusicAiCardInfo? _cardInfo(Object? value) {
  final wire = wireMap(value);
  if (wire == null) return null;
  return MusicAiCardInfo(
    cardTitle: wireText(wire['card_title']),
    cardId: discoveryOptionalUnsigned(wire['card_id']),
  );
}

MusicDiscoverySong _convertAiSong(Map<String, Object?> wire) {
  // album_info / audio_info 都是 object 语义：非 object → 全默认。
  final album = wireMap(wire['album_info']) ?? const <String, Object?>{};
  final audio = wireMap(wire['audio_info']) ?? const <String, Object?>{};

  final trans = discoveryConvertTransParam(audio['trans_param']);
  final resources = List.of(trans.resources);
  // 十档资源全部无条件入表；bitrate_* 一律乘 1000；extension 仅 128/super 有。
  for (final (quality, hash, size, durationMs, privilege, bitrate, ext)
      in <(String, String, int?, int?, int?, int?, String?)>[
        (
          '128',
          wireText(audio['hash_128']),
          discoveryOptionalUnsigned(audio['filesize_128']),
          discoveryOptionalUnsigned(audio['timelength_128']),
          discoveryOptionalUnsigned32(audio['privilege_128']),
          discoveryOptionalUnsigned(audio['bitrate']),
          wireText(audio['extname']),
        ),
        (
          '320',
          wireText(audio['hash_320']),
          discoveryOptionalUnsigned(audio['filesize_320']),
          discoveryOptionalUnsigned(audio['timelength_320']),
          discoveryOptionalUnsigned32(audio['privilege_320']),
          null,
          null,
        ),
        (
          'flac',
          wireText(audio['hash_flac']),
          discoveryOptionalUnsigned(audio['filesize_flac']),
          discoveryOptionalUnsigned(audio['timelength_flac']),
          discoveryOptionalUnsigned32(audio['privilege_flac']),
          discoveryOptionalUnsigned(audio['bitrate_flac']),
          null,
        ),
        (
          'high',
          wireText(audio['hash_high']),
          discoveryOptionalUnsigned(audio['filesize_high']),
          discoveryOptionalUnsigned(audio['timelength_high']),
          discoveryOptionalUnsigned32(audio['privilege_high']),
          discoveryOptionalUnsigned(audio['bitrate_high']),
          null,
        ),
        (
          'super',
          wireText(audio['hash_super']),
          discoveryOptionalUnsigned(audio['filesize_super']),
          discoveryOptionalUnsigned(audio['timelength_super']),
          discoveryOptionalUnsigned32(audio['privilege_super']),
          discoveryOptionalUnsigned(audio['bitrate_super']),
          wireText(audio['extname_super']),
        ),
        (
          'dolby_448',
          wireText(audio['hash_dolby_448']),
          discoveryOptionalUnsigned(audio['filesize_dolby_448']),
          discoveryOptionalUnsigned(audio['timelength_dolby_448']),
          discoveryOptionalUnsigned32(audio['privilege_dolby_448']),
          discoveryOptionalUnsigned(audio['bitrate_dolby_448']),
          null,
        ),
        (
          'dolby_640',
          wireText(audio['hash_dolby_640']),
          discoveryOptionalUnsigned(audio['filesize_dolby_640']),
          discoveryOptionalUnsigned(audio['timelength_dolby_640']),
          discoveryOptionalUnsigned32(audio['privilege_dolby_640']),
          discoveryOptionalUnsigned(audio['bitrate_dolby_640']),
          null,
        ),
        (
          'dolby_768',
          wireText(audio['hash_dolby_768']),
          discoveryOptionalUnsigned(audio['filesize_dolby_768']),
          discoveryOptionalUnsigned(audio['timelength_dolby_768']),
          discoveryOptionalUnsigned32(audio['privilege_dolby_768']),
          discoveryOptionalUnsigned(audio['bitrate_dolby_768']),
          null,
        ),
        (
          'multichannel',
          wireText(audio['hash_multichannel']),
          discoveryOptionalUnsigned(audio['filesize_multichannel']),
          discoveryOptionalUnsigned(audio['timelength_multichannel']),
          discoveryOptionalUnsigned32(audio['privilege_multichannel']),
          discoveryOptionalUnsigned(audio['bitrate_multichannel']),
          null,
        ),
        (
          'vinylrecord',
          wireText(audio['hash_vinylrecord']),
          discoveryOptionalUnsigned(audio['filesize_vinylrecord']),
          discoveryOptionalUnsigned(audio['timelength_vinylrecord']),
          discoveryOptionalUnsigned32(audio['privilege_vinylrecord']),
          discoveryOptionalUnsigned(audio['bitrate_vinylrecord']),
          null,
        ),
      ]) {
    resources.add(
      MusicDiscoveryAudioResource(
        quality: quality,
        hash: hash,
        sizeBytes: size,
        durationMs: durationMs,
        bitRateBps: bitrate == null ? null : bitrate * 1000,
        extension: ext,
        privilege: privilege,
      ),
    );
  }

  final authors = _authors(wireList(wire['authors'], 'authors'));
  final authorName = wireText(wire['author_name']);
  // authors 为空且顶层 author_name 非空 → 单条回退歌手。
  if (authors.isEmpty && authorName.isNotEmpty) {
    authors.add(MusicDiscoveryArtistDetail(name: authorName));
  }

  // 身份优先级：mixsongid → album_audio_id → 音频 hash。
  final id = <String>[
    wireText(wire['mixsongid']),
    wireText(wire['album_audio_id']),
    wireText(audio['hash']),
  ].firstWhere((value) => value.isNotEmpty, orElse: () => '');
  final audioHash = wireText(audio['hash']);
  final hash = audioHash.isEmpty ? wireText(audio['hash_128']) : audioHash;
  final albumName = wireText(album['album_name']);
  final songLanguage = wireText(wire['language']);

  final summary = MusicDiscoverySongSummary(
    id: id,
    hash: hash,
    title: wireText(wire['songname']),
    artists: <MusicArtistRef>[
      for (final artist in authors)
        MusicArtistRef(id: artist.id, name: artist.name),
    ],
    albumId: wireText(album['album_id']),
    albumTitle: albumName.isEmpty ? null : albumName,
    durationMs: discoveryOptionalUnsigned(audio['timelength']),
    coverUrl: coverUrl(wireText(album['sizable_cover'])),
    privilege:
        discoveryOptionalUnsigned32(audio['privilege']) ??
        discoveryOptionalUnsigned32(audio['privilege_128']),
  );
  final metadata = MusicDiscoverySongMetadata(
    audioId:
        discoveryOptionalUnsigned(wire['audio_id']) ??
        discoveryOptionalUnsigned(audio['audio_id']),
    // 上游恒 Some（空串保留）；remark 语义未确立 → 空串并保留原键进扩展。
    originalTitle: wireText(wire['ori_audio_name']),
    officialTitle: wireText(wire['official_songname']),
    titleSuffix: wireText(wire['suffix_audio_name']),
    albumAudioRemark: '',
    sourceFileName: wireText(wire['filename']),
    // 顶层 language 优先，缺省回退 trans_param language。
    language: songLanguage.isEmpty ? trans.language : songLanguage,
    publishedAt: wireText(wire['publish_date']),
    publicationCode: discoveryOptionalUnsigned32(wire['is_publish']),
    originalityCode: discoveryOptionalUnsigned32(wire['is_original']),
    hasAccompaniment: null,
    accompanimentCode: null,
    relatedGoodsExtension: null,
    providerExtension: _providerExtension(wire),
    paymentType: discoveryOptionalUnsigned32(audio['pay_type']),
    failureCode: discoveryOptionalUnsigned32(audio['fail_process']),
    oldCopyrightCode: discoveryOptionalUnsigned32(audio['old_cpy']),
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
    artists: authors,
    relatedVersions: const <MusicDiscoveryRelatedVersion>[],
  );
  return MusicDiscoverySong(song: summary, metadata: metadata);
}

/// `Vec<Author>`（list 语义：元素非 object → decode）。
List<MusicDiscoveryArtistDetail> _authors(List<Object?> authors) {
  final result = <MusicDiscoveryArtistDetail>[];
  for (final raw in authors) {
    final author = wireMap(raw);
    if (author == null) {
      throw const KugouApiException('decode', 'AI 推荐作者项不是 object');
    }
    result.add(
      MusicDiscoveryArtistDetail(
        id: discoveryOptionalUnsigned(author['author_id']),
        name: wireText(author['author_name']),
        avatarUrl: coverUrl(wireText(author['sizable_avatar'])),
        publicationCode: discoveryOptionalUnsigned32(author['is_publish']),
      ),
    );
  }
  return result;
}

/// ai_recommend_song.rs `provider_extension`：按嵌套路径丢弃已消费键
/// （audio_info.filesize 与 filesize_128 重复，留在扩展里），剩余非空才保留。
Object? _providerExtension(Map<String, Object?> wire) {
  final raw = Map<String, Object?>.of(wire);
  dropDiscoveryConsumedKeys(
    raw,
    'audio_info.trans_param',
    kugouDiscoveryTransConsumedKeys,
  );
  dropDiscoveryConsumedKeys(raw, 'audio_info', _aiAudioKeys);
  dropDiscoveryConsumedKeys(raw, 'album_info', <String>[
    'album_id',
    'album_name',
    'sizable_cover',
  ]);
  dropDiscoveryConsumedKeys(raw, '', _aiSongKeys);
  return raw.isEmpty ? null : raw;
}
