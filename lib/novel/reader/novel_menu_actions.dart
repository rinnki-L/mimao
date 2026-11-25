// ignore_for_file: deprecated_member_use — 见 lib/main.dart 文件头说明。
// 阅读菜单动作注册表：顶栏 / 底栏 / 浮动行共用的唯一事实源。
//
// 对照 legado 的 ReadMenuActionDefs.kt：一个按钮的 id、文案、图标、可用性判定
// 只在这里写一遍；三处 UI 各按自己的配置（顺序 + 启用）从同一张表取用，
// 并按 [NovelMenuActionDef.isAvailable] 过滤掉当前这本书用不上的按钮。
//
// 动作本身复用 [NovelClickAction]（区 2 落地的枚举）：注册表里的
// [NovelMenuActionDef.clickAction] 非空时，点击分发直接走
// [dispatchClickAction]，不在页面里另写一套 switch。顶栏专属的
// 缓存 / 刷新 / 换源 / 更多 不是点击区动作，只在这里定义。
//
// 可用性用「谓词 + 上下文快照」而不是枚举上的静态 available：
// 「加书签」要看书签库是否就绪（区 4），同一份配置在书签库落地后自动
// 生效，不需要用户重新配一遍。

import 'package:flutter/material.dart' show IconData, Icons;

import 'novel_click_actions.dart';

/// 三处菜单栏的标识（配置分别存，互不影响）。
enum NovelMenuBar { titleBar, bottomBar, floatingBar }

/// 渲染时的只读状态快照；由阅读页构造，注册表只读不写。
class NovelMenuActionContext {
  const NovelMenuActionContext({
    this.hasOnlineSource = false,
    this.bookmarkReady = false,
    this.contentEditReady = false,
    this.replaceReady = false,
    this.syncReady = false,
  });

  /// 当前书是否连着在线书源（本地 txt 为 false）。
  final bool hasOnlineSource;

  /// 书签库是否就绪（区 4）。
  final bool bookmarkReady;

  /// 正文编辑是否就绪。
  final bool contentEditReady;

  /// 替换规则面板是否就绪。
  final bool replaceReady;

  /// WebDAV 同步是否就绪。
  final bool syncReady;
}

/// 可用性谓词：返回 false 的动作在渲染前被剔除。
typedef NovelMenuAvailability = bool Function(NovelMenuActionContext context);

/// 一个菜单动作的运行时定义。
class NovelMenuActionDef {
  const NovelMenuActionDef({
    required this.id,
    required this.label,
    required this.icon,
    this.clickAction,
    this.available,
    this.unavailableHint,
  });

  /// 落库的键，改名要先想兼容性（旧值解析不到会被静默丢弃）。
  final String id;

  final String label;
  final IconData icon;

  /// 复用 [NovelClickAction] 的动作；null 表示顶栏专属动作。
  final NovelClickAction? clickAction;

  /// 可用性谓词；null 表示始终可用。
  final NovelMenuAvailability? available;

  /// 不可用时给用户看的说明（「需先完成 X」）。
  final String? unavailableHint;

  bool isAvailable(NovelMenuActionContext context) =>
      available?.call(context) ?? true;

  /// 当前上下文下不可用时的说明；可用返回 null。
  String? unavailableHintFor(NovelMenuActionContext context) =>
      isAvailable(context) ? null : unavailableHint;
}

// ── 动作 id 常量（配置里存的就是这些字符串） ─────────────────────────────

const String novelMenuActionSearch = 'search';
const String novelMenuActionAutoPage = 'autoPage';
const String novelMenuActionCatalog = 'catalog';
const String novelMenuActionTts = 'ttsToggle';
const String novelMenuActionSettings = 'menu';
const String novelMenuActionPreviousPage = 'previousPage';
const String novelMenuActionNextPage = 'nextPage';
const String novelMenuActionPreviousChapter = 'previousChapter';
const String novelMenuActionNextChapter = 'nextChapter';
const String novelMenuActionAddBookmark = 'addBookmark';
const String novelMenuActionEditContent = 'editContent';
const String novelMenuActionReplace = 'replaceToggle';
const String novelMenuActionSyncProgress = 'syncProgress';
const String novelMenuActionDownload = 'download';
const String novelMenuActionRefresh = 'refresh';
const String novelMenuActionSwitchSource = 'switchSource';
const String novelMenuActionMore = 'more';
const String novelMenuActionMorePanel = 'moreActions';

/// 顶栏最多展示的按钮数（与上游 MAX_TITLE_BAR_ACTIONS 一致）：
/// 再多就会挤压书名与章节名。
const int novelTitleBarMaxActions = 6;

/// 完整动作表。顺序只影响「设置页里的默认排列」，不决定渲染顺序。
const List<NovelMenuActionDef> novelMenuActionDefs = <NovelMenuActionDef>[
  NovelMenuActionDef(
    id: novelMenuActionSearch,
    label: '书内搜索',
    icon: Icons.search,
    clickAction: NovelClickAction.search,
  ),
  NovelMenuActionDef(
    id: novelMenuActionAutoPage,
    label: '自动翻页',
    icon: Icons.play_arrow,
    clickAction: NovelClickAction.autoPage,
  ),
  NovelMenuActionDef(
    id: novelMenuActionCatalog,
    label: '目录',
    icon: Icons.menu,
    clickAction: NovelClickAction.catalog,
  ),
  NovelMenuActionDef(
    id: novelMenuActionTts,
    label: '语音朗读',
    icon: Icons.record_voice_over_outlined,
    clickAction: NovelClickAction.ttsToggle,
  ),
  NovelMenuActionDef(
    id: novelMenuActionSettings,
    label: '阅读设置',
    icon: Icons.settings_outlined,
    clickAction: NovelClickAction.menu,
  ),
  NovelMenuActionDef(
    id: novelMenuActionPreviousPage,
    label: '上一页',
    icon: Icons.chevron_left,
    clickAction: NovelClickAction.previousPage,
  ),
  NovelMenuActionDef(
    id: novelMenuActionNextPage,
    label: '下一页',
    icon: Icons.chevron_right,
    clickAction: NovelClickAction.nextPage,
  ),
  NovelMenuActionDef(
    id: novelMenuActionPreviousChapter,
    label: '上一章',
    icon: Icons.skip_previous,
    clickAction: NovelClickAction.previousChapter,
  ),
  NovelMenuActionDef(
    id: novelMenuActionNextChapter,
    label: '下一章',
    icon: Icons.skip_next,
    clickAction: NovelClickAction.nextChapter,
  ),
  NovelMenuActionDef(
    id: novelMenuActionAddBookmark,
    label: '加书签',
    icon: Icons.bookmark_add_outlined,
    clickAction: NovelClickAction.addBookmark,
    available: _bookmarkReady,
    unavailableHint: '需先完成书签库',
  ),
  NovelMenuActionDef(
    id: novelMenuActionEditContent,
    label: '正文编辑',
    icon: Icons.edit_outlined,
    clickAction: NovelClickAction.editContent,
    available: _contentEditReady,
    unavailableHint: '需先完成正文编辑',
  ),
  NovelMenuActionDef(
    id: novelMenuActionReplace,
    label: '替换规则',
    icon: Icons.find_replace,
    clickAction: NovelClickAction.replaceToggle,
    available: _replaceReady,
    unavailableHint: '需先完成替换规则面板',
  ),
  NovelMenuActionDef(
    id: novelMenuActionSyncProgress,
    label: '同步进度',
    icon: Icons.cloud_sync_outlined,
    clickAction: NovelClickAction.syncProgress,
    available: _syncReady,
    unavailableHint: '需先完成 WebDAV 同步',
  ),
  NovelMenuActionDef(
    id: novelMenuActionDownload,
    label: '缓存本章',
    icon: Icons.cloud_download_outlined,
    available: _onlineOnly,
    unavailableHint: '仅在线书籍可用',
  ),
  NovelMenuActionDef(
    id: novelMenuActionRefresh,
    label: '刷新本章',
    icon: Icons.refresh,
    available: _onlineOnly,
    unavailableHint: '仅在线书籍可用',
  ),
  NovelMenuActionDef(
    id: novelMenuActionSwitchSource,
    label: '换源',
    icon: Icons.swap_horiz,
    available: _onlineOnly,
    unavailableHint: '仅在线书籍可用',
  ),
  NovelMenuActionDef(
    id: novelMenuActionMore,
    label: '更多',
    icon: Icons.more_vert,
  ),
  NovelMenuActionDef(
    id: novelMenuActionMorePanel,
    label: '更多动作',
    icon: Icons.apps,
  ),
];

bool _bookmarkReady(NovelMenuActionContext context) => context.bookmarkReady;
bool _contentEditReady(NovelMenuActionContext context) =>
    context.contentEditReady;
bool _replaceReady(NovelMenuActionContext context) => context.replaceReady;
bool _syncReady(NovelMenuActionContext context) => context.syncReady;
bool _onlineOnly(NovelMenuActionContext context) => context.hasOnlineSource;

/// 按 id 取定义；未知 id 返回 null（旧配置降级，不抛异常）。
NovelMenuActionDef? novelMenuActionById(String id) {
  for (final def in novelMenuActionDefs) {
    if (def.id == id) return def;
  }
  return null;
}

/// 一条「顺序 + 启用」配置项（顶栏/底栏/浮动行各存一份）。
class NovelMenuButtonItem {
  const NovelMenuButtonItem(this.id, {this.enabled = true});

  final String id;
  final bool enabled;

  NovelMenuButtonItem copyWith({bool? enabled}) =>
      NovelMenuButtonItem(id, enabled: enabled ?? this.enabled);

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'enabled': enabled,
  };

  /// 坏数据返回 null，由调用方跳过这一项。
  static NovelMenuButtonItem? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    if (id is! String || id.isEmpty) return null;
    final enabled = raw['enabled'];
    return NovelMenuButtonItem(id, enabled: enabled is bool ? enabled : true);
  }

  static List<NovelMenuButtonItem> listFromJson(Object? raw) {
    if (raw is! List) return const <NovelMenuButtonItem>[];
    final result = <NovelMenuButtonItem>[];
    for (final item in raw) {
      final parsed = fromJson(item);
      if (parsed != null) result.add(parsed);
    }
    return result;
  }

  static List<Map<String, Object?>> listToJson(
    List<NovelMenuButtonItem> items,
  ) => <Map<String, Object?>>[for (final item in items) item.toJson()];

  @override
  bool operator ==(Object other) =>
      other is NovelMenuButtonItem &&
      other.id == id &&
      other.enabled == enabled;

  @override
  int get hashCode => Object.hash(id, enabled);

  @override
  String toString() => 'NovelMenuButtonItem($id, enabled: $enabled)';
}

/// 顶栏默认：缓存本章 / 刷新本章 / 换源 / 更多（改造前写死的那四个）。
const List<NovelMenuButtonItem> novelDefaultTitleBarMenu =
    <NovelMenuButtonItem>[
      NovelMenuButtonItem(novelMenuActionDownload),
      NovelMenuButtonItem(novelMenuActionRefresh),
      NovelMenuButtonItem(novelMenuActionSwitchSource),
      NovelMenuButtonItem(novelMenuActionMore),
    ];

/// 底栏默认：搜索 / 自动翻页 / 目录 / 朗读 / 设置（顺序与行为都不变）。
const List<NovelMenuButtonItem> novelDefaultBottomBarMenu =
    <NovelMenuButtonItem>[
      NovelMenuButtonItem(novelMenuActionSearch),
      NovelMenuButtonItem(novelMenuActionAutoPage),
      NovelMenuButtonItem(novelMenuActionCatalog),
      NovelMenuButtonItem(novelMenuActionTts),
      NovelMenuButtonItem(novelMenuActionSettings),
    ];

/// 浮动行默认空：不配置就不出现，避免默认多出一排按钮。
const List<NovelMenuButtonItem> novelDefaultFloatingMenu =
    <NovelMenuButtonItem>[];

/// 某个动作在测试/自动化里的稳定 key。
///
/// 历史 key 是手写的（`novel-reader-search` / `novel-reader-switch-source`），
/// 改名会让既有 UI 测试与截图脚本失效，所以这里保留原名。
String novelMenuActionKey(String id) => switch (id) {
  novelMenuActionSearch => 'novel-reader-search',
  novelMenuActionAutoPage => 'novel-reader-auto-page',
  novelMenuActionCatalog => 'novel-reader-catalog',
  novelMenuActionTts => 'novel-reader-tts',
  novelMenuActionSettings => 'novel-reader-settings',
  novelMenuActionSwitchSource => 'novel-reader-switch-source',
  _ => 'novel-reader-$id',
};

/// 按配置解析出实际要渲染的动作：跳过禁用项、未知 id、当前不可用的动作。
///
/// 纯函数：不碰 State、不读全局变量，便于单测。
List<NovelMenuActionDef> resolveNovelMenuActions({
  required List<NovelMenuButtonItem> items,
  required NovelMenuActionContext context,
  int? maxActions,
}) {
  final result = <NovelMenuActionDef>[];
  for (final item in items) {
    if (!item.enabled) continue;
    final def = novelMenuActionById(item.id);
    if (def == null) continue;
    if (!def.isAvailable(context)) continue;
    result.add(def);
    if (maxActions != null && result.length >= maxActions) break;
  }
  return List<NovelMenuActionDef>.unmodifiable(result);
}

/// 顶栏解析：紧凑模式只留「更多」；过滤 + 截断到
/// [novelTitleBarMaxActions]；一个都不剩时至少保留「更多」，
/// 避免出现没有任何入口的顶栏。
List<NovelMenuActionDef> resolveNovelTitleBarActions({
  required List<NovelMenuButtonItem> items,
  required NovelMenuActionContext context,
  required bool compact,
}) {
  final more = novelMenuActionById(novelMenuActionMore)!;
  if (compact) return <NovelMenuActionDef>[more];
  final actions = resolveNovelMenuActions(
    items: items,
    context: context,
    maxActions: novelTitleBarMaxActions,
  );
  return actions.isEmpty ? <NovelMenuActionDef>[more] : actions;
}

/// 按「每行几个 + 几行」排出来的结果。
class NovelMenuRowLayout {
  const NovelMenuRowLayout({required this.rows, required this.overflow});

  /// 实际渲染的若干行（每行 ≤ itemsPerRow）。
  final List<List<NovelMenuActionDef>> rows;

  /// 放不下、要收进「更多动作」面板的动作。
  final List<NovelMenuActionDef> overflow;

  List<NovelMenuActionDef> get visible => <NovelMenuActionDef>[
    for (final row in rows) ...row,
  ];
}

/// 把动作列表排成 rows × perRow 的网格。
///
/// [showMore] 为 true 且放不下时，最后一个格子留给「更多动作」入口，
/// 保证总格子数不超过 rows × perRow（行数是用户显式配的上限）。
NovelMenuRowLayout layoutNovelMenuRows({
  required List<NovelMenuActionDef> actions,
  required int itemsPerRow,
  required int rowCount,
  bool showMore = true,
}) {
  final perRow = itemsPerRow.clamp(2, 8);
  final rowTotal = rowCount.clamp(1, 2);
  var capacity = perRow * rowTotal;
  if (capacity <= 0) {
    return const NovelMenuRowLayout(
      rows: <List<NovelMenuActionDef>>[],
      overflow: <NovelMenuActionDef>[],
    );
  }

  var visible = actions;
  var overflow = const <NovelMenuActionDef>[];
  if (actions.length > capacity) {
    if (showMore && capacity > 1) {
      capacity -= 1;
      visible = actions.take(capacity).toList();
      overflow = actions.skip(capacity).toList();
      final more = novelMenuActionById(novelMenuActionMorePanel);
      if (more != null) visible = <NovelMenuActionDef>[...visible, more];
    } else {
      visible = actions.take(capacity).toList();
      overflow = actions.skip(capacity).toList();
    }
  }

  final rows = <List<NovelMenuActionDef>>[];
  for (var start = 0; start < visible.length; start += perRow) {
    rows.add(
      List<NovelMenuActionDef>.unmodifiable(visible.skip(start).take(perRow)),
    );
  }
  return NovelMenuRowLayout(
    rows: List<List<NovelMenuActionDef>>.unmodifiable(rows),
    overflow: List<NovelMenuActionDef>.unmodifiable(overflow),
  );
}
