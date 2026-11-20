/// 歌手音效目录——EchoMusicNext `crates/echo-api/src/module/effects_artist.rs`
/// 的翻译（docs/architecture.md §4.3：`music/api/` ← module，一端点一文件）。
///
/// 走公开音效目录：上游 `request_effect_catalog` → `send_endpoint(cloud=false,
/// clear_defaults=true)`——query 只含端点参数 + Android signature，不注入
/// appid/mid/dfid/clienttime/token/userid/uuid 等默认身份字段。
library;

import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/models/effects_models.dart';
import 'package:mimao/music/models/music_models.dart';

/// 歌手音效列表输入（effects_artist.rs `Query`）。
class EffectsArtistQuery {
  const EffectsArtistQuery({required this.page, required this.pageSize});

  /// 1 起始页码。
  final int page;
  final int pageSize;

  void validate() => validateEffectsPaging(page, pageSize);
}

/// GET /api/v3/sound/list（effectsCatalog 主机 + clearDefaults 公开目录签名）。
Future<MusicPage<MusicEffect>> fetchEffectsArtist(
  MusicSession session,
  EffectsArtistQuery query,
) async {
  final identity = await session.ensureDevice();
  query.validate();
  final response = await session.client.sendEndpoint(
    identity,
    KugouEndpoint(
      origin: KugouOrigin.effectsCatalog,
      path: '/api/v3/sound/list',
      method: 'GET',
      params: <String, String>{
        'plat': '2',
        'version': '12460',
        'apiver': '2',
        'sort': '1',
        'classify': '1',
        'page': query.page.toString(),
        'pagesize': query.pageSize.toString(),
      },
    ),
    clearDefaults: true,
  );
  return convertEffectsCatalogPage(
    response.bytes,
    query.page,
    query.pageSize,
    'artist',
  );
}
