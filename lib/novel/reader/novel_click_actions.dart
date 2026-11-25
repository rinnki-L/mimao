// 阅读器点击区：动作枚举 + 3×3 九宫格默认映射 + 动作分发。
//
// 对照「阅读（legado）」的 ClickActionConfigSheet（15 种动作 + 九宫格映射）。
// 这里是唯一的动作事实源：
// - 设置面板的下拉、九宫格配置面板的格子文案、阅读页的点击分发，都从
//   [NovelClickAction] 取值，不各写一套字符串；
// - 动作枚举名就是落库的键（`clickZones` 存 9 个 enum name），改名前先想清楚
//   兼容性：旧值解析不到一律降级为 [NovelClickAction.none]；
// - 没实现的动作不静默无效：[NovelClickAction.available] 为 false，UI 显灰并
//   用 [NovelClickAction.unavailableHint] 说明「需先完成 X」。
//
// 九宫格顺序与 legado 一致：左上 → 右下，共 9 格。

/// 九宫格里的一个格子（下标即 [NovelClickZones] 列表下标）。
enum NovelClickZone {
  topLeft('左上'),
  topCenter('上'),
  topRight('右上'),
  centerLeft('左'),
  center('中'),
  centerRight('右'),
  bottomLeft('左下'),
  bottomCenter('下'),
  bottomRight('右下');

  const NovelClickZone(this.label);

  final String label;
}

/// 点击区可绑定的动作。
///
/// 顺序即下拉顺序；[none] 在最前，未实现的动作排在最后并显灰。
enum NovelClickAction {
  none('无动作'),
  menu('菜单'),
  previousPage('上一页'),
  nextPage('下一页'),
  previousChapter('上一章'),
  nextChapter('下一章'),
  ttsToggle('朗读暂停/继续'),
  autoPage('自动翻页'),
  addBookmark('加书签'),
  catalog('目录'),
  search('书内搜索'),
  editContent('正文编辑'),
  replaceToggle('替换开关'),
  syncProgress('同步进度', requires: 'WebDAV 同步');

  const NovelClickAction(this.label, {this.requires});

  final String label;

  /// 非空表示该动作尚未落地，文案是「需先完成 X」里的 X。
  final String? requires;

  /// 是否已实现；未实现的动作在 UI 里显灰、点按不生效。
  bool get available => requires == null;

  /// 未实现动作的说明；已实现返回 null。
  String? get unavailableHint => requires == null ? null : '需先完成$requires';
}

/// 长按动作（默认选文）。
enum NovelLongPressAction {
  selectText('选文'),
  menu('菜单'),
  nextPage('下一页'),
  previousPage('上一页'),
  ttsToggle('朗读暂停/继续'),
  none('无动作');

  const NovelLongPressAction(this.label);

  final String label;
}

/// 双击动作（默认无）。
enum NovelDoubleTapAction {
  none('无动作'),
  menu('菜单'),
  nextPage('下一页'),
  previousPage('上一页'),
  addBookmark('加书签'),
  ttsToggle('朗读暂停/继续');

  const NovelDoubleTapAction(this.label);

  final String label;
}

/// 九宫格默认动作：只开中间一行，沿用改造前的手感
/// （左 = 上一页、中 = 菜单、右 = 下一页）。
///
/// 上/下两行默认无动作：那里离页眉页脚最近，误触翻页比「点了没反应」更烦；
/// 想要全屏可点，用户自己在配置里把上/下格填上即可。
const List<NovelClickAction> novelDefaultClickZones = <NovelClickAction>[
  NovelClickAction.none, // 左上
  NovelClickAction.none, // 上
  NovelClickAction.none, // 右上
  NovelClickAction.previousPage, // 左
  NovelClickAction.menu, // 中
  NovelClickAction.nextPage, // 右
  NovelClickAction.none, // 左下
  NovelClickAction.none, // 下
  NovelClickAction.none, // 右下
];

/// 把任意长度的列表补齐/截断成 9 格；不认识的值降级为 [NovelClickAction.none]。
List<NovelClickAction> normalizeClickZones(List<NovelClickAction> raw) {
  final result = List<NovelClickAction>.filled(
    NovelClickZone.values.length,
    NovelClickAction.none,
  );
  for (var i = 0; i < result.length && i < raw.length; i++) {
    result[i] = raw[i];
  }
  return List<NovelClickAction>.unmodifiable(result);
}

/// 把点击坐标映射到九宫格格子。
///
/// 只做几何判定，不关心动作：页面拿到格子后再去取该格配置的动作。
/// 边界按三等分：`x / width * 3` 取整并 clamp 到 0..2，避免恰好在右/下边缘
/// 时算出 3。宽/高非正时退到中心格（空页面不该因为尺寸 0 抛异常）。
NovelClickZone clickZoneAt(double x, double y, double width, double height) {
  if (width <= 0 || height <= 0) return NovelClickZone.center;
  final column = (x / width * 3).floor().clamp(0, 2);
  final row = (y / height * 3).floor().clamp(0, 2);
  return NovelClickZone.values[row * 3 + column];
}

/// 一次点击分发的目标：动作 + 该动作要处理的副作用入口。
///
/// 阅读页实现这个接口；分发器只做「动作 → 调用哪个方法」的映射，
/// 不直接碰页面 State，因此可以在单测里用假实现验证分发。
abstract interface class NovelClickActionHandler {
  void openMenu();
  void turnPreviousPage();
  void turnNextPage();
  void openPreviousChapter();
  void openNextChapter();
  void toggleTts();
  void toggleAutoPage();
  void addBookmark();
  void openCatalog();
  void openSearch();
  void openContentEdit();
  void toggleReplace();
  void syncProgress();
}

/// 动作分发：把 [action] 落到 [handler] 的对应方法上。
///
/// 未实现（[NovelClickAction.available] 为 false）或未知的动作一律当
/// [NovelClickAction.none]：不抛异常、不静默做别的事，返回 false 表示「没执行」。
bool dispatchClickAction(
  NovelClickAction action,
  NovelClickActionHandler handler,
) {
  if (!action.available) return false;
  switch (action) {
    case NovelClickAction.none:
      return false;
    case NovelClickAction.menu:
      handler.openMenu();
    case NovelClickAction.previousPage:
      handler.turnPreviousPage();
    case NovelClickAction.nextPage:
      handler.turnNextPage();
    case NovelClickAction.previousChapter:
      handler.openPreviousChapter();
    case NovelClickAction.nextChapter:
      handler.openNextChapter();
    case NovelClickAction.ttsToggle:
      handler.toggleTts();
    case NovelClickAction.autoPage:
      handler.toggleAutoPage();
    case NovelClickAction.addBookmark:
      handler.addBookmark();
    case NovelClickAction.catalog:
      handler.openCatalog();
    case NovelClickAction.search:
      handler.openSearch();
    case NovelClickAction.editContent:
      handler.openContentEdit();
    case NovelClickAction.replaceToggle:
      handler.toggleReplace();
    case NovelClickAction.syncProgress:
      handler.syncProgress();
  }
  return true;
}

/// 长按动作分发；[selectText] 由页面自己处理（要交给 SelectionArea），
/// 这里只返回 false 表示「页面应走默认选文」。
bool dispatchLongPressAction(
  NovelLongPressAction action,
  NovelClickActionHandler handler,
) {
  switch (action) {
    case NovelLongPressAction.selectText:
    case NovelLongPressAction.none:
      return false;
    case NovelLongPressAction.menu:
      handler.openMenu();
    case NovelLongPressAction.nextPage:
      handler.turnNextPage();
    case NovelLongPressAction.previousPage:
      handler.turnPreviousPage();
    case NovelLongPressAction.ttsToggle:
      handler.toggleTts();
  }
  return true;
}

/// 双击动作分发；未实现动作降级为无动作。
bool dispatchDoubleTapAction(
  NovelDoubleTapAction action,
  NovelClickActionHandler handler,
) {
  switch (action) {
    case NovelDoubleTapAction.none:
      return false;
    case NovelDoubleTapAction.menu:
      handler.openMenu();
    case NovelDoubleTapAction.nextPage:
      handler.turnNextPage();
    case NovelDoubleTapAction.previousPage:
      handler.turnPreviousPage();
    case NovelDoubleTapAction.addBookmark:
      handler.addBookmark();
    case NovelDoubleTapAction.ttsToggle:
      handler.toggleTts();
  }
  return true;
}
