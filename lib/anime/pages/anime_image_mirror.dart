/// Bangumi 封面「直连 / 镜像」加速工具——对齐 Kazumi 的 ImageAcceleration 设计。
///
/// Kazumi 上游把图片加速做成三态（direct/ech/mirror），本项目按用户拍板只保留
/// 两态：直连（加载原始图片）与镜像（走图片代理）。ECH 依赖原生插件 ech_http，
/// CI / 本机不可用，故不引入（详见 docs 上游源码 services/network/）。
///
/// 背景：bangumi 图床 `lain.bgm.tv` 在国内直连常超时，且规则站点封面多有防盗链，
/// `Image.network` 不带 Referer/UA 时直接不显示。镜像态把图片 URL 改写成公共
/// 图片代理 `wsrv.nl/?url=...`（Kazumi 同款服务），由代理在服务端取图绕过限制。
/// 实测（2026-11-20 本机）：api.bgm.tv/lain.bgm.tv 直连超时，wsrv.nl 代理 200。
library;

import 'package:flutter/foundation.dart';

import 'package:mimao/core/settings.dart';

/// 设置项 key（写进 core 的 app_settings 表，[SettingsRepository] 读写）。
const String animeImageAccelerationKey = 'anime.imageAcceleration';

/// 图片加速模式——对齐 Kazumi 的 ImageAcceleration（去掉需原生依赖的 ECH）。
enum AnimeImageAcceleration {
  /// 直连：加载原始图片地址（Kazumi: direct）。
  direct('直连', '加载原始图片'),

  /// 镜像：经图片代理加载（Kazumi: mirror）。
  mirror('镜像', '使用图片镜像（wsrv.nl）');

  const AnimeImageAcceleration(this.label, this.description);

  final String label;
  final String description;

  /// 从持久化字符串还原；未知值回退 [defaultMode]。
  static AnimeImageAcceleration fromName(
    String? name, [
    AnimeImageAcceleration fallback = defaultMode,
  ]) {
    for (final mode in values) {
      if (mode.name == name) return mode;
    }
    return fallback;
  }

  static const defaultMode = AnimeImageAcceleration.mirror;
}

/// 镜像服务前缀（带结尾 `?url=`，目标地址会被 URI 编码后拼接）。
///
/// 与 Kazumi `BangumiImageUrlRewriter` 同款 `wsrv.nl`。允许注入以便替换服务。
const String animeImageMirrorTemplate = 'https://wsrv.nl/?url=';

/// 已知镜像前缀，用于幂等判断（避免对已镜像地址二次包裹）。
const List<String> _mirrorPrefixes = <String>[
  animeImageMirrorTemplate,
  'https://images.weserv.nl/?url=',
  'https://wsrv.nl/?url=',
];

/// bangumi 图床 host：镜像/直连判断与元数据服务共用。
const String bangumiImageHost = 'lain.bgm.tv';
const String bangumiApiHost = 'api.bgm.tv';

/// 是否为 bangumi 图片（对齐 Kazumi `BangumiImageUrlRewriter.isBangumiImage`）。
bool isBangumiImage(Uri uri) {
  if (uri.scheme != 'http' && uri.scheme != 'https') return false;
  if (uri.host == bangumiImageHost) return true;
  if (uri.host != bangumiApiHost) return false;
  final segments = uri.pathSegments;
  if (segments.length != 4 || segments[0] != 'v0' || segments[3] != 'image') {
    return false;
  }
  const kinds = <String>{'subjects', 'characters', 'persons'};
  final id = int.tryParse(segments[2]);
  return kinds.contains(segments[1]) && id != null && id > 0;
}

/// 把图片地址按加速模式改写。
///
/// - [mode] 为直连、URL 为空/`assets/`/非 http(s)/已是镜像地址时原样返回；
/// - 镜像态：只对 http(s) 图片改写为 `wsrv.nl/?url=<encoded>`；gif 追加 `n=-1`
///   （对齐 Kazumi，禁止动图循环播放）；
/// - [template] 允许测试或用户替换为其它兼容 `?url=` 约定的代理前缀。
String applyAnimeImageAcceleration(
  String url, {
  required AnimeImageAcceleration mode,
  String template = animeImageMirrorTemplate,
}) {
  final trimmed = url.trim();
  if (mode == AnimeImageAcceleration.direct || trimmed.isEmpty) return trimmed;
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
  final isGif = uri.path.toLowerCase().endsWith('.gif');
  // 目标参数值用完整 URL 编码——实测 wsrv.nl 同时接受带/不带 scheme，
  // 保留 scheme 对非 bgm 图床（规则站点）兼容更好。
  return '$template${Uri.encodeQueryComponent(trimmed)}'
      '${isGif ? '&n=-1' : ''}';
}

/// 图片加速控制器：内存态 + 可选持久化，所有封面 widget 监听它即时刷新。
///
/// 由 registry 创建并注入 AnimeModule，同一个实例贯穿设置 tab 与搜索/详情/时间表。
/// [settings] 为 null 时（widget 测试）只维护内存态，不碰数据库。
class AnimeImageAccelerationController
    extends ValueNotifier<AnimeImageAcceleration> {
  AnimeImageAccelerationController({
    SettingsRepository? settings,
    AnimeImageAcceleration? initial,
  }) : _settings = settings,
       super(initial ?? AnimeImageAcceleration.defaultMode);

  final SettingsRepository? _settings;

  /// 从持久化层读取初值；读失败退回默认值，绝不卡启动。
  Future<void> load() async {
    final settings = _settings;
    if (settings == null) return;
    try {
      final name = await settings.get(animeImageAccelerationKey);
      value = AnimeImageAcceleration.fromName(name);
    } on Object {
      // 读设置失败保留内存默认值，不冒泡。
    }
  }

  /// 切换模式并持久化；写失败不回滚内存态（UI 仍按用户操作立即生效）。
  Future<void> set(AnimeImageAcceleration mode) async {
    value = mode;
    final settings = _settings;
    if (settings == null) return;
    try {
      await settings.set(animeImageAccelerationKey, mode.name);
    } on Object {
      // 写失败保留内存态，不冒泡。
    }
  }

  /// 用当前模式改写一条封面 URL。
  String accelerate(String url) =>
      applyAnimeImageAcceleration(url, mode: value);
}
