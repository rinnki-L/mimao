/// 搜索端点——EchoMusicNext `crates/echo-api/src/module/search.rs` 的翻译
/// （docs/architecture.md §4.3：`music/api/` ← module）。
///
/// 单曲（SearchKind::Song）是最早落地的分支；扩容后补齐 Album/Author/
/// Special/Lyric 四个分支（Mv 按排除清单不实现）。六个 item 模型字段互不回退
/// （search.rs 首行注释），各分支独立转换。
library;

import 'dart:typed_data';

import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import 'package:mimao/music/models/catalog_models.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/models/search_models.dart';

/// 搜索单曲的输入（search.rs `Query` 的 Song 分支）。
class SearchSongsQuery {
  const SearchSongsQuery({
    required this.keyword,
    this.page = 1,
    this.pageSize = 30,
  });

  final String keyword;

  /// 1 起始页码。
  final int page;
  final int pageSize;

  void validate() {
    if (keyword.trim().isEmpty) {
      throw const KugouApiException('input', '搜索关键词不能为空');
    }
    if (page < 1) {
      throw const KugouApiException('input', '搜索页码无效');
    }
    if (pageSize < 1 || pageSize > 100) {
      throw const KugouApiException('input', '搜索分页大小无效');
    }
  }
}

/// /v2/search/song（网关 + x-router=complexsearch.kugou.com）。
Future<MusicPage<MusicSong>> searchSongs(
  KugouClient client,
  KugouIdentity identity,
  SearchSongsQuery query,
) async {
  query.validate();
  final params = <String, String>{
    'keyword': query.keyword,
    'page': query.page.toString(),
    'pagesize': query.pageSize.toString(),
    'platform': 'AndroidFilter',
    'iscorrection': '1',
    // 真实匿名采样：省略 userid 会返回 152；显式 0 可成功且不注入 token/t1
    // ——这是端点参数，不是跳过鉴权策略的例外（上游注释原样保留）。
    'userid': identity.userId.toString(),
    'clientver': '201',
    'privilegefilter': '0',
    'area_code': '1',
    'dopicfull': '1',
  };
  final response = await client.sendEndpoint(
    identity,
    KugouEndpoint(
      origin: KugouOrigin.gateway,
      path: '/v2/search/song',
      router: 'complexsearch.kugou.com',
      method: 'GET',
      params: params,
    ),
  );
  return _convertSearchSongs(response.bytes);
}

/// wire 解析（search.rs Song 分支 + SongFacts）。
MusicPage<MusicSong> _convertSearchSongs(Uint8List bytes) {
  final data = decodeBusinessEnvelope(bytes, context: '搜索').data;
  final page = wireMap(data);
  if (page == null) {
    throw const KugouApiException('decode', '搜索响应 data 不是 object');
  }
  // lists 是必填字段（Rust WirePage.lists 无 default）。
  if (!page.containsKey('lists')) {
    throw const KugouApiException('decode', '搜索响应缺少 lists');
  }
  final lists = wireList(page['lists'], 'lists').map(_convertSong).toList();
  return MusicPage<MusicSong>(
    page: optionalInt(page['page']),
    pageSize: optionalInt(page['pagesize']),
    total: optionalInt(page['total']),
    items: lists,
  );
}

/// 搜索专辑（search.rs Album 分支）。
///
/// `query` 即 search.rs `Query` 的分页/关键词输入——Song 分支骨架期把它拆成
/// 了 SearchSongsQuery，四个分支的校验完全同源，直接复用。
Future<MusicPage<MusicAlbumSummary>> fetchSearchAlbums(
  MusicSession session,
  SearchSongsQuery query,
) async {
  final identity = await session.ensureDevice();
  final response = await session.client.sendEndpoint(
    identity,
    KugouEndpoint(
      origin: KugouOrigin.gateway,
      path: '/v1/search/album',
      router: 'complexsearch.kugou.com',
      method: 'GET',
      params: _searchPageParams(query)
        ..addAll(const <String, String>{
          'clientver': '201',
          'category': '1',
          'sorttype': '0',
          'searchsong': '0',
        }),
    ),
  );
  return _convertSearchAlbums(response.bytes);
}

/// 搜索歌手（search.rs Author 分支）。
Future<MusicPage<MusicArtistSummary>> fetchSearchArtists(
  MusicSession session,
  SearchSongsQuery query,
) async {
  final identity = await session.ensureDevice();
  final response = await session.client.sendEndpoint(
    identity,
    KugouEndpoint(
      origin: KugouOrigin.gateway,
      path: '/v1/search/author',
      router: 'complexsearch.kugou.com',
      method: 'GET',
      params: _searchPageParams(query)
        ..addAll(const <String, String>{'albumhide': '0', 'nocollect': '0'}),
    ),
  );
  return _convertSearchArtists(response.bytes);
}

/// 搜索歌单（search.rs Special 分支；wire 键是 special*）。
Future<MusicPage<MusicPlaylistSummary>> fetchSearchPlaylists(
  MusicSession session,
  SearchSongsQuery query,
) async {
  final identity = await session.ensureDevice();
  final response = await session.client.sendEndpoint(
    identity,
    KugouEndpoint(
      origin: KugouOrigin.gateway,
      path: '/v1/search/special',
      router: 'complexsearch.kugou.com',
      method: 'GET',
      params: _searchPageParams(query)
        ..addAll(const <String, String>{'albumhide': '0', 'nocollect': '0'}),
    ),
  );
  return _convertSearchPlaylists(response.bytes);
}

/// 搜索歌词命中（search.rs Lyric 分支）。
Future<MusicPage<MusicLyricHit>> fetchSearchLyrics(
  MusicSession session,
  SearchSongsQuery query,
) async {
  final identity = await session.ensureDevice();
  final response = await session.client.sendEndpoint(
    identity,
    KugouEndpoint(
      origin: KugouOrigin.gateway,
      path: '/v1/search/lyric',
      router: 'complexsearch.kugou.com',
      method: 'GET',
      params: _searchPageParams(query)
        ..addAll(const <String, String>{'albumhide': '0', 'nocollect': '0'}),
    ),
  );
  return _convertSearchLyricHits(response.bytes);
}

/// Album/Author/Special/Lyric 四个分支共用的基础参数
/// （search.rs execute 的 BTreeMap 公共段）。
Map<String, String> _searchPageParams(SearchSongsQuery query) {
  query.validate();
  return <String, String>{
    'keyword': query.keyword,
    'page': query.page.toString(),
    'pagesize': query.pageSize.toString(),
    'platform': 'AndroidFilter',
    'iscorrection': '1',
  };
}

/// wire 解析（search.rs 各非 Song 分支：Envelope + WirePage）。
///
/// 与 Song 分支唯一的结构差异：扩容期上游的 WirePage.lists 带
/// `#[serde(default)]`——lists 键缺失回空页（Song 分支保持骨架期的必填语义）。
MusicPage<T> _convertSearchPage<T>(
  Uint8List bytes,
  T Function(Object? raw) convertItem,
) {
  final data = decodeBusinessEnvelope(bytes, context: '搜索').data;
  final page = wireMap(data);
  if (page == null) {
    throw const KugouApiException('decode', '搜索响应 data 不是 object');
  }
  final lists = wireList(page['lists'], 'lists').map(convertItem).toList();
  return MusicPage<T>(
    page: optionalInt(page['page']),
    pageSize: optionalInt(page['pagesize']),
    total: optionalInt(page['total']),
    items: lists,
  );
}

/// 歌手列表（search.rs `Singer` → ArtistRef；非 object 项按 decode 失败）。
List<MusicArtistRef> _searchSingers(List<Object?> raw) => raw.map((singer) {
  final map = wireMap(singer);
  if (map == null) {
    throw const KugouApiException('decode', '搜索结果歌手项不是 object');
  }
  return MusicArtistRef(
    id: optionalInt(map['id']),
    name: wireText(map['name']),
  );
}).toList();

/// wire 解析（search.rs Album 分支 → AlbumSummary）。
MusicPage<MusicAlbumSummary> _convertSearchAlbums(Uint8List bytes) =>
    _convertSearchPage(bytes, _convertAlbum);

MusicAlbumSummary _convertAlbum(Object? raw) {
  final wire = wireMap(raw);
  if (wire == null) {
    throw const KugouApiException('decode', '搜索结果项不是 object');
  }
  return MusicAlbumSummary(
    id: optionalInt(wire['albumid']),
    title: wireText(wire['albumname']),
    artists: _searchSingers(wireList(wire['singers'], 'singers')),
    coverUrl: coverUrl(wireText(wire['img'])),
    songCount: optionalInt(wire['songcount']),
    publishedAt: wireText(wire['publish_time']),
  );
}

/// wire 解析（search.rs Author 分支 → ArtistSummary）。
MusicPage<MusicArtistSummary> _convertSearchArtists(Uint8List bytes) =>
    _convertSearchPage(bytes, _convertArtist);

MusicArtistSummary _convertArtist(Object? raw) {
  final wire = wireMap(raw);
  if (wire == null) {
    throw const KugouApiException('decode', '搜索结果项不是 object');
  }
  // 注意：Author 头像不做 cover_url 占位符替换（上游 avatar_url: a.avatar）。
  return MusicArtistSummary(
    id: optionalInt(wire['AuthorId']),
    name: wireText(wire['AuthorName']),
    avatarUrl: wireText(wire['Avatar']),
    albumCount: optionalInt(wire['AlbumCount']),
    songCount: optionalInt(wire['AudioCount']),
    fans: optionalInt(wire['FansNum']),
  );
}

/// wire 解析（search.rs Special 分支 → PlaylistSummary）。
MusicPage<MusicPlaylistSummary> _convertSearchPlaylists(Uint8List bytes) =>
    _convertSearchPage(bytes, _convertPlaylist);

/// Special 的封面同样不替换占位符（上游 cover_url: s.img）。
MusicPlaylistSummary _convertPlaylist(Object? raw) {
  final wire = wireMap(raw);
  if (wire == null) {
    throw const KugouApiException('decode', '搜索结果项不是 object');
  }
  return MusicPlaylistSummary(
    id: optionalInt(wire['specialid']),
    globalId: wireText(wire['gid']),
    title: wireText(wire['specialname']),
    creatorId: wireText(wire['suid']),
    creatorName: wireText(wire['nickname']),
    coverUrl: wireText(wire['img']),
    songCount: optionalInt(wire['song_count']),
    // wire play_count 是文本字段，Rust 用 u64 parse：负数/非数字 → null。
    playCount: _parseUnsignedCount(wireText(wire['play_count'])),
  );
}

/// `String::parse::<u64>()` 语义：负数与非法文本都回 null。
int? _parseUnsignedCount(String text) =>
    text.startsWith('-') ? null : int.tryParse(text);

/// wire 解析（search.rs Lyric 分支 → LyricHit；facts 与 Song 分支同构）。
MusicPage<MusicLyricHit> _convertSearchLyricHits(Uint8List bytes) =>
    _convertSearchPage(bytes, _convertLyricHit);

MusicLyricHit _convertLyricHit(Object? raw) {
  final wire = wireMap(raw);
  if (wire == null) {
    throw const KugouApiException('decode', '搜索结果项不是 object');
  }
  final durationSeconds = optionalInt(wire['TimeLength']);
  final facts = _SongFacts.of(wire);
  final song = MusicSong(
    // 注释原文：与单曲搜索不同，该分支的 MixSongID 是 JSON 数字——text 解码
    // 统一成字符串（Rust s.id.to_string()）。
    id: wireText(wire['MixSongID']),
    hash: wireText(wire['FileHash']),
    title: wireText(wire['SongName']),
    artists: _searchSingers(wireList(wire['Singers'], 'Singers')),
    albumId: wireText(wire['AlbumID']),
    // Rust album_title: None——模型用空串表达「没有专辑名」。
    albumTitle: '',
    durationMs: durationSeconds == null ? null : durationSeconds * 1000,
    coverUrl: _coverUrl(wireText(wire['Image'])),
    privilege:
        optionalInt(wire['AlbumPrivilege']) ?? optionalInt(wire['Privilege']),
    resources: facts.resources,
  );
  return MusicLyricHit(
    song: song,
    lyricId: optionalInt(wire['LyricID']),
    excerpt: wireText(wire['Lyric']),
  );
}

MusicSong _convertSong(Object? raw) {
  final wire = wireMap(raw);
  if (wire == null) {
    throw const KugouApiException('decode', '搜索结果项不是 object');
  }
  final singers = wireList(wire['Singers'], 'Singers').map((singer) {
    final map = wireMap(singer);
    return MusicArtistRef(
      id: map == null ? null : optionalInt(map['id']),
      name: map == null ? '' : wireText(map['name']),
    );
  }).toList();

  final durationSeconds = optionalInt(wire['Duration']);
  final facts = _SongFacts.of(wire);
  return MusicSong(
    id: wireText(wire['MixSongID']),
    audioId: optionalInt(wire['Audioid']),
    hash: wireText(wire['FileHash']),
    title: wireText(wire['SongName']),
    artists: singers,
    albumId: wireText(wire['AlbumID']),
    albumTitle: wireText(wire['AlbumName']),
    durationMs: durationSeconds == null ? null : durationSeconds * 1000,
    coverUrl: _coverUrl(wireText(wire['Image'])),
    // search.rs facts.privilege(s)：AlbumPrivilege 存在时优先，回退 Privilege。
    privilege:
        optionalInt(wire['AlbumPrivilege']) ?? optionalInt(wire['Privilege']),
    resources: facts.resources,
  );
}

/// domain.rs `cover_url`：`{size}` 占位符 → 240。
String _coverUrl(String template) => template.replaceAll('{size}', '240');

/// SongFacts——平铺的 HQ/SQ/Res 字段与嵌套 HQ/SQ/Res 对象折叠成资源表。
/// trans_param（版权映射 WireTrans）骨架期不解析，见 README。
class _SongFacts {
  const _SongFacts._(this.resources);

  final List<MusicAudioResource> resources;

  static _SongFacts of(Map<String, Object?> wire) {
    final resources = <MusicAudioResource>[];
    void push(
      String quality,
      String hash,
      int? size,
      int? durationSeconds,
      int? bitrate,
      String? extName, {
      int? privilege,
      int? payType,
      int? failure,
    }) {
      final hashOrNull = hash.isEmpty ? null : hash;
      // 上游 push_quality：跳过判定用**解析后**的值（response::optional 已把
      // 非数字归 None）；全空条目跳过；(quality, hash) 重复条目跳过。
      if (hashOrNull == null &&
          size == null &&
          durationSeconds == null &&
          bitrate == null &&
          extName == null) {
        return;
      }
      final exists = resources.any(
        (r) => r.quality == quality && r.hash == hashOrNull,
      );
      if (exists) return;
      resources.add(
        MusicAudioResource(
          quality: quality,
          hash: hashOrNull,
          sizeBytes: size,
          durationMs: durationSeconds == null ? null : durationSeconds * 1000,
          bitRateBps: bitrate == null ? null : bitrate * 1000,
          extension: extName,
          privilege: privilege,
          payType: payType,
          failureCode: failure,
        ),
      );
    }

    // 平铺字段（HQ→320、SQ→flac；Res→high 不带权限事实——上游一致）。
    // 平铺 extName 走 text+非空过滤（Rust Some(hq_ext_name).filter(!empty)）。
    String? flatExt(Object? value) {
      final text = optionalText(value);
      return (text == null || text.isEmpty) ? null : text;
    }

    push(
      '320',
      wireText(wire['HQFileHash']),
      optionalInt(wire['HQFileSize']),
      optionalInt(wire['HQDuration']),
      optionalInt(wire['HQBitrate']),
      flatExt(wire['HQExtName']),
      privilege: optionalInt(wire['HQPrivilege']),
      payType: optionalInt(wire['HQPayType']),
      failure: optionalInt(wire['HQFailProcess']),
    );
    push(
      'flac',
      wireText(wire['SQFileHash']),
      optionalInt(wire['SQFileSize']),
      optionalInt(wire['SQDuration']),
      optionalInt(wire['SQBitrate']),
      flatExt(wire['SQExtName']),
      privilege: optionalInt(wire['SQPrivilege']),
      payType: optionalInt(wire['SQPayType']),
      failure: optionalInt(wire['SQFailProcess']),
    );
    push(
      'high',
      wireText(wire['ResFileHash']),
      optionalInt(wire['ResFileSize']),
      optionalInt(wire['ResDuration']),
      optionalInt(wire['ResBitrate']),
      null,
    );

    // 嵌套对象（PascalCase 键；同 (quality, hash) 会被上面的平铺条目去重）。
    // 嵌套 extName 不过滤空串（Rust 直接传 entry.ext_name）——空串会阻止
    // 全空跳过并以 Some("") 入表，语义与平铺分支刻意不同。
    for (final (quality, key) in const <(String, String)>[
      ('320', 'HQ'),
      ('flac', 'SQ'),
      ('high', 'Res'),
    ]) {
      final nested = wireMap(wire[key]);
      if (nested == null) continue;
      push(
        quality,
        wireText(nested['hash']),
        optionalInt(nested['fileSize']),
        optionalInt(nested['duration']),
        optionalInt(nested['bitRate']),
        optionalText(nested['extName']),
        privilege: optionalInt(nested['privilege']),
        payType: optionalInt(nested['payType']),
        failure: optionalInt(nested['failProcess']),
      );
    }
    return _SongFacts._(resources);
  }
}
