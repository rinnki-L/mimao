/// 专辑详情端点——EchoMusicNext `crates/echo-api/src/module/album_detail.rs`
/// 的翻译（docs/architecture.md §4.3：`music/api/` ← module，一端点一文件）。
///
/// POST `/kmr/v2/albums`（网关 + x-router=openapi.kugou.com）。采样里 id/flag
/// 都是字符串：标量表示与可选元数据不挡专辑行（上游模块注释）。
library;

import 'dart:typed_data';

import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/album_models.dart';
import 'package:mimao/music/models/music_models.dart';

/// POST body 的 `fields` 值（album_detail.rs `Body.fields` 原样，字段顺序不动）。
const String kugouAlbumDetailFields =
    'album_id,album_name,publish_date,sizable_cover,intro,language,is_publish,'
    'heat,type,quality,authors,exclusive,author_name,trans_param,publish_company';

/// 专辑详情（album_detail.rs `execute`：无独立 Query 结构，id 直传 u64）。
Future<MusicAlbumDetail?> fetchAlbumDetail(MusicSession session, int id) async {
  final identity = await session.ensureDevice();
  // serde 序列化顺序 = 字段声明顺序：data → is_buy → fields（JSON body 顺序
  // 不许重排，黄金采样按字节对拍）。
  final response = await session.client.sendEndpoint(
    identity,
    KugouEndpoint(
      origin: KugouOrigin.gateway,
      path: '/kmr/v2/albums',
      router: 'openapi.kugou.com',
      method: 'POST',
      body: encodeJsonBody(<String, Object?>{
        'data': <Object?>[
          <String, Object?>{'album_id': id.toString()},
        ],
        'is_buy': 0,
        'fields': kugouAlbumDetailFields,
      }),
      headers: const <(String, String)>[('kg-tid', '255')],
    ),
  );
  return _convertAlbumDetail(response.bytes);
}

/// wire 解析（album_detail.rs `convert`）：返回 null 表示「无此专辑」，
/// 与业务失败（business）是两条路。
MusicAlbumDetail? _convertAlbumDetail(Uint8List bytes) {
  final envelope = decodeBusinessEnvelope(bytes, context: '专辑详情');
  // Wire.data 是 list 语义：缺省/空对象宽容，其它错配按 decode 失败。
  final data = wireList(envelope.data, 'data');
  // 空数组 → 无首条 → 无专辑（into_iter().next() → None）。
  if (data.isEmpty) return null;
  final first = data.first;
  // 空对象 → 无专辑（上游在 Album 反序列化之前显式判定）。
  final wire = wireMap(first);
  if (wire != null && wire.isEmpty) return null;
  // 非对象条目 → from_value(Album) 失败 → decode；部分字段缺失的「残缺专辑」
  // 保留可用事实（所有字段 default）。
  if (wire == null) {
    throw const KugouApiException('decode', '专辑详情条目不是 object');
  }
  final authors = wireList(
    wire['authors'],
    'authors',
  ).map(_convertAuthor).toList();
  final sizableCover = wireText(wire['sizable_cover']);
  return MusicAlbumDetail(
    id: _parseUnsigned(wireText(wire['album_id'])),
    title: wireText(wire['album_name']),
    artists: authors,
    coverUrl: coverUrl(sizableCover),
    publishedAt: wireText(wire['publish_date']),
    publisher: wireText(wire['publish_company']),
    description: wireText(wire['intro']),
    language: wireText(wire['language']),
    category: wireText(wire['type']),
    heat: _parseUnsigned(wireText(wire['heat'])),
    quality: _parseUnsigned(wireText(wire['quality'])),
    exclusive: _flag(wireText(wire['exclusive'])),
    published: _flag(wireText(wire['is_publish'])),
  );
}

MusicArtistRef _convertAuthor(Object? raw) {
  final author = wireMap(raw);
  if (author == null) {
    throw const KugouApiException('decode', '专辑作者条目不是 object');
  }
  return MusicArtistRef(
    id: _parseUnsigned(wireText(author['author_id'])),
    name: wireText(author['author_name']),
  );
}

/// Rust `u64::from_str` 的 Dart 等价：可选 `+` 号、纯数字、不 trim、不容负号
/// （parse().ok() 失败归 null）。
int? _parseUnsigned(String text) {
  final digits = text.startsWith('+') ? text.substring(1) : text;
  if (digits.isEmpty) return null;
  for (final code in digits.codeUnits) {
    if (code < 0x30 || code > 0x39) return null;
  }
  return int.tryParse(digits);
}

/// album_detail.rs `flag`：文本 → u32 解析 → numeric::boolean
/// （0→false、1→true、其它/不可解析→null）。
bool? _flag(String text) {
  final value = _parseUnsigned(text);
  return switch (value) {
    null => null,
    0 => false,
    1 => true,
    _ => null,
  };
}
