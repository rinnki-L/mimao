/// 番剧封面镜像（反防盗链）工具——纯函数，不依赖 Flutter/网络库，便于单测。
///
/// 背景：规则站点多数对图片做了防盗链——`Image.network` 不带 Referer/UA，
/// 直链要么 403、要么返回占位图，于是搜索结果「没有图片」。
///
/// 开启镜像后，封面直链被改写成公共图片代理的地址：代理在服务端代为取图，
/// 绕开浏览器端的同源/防盗链限制。镜像只作用于 http(s) 封面直链；
/// `assets/` 路径、空串、非 http(s) 地址原样返回，不影响离线占位逻辑。
///
/// 一个 URL 即便被改写多次也不会嵌套：`_mirrorPrefixes` 命中时直接返回原串。
library;

import 'package:flutter/foundation.dart';

import 'package:mimao/core/settings.dart';

/// 设置项 key（写进 core 的 app_settings 表，[SettingsRepository] 读写）。
const String animeImageMirrorKey = 'anime.imageMirror.enabled';

/// 镜像开关默认值：默认开启——让搜索封面直接可见（用户的原始诉求）；
/// 用户可在番剧「设置」tab 关闭（例如不想把直链交给第三方代理时）。
const bool animeImageMirrorDefault = true;

/// 镜像服务前缀（带结尾 `?url=`，目标地址会被 URI 编码后拼接）。
///
/// 选 `wsrv.nl`（images.weserv.nl 的短域）作为默认：公开、稳定、支持任意
/// http(s) 源图与缩放参数，对防盗链站点兼容性好。允许外部注入以便替换服务。
const String animeImageMirrorTemplate = 'https://wsrv.nl/?url=';

/// 已知镜像前缀，用于幂等判断（避免对已镜像地址二次包裹）。
const List<String> _mirrorPrefixes = <String>[
  animeImageMirrorTemplate,
  'https://images.weserv.nl/?url=',
  'https://wsrv.nl/?url=',
];

/// 把封面直链按镜像开关改写成代理地址。
///
/// - [enabled] 为 false、[url] 为空/`assets/`/非 http(s)/已是镜像地址时原样返回；
/// - [template] 允许测试或用户替换为其它兼容 `?url=` 约定的代理前缀；
/// - 只对 `http`/`https` 生效。
String applyAnimeImageMirror(
  String url, {
  required bool enabled,
  String template = animeImageMirrorTemplate,
}) {
  final trimmed = url.trim();
  if (!enabled || trimmed.isEmpty) return trimmed;
  for (final prefix in _mirrorPrefixes) {
    if (trimmed.startsWith(prefix)) return trimmed;
  }
  final uri = Uri.tryParse(trimmed);
  if (uri == null ||
      !uri.hasScheme ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.isEmpty) {
    return trimmed;
  }
  return '$template${Uri.encodeComponent(trimmed)}';
}

/// 镜像开关控制器：内存态 + 可选持久化，所有封面 widget 监听它即时刷新。
///
/// 由 registry 创建并注入 AnimeModule，同一个实例贯穿设置 tab 与搜索/详情/时间表。
/// [settings] 为 null 时（widget 测试）只维护内存态，不碰数据库。
class AnimeImageMirrorController extends ValueNotifier<bool> {
  AnimeImageMirrorController({SettingsRepository? settings, bool? initial})
    : _settings = settings,
      super(initial ?? animeImageMirrorDefault);

  final SettingsRepository? _settings;

  /// 从持久化层读取初值；读失败退回默认值，绝不卡启动。
  Future<void> load() async {
    final settings = _settings;
    if (settings == null) return;
    try {
      value = await settings.getBool(
        animeImageMirrorKey,
        fallback: animeImageMirrorDefault,
      );
    } on Object {
      // 读设置失败保留内存默认值，不冒泡。
    }
  }

  /// 切换开关并持久化；写失败不回滚内存态（UI 仍按用户操作立即生效）。
  Future<void> set(bool enabled) async {
    value = enabled;
    final settings = _settings;
    if (settings == null) return;
    try {
      await settings.setBool(animeImageMirrorKey, enabled);
    } on Object {
      // 写失败保留内存态，不冒泡。
    }
  }

  /// 用当前开关改写一条封面 URL。
  String mirror(String url) => applyAnimeImageMirror(url, enabled: value);
}
