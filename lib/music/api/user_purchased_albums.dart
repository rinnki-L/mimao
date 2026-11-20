/// 已购专辑端点——EchoMusicNext `crates/echo-api/src/module/
/// user_purchased_albums.rs` 的翻译（docs/architecture.md §4.3）。
///
/// 行语义按 2026-10-28 非空样本映射：专辑 id 过滤 >0，歌手只取名字串，
/// 未知键原样进 provider_extension。
library;

import 'dart:typed_data';

import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/catalog_models.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/models/user_library_models.dart';

/// 已购列表的公共分页请求（user_purchased_albums.rs / user_purchased_songs.rs
/// `Query`：page/page_size，1..=100）。
class MusicUserPagedQuery {
  const MusicUserPagedQuery({required this.page, required this.pageSize});

  /// 1 起始页码（u32，0 无效）。
  final int page;

  /// 1..=100。
  final int pageSize;

  /// 上游两条端点的 input 文案不同，由端点函数携带。
  void validate({String invalidMessage = '已购专辑分页参数无效'}) {
    if (page == 0 || pageSize < 1 || pageSize > 100) {
      throw KugouApiException('input', invalidMessage);
    }
  }
}

/// POST /openapi/v1/copyright/get_album_goods（网关；需要账号）。
Future<MusicPage<MusicPurchasedAlbum>> fetchUserPurchasedAlbums(
  MusicSession session,
  MusicUserPagedQuery query,
) async {
  final identity = await session.ensureDevice();
  requireMusicAccount(identity);
  query.validate();
  final response = await session.client.sendEndpoint(
    identity,
    KugouEndpoint(
      origin: KugouOrigin.gateway,
      path: '/openapi/v1/copyright/get_album_goods',
      method: 'POST',
      // Rust json! 宏经 BTreeMap 序列化：键按字典序输出。
      body: encodeJsonBody(<String, Object?>{
        'appid': 3116,
        'clientver': '11440',
        'deleted': 0,
        'page': query.page,
        'pagesize': query.pageSize,
        'token': identity.token,
        'userid': identity.userId,
      }),
    ),
  );
  return _convertPurchasedAlbums(response.bytes, query.page, query.pageSize);
}

/// wire 解析（user_purchased_albums.rs `convert`）。
MusicPage<MusicPurchasedAlbum> _convertPurchasedAlbums(
  Uint8List bytes,
  int page,
  int pageSize,
) {
  final envelope = decodeEnvelope(bytes);
  if (envelope.status != 1 && envelope.errorCode == 20017) {
    throw KugouApiException(
      'authentication',
      '账号认证无效，请重新登录',
      code: envelope.errorCode,
    );
  }
  ensureBusinessSuccess(envelope.status, envelope.errorCode, context: '已购专辑');
  final data = wireMap(envelope.data);
  if (data == null) {
    throw const KugouApiException('decode', '已购专辑响应 data 不是 object');
  }
  final items = wireList(
    data['goods'],
    'goods',
  ).map(_convertPurchasedAlbum).toList();
  return MusicPage<MusicPurchasedAlbum>(
    page: page,
    pageSize: pageSize,
    total: musicWireUnsigned(data['total']),
    items: items,
  );
}

const Set<String> _kAlbumRowKeys = <String>{
  'album_id',
  'album_name',
  'singer_name',
  'cover',
  'is_publish',
};

MusicPurchasedAlbum _convertPurchasedAlbum(Object? raw) {
  final row = wireMap(raw);
  if (row == null) {
    throw const KugouApiException('decode', '已购专辑条目不是 object');
  }
  final albumId = musicWireUnsigned(row['album_id']);
  final singerName = wireText(row['singer_name']);
  return MusicPurchasedAlbum(
    // id 过滤 >0（0/缺省 → null）。
    album: MusicAlbumSummary(
      id: albumId != null && albumId > 0 ? albumId : null,
      title: wireText(row['album_name']),
      // 歌手只有名字串（id 不下发）；空歌手名 → 空表。
      artists: singerName.isEmpty
          ? const <MusicArtistRef>[]
          : <MusicArtistRef>[MusicArtistRef(name: singerName)],
      coverUrl: wireText(row['cover']).replaceAll('{size}', '400'),
      songCount: null,
      publishedAt: '',
    ),
    publicationCode: musicWireU32(row['is_publish']),
    providerExtension: _extraOf(row, _kAlbumRowKeys),
  );
}

/// `#[serde(flatten)] extra`：wire 里的未知键原样保留（有序输出由调用方
/// 决定；这里按 BTreeMap 键序整理）。
Map<String, Object?> _extraOf(Map<String, Object?> wire, Set<String> known) {
  final extraKeys = wire.keys.where((key) => !known.contains(key)).toList()
    ..sort();
  return <String, Object?>{for (final key in extraKeys) key: wire[key]};
}
