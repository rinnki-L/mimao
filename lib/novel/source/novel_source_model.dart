/// Legado（阅读）书源的领域镜像与两个纯函数：书源 JSON 解析、`yuedu://` 导入链接解析。
///
/// 本站的「一键导入」按钮本质是 `yuedu://booksource/importonline?src=<书源文件地址>`，
/// 书源文件是一个 JSON 数组（.json / .txt 扩展名都有，内容同为 JSON）。这里只做
/// 与平台/IO 无关的解析与建模，抓取与落盘分别在 import / store 两个文件。
library;

import 'dart:convert';

/// 书源网站地址（应用内 WebView 打开它，点页面里的「一键导入」即可回灌本应用）。
const String novelSourceSiteUrl = 'https://yuedu.miaogongzi.net/gx.html';

/// 一条已导入的 Legado 书源。
///
/// [raw] 保留书源完整 JSON 对象，后续书源引擎切片直接消费它，不需要二次抓网页。
class NovelBookSource {
  const NovelBookSource({
    required this.key,
    required this.name,
    required this.url,
    required this.type,
    required this.enabled,
    required this.raw,
  });

  /// 稳定文件主键：源地址（大小写不敏感）的 base64url，天然规避路径分隔符。
  final String key;
  final String name;
  final String url;
  final int type;
  final bool enabled;
  final Map<String, dynamic> raw;

  static String keyFor(String url) =>
      base64Url.encode(utf8.encode(url.trim().toLowerCase()));

  Map<String, Object?> toJson() => <String, Object?>{
    'key': key,
    'name': name,
    'url': url,
    'type': type,
    'enabled': enabled,
    'raw': raw,
  };

  factory NovelBookSource.fromJson(Map<String, Object?> json) =>
      NovelBookSource(
        key: '${json['key'] ?? ''}',
        name: '${json['name'] ?? ''}',
        url: '${json['url'] ?? ''}',
        type: json['type'] is num ? (json['type']! as num).toInt() : 0,
        enabled: json['enabled'] is bool ? json['enabled'] as bool : true,
        raw: Map<String, dynamic>.from(
          json['raw'] as Map? ?? const <String, Object?>{},
        ),
      );

  /// 从 Legado 书源 JSON 的一条原始对象建模。
  factory NovelBookSource.fromLegado(Map<String, dynamic> json) {
    final url = '${json['bookSourceUrl'] ?? ''}'.trim();
    final name = '${json['bookSourceName'] ?? ''}'.trim();
    return NovelBookSource(
      key: keyFor(url),
      name: name.isEmpty ? url : name,
      url: url,
      type: json['bookSourceType'] is num
          ? (json['bookSourceType']! as num).toInt()
          : 0,
      enabled: json['enabled'] is bool ? json['enabled'] as bool : true,
      raw: json,
    );
  }

  NovelBookSource copyWith({bool? enabled}) => NovelBookSource(
    key: key,
    name: name,
    url: url,
    type: type,
    enabled: enabled ?? this.enabled,
    raw: raw,
  );

  /// Legado 书源分组名：`bookSourceGroup` 是逗号分隔串，个别源用中文顿号/分号。
  /// 去空白、去重、保序；无分组返回空列表。
  List<String> get groups {
    final value = raw['bookSourceGroup'];
    if (value is! String || value.trim().isEmpty) return const <String>[];
    final seen = <String>{};
    final result = <String>[];
    for (final part in value.split(RegExp(r'[,，、;；]'))) {
      final name = part.trim();
      if (name.isEmpty || !seen.add(name)) continue;
      result.add(name);
    }
    return result;
  }

  /// 分组展示文案（无分组时给"未分组"，用于筛选面板）。
  String get groupLabel => groups.isEmpty ? '未分组' : groups.join(' · ');

  /// 书源类型文案（Legado `bookSourceType`：0 文本 / 1 音频 / 2 图片 / 3 文件）。
  String get typeLabel => switch (type) {
    0 => '文本',
    1 => '音频',
    2 => '图片',
    3 => '文件',
    _ => '其他',
  };

  @override
  String toString() => 'NovelBookSource($name: $url)';
}

/// 解析书源文件正文：既接受 JSON 数组，也接受单条对象；键名沿用 Legado 的
/// `bookSourceUrl`。非法正文抛 [FormatException]，由上层收敛成可读错误。
List<Map<String, dynamic>> parseLegadoSources(String text) {
  // BOM（UTF-8 签名）会让 jsonDecode 直接抛，先剥掉。
  final body = text.startsWith('\uFEFF') ? text.substring(1) : text;
  final decoded = jsonDecode(body);
  final iterable = <Object?>[if (decoded is List) ...decoded else decoded];
  final result = <Map<String, dynamic>>[];
  for (final item in iterable) {
    if (item is Map) {
      result.add(Map<String, dynamic>.from(item));
    }
  }
  return result;
}

/// 从 `yuedu://booksource/importonline?src=...` 中提取书源文件地址。
///
/// 不是该协议/路径或缺少 src 时返回 null（调用方据此决定"没拦到深链"）。
String? parseImportSourceUrl(String link) {
  final uri = Uri.tryParse(link);
  if (uri == null) return null;
  if (uri.scheme.toLowerCase() != 'yuedu') return null;
  if (uri.host.toLowerCase() != 'booksource') return null;
  if (!uri.path.toLowerCase().endsWith('/importonline')) return null;

  var src = uri.queryParameters['src'];
  if (src == null || src.isEmpty) {
    // uri 解析对未转义的中文/特殊字符可能失真，退回原文截取兜底。
    const marker = 'src=';
    final index = link.indexOf(marker);
    if (index < 0) return null;
    src = link.substring(index + marker.length);
    final ampersand = src.indexOf('&');
    if (ampersand >= 0) src = src.substring(0, ampersand);
  }
  final fragment = src.indexOf('#');
  if (fragment >= 0) src = src.substring(0, fragment);
  return src.isEmpty ? null : src;
}

/// 是否是可抓取的 http(s) 书源地址（深链 src 或手动粘贴都过这道门）。
bool isFetchableSourceUrl(String url) {
  final uri = Uri.tryParse(url);
  return uri != null &&
      uri.isAbsolute &&
      (uri.scheme == 'http' || uri.scheme == 'https');
}
