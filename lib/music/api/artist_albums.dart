/// 歌手专辑端点——EchoMusicNext `crates/echo-api/src/module/artist_albums.rs`
/// 的翻译（docs/architecture.md §4.3：`music/api/` ← module，一端点一文件）。
///
/// /artist/albums 映射 /kmr/v1/author/albums（网关 POST，x-router=
/// openapi.kugou.com，kg-tid=36）：`total` 与 `data` 是信封根上的平铺字段，
/// 每张专辑自带 authors；卡片事实保持可选。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/catalog_models.dart';
import 'package:mimao/music/models/music_models.dart';

/// 歌手专辑查询（albums.rs `Query`：page=1、page_size=30、sort='hot' 缺省）。
class MusicArtistAlbumsQuery {
  const MusicArtistAlbumsQuery({
    required this.id,
    this.page = 1,
    this.pageSize = 30,
    this.sort = 'hot',
  });

  /// 歌手 id（u64 输入域；负数在 Rust 侧是反序列化失败）。
  final int id;

  /// 1 起始页码。
  final int page;
  final int pageSize;
  final String sort;

  /// 上游 execute() 入口校验（顺序一致：分页在前，排序映射在后）。
  void validate() {
    if (id < 0) {
      throw const KugouApiException('input', '歌手 id 无效');
    }
    if (page < 1 || pageSize < 1 || pageSize > 100) {
      throw const KugouApiException('input', '歌手专辑分页参数无效');
    }
    if (sort != 'hot' && sort != 'new') {
      throw const KugouApiException('input', '歌手专辑排序无效');
    }
  }
}

/// 排序词 → wire sort（albums.rs：hot→3、new→1）。
int artistAlbumsSortCode(String sort) => sort == 'hot' ? 3 : 1;

/// 歌手专辑分页（摘要复用共享 `MusicAlbumSummary`，song_count 恒 null）。
Future<MusicPage<MusicAlbumSummary>> fetchArtistAlbums(
  MusicSession session,
  MusicArtistAlbumsQuery query,
) async {
  query.validate();
  final identity = await session.ensureDevice();
  final response = await session.client.sendEndpoint(
    identity,
    KugouEndpoint(
      origin: KugouOrigin.gateway,
      path: '/kmr/v1/author/albums',
      router: 'openapi.kugou.com',
      method: 'POST',
      body: encodeJsonBody(<String, Object?>{
        'author_id': query.id,
        'pagesize': query.pageSize,
        'page': query.page,
        'sort': artistAlbumsSortCode(query.sort),
        'category': 1,
        'area_code': 'all',
      }),
      headers: const <(String, String)>[('kg-tid', '36')],
    ),
  );
  return _convertArtistAlbums(response.bytes, query.page, query.pageSize);
}

/// albums.rs `Wire`：status/error_code/total/data 全部在信封根上。
class _AlbumsWire {
  const _AlbumsWire(this.status, this.errorCode, this.total, this.data);

  final int status;
  final int errorCode;
  final int? total;
  final List<Object?> data;
}

/// 信封解码（albums.rs `request::decode_envelope(bytes, "error_code")`）：
/// 结构解析失败时按 error_code 非 0 或 status=0 兜底成 business——只有
/// 真正的结构缺陷才回 decode。
_AlbumsWire _decodeAlbumsEnvelope(Uint8List bytes) {
  final root = _decodeRootObject(bytes, '歌手专辑响应');
  // request.rs decode() 在 serde 之前统一判登录过期码（error_code 键）。
  final errorCode = optionalInt(root['error_code']);
  if (errorCode == kugouErrorCodeAuthenticationExpired) {
    throw const KugouApiException('authentication', '登录已过期，请重新登录酷狗账号');
  }
  final status = optionalInt(root['status']);
  if (status == null || errorCode == null) {
    // decode_envelope 兜底：error_code 非 0 或 status==0 → business(code)。
    if ((errorCode != null && errorCode != 0) || status == 0) {
      throw KugouApiException(
        'business',
        '音乐服务返回失败（歌手专辑）',
        code: errorCode ?? 0,
      );
    }
    throw const KugouApiException('decode', '响应字段 status/error_code 缺失或不是标量数字');
  }
  ensureBusinessSuccess(status, errorCode, context: '歌手专辑');
  return _AlbumsWire(
    status,
    errorCode,
    optionalInt(root['total']),
    wireList(root['data'], 'data'),
  );
}

/// 根 object 解码（JSON 非法/不是 object → decode）。
Map<String, Object?> _decodeRootObject(Uint8List bytes, String context) {
  Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(bytes));
  } on Object {
    throw const KugouApiException('decode', '响应不是合法 JSON');
  }
  final root = wireMap(decoded);
  if (root == null) {
    throw KugouApiException('decode', '$context不是 JSON object');
  }
  return root;
}

/// wire 解析（albums.rs `convert`）。
MusicPage<MusicAlbumSummary> _convertArtistAlbums(
  Uint8List bytes,
  int page,
  int pageSize,
) {
  final wire = _decodeAlbumsEnvelope(bytes);
  final items = <MusicAlbumSummary>[];
  for (final raw in wire.data) {
    final album = wireMap(raw);
    if (album == null) {
      throw const KugouApiException('decode', '歌手专辑响应 data 元素不是 object');
    }
    final artists = <MusicArtistRef>[];
    for (final entry in wireList(album['authors'], 'authors')) {
      final author = wireMap(entry);
      if (author == null) {
        throw const KugouApiException('decode', '歌手专辑响应 authors 元素不是 object');
      }
      final name = wireText(author['author_name']);
      // 上游 filter(!author_name.is_empty())：空名作者直接丢弃。
      if (name.isEmpty) continue;
      artists.add(
        MusicArtistRef(id: optionalInt(author['author_id']), name: name),
      );
    }
    // authors 全空时回退平铺 author_name（id 无源，恒 null）。
    final flatAuthorName = wireText(album['author_name']);
    if (artists.isEmpty && flatAuthorName.isNotEmpty) {
      artists.add(MusicArtistRef(id: null, name: flatAuthorName));
    }
    items.add(
      MusicAlbumSummary(
        id: optionalInt(album['album_id']),
        title: wireText(album['album_name']),
        artists: artists,
        coverUrl: coverUrl(wireText(album['sizable_cover'])),
        songCount: null,
        publishedAt: wireText(album['publish_date']),
      ),
    );
  }
  return MusicPage<MusicAlbumSummary>(
    page: page,
    pageSize: pageSize,
    total: wire.total,
    items: items,
  );
}
