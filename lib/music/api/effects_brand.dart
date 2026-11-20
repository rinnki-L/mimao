/// 耳机品牌列表——EchoMusicNext `crates/echo-api/src/module/effects_brand.rs`
/// 的翻译（docs/architecture.md §4.3：`music/api/` ← module，一端点一文件）。
///
/// 与 effects_artist 一样走公开音效目录（`request_effect_catalog` →
/// `send_endpoint(cloud=false, clear_defaults=true)`）：query 只含端点参数 +
/// Android signature，不注入默认身份字段。
library;

import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/models/effects_models.dart';
import 'package:mimao/music/models/music_models.dart';

/// 品牌列表输入（effects_brand.rs `Query`）。
class EffectsBrandQuery {
  const EffectsBrandQuery({required this.page, required this.pageSize});

  /// 1 起始页码。
  final int page;
  final int pageSize;

  void validate() => validateEffectsPaging(page, pageSize);
}

/// GET /api/v5/earphone/get_brand（effectsCatalog 主机 + clearDefaults）。
Future<MusicPage<MusicEarphoneBrand>> fetchEffectsBrand(
  MusicSession session,
  EffectsBrandQuery query,
) async {
  final identity = await session.ensureDevice();
  query.validate();
  final response = await session.client.sendEndpoint(
    identity,
    KugouEndpoint(
      origin: KugouOrigin.effectsCatalog,
      path: '/api/v5/earphone/get_brand',
      method: 'GET',
      params: <String, String>{
        'sort': '1',
        'page': query.page.toString(),
        'pagesize': query.pageSize.toString(),
      },
    ),
    clearDefaults: true,
  );
  return convertEffectsBrandPage(response.bytes, query.page, query.pageSize);
}
