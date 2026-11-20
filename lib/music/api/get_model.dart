/// 音效商城目录端点——EchoMusicNext `crates/echo-api/src/module/get_model.rs`
/// 的翻译（docs/architecture.md §4.3：`music/api/` ← module，一端点一文件）。
///
/// 与 G6 公开目录（clearDefaults）不同：上游走普通 `client.request`——query
/// 带全套 lite 默认字段（appid/clientver/clienttime/dfid/mid/uuid，登录后还
/// 注入 token/userid）+ Android 签名。解码复用 G6 的 effects_models（source=
/// 'market'），不重复造分页/Effect 类型。
library;

import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/effects_models.dart';
import 'package:mimao/music/models/music_models.dart';

/// 音效商城列表输入（get_model.rs `Query`）。
class GetModelQuery {
  const GetModelQuery({
    required this.page,
    required this.pageSize,
    required this.sort,
  });

  /// 1 起始页码。
  final int page;
  final int pageSize;

  /// 排序码：只允许 2/3/4（上游白名单，语义由服务端定义）。
  final int sort;

  void validate() {
    // audio_effect.rs `paging`（复用 G6 校验）。
    validateEffectsPaging(page, pageSize);
    if (sort != 2 && sort != 3 && sort != 4) {
      throw const KugouApiException('input', '音效排序无效');
    }
  }
}

/// GET /ocean/v6/sound/list（网关主机、无 router；普通签名请求）。
Future<MusicPage<MusicEffect>> fetchGetModel(
  MusicSession session,
  GetModelQuery query,
) async {
  query.validate();
  final identity = await session.ensureDevice();
  final response = await session.client.sendEndpoint(
    identity,
    KugouEndpoint(
      origin: KugouOrigin.gateway,
      path: '/ocean/v6/sound/list',
      method: 'GET',
      params: <String, String>{
        'super_vip': '1',
        'sound_ver': '2',
        'apiver': '3',
        'classify': '2,3',
        'plat': '2',
        'privilege': '1',
        'page': query.page.toString(),
        'pagesize': query.pageSize.toString(),
        'sort': query.sort.toString(),
      },
    ),
  );
  // audio_effect.rs `catalog_page(bytes, page, size, "market")`（G6 翻译）。
  return convertEffectsCatalogPage(
    response.bytes,
    query.page,
    query.pageSize,
    'market',
  );
}
