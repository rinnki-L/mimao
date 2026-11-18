/// 搜索端点——EchoMusicNext `crates/echo-api/src/module/search.rs` 的骨架期
/// 翻译子集（docs/architecture.md §4.3：`music/api/` ← module）。
///
/// 骨架只落单曲搜索（SearchKind::Song）——它的 wire 结构最全（含音质事实），
/// 播放链路直接消费；专辑/歌手/歌单/歌词/MV 分支随后续切片在同一文件补齐。
library;

import 'dart:typed_data';

import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import 'package:mimao/music/models/music_models.dart';

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
