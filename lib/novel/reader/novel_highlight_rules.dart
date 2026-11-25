/// 高亮规则：正则 → 样式（日夜两套色），按书 / 全局作用域。
///
/// 对照 legado 的 [HighlightRule]：规则本身只描述「匹配什么、画成什么样」，
/// 渲染层把命中区间叠加到正文 TextSpan 上——不插 Widget、不改字号/行高，
/// 因此分页结果与未开高亮时一致。
///
/// 颜色存 ARGB 整数（规则跨主题/跨日夜保留用户选择），渲染时再转 [Color]；
/// 编辑面板里的取色板从 `ColorScheme` 角色生成，不在页面写死色值。
library;

import 'dart:convert';
import 'dart:ui' show Color;

/// 高亮样式：文字色 / 背景色 / 下划线 / 加粗。背景色为空 = 只改文字色。
class NovelHighlightStyle {
  const NovelHighlightStyle({
    required this.foreground,
    this.background,
    this.underline = false,
    this.bold = false,
  });

  final Color foreground;
  final Color? background;
  final bool underline;
  final bool bold;
}

/// 一条高亮规则。[bookId] 为空 = 全局；非空只对这本书生效。
class NovelHighlightRule {
  const NovelHighlightRule({
    this.id,
    this.bookId = '',
    required this.name,
    required this.pattern,
    required this.foregroundLightArgb,
    this.backgroundLightArgb,
    required this.foregroundDarkArgb,
    this.backgroundDarkArgb,
    this.enabled = true,
    this.underline = false,
    this.bold = false,
    this.raw = const <String, Object?>{},
  });

  /// 数据库主键；新建时为 null。
  final int? id;

  /// 作用域：空 = 全局，否则只对这本书（[String] bookId）。
  final String bookId;

  final String name;

  /// 正则表达式（高亮规则只支持正则；坏正则整条跳过）。
  final String pattern;

  final int foregroundLightArgb;
  final int? backgroundLightArgb;
  final int foregroundDarkArgb;
  final int? backgroundDarkArgb;

  final bool enabled;
  final bool underline;
  final bool bold;

  /// 导入时的原始 JSON（编辑保存时原样带回，不丢来源信息）。
  final Map<String, Object?> raw;

  bool get isGlobal => bookId.isEmpty;

  String get scopeLabel => isGlobal ? '全局' : '本书';

  /// 这条规则是否作用于 [bookId] 这本书。
  bool appliesToBook(String bookId) => isGlobal || this.bookId == bookId;

  /// 当前阅读背景（日/夜）下实际使用的样式。
  NovelHighlightStyle styleFor({required bool dark}) => NovelHighlightStyle(
    foreground: Color(dark ? foregroundDarkArgb : foregroundLightArgb),
    background: dark
        ? (backgroundDarkArgb == null ? null : Color(backgroundDarkArgb!))
        : (backgroundLightArgb == null ? null : Color(backgroundLightArgb!)),
    underline: underline,
    bold: bold,
  );

  NovelHighlightRule copyWith({
    int? id,
    String? bookId,
    String? name,
    String? pattern,
    int? foregroundLightArgb,
    int? backgroundLightArgb,
    bool clearBackgroundLight = false,
    int? foregroundDarkArgb,
    int? backgroundDarkArgb,
    bool clearBackgroundDark = false,
    bool? enabled,
    bool? underline,
    bool? bold,
  }) => NovelHighlightRule(
    id: id ?? this.id,
    bookId: bookId ?? this.bookId,
    name: name ?? this.name,
    pattern: pattern ?? this.pattern,
    foregroundLightArgb: foregroundLightArgb ?? this.foregroundLightArgb,
    backgroundLightArgb: clearBackgroundLight
        ? null
        : (backgroundLightArgb ?? this.backgroundLightArgb),
    foregroundDarkArgb: foregroundDarkArgb ?? this.foregroundDarkArgb,
    backgroundDarkArgb: clearBackgroundDark
        ? null
        : (backgroundDarkArgb ?? this.backgroundDarkArgb),
    enabled: enabled ?? this.enabled,
    underline: underline ?? this.underline,
    bold: bold ?? this.bold,
    raw: raw,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    if (id != null) 'id': id,
    'bookId': bookId,
    'name': name,
    'pattern': pattern,
    'foregroundLight': foregroundLightArgb,
    'backgroundLight': backgroundLightArgb,
    'foregroundDark': foregroundDarkArgb,
    'backgroundDark': backgroundDarkArgb,
    'enabled': enabled,
    'underline': underline,
    'bold': bold,
    'raw': raw,
  };

  /// 坏数据回退：缺 name 用 pattern，缺颜色用调用方给的默认值。
  factory NovelHighlightRule.fromJson(
    Map<String, Object?> json, {
    required int defaultForegroundLight,
    required int defaultForegroundDark,
  }) {
    final pattern = '${json['pattern'] ?? ''}';
    final name = '${json['name'] ?? ''}'.trim();
    int? readArgb(Object? value) => value is num ? value.toInt() : null;
    return NovelHighlightRule(
      id: readArgb(json['id']),
      bookId: '${json['bookId'] ?? ''}'.trim(),
      name: name.isEmpty ? pattern : name,
      pattern: pattern,
      foregroundLightArgb:
          readArgb(json['foregroundLight']) ?? defaultForegroundLight,
      backgroundLightArgb: readArgb(json['backgroundLight']),
      foregroundDarkArgb:
          readArgb(json['foregroundDark']) ?? defaultForegroundDark,
      backgroundDarkArgb: readArgb(json['backgroundDark']),
      enabled: json['enabled'] is bool ? json['enabled'] as bool : true,
      underline: json['underline'] == true,
      bold: json['bold'] == true,
      raw: Map<String, Object?>.from(
        json['raw'] as Map? ?? const <String, Object?>{},
      ),
    );
  }

  /// 编码成一段可直接落库的 JSON（drift 表里一个 text 列）。
  String encode() => jsonEncode(toJson());

  static NovelHighlightRule? tryDecode(String raw) {
    if (raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return NovelHighlightRule.fromJson(
        Map<String, Object?>.from(decoded),
        // 缺色的旧行回退到主题可读的黑/白，由渲染层再叠加，不会不可见。
        defaultForegroundLight: 0xFF1F1F1F,
        defaultForegroundDark: 0xFFEDEDED,
      );
    } on Object {
      return null;
    }
  }

  @override
  String toString() => 'NovelHighlightRule($id, $name, $pattern)';
}

/// 一次正则命中（坐标基于传入的整段文本）。
class NovelHighlightSpan {
  const NovelHighlightSpan({
    required this.start,
    required this.end,
    required this.rule,
    required this.style,
  });

  final int start;
  final int end;
  final NovelHighlightRule rule;
  final NovelHighlightStyle style;

  int get length => end - start;

  /// 把区间夹到 `[0, textLength]`；完全落在文本外返回 null。
  ///
  /// 渲染层拿到的切片可能比匹配时的段落短（翻页把一段切成两片），也需要
  /// 用同一套夹取，避免 substring 越界。
  NovelHighlightSpan? clampedTo(int textLength) {
    final nextStart = start.clamp(0, textLength);
    final nextEnd = end.clamp(0, textLength);
    if (nextEnd <= nextStart) return null;
    if (nextStart == start && nextEnd == end) return this;
    return NovelHighlightSpan(
      start: nextStart,
      end: nextEnd,
      rule: rule,
      style: style,
    );
  }
}

/// 单条规则最多收多少个命中；避免 `.*` 之类在长段落里把渲染拖死。
const int novelHighlightMaxMatchesPerRule = 500;

/// 在 [text] 上匹配所有启用且作用于 [bookId] 的规则。
///
/// - 坏正则整条跳过，不打断其余规则；
/// - 零宽命中（如 `^`）跳过，避免给空区间画样式；
/// - 每个命中按当前日夜取色，[dark] 来自阅读背景亮度。
List<NovelHighlightSpan> matchNovelHighlights(
  String text,
  Iterable<NovelHighlightRule> rules, {
  required String bookId,
  required bool dark,
}) {
  if (text.isEmpty) return const <NovelHighlightSpan>[];
  final spans = <NovelHighlightSpan>[];
  for (final rule in rules) {
    if (!rule.enabled || rule.pattern.isEmpty) continue;
    if (!rule.appliesToBook(bookId)) continue;
    try {
      final regex = RegExp(rule.pattern);
      final style = rule.styleFor(dark: dark);
      var count = 0;
      for (final match in regex.allMatches(text)) {
        if (match.end <= match.start) continue;
        spans.add(
          NovelHighlightSpan(
            start: match.start,
            end: match.end,
            rule: rule,
            style: style,
          ),
        );
        if (++count >= novelHighlightMaxMatchesPerRule) break;
      }
    } on Object {
      // 坏正则跳过这条。
    }
  }
  return List<NovelHighlightSpan>.unmodifiable(spans);
}

/// 区间内是否覆盖 [offset]；重叠时后添加的规则优先（列表顺序即优先级）。
NovelHighlightSpan? highlightSpanAt(
  List<NovelHighlightSpan> spans,
  int offset,
) {
  for (var i = spans.length - 1; i >= 0; i--) {
    final span = spans[i];
    if (offset >= span.start && offset < span.end) return span;
  }
  return null;
}
