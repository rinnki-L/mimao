/// 私人 FM 端点——EchoMusicNext `crates/echo-api/src/module/personal_fm.rs`
/// 的翻译（预览/补充/反馈共用一个供应商端点）。
///
/// 老用户协议 body：account 必需（user_protocol::require_account）、固定
/// fakem 常量与 md5 `key`（timestamp_key）；信封的 error_code 带 serde
/// default（缺省 → 0）。FM 列表复用 recommendation_song 的 Song 协议后再做
/// FM 专属覆盖（mixsongid/作者回退/封面回退/专辑名回退/relate_goods 资源）。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:mimao/music/api/everyday_recommend.dart';
import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import 'package:mimao/music/models/discovery_models.dart';
import 'package:mimao/music/models/music_models.dart';

/// personal_fm.rs `Mode`（wire snake_case）。
enum MusicPersonalFmMode { normal, small, peak, radio }

/// personal_fm.rs `Action`（wire snake_case）。
enum MusicPersonalFmAction {
  play,
  login,
  garbage,
  cancelGarbage,
  clickRed,
  cancelRed,
  download,
  blackSinger,
  cancelBlackSinger,
  updateRecommendSource,
  changeSongPool,
}

/// 私人 FM 输入（personal_fm.rs `Query`）。
class MusicPersonalFmQuery {
  const MusicPersonalFmQuery({
    this.mode = MusicPersonalFmMode.normal,
    this.action = MusicPersonalFmAction.play,
    this.songPoolId = 0,
    this.remainSongcnt = 0,
    this.isOverplay = false,
    this.hash = '',
    this.songId,
    this.playtime,
    this.curMark = '',
  });

  final MusicPersonalFmMode mode;
  final MusicPersonalFmAction action;
  final int songPoolId;
  final int remainSongcnt;
  final bool isOverplay;
  final String hash;
  final int? songId;
  final int? playtime;
  final String curMark;

  /// song_pool_id > 2 → input（personal_fm.rs `body` 的校验，账号校验之后）。
  void validate() {
    if (songPoolId > 2) {
      throw const KugouApiException('input', '无效的 FM 歌曲范围');
    }
  }
}

String _modeWire(MusicPersonalFmMode mode) => switch (mode) {
  MusicPersonalFmMode.normal => 'normal',
  MusicPersonalFmMode.small => 'small',
  MusicPersonalFmMode.peak => 'peak',
  MusicPersonalFmMode.radio => 'radio',
};

String _actionWire(MusicPersonalFmAction action) => switch (action) {
  MusicPersonalFmAction.play => 'play',
  MusicPersonalFmAction.login => 'login',
  MusicPersonalFmAction.garbage => 'garbage',
  MusicPersonalFmAction.cancelGarbage => 'cancel_garbage',
  MusicPersonalFmAction.clickRed => 'click_red',
  MusicPersonalFmAction.cancelRed => 'cancel_red',
  MusicPersonalFmAction.download => 'download',
  MusicPersonalFmAction.blackSinger => 'black_singer',
  MusicPersonalFmAction.cancelBlackSinger => 'cancel_black_singer',
  MusicPersonalFmAction.updateRecommendSource => 'update_recommend_source',
  MusicPersonalFmAction.changeSongPool => 'change_song_pool',
};

/// user_protocol.rs `timestamp_key`：md5("3116" + lite salt + "11440" + time)
/// 的小写 hex（time 是毫秒）。
String kugouPersonalFmTimestampKey(int timeMs) => md5
    .convert(utf8.encode('3116LnT6xpN3khm36zse0QzvmgTZ3waWdRSA11440$timeMs'))
    .toString();

/// personal_fm.rs `body`：require_account → song_pool_id 校验 → 组装。
/// [timeMs] 对齐 request::unix_milliseconds（测试注入）。
///
/// serde_json 的 Map 默认按 BTreeMap 落盘：返回的键序即字典序，签名覆盖的
/// 请求体字节与上游一致。
Map<String, Object?> personalFmRequestBody(
  KugouIdentity identity,
  MusicPersonalFmQuery query,
  int timeMs,
) {
  // user_protocol::require_account：userid=0 或 token 空 → authentication。
  if (identity.userId == 0 || identity.token.isEmpty) {
    throw const KugouApiException('authentication', '请先登录');
  }
  query.validate();
  final body = <String, Object?>{
    'action': _actionWire(query.action),
    'appid': 3116,
    'area_code': 1,
    'callerid': 0,
    'clienttime': timeMs,
    'clientver': 11440,
    'fakem': 'ca981cfc583a4c37f28d2d49000013c16a0a',
    'is_overplay': query.isOverplay ? 1 : 0,
    'key': kugouPersonalFmTimestampKey(timeMs),
    'kguid': identity.userId,
    'm_type': 1,
    'mid': identity.mid,
    'mode': _modeWire(query.mode),
    'platform': 'ios',
    'recommend_source_locked': 0,
    'remain_songcnt': query.remainSongcnt,
    'song_pool_id': query.songPoolId,
    'token': identity.token,
    'userid': identity.userId,
  };
  // 可选键：非空/非零才带（上游 filter 语义）。
  if (query.hash.isNotEmpty) body['hash'] = query.hash;
  if (query.curMark.isNotEmpty) body['cur_mark'] = query.curMark;
  if (query.songId != null && query.songId != 0) body['songid'] = query.songId;
  if (query.playtime != null && query.playtime != 0) {
    body['playtime'] = query.playtime;
  }
  return <String, Object?>{
    for (final key in body.keys.toList()..sort()) key: body[key],
  };
}

/// POST /v2/personal_recommend（网关 + x-router=persnfm.service.kugou.com）。
Future<MusicPersonalFmSongs> fetchPersonalFm(
  MusicSession session,
  MusicPersonalFmQuery query, {
  int? timeMs,
}) async {
  final identity = await session.ensureDevice();
  final time = timeMs ?? DateTime.now().millisecondsSinceEpoch;
  final body = personalFmRequestBody(identity, query, time);
  final response = await session.client.sendEndpoint(
    identity,
    KugouEndpoint(
      origin: KugouOrigin.gateway,
      path: '/v2/personal_recommend',
      router: 'persnfm.service.kugou.com',
      method: 'POST',
      body: encodeJsonBody(body),
    ),
  );
  return _convertPersonalFm(response.bytes);
}

/// personal_fm.rs 顶层消费键（`convert` 的平铺 drop 列表）；trans_param/
/// rec_song_info/tracker_info 经各自嵌套路径丢弃。
const List<String> _personalFmConsumedKeys = <String>[
  'album_audio_id',
  'mixsongid',
  'album_id',
  'hash',
  'songname',
  'album_name',
  'time_length',
  'sizable_cover',
  'privilege',
  'relate_goods',
  'singerinfo',
  'songid',
  'author_name',
  'ori_audio_name',
  'official_songname',
  'suffix_audio_name',
  'album_audio_remark',
  'filename',
  'language',
  'publish_date',
  'is_publish',
  'is_original',
  'has_accompany',
  'pay_type',
  'fail_process',
  'old_cpy',
  'hash_128',
  'hash_192',
  'hash_320',
  'hash_flac',
  'hash_ape',
  'hash_other',
  'filesize_128',
  'filesize_192',
  'filesize_320',
  'filesize_flac',
  'filesize_ape',
  'filesize_other',
  'timelength_320',
  'bitrate',
  'extname',
  'mv_hash',
  'mv_type',
  'tags',
  'ips_tags',
  'rec_copy_write',
  'rec_sub_copy_write',
  'rank_label',
  'cur_mark',
  'climax_start_time',
  'climax_end_time',
  'climax_timelength',
];

/// wire 解析（personal_fm.rs `convert`）。
MusicPersonalFmSongs _convertPersonalFm(Uint8List bytes) {
  final envelope = decodeDiscoveryEnvelope(bytes, errorCodeRequired: false);
  ensureBusinessSuccess(envelope.status, envelope.errorCode, context: '私人FM');
  // data 是 object 语义：非 object → 默认空数据（不报 decode）。
  final data = wireMap(envelope.data) ?? const <String, Object?>{};
  final songs = <MusicPersonalFmSong>[];
  for (final raw in wireList(data['song_list'], 'song_list')) {
    final wire = wireMap(raw);
    if (wire == null) {
      throw const KugouApiException('decode', '私人FM歌曲项不是 object');
    }
    songs.add(_convertFmSong(wire));
  }
  return MusicPersonalFmSongs(
    songs: songs,
    batchMark: wireText(data['cur_mark']),
    // serde flatten：data 里除 song_list/cur_mark 外的全部键。
    providerExtension: <String, Object?>{
      for (final entry in data.entries)
        if (entry.key != 'song_list' && entry.key != 'cur_mark')
          entry.key: entry.value,
    },
  );
}

/// relate_goods 单条（Good + object 语义的 info）。
typedef _FmGood = ({Map<String, Object?> good, Map<String, Object?> info});

MusicPersonalFmSong _convertFmSong(Map<String, Object?> entry) {
  // FmWireSong：flattened Song（recommendation_song 协议）+ FM 专属字段。
  final converted = discoveryRecommendationSongFromWire(entry);
  var summary = converted.song;
  var metadata = converted.metadata;

  final mixsongid = wireText(entry['mixsongid']);
  final authorName = wireText(entry['author_name']);
  final entryCurMark = wireText(entry['cur_mark']);
  final rec = _recommendation(entry['rec_song_info']);
  final relateGoods = _goods(wireList(entry['relate_goods'], 'relate_goods'));
  final climaxStart = discoveryOptionalUnsigned(entry['climax_start_time']);
  final climaxEnd = discoveryOptionalUnsigned(entry['climax_end_time']);
  final climaxLength = discoveryOptionalUnsigned(entry['climax_timelength']);

  // related_goods_extension 用原始 wire 值（可为任意 JSON 值，不过 optional）。
  metadata = metadata.copyWith(relatedGoodsExtension: entry['relate_goods']);
  if (mixsongid.isNotEmpty) {
    summary = summary.copyWith(id: mixsongid);
  }
  if (summary.id.isEmpty) {
    summary = summary.copyWith(id: summary.hash);
  }
  if (summary.artists.isEmpty && authorName.isNotEmpty) {
    summary = summary.copyWith(
      artists: <MusicArtistRef>[
        ...summary.artists,
        MusicArtistRef(id: null, name: authorName),
      ],
    );
    metadata = metadata.copyWith(
      artists: <MusicDiscoveryArtistDetail>[
        ...metadata.artists,
        MusicDiscoveryArtistDetail(name: authorName),
      ],
    );
  }
  if (summary.coverUrl.isEmpty) {
    summary = summary.copyWith(coverUrl: metadata.rights.coverUrl ?? '');
  }
  if (summary.albumTitle == null || summary.albumTitle!.isEmpty) {
    summary = summary.copyWith(
      // 首个 good 存在即 Some(albumname)（空串也保留）；无 good → null。
      albumTitle: relateGoods.isEmpty
          ? null
          : wireText(relateGoods.first.good['albumname']),
    );
  }
  final resources = List.of(metadata.resources);
  for (final (:good, :info) in relateGoods) {
    resources.add(
      MusicDiscoveryAudioResource(
        quality: wireText(good['quality']),
        hash: optionalText(good['hash']),
        sizeBytes: discoveryOptionalUnsigned(info['filesize']),
        // good.info.duration 原样进 duration_ms（不乘 1000，上游一致）。
        durationMs: discoveryOptionalUnsigned(info['duration']),
        bitRateBps: _checkedMul1000(discoveryOptionalUnsigned(info['bitrate'])),
        extension: optionalText(info['extname']),
        privilege: discoveryOptionalUnsigned32(good['privilege']),
        paymentType: discoveryOptionalUnsigned32(good['pay_type']),
        failureCode: discoveryOptionalUnsigned32(good['fail_process']),
        downloadStatus: discoveryOptionalUnsigned32(good['status']),
      ),
    );
  }
  metadata = metadata.copyWith(resources: resources);

  // 保留未映射供应商事实：tracker_info 只丢 auth（临时媒体授权不入扩展），
  // trans_param/rec_song_info 经各自路径丢已消费键，平铺键按上游列表丢弃。
  final raw = Map<String, Object?>.of(entry);
  dropDiscoveryConsumedKeys(raw, 'tracker_info', <String>['auth']);
  dropDiscoveryConsumedKeys(
    raw,
    'trans_param',
    kugouDiscoveryTransConsumedKeys,
  );
  dropDiscoveryConsumedKeys(raw, 'rec_song_info', <String>[
    'rec_desc',
    'rec_desc2',
    'similar_desc',
    'alg_path',
    'cur_mark',
  ]);
  dropDiscoveryConsumedKeys(raw, '', _personalFmConsumedKeys);
  metadata = metadata.copyWith(providerExtension: raw.isEmpty ? null : raw);

  metadata = metadata.copyWith(
    recommendation: metadata.recommendation.copyWith(
      headline: rec.$1,
      detail: rec.$2,
    ),
  );
  return MusicPersonalFmSong(
    song: MusicDiscoverySong(song: summary, metadata: metadata),
    personalFm: MusicPersonalFmMetadata(
      // rec.cur_mark 非空优先，否则条目级 cur_mark。
      mark: rec.$5.isEmpty ? entryCurMark : rec.$5,
      similarity: rec.$3,
      algorithm: rec.$4,
      climaxStartMs: climaxStart,
      climaxEndMs: climaxEnd,
      climaxDurationMs: climaxLength,
    ),
  );
}

/// rec_song_info（object 语义 → 非 object 全默认）：
/// (recDesc, recDesc2, similarDesc, algPath, curMark)。
(String, String, String, String, String) _recommendation(Object? value) {
  final wire = wireMap(value) ?? const <String, Object?>{};
  return (
    wireText(wire['rec_desc']),
    wireText(wire['rec_desc2']),
    wireText(wire['similar_desc']),
    wireText(wire['alg_path']),
    wireText(wire['cur_mark']),
  );
}

/// `Vec<Good>`（list 语义：元素非 object → decode）。
List<_FmGood> _goods(List<Object?> goods) {
  final result = <_FmGood>[];
  for (final raw in goods) {
    final good = wireMap(raw);
    if (good == null) {
      throw const KugouApiException('decode', '私人FM商品项不是 object');
    }
    result.add((
      good: good,
      // info 是 object 语义：非 object → 全默认。
      info: wireMap(good['info']) ?? const <String, Object?>{},
    ));
  }
  return result;
}

/// checked_mul(1000)：溢出 → null（Dart 侧以 i64 上界近似）。
int? _checkedMul1000(int? value) {
  if (value == null) return null;
  if (value > 9223372036854775) return null;
  return value * 1000;
}
