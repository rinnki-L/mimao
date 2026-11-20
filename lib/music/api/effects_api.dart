/// 音效/品牌端点组门面——effects_artist / effects_brand / effects_brand_detail /
/// effects_match 四端点的组接口（music-api-expansion §4：MusicXxxApi +
/// KugouXxxApi，方法名带组前缀）。
library;

import 'package:mimao/music/api/effects_artist.dart';
import 'package:mimao/music/api/effects_brand.dart';
import 'package:mimao/music/api/effects_brand_detail.dart';
import 'package:mimao/music/api/effects_match.dart';
import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/models/effects_models.dart';
import 'package:mimao/music/models/music_models.dart';

/// 音效/品牌端点组接口。
abstract interface class MusicEffectsApi {
  /// 歌手音效目录（effects_artist.rs）。
  Future<MusicPage<MusicEffect>> effectsArtist(EffectsArtistQuery query);

  /// 耳机品牌列表（effects_brand.rs）。
  Future<MusicPage<MusicEarphoneBrand>> effectsBrand(EffectsBrandQuery query);

  /// 品牌下的耳机型号音效（effects_brand_detail.rs）。
  Future<MusicPage<MusicEffect>> effectsBrandDetail(
    EffectsBrandDetailQuery query,
  );

  /// 当前设备匹配的耳机音效；无匹配 → null（effects_match.rs）。
  Future<MusicEffect?> effectsMatch();
}

/// [MusicEffectsApi] 的酷狗实现：四个端点都是公开目录（clearDefaults 签名），
/// 只依赖会话里的设备身份（mid/dfid 头），不需要账号。
class KugouEffectsApi implements MusicEffectsApi {
  KugouEffectsApi(this.session);

  final MusicSession session;

  @override
  Future<MusicPage<MusicEffect>> effectsArtist(EffectsArtistQuery query) =>
      fetchEffectsArtist(session, query);

  @override
  Future<MusicPage<MusicEarphoneBrand>> effectsBrand(EffectsBrandQuery query) =>
      fetchEffectsBrand(session, query);

  @override
  Future<MusicPage<MusicEffect>> effectsBrandDetail(
    EffectsBrandDetailQuery query,
  ) => fetchEffectsBrandDetail(session, query);

  @override
  Future<MusicEffect?> effectsMatch() => fetchEffectsMatch(session);
}
