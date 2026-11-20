/// 品牌耳机型号音效——EchoMusicNext
/// `crates/echo-api/src/module/effects_brand_detail.rs` 的翻译
/// （docs/architecture.md §4.3：`music/api/` ← module，一端点一文件）。
///
/// 走公开音效目录（`request_effect_catalog` → `send_endpoint(cloud=false,
/// clear_defaults=true)`）；list 元素按 audio_effect.rs `Headphone` 严格解码
/// （缺 sound / sound.id 的条目让整页 decode 失败，不静默跳过）。
library;

import 'dart:typed_data';

import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/effects_models.dart';
import 'package:mimao/music/models/music_models.dart';

/// 型号音效列表输入（effects_brand_detail.rs `Query`）。
class EffectsBrandDetailQuery {
  const EffectsBrandDetailQuery({
    required this.page,
    required this.pageSize,
    required this.brandId,
  });

  /// 1 起始页码。
  final int page;
  final int pageSize;

  /// 品牌 id（effects_brand 的 `Brand.id`）。
  final int brandId;

  void validate() {
    // 上游先 paging 再判 brand_id，错误分支顺序保持一致。
    validateEffectsPaging(page, pageSize);
    if (brandId <= 0) {
      throw const KugouApiException('input', '耳机品牌无效');
    }
  }
}

/// GET /api/v5/earphone/get_model（effectsCatalog 主机 + clearDefaults）。
Future<MusicPage<MusicEffect>> fetchEffectsBrandDetail(
  MusicSession session,
  EffectsBrandDetailQuery query,
) async {
  final identity = await session.ensureDevice();
  query.validate();
  final response = await session.client.sendEndpoint(
    identity,
    KugouEndpoint(
      origin: KugouOrigin.effectsCatalog,
      path: '/api/v5/earphone/get_model',
      method: 'GET',
      params: <String, String>{
        'brand_id': query.brandId.toString(),
        'page': query.page.toString(),
        'pagesize': query.pageSize.toString(),
      },
    ),
    clearDefaults: true,
  );
  return _convertModels(response.bytes, query.page, query.pageSize);
}

/// effects_brand_detail.rs `convert`：信封 + data.list 逐行 headphone()。
MusicPage<MusicEffect> _convertModels(Uint8List bytes, int page, int size) {
  final envelope = decodeEffectsEnvelope(bytes);
  final data = requiredWireMap(envelope.data, 'data');
  final items = wireList(data['list'], 'list').map(_headphoneItem).toList();
  return MusicPage<MusicEffect>(
    page: page,
    pageSize: size,
    total: effectsOptionalUnsigned(data['total']),
    items: items,
  );
}

/// response.rs `list<Headphone>` 元素严格解码：非法条目 → 整页 decode 失败
/// （与 effects_match 的 optional 宽容刻意不同）。
MusicEffect _headphoneItem(Object? raw) {
  final effect = effectsHeadphoneFromWire(raw);
  if (effect == null) {
    throw const KugouApiException('decode', '耳机型号条目不是合法 object');
  }
  return effect;
}
