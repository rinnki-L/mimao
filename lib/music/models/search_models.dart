/// 搜索扩展端点的响应模型——EchoMusicNext `crates/echo-api/src/domain.rs`
/// 与各 `module/search_*.rs` 输出结构的 Dart 镜像（docs/architecture.md §4.3：
/// `music/models/` ← domain）。
///
/// G1（搜索扩展）自包含：与其它组不共享的类型一律 `Music` 前缀且全局唯一
/// （规格第 4 节——集成时所有组会同时被导入）。字段序与 Rust `Serialize`
/// 结构逐一对齐；Rust 的 `CatalogSongFacts` 元数据骨架期不建模——音质资源
/// 折叠进 [MusicSong.resources]，与 search.dart 的 Song 分支口径一致。
library;

import 'package:mimao/music/models/music_models.dart';

/// 歌词搜索命中（search.rs `LyricHit`）。
class MusicLyricHit {
  const MusicLyricHit({
    required this.song,
    this.lyricId,
    required this.excerpt,
  });

  final MusicSong song;

  /// wire `LyricID`；结果可能缺省。
  final int? lyricId;

  /// wire `Lyric`——歌词片段原文。
  final String excerpt;

  Map<String, Object?> toJson() => <String, Object?>{
    'song': song.toJson(),
    'lyricId': lyricId,
    'excerpt': excerpt,
  };
}

/// 默认搜索词（search_default.rs `DefaultSearch`）。
class MusicSearchDefault {
  const MusicSearchDefault({required this.promotions, this.fallbackExtension});

  final List<MusicSearchPromotion> promotions;

  /// 未建模的服务端扩展（Rust 注释：单独保留，绝不把它重新解读成搜索词）。
  final Object? fallbackExtension;

  Map<String, Object?> toJson() => <String, Object?>{
    'promotions': [for (final promotion in promotions) promotion.toJson()],
    'fallbackExtension': fallbackExtension,
  };
}

/// 默认搜索词里的推广位（search_default.rs `Promotion`）。
class MusicSearchPromotion {
  const MusicSearchPromotion({
    this.id,
    required this.title,
    required this.mainTitle,
    required this.subtitle,
    required this.jumpType,
    required this.encodedDestination,
  });

  final int? id;
  final String title;
  final String mainTitle;
  final String subtitle;
  final String jumpType;

  /// wire `unifiedUrl` 原样（上游不做 URL 解码/校验）。
  final String encodedDestination;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'title': title,
    'mainTitle': mainTitle,
    'subtitle': subtitle,
    'jumpType': jumpType,
    'encodedDestination': encodedDestination,
  };
}

/// 热搜关键词（search_hot.rs `HotKeyword`）。
class MusicHotKeyword {
  const MusicHotKeyword({
    required this.keyword,
    required this.reason,
    this.kind,
    this.icon,
    required this.jumpUrl,
    required this.jsonUrl,
  });

  final String keyword;
  final String reason;

  /// wire `type`（榜单类型码；语义随热搜切片再展开）。
  final int? kind;
  final int? icon;
  final String jumpUrl;
  final String jsonUrl;

  Map<String, Object?> toJson() => <String, Object?>{
    'keyword': keyword,
    'reason': reason,
    'kind': kind,
    'icon': icon,
    'jumpUrl': jumpUrl,
    'jsonUrl': jsonUrl,
  };
}

/// 热搜分组（search_hot.rs `HotSearchGroup`）。
class MusicHotSearchGroup {
  const MusicHotSearchGroup({required this.title, required this.keywords});

  final String title;
  final List<MusicHotKeyword> keywords;

  Map<String, Object?> toJson() => <String, Object?>{
    'title': title,
    'keywords': [for (final keyword in keywords) keyword.toJson()],
  };
}

/// 搜索建议跳转（search_suggest.rs `Jump`）。
class MusicSuggestJump {
  const MusicSuggestJump({required this.kind, this.id, required this.url});

  /// wire `type`（跳转类型词）。
  final String kind;
  final int? id;
  final String url;

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind,
    'id': id,
    'url': url,
  };
}

/// 单条搜索建议（search_suggest.rs `Suggestion`）。
class MusicSearchSuggestion {
  const MusicSearchSuggestion({
    required this.text,
    this.matches,
    this.heat,
    required this.source,
    required this.subtitle,
    this.tags,
    this.jump,
  });

  /// wire `HintInfo`——展示文本。
  final String text;
  final int? matches;
  final int? heat;

  /// wire `Use`——来源渠道词。
  final String source;
  final String subtitle;

  /// wire `tags`：缺省/非法（非文本项等）→ null（Rust `optional` 的宽容语义）。
  final List<String>? tags;
  final MusicSuggestJump? jump;

  Map<String, Object?> toJson() => <String, Object?>{
    'text': text,
    'matches': matches,
    'heat': heat,
    'source': source,
    'subtitle': subtitle,
    'tags': tags,
    'jump': jump?.toJson(),
  };
}

/// 搜索建议分组（search_suggest.rs `SuggestionGroup`）。
class MusicSuggestionGroup {
  const MusicSuggestionGroup({
    required this.title,
    this.reportedCount,
    required this.items,
  });

  /// wire `LableName`（上游拼写原样保留）。
  final String title;
  final int? reportedCount;
  final List<MusicSearchSuggestion> items;

  Map<String, Object?> toJson() => <String, Object?>{
    'title': title,
    'reportedCount': reportedCount,
    'items': [for (final item in items) item.toJson()],
  };
}

/// 搜索建议聚合（search_suggest.rs `Suggestions`）。
class MusicSearchSuggestions {
  const MusicSearchSuggestions({
    required this.groups,
    this.singerShortcutExtension,
    this.shortcutsExtension,
  });

  final List<MusicSuggestionGroup> groups;

  /// 未建模的服务端扩展：歌手快捷入口/Shortcuts 原样保留（Rust 注释：导航
  /// 语义确立前不并入分组）。
  final Object? singerShortcutExtension;
  final Object? shortcutsExtension;

  Map<String, Object?> toJson() => <String, Object?>{
    'groups': [for (final group in groups) group.toJson()],
    'singerShortcutExtension': singerShortcutExtension,
    'shortcutsExtension': shortcutsExtension,
  };
}

/// 歌词候选（search_lyric.rs `Candidate`）——downloadLyric 的输入。
class MusicLyricCandidate {
  const MusicLyricCandidate({
    required this.sourceId,
    required this.accessKey,
    required this.artist,
    required this.nickname,
    required this.title,
    this.durationMs,
    required this.sourceLabel,
    required this.language,
    this.wordTimed,
    this.score,
    this.scrollable,
    this.sourceFormatCode,
    this.contentTypeCode,
  });

  /// wire `id`——歌词 id（后续取歌词内容用）。
  final String sourceId;

  /// wire `accesskey`——临时取词凭证（不落盘、不进日志；上游注释）。
  final String accessKey;
  final String artist;
  final String nickname;
  final String title;

  /// wire `duration` 本身就是毫秒（与搜索端点的秒语义不同）。
  final int? durationMs;

  /// wire `product_from`——来源标签。
  final String sourceLabel;
  final String language;

  /// 逐字歌词：krctype 1→true、2→false、其它/缺省 → null。
  final bool? wordTimed;
  final int? score;

  /// 可滚动：contenttype 0/1→true、2→false、其它/缺省 → null。
  final bool? scrollable;

  /// wire `krctype` 原始码。
  final int? sourceFormatCode;

  /// wire `contenttype` 原始码。
  final int? contentTypeCode;

  Map<String, Object?> toJson() => <String, Object?>{
    'sourceId': sourceId,
    'accessKey': accessKey,
    'artist': artist,
    'nickname': nickname,
    'title': title,
    'durationMs': durationMs,
    'sourceLabel': sourceLabel,
    'language': language,
    'wordTimed': wordTimed,
    'score': score,
    'scrollable': scrollable,
    'sourceFormatCode': sourceFormatCode,
    'contentTypeCode': contentTypeCode,
  };
}

/// sidedt 确认回执（verify_user_info.rs `Acknowledgement`）。
///
/// data.msg 是描述文案、不是接受条件（上游注释）；成功即 acknowledged=true。
class MusicSideDtAcknowledgement {
  const MusicSideDtAcknowledgement({required this.acknowledged});

  final bool acknowledged;

  Map<String, Object?> toJson() => <String, Object?>{
    'acknowledged': acknowledged,
  };
}
