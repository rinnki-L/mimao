/// 歌手目录端点——EchoMusicNext `crates/echo-api/src/module/artist_lists.rs`
/// 的翻译（docs/architecture.md §4.3：`music/api/` ← module，一端点一文件）。
///
/// 歌手字母/热度分组与分类筛选，映射 /ocean/v6/singer/list。注意：上游走
/// `ApiClient::request`（headers 为空）——**不带 kg-tid**，也没有 x-router；
/// 业务码字段是 `errcode`（ErrcodeEnvelope），且上游 decode() 的过期探测只看
/// `error_code` 键，因此 errcode=20018 在这里按业务码走（success → business）。
library;

import 'dart:typed_data';

import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/artist_models.dart';

/// 歌手目录查询（lists.rs `Query`：sex/category/musician 全必填，无缺省）。
class MusicArtistListsQuery {
  const MusicArtistListsQuery({
    required this.sex,
    required this.category,
    required this.musician,
  });

  /// 性别（wire `sextype`；u32 输入域，上游上限 3）。
  final int sex;

  /// 类型（wire `type`；u32 输入域，上游上限 8）。
  final int category;

  /// 音乐人标记（只允许 0 或 3）。
  final int musician;

  /// 上游 execute() 入口校验（u32 输入域等价拒绝负数）。
  void validate() {
    if (sex < 0 ||
        sex > 3 ||
        category < 0 ||
        category > 8 ||
        (musician != 0 && musician != 3)) {
      throw const KugouApiException('input', '歌手分类无效');
    }
  }
}

/// 歌手目录（分组卡片 + 性别/类型筛选）。
Future<MusicArtistDirectory> fetchArtistLists(
  MusicSession session,
  MusicArtistListsQuery query,
) async {
  query.validate();
  final identity = await session.ensureDevice();
  final response = await session.client.sendEndpoint(
    identity,
    KugouEndpoint(
      origin: KugouOrigin.gateway,
      path: '/ocean/v6/singer/list',
      method: 'GET',
      params: <String, String>{
        'musician': query.musician.toString(),
        'sextype': query.sex.toString(),
        'showtype': '2',
        'type': query.category.toString(),
        'hotsize': '100',
      },
    ),
  );
  return _convertArtistLists(response.bytes);
}

/// wire 解析（lists.rs `convert`；decode_value 的字段白名单只影响错误路径
/// 文案，这里按 decode 语义直接映射）。
MusicArtistDirectory _convertArtistLists(Uint8List bytes) {
  // ErrcodeEnvelope：业务码字段是 errcode；过期映射关闭（见文件头注释）。
  final envelope = decodeEnvelopeWithFields(
    bytes,
    errorCodeKey: 'errcode',
    mapAuthenticationExpired: false,
  );
  ensureBusinessSuccess(envelope.status, envelope.errorCode, context: '歌手目录');
  // data 缺省/null/数组 → decode 失败（from_value::<Data> 对非 object 必败）。
  final data = requiredWireMap(envelope.data, 'data');

  final groups = <MusicArtistGroup>[];
  for (final rawGroup in wireList(data['info'], 'info')) {
    final group = wireMap(rawGroup);
    if (group == null) {
      throw const KugouApiException('decode', '歌手目录响应 info 元素不是 object');
    }
    final artists = <MusicArtistCard>[];
    for (final rawArtist in wireList(group['singer'], 'singer')) {
      artists.add(_convertArtistCard(rawArtist));
    }
    groups.add(
      MusicArtistGroup(label: wireText(group['title']), artists: artists),
    );
  }

  // enu_list 按 `object` 反序列化：缺省/非 object → 空 Enums，不报错。
  final enums = wireMap(data['enu_list']) ?? const <String, Object?>{};
  final sexFilters = <MusicArtistFilter>[];
  for (final raw in wireList(enums['sextypes'], 'sextypes')) {
    final sex = wireMap(raw);
    if (sex == null) {
      throw const KugouApiException('decode', '歌手目录响应 sextypes 元素不是 object');
    }
    // key 是无 default 的必填标量（缺失/非标量 → 整条解码失败）。
    final key = requiredScalarInt(sex['key'], 'sextypes.key');
    sexFilters.add(
      MusicArtistFilter(
        id: '$key',
        label: wireText(sex['value']),
        category: key,
        musician: 0,
      ),
    );
  }
  final typeFilters = <MusicArtistFilter>[];
  for (final raw in wireList(enums['types'], 'types')) {
    final type = wireMap(raw);
    if (type == null) {
      throw const KugouApiException('decode', '歌手目录响应 types 元素不是 object');
    }
    final key = requiredScalarInt(type['key'], 'types.key');
    // musician 文本原样进 id（如 "1:" 表示文本缺省），数值按 decimal 解析。
    final musicianText = wireText(type['musician']);
    typeFilters.add(
      MusicArtistFilter(
        id: '$key:$musicianText',
        label: wireText(type['value']),
        category: key,
        musician: _decimalOption(musicianText),
      ),
    );
  }

  return MusicArtistDirectory(
    groups: groups,
    sexFilters: sexFilters,
    typeFilters: typeFilters,
    timestamp: optionalInt(data['timestamp']),
  );
}

MusicArtistCard _convertArtistCard(Object? raw) {
  final artist = wireMap(raw);
  if (artist == null) {
    throw const KugouApiException('decode', '歌手目录响应 singer 元素不是 object');
  }
  // singerid 必填标量：缺失/非标量 → 整个 data 解码失败（无 default 字段）。
  final singerId = requiredScalarInt(artist['singerid'], 'singerid');
  // dycover 按 `object` 反序列化：缺省/非 object → 空 Dynamic，不报错。
  final dycover = wireMap(artist['dycover']) ?? const <String, Object?>{};
  return MusicArtistCard(
    id: '$singerId',
    title: wireText(artist['singername']),
    creator: '',
    coverUrl: coverUrl(wireText(artist['imgurl'])),
    metadata: MusicArtistCardMetadata(
      albumCount: optionalInt(artist['albumcount']),
      songCount: optionalInt(artist['songcount']),
      fansCount: optionalInt(artist['fanscount']),
      mvCount: optionalInt(artist['mvcount']),
      description: optionalText(artist['descibe']),
      introduction: wireText(artist['intro']),
      settledCode: optionalInt(artist['is_settled']),
      heat: optionalInt(artist['heat']),
      heatChange: optionalInt(artist['heatoffset']),
      sortChange: optionalInt(artist['sortoffset']),
      dynamicFrameUrl: coverUrl(wireText(dycover['first_frame_image'])),
    ),
  );
}

/// `recommendation_song::decimal` + `u32::try_from`：纯数字文本且落在 u32 域
/// 内才有效，否则 null（空文本/越界/带小数都按未知处理）。
int? _decimalOption(String text) {
  if (text.isEmpty) return null;
  final parsed = int.tryParse(text);
  if (parsed == null || parsed < 0 || parsed > 0xFFFFFFFF) return null;
  return parsed;
}
