/// 书架展示配置与纯函数分组/排序工具。
///
/// 刻意与 Widget 无关：布局配置的编解码、系列/文件夹归组、手动顺序的
/// 应用都能在单测里直接跑，不依赖 Flutter 绑定。页面只负责把
/// [NovelShelfViewConfig] 翻译成具体布局，并把 [NovelShelfBookView] 的
/// 字段摆到卡片上。
library;

import 'dart:convert';

/// 书架布局模式。
///
/// - [grid]：等宽网格（原有形态）；
/// - [list]：单列行卡；
/// - [waterfall]：瀑布流，封面按宽度自适应、列数随窗口变化；
/// - [folder]：按书架分组（`groupName`）分节，节头像文件夹；
/// - [dualColumn]：平板双列——左右两栏各自滚动，每栏内部仍是网格。
enum NovelShelfMode { grid, list, waterfall, folder, dualColumn }

extension NovelShelfModeLabel on NovelShelfMode {
  String get label => switch (this) {
    NovelShelfMode.grid => '网格',
    NovelShelfMode.list => '列表',
    NovelShelfMode.waterfall => '瀑布',
    NovelShelfMode.folder => '文件夹分组',
    NovelShelfMode.dualColumn => '平板双列',
  };

  String get key => name;

  /// 旧 kv（`shelf_layout`）只有 grid/list 两值。
  static NovelShelfMode fromKey(String? value) => switch (value) {
    'list' => NovelShelfMode.list,
    'waterfall' => NovelShelfMode.waterfall,
    'folder' => NovelShelfMode.folder,
    'dualColumn' => NovelShelfMode.dualColumn,
    _ => NovelShelfMode.grid,
  };
}

/// 书架展示配置（存模块 kv `shelf_view` 的 JSON）。
///
/// 默认值刻意等于改造前的观感：网格、自动列数、无阴影、不显示标签/
/// 简介/更新时间。用户不动设置时看到的就是原来的书架。
class NovelShelfViewConfig {
  const NovelShelfViewConfig({
    this.mode = NovelShelfMode.grid,
    this.columns = 0,
    this.coverWidth = defaultCoverWidth,
    this.coverRadius = defaultCoverRadius,
    this.coverShadow = false,
    this.showTags = false,
    this.showLatestChapter = true,
    this.showIntro = false,
    this.showUpdateTime = false,
    this.groupBySeries = false,
  });

  /// 自动列数按这个基准宽度算（与改造前 `width / 142` 一致）。
  static const double defaultCoverWidth = 142;

  /// 与 `MimaoShapes.md` 相同；这里存数值是为了让配置文件不依赖 Flutter。
  static const double defaultCoverRadius = 14;

  /// 封面宽度下限/上限（防止设置里填出不可用的极端值）。
  static const double minCoverWidth = 96;
  static const double maxCoverWidth = 220;
  static const double minCoverRadius = 0;
  static const double maxCoverRadius = 28;

  final NovelShelfMode mode;

  /// 0 = 按窗口宽度自动；否则固定列数（3..10）。
  final int columns;

  final double coverWidth;
  final double coverRadius;
  final bool coverShadow;

  /// 卡片上是否显示分类标签（`NovelSummary.kind`，逗号分隔取前两个）。
  final bool showTags;

  final bool showLatestChapter;
  final bool showIntro;

  /// 更新时间（书源 `updateTime` 规则；没有就退回最近阅读时间）。
  final bool showUpdateTime;

  /// 是否把同系列的书收进「系列」节（与文件夹分组正交）。
  final bool groupBySeries;

  NovelShelfViewConfig copyWith({
    NovelShelfMode? mode,
    int? columns,
    double? coverWidth,
    double? coverRadius,
    bool? coverShadow,
    bool? showTags,
    bool? showLatestChapter,
    bool? showIntro,
    bool? showUpdateTime,
    bool? groupBySeries,
  }) => NovelShelfViewConfig(
    mode: mode ?? this.mode,
    columns: columns ?? this.columns,
    coverWidth: coverWidth ?? this.coverWidth,
    coverRadius: coverRadius ?? this.coverRadius,
    coverShadow: coverShadow ?? this.coverShadow,
    showTags: showTags ?? this.showTags,
    showLatestChapter: showLatestChapter ?? this.showLatestChapter,
    showIntro: showIntro ?? this.showIntro,
    showUpdateTime: showUpdateTime ?? this.showUpdateTime,
    groupBySeries: groupBySeries ?? this.groupBySeries,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'mode': mode.key,
    'columns': columns,
    'coverWidth': coverWidth,
    'coverRadius': coverRadius,
    'shadow': coverShadow,
    'showTags': showTags,
    'showLatest': showLatestChapter,
    'showIntro': showIntro,
    'showUpdated': showUpdateTime,
    'groupBySeries': groupBySeries,
  };

  factory NovelShelfViewConfig.fromJson(Map<String, Object?> json) =>
      NovelShelfViewConfig(
        mode: NovelShelfModeLabel.fromKey(json['mode'] as String?),
        columns: _intOf(json['columns'], 0).clamp(0, 10),
        coverWidth: _doubleOf(
          json['coverWidth'],
          defaultCoverWidth,
        ).clamp(minCoverWidth, maxCoverWidth),
        coverRadius: _doubleOf(
          json['coverRadius'],
          defaultCoverRadius,
        ).clamp(minCoverRadius, maxCoverRadius),
        coverShadow: json['shadow'] == true,
        showTags: json['showTags'] == true,
        showLatestChapter: json['showLatest'] != false,
        showIntro: json['showIntro'] == true,
        showUpdateTime: json['showUpdated'] == true,
        groupBySeries: json['groupBySeries'] == true,
      );

  String encode() => jsonEncode(toJson());

  /// 读取 kv：空/坏数据/旧值（`grid` / `list`）都收敛成可用配置。
  static NovelShelfViewConfig decode(String? raw) {
    final text = raw?.trim() ?? '';
    if (text.isEmpty) return const NovelShelfViewConfig();
    if (!text.startsWith('{')) {
      // 旧版只存了 'grid' / 'list'。
      return NovelShelfViewConfig(mode: NovelShelfModeLabel.fromKey(text));
    }
    try {
      final value = jsonDecode(text);
      if (value is Map) {
        return NovelShelfViewConfig.fromJson(
          value.map((key, value) => MapEntry('$key', value)),
        );
      }
    } on Object {
      // 坏 JSON 用默认值，不让偏好把整页拖进错误态。
    }
    return const NovelShelfViewConfig();
  }

  static int _intOf(Object? value, int fallback) {
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? fallback;
  }

  static double _doubleOf(Object? value, double fallback) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? fallback;
  }
}

/// 手动顺序（拖拽排序）编解码：存 bookId 的 JSON 数组。
///
/// 顺序只是"用户摆过的样子"，不是权威数据：书被移除、新书加入时，
/// [applyShelfOrder] 会把未知项按原顺序补在后面，不丢书。
String encodeShelfOrder(List<String> ids) => jsonEncode(ids);

List<String> decodeShelfOrder(String? raw) {
  final text = raw?.trim() ?? '';
  if (text.isEmpty || !text.startsWith('[')) return const <String>[];
  try {
    final value = jsonDecode(text);
    if (value is List) {
      return <String>[
        for (final item in value)
          if ('$item'.trim().isNotEmpty) '$item',
      ];
    }
  } on Object {
    // 坏数据当"没有手动顺序"。
  }
  return const <String>[];
}

/// 按手动顺序重排 [books]；不在 [order] 里的书按原顺序追加在后。
List<T> applyShelfOrder<T>(
  List<T> books,
  List<String> order,
  String Function(T) idOf,
) {
  if (order.isEmpty || books.isEmpty) return List<T>.of(books);
  final byId = <String, T>{for (final book in books) idOf(book): book};
  final seen = <String>{};
  final ordered = <T>[];
  for (final id in order) {
    final book = byId[id];
    if (book == null || !seen.add(id)) continue;
    ordered.add(book);
  }
  for (final book in books) {
    if (seen.add(idOf(book))) ordered.add(book);
  }
  return ordered;
}

/// 书架分节：文件夹模式按 [folder] 分；系列模式按 [seriesId] 分。
class NovelShelfSection<T> {
  const NovelShelfSection({
    required this.title,
    required this.books,
    this.folder,
    this.seriesId,
  });

  final String title;
  final List<T> books;

  /// 分组名；null = 未分组（文件夹模式下只有一个这样的节）。
  final String? folder;

  /// 系列 id；null = 非系列节。
  final int? seriesId;
}

/// 文件夹分组：按分组名分节，组名排序，未分组排最后（且无分组时不出节）。
List<NovelShelfSection<T>> groupShelfByFolder<T>({
  required List<T> books,
  required String? Function(T) folderOf,
  String ungroupedTitle = '未分组',
}) {
  final buckets = <String, List<T>>{};
  final ungrouped = <T>[];
  for (final book in books) {
    final folder = folderOf(book)?.trim();
    if (folder == null || folder.isEmpty) {
      ungrouped.add(book);
    } else {
      buckets.putIfAbsent(folder, () => <T>[]).add(book);
    }
  }
  final names = buckets.keys.toList()..sort();
  return <NovelShelfSection<T>>[
    for (final name in names)
      NovelShelfSection<T>(title: name, folder: name, books: buckets[name]!),
    if (ungrouped.isNotEmpty)
      NovelShelfSection<T>(
        title: ungroupedTitle,
        folder: null,
        books: ungrouped,
      ),
  ];
}

/// 系列归组结果：系列节（按系列名排序）+ 不属于任何系列的散书。
class NovelShelfSeriesGrouping<T> {
  const NovelShelfSeriesGrouping({required this.series, required this.singles});

  final List<NovelShelfSection<T>> series;
  final List<T> singles;

  bool get hasSeries => series.isNotEmpty;
}

/// 系列归组：同一系列 >= 1 本即成一节（单本系列也照实显示，用户明确设过）。
///
/// 系列 id 找不到名字（系列已被删）时按散书处理，不造"系列 #3"这种假标题。
NovelShelfSeriesGrouping<T> groupShelfBySeries<T>({
  required List<T> books,
  required int? Function(T) seriesOf,
  required Map<int, String> seriesNames,
}) {
  final buckets = <int, List<T>>{};
  final singles = <T>[];
  for (final book in books) {
    final id = seriesOf(book);
    final name = id == null ? null : seriesNames[id];
    if (id == null || name == null) {
      singles.add(book);
      continue;
    }
    buckets.putIfAbsent(id, () => <T>[]).add(book);
  }
  final ids = buckets.keys.toList()
    ..sort((a, b) => seriesNames[a]!.compareTo(seriesNames[b]!));
  return NovelShelfSeriesGrouping<T>(
    series: <NovelShelfSection<T>>[
      for (final id in ids)
        NovelShelfSection<T>(
          title: seriesNames[id]!,
          seriesId: id,
          books: buckets[id]!,
        ),
    ],
    singles: singles,
  );
}

/// 自动列数：窗口宽度 / 封面宽度，夹到 3..10（与改造前一致的下限）。
int autoShelfColumns(double width, double coverWidth) {
  final target = coverWidth <= 0
      ? NovelShelfViewConfig.defaultCoverWidth
      : coverWidth;
  return (width / target).floor().clamp(3, 10).toInt();
}
