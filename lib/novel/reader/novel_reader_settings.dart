// 阅读设置的纯数据模型：可序列化到模块 kv，不认识 Widget。
//
// 对照「阅读（legado）」的阅读界面：字号 / 字体 / 背景预设与背景图 / 行距 /
// 段距 / 左右边距 / 翻页方式 / 自动翻页间隔 / 阅读亮度 / 正文与标题排版 /
// 文字装饰 / 页眉页脚三槽 / 简繁转换 / 双栏。背景色、文字色、阴影色都是
// 「覆盖在阅读画布上的自定义颜色」，属于 ColorScheme 角色的例外（与漫画
// 阅读器的亮度遮罩同款）。
//
// 兼容性约定：新增字段一律给默认值；[fromJson] 对缺字段、坏字段、越界值都
// 回退到默认并 clamp。旧版本只写了 footerLeft/footerRight 两个键，这里仍然
// 解析成三槽里的左/右槽，老用户升级不丢设置。

import 'dart:convert';

import 'package:mimao/novel/library_api.dart'
    show
        NovelPrefsApi,
        novelPrefReaderBookSettings,
        novelPrefReaderFontSize,
        novelPrefReaderSettings;
import 'package:mimao/novel/reader/novel_click_actions.dart';
import 'package:mimao/novel/reader/novel_menu_actions.dart';

/// 翻页方式：上下滚动（默认）/ 左右翻页。
enum NovelPageMode { scroll, page }

/// 一次修改的作用域：改全局，还是只改当前这本书。
///
/// 默认 [global]（与上游一致）；[book] 时只把「与全局不同的字段」写进
/// 每书覆盖，全局设置保持不动。
enum NovelSettingsScope { global, book }

/// 左右翻页的过渡动画风格（对照 legado 的 PageAnim）。
///
/// 只做能稳定还原的六种；卷曲/仿真翻页（iosCurl / googleCurl /
/// simulationPageAnim）明确不做，设置项里不出现。
enum NovelPageAnimStyle {
  none('无动画'),
  fade('淡入淡出'),
  slide('滑动'),
  cover('覆盖'),
  scroll('滚动'),
  parallax('视差');

  const NovelPageAnimStyle(this.label);

  final String label;
}

/// 页脚左槽内容（旧版枚举，只用于读取历史 JSON）。
enum NovelFooterLeft {
  chapter('章节标题'),
  book('书名'),
  none('无');

  const NovelFooterLeft(this.label);

  final String label;
}

/// 页脚右槽内容（旧版枚举，只用于读取历史 JSON）。
enum NovelFooterRight {
  pageAndPercent('页码 + 进度'),
  page('页码'),
  percent('进度'),
  none('无');

  const NovelFooterRight(this.label);

  final String label;
}

/// 页眉/页脚单个槽位可放的内容（对照 legado 的三槽配置，并补自定义文案）。
enum NovelChromeSlot {
  none('无'),
  chapter('章节名'),
  book('书名'),
  page('页码'),
  percent('进度'),
  pageAndPercent('页码 + 进度'),
  custom('自定义文案');

  const NovelChromeSlot(this.label);

  final String label;
}

/// 标题排版：居左 / 居中 / 隐藏。
enum NovelTitleMode {
  left('居左'),
  center('居中'),
  hide('隐藏');

  const NovelTitleMode(this.label);

  final String label;
}

/// 正文下划线样式（对照 legado 的「文字下划线」：实线 / 波浪 / 虚线）。
enum NovelUnderlineStyle {
  none('无'),
  solid('实线'),
  wave('波浪线'),
  dash('虚线');

  const NovelUnderlineStyle(this.label);

  final String label;
}

/// 背景图铺放方式（对应 BoxFit 的常用子集）。
enum NovelBackgroundFit {
  cover('裁剪填满'),
  contain('完整显示'),
  fill('拉伸填满'),
  fitWidth('按宽铺满'),
  fitHeight('按高铺满');

  const NovelBackgroundFit(this.label);

  final String label;
}

/// 九宫格对齐（背景图铺放后的锚点）。
enum NovelBackgroundAlign {
  topLeft('左上'),
  topCenter('上'),
  topRight('右上'),
  centerLeft('左'),
  center('居中'),
  centerRight('右'),
  bottomLeft('左下'),
  bottomCenter('下'),
  bottomRight('右下');

  const NovelBackgroundAlign(this.label);

  final String label;
}

/// 背景纹理预设：纯代码绘制的低对比纹理，不需要图片资源。
enum NovelBackgroundTexture {
  none('无'),
  dots('细点'),
  lines('横线'),
  grid('方格'),
  diagonal('斜纹');

  const NovelBackgroundTexture(this.label);

  final String label;
}

/// 简繁转换（离线映射，只影响渲染，不回写正文）。
enum NovelChineseConvert {
  none('不转换'),
  simplifiedToTraditional('简体 → 繁体'),
  traditionalToSimplified('繁体 → 简体');

  const NovelChineseConvert(this.label);

  final String label;
}

/// 一个背景预设：名称 + ARGB 颜色 + 是否深色底。
class NovelReaderBackground {
  const NovelReaderBackground(this.name, this.argb, {required this.dark});

  final String name;
  final int argb;
  final bool dark;
}

/// 内置背景色板（对应截图里的预设 1/2/3 与更多色板）。
const List<NovelReaderBackground> novelReaderBackgrounds =
    <NovelReaderBackground>[
      NovelReaderBackground('纯黑', 0xFF000000, dark: true),
      NovelReaderBackground('深灰', 0xFF2B2B2B, dark: true),
      NovelReaderBackground('墨绿', 0xFF1C2A24, dark: true),
      NovelReaderBackground('羊皮纸', 0xFFF2E6CF, dark: false),
      NovelReaderBackground('米黄', 0xFFF7F1E4, dark: false),
      NovelReaderBackground('护眼绿', 0xFFDCE8D5, dark: false),
      NovelReaderBackground('纯白', 0xFFFFFFFF, dark: false),
    ];

/// 默认背景：深灰（与截图一致）。
const int novelReaderDefaultBackground = 1;

/// 正文字体候选。`family` 为空表示跟随 app 默认字体（雅黑）。
///
/// 这是阅读正文的独立选项目（截图里的 Tt 按钮），只在正文生效；
/// app 其余界面仍锁 `MimaoFonts.family`。导入的 .ttf/.otf 以文件名为
/// family，同样走这个字段持久化。
class NovelReaderFont {
  const NovelReaderFont(this.name, this.family);

  final String name;
  final String family;
}

const List<NovelReaderFont> novelReaderFonts = <NovelReaderFont>[
  NovelReaderFont('系统默认', ''),
  NovelReaderFont('宋体', 'SimSun'),
  NovelReaderFont('黑体', 'SimHei'),
  NovelReaderFont('楷体', 'KaiTi'),
  NovelReaderFont('仿宋', 'FangSong'),
];

/// 一次阅读设置的完整快照（不可变；改设置用 copyWith 产生新对象）。
class NovelReaderSettings {
  const NovelReaderSettings({
    this.fontSize = 20,
    this.fontFamily = '',
    this.lineHeight = 1.8,
    this.paragraphSpacing = 12,
    this.horizontalPadding = 24,
    this.backgroundIndex = novelReaderDefaultBackground,
    this.customBackgroundArgb,
    this.dimBrightness = 100,
    this.pageMode = NovelPageMode.scroll,
    this.pageAnimation = true,
    this.pageAnimStyle = NovelPageAnimStyle.slide,
    this.pageAnimationMs = 260,
    List<NovelClickAction>? clickZones,
    this.longPressAction = NovelLongPressAction.selectText,
    this.doubleTapAction = NovelDoubleTapAction.none,
    this.swipeDownBookmark = false,
    this.autoPageSeconds = 15,
    this.showFooter = true,
    this.footerLeft = NovelFooterLeft.chapter,
    this.footerRight = NovelFooterRight.pageAndPercent,
    this.eyeProtection = false,
    this.autoBrightness = false,
    this.textAlignJustify = false,
    this.letterSpacing = 0,
    this.textBold = false,
    this.textItalic = false,
    this.indentCount = 2,
    this.lineHeightIncludesPadding = true,
    this.titleMode = NovelTitleMode.left,
    this.titleSize = 6,
    this.titleSizeRelative = true,
    this.titleTopSpacing = 4,
    this.titleBottomSpacing = 18,
    this.titleSegment = false,
    this.titleSegmentDivider = '·',
    this.titleSegmentScale = 0.7,
    this.shadowRadius = 0,
    this.shadowOffsetX = 0,
    this.shadowOffsetY = 1,
    this.shadowColorArgb,
    this.underlineStyle = NovelUnderlineStyle.none,
    this.underlineThickness = 1,
    this.underlineSpacing = 2,
    this.underlineExtend = false,
    this.showHeader = false,
    this.headerSlots = const <NovelChromeSlot>[
      NovelChromeSlot.none,
      NovelChromeSlot.chapter,
      NovelChromeSlot.none,
    ],
    List<NovelChromeSlot>? footerSlots,
    this.headerCustomText = '',
    this.footerCustomText = '',
    this.headerFontSize = 12,
    this.footerFontSize = 12,
    this.backgroundImagePath,
    this.backgroundImageFit = NovelBackgroundFit.cover,
    this.backgroundImageOpacity = 100,
    this.backgroundImageAlign = NovelBackgroundAlign.center,
    this.backgroundTexture = NovelBackgroundTexture.none,
    this.chineseConvert = NovelChineseConvert.none,
    this.twoColumn = false,
    this.menuIconItemsPerRow = 5,
    this.menuIconRowCount = 1,
    this.menuBottomRadius = 32,
    this.menuShowIconText = false,
    this.titleBarCompact = false,
    List<NovelMenuButtonItem>? titleBarMenu,
    List<NovelMenuButtonItem>? bottomBarMenu,
    List<NovelMenuButtonItem>? floatingBarMenu,
  }) : _footerSlots = footerSlots,
       _clickZones = clickZones,
       _titleBarMenu = titleBarMenu,
       _bottomBarMenu = bottomBarMenu,
       _floatingBarMenu = floatingBarMenu;

  static const double minFontSize = 12;
  static const double maxFontSize = 40;
  static const double minLineHeight = 1.3;
  static const double maxLineHeight = 2.6;
  static const double minParagraphSpacing = 0;
  static const double maxParagraphSpacing = 32;
  static const double minHorizontalPadding = 12;
  static const double maxHorizontalPadding = 64;
  static const int minAutoPageSeconds = 5;
  static const int maxAutoPageSeconds = 120;

  static const double minLetterSpacing = -1;
  static const double maxLetterSpacing = 3;
  static const int minIndentCount = 0;
  static const int maxIndentCount = 4;
  static const double minTitleSize = 0;
  static const double maxTitleSizeRelative = 40;
  static const double maxTitleSizeAbsolute = 60;
  static const double minTitleSpacing = 0;
  static const double maxTitleSpacing = 48;
  static const double minTitleSegmentScale = 0.3;
  static const double maxTitleSegmentScale = 1;
  static const double minShadowRadius = 0;
  static const double maxShadowRadius = 16;
  static const double minShadowOffset = -8;
  static const double maxShadowOffset = 8;
  static const double minUnderlineThickness = 0.5;
  static const double maxUnderlineThickness = 4;
  static const double minUnderlineSpacing = 0;
  static const double maxUnderlineSpacing = 8;
  static const double minChromeFontSize = 8;
  static const double maxChromeFontSize = 24;
  static const int minBackgroundImageOpacity = 0;
  static const int maxBackgroundImageOpacity = 100;

  static const int minMenuIconItemsPerRow = 2;
  static const int maxMenuIconItemsPerRow = 8;
  static const int minMenuIconRowCount = 1;
  static const int maxMenuIconRowCount = 2;
  static const int minMenuBottomRadius = 0;
  static const int maxMenuBottomRadius = 32;

  /// 正文字号（逻辑像素，与截图里的 20 对齐）。
  final double fontSize;

  /// 正文字体族；空串 = 跟随 app 默认（雅黑），其余是系统字体或导入字体名。
  final String fontFamily;

  /// 行高倍率。
  final double lineHeight;

  /// 段间距。
  final double paragraphSpacing;

  /// 正文左右留白。
  final double horizontalPadding;

  /// 背景预设下标（[novelReaderBackgrounds]）。
  final int backgroundIndex;

  /// 长按自定义的背景色；非空时优先于 [backgroundIndex]。
  final int? customBackgroundArgb;

  /// 阅读内亮度 20~100（100 = 不压暗，桌面端用黑色遮罩实现）。
  final int dimBrightness;

  /// 翻页方式，默认上下滚动。
  final NovelPageMode pageMode;

  /// 左右翻页时是否播放过渡动画。
  final bool pageAnimation;

  /// 左右翻页的过渡动画风格；[pageAnimation] 关掉时一律当 [none]。
  final NovelPageAnimStyle pageAnimStyle;

  /// 翻页动画时长（毫秒，对应 legado 的「翻页动画速度」）。
  final int pageAnimationMs;

  /// 3×3 九宫格点击区；null = 用 [novelDefaultClickZones]。
  final List<NovelClickAction>? _clickZones;

  /// 长按动作（默认选文）。
  final NovelLongPressAction longPressAction;

  /// 双击动作（默认无）。
  final NovelDoubleTapAction doubleTapAction;

  /// 在正文顶部继续下滑时加/删书签（默认关：避免与回弹/刷新抢手势）。
  final bool swipeDownBookmark;

  /// 自动翻页间隔（秒）。
  final int autoPageSeconds;

  /// 是否显示页脚。
  final bool showFooter;

  /// 旧版页脚左槽（仅用于读取历史 JSON；新数据看 [footerSlots]）。
  final NovelFooterLeft footerLeft;

  /// 旧版页脚右槽（仅用于读取历史 JSON；新数据看 [footerSlots]）。
  final NovelFooterRight footerRight;

  /// 护眼模式（暖色滤光层）。
  final bool eyeProtection;

  /// 自动亮度（仅 Android 有意义；桌面端隐藏该按钮）。
  final bool autoBrightness;

  // ── 正文排版 ──────────────────────────────────────────────────────────

  /// 正文两端对齐。
  final bool textAlignJustify;

  /// 字距（逻辑像素，可负）。
  final double letterSpacing;

  /// 正文加粗。
  final bool textBold;

  /// 正文斜体。
  final bool textItalic;

  /// 段首缩进的全角空格个数（默认 2 = 「　　」）。
  final int indentCount;

  /// 行距是否含行内留白：true 时 [lineHeight] 作用于整行（含首末行
  /// 的上下留白）；false 时只拉开行与行之间的距离。
  final bool lineHeightIncludesPadding;

  // ── 标题 ──────────────────────────────────────────────────────────────

  final NovelTitleMode titleMode;

  /// 标题字号：相对模式是「相对正文的偏移」，绝对模式是实际字号。
  final double titleSize;

  final bool titleSizeRelative;
  final double titleTopSpacing;
  final double titleBottomSpacing;

  /// 标题分段：把「第X章 标题」按空白切成主标题 + 副标题。
  final bool titleSegment;

  /// 分段连接符（在主标题与副标题之间插入）。
  final String titleSegmentDivider;

  /// 副标题相对标题字号的缩放。
  final double titleSegmentScale;

  // ── 文字装饰 ──────────────────────────────────────────────────────────

  /// 阴影模糊半径；0 = 不画阴影。
  final double shadowRadius;

  final double shadowOffsetX;
  final double shadowOffsetY;

  /// 阴影颜色；空 = 用正文色半透明（深底浅字也自然）。
  final int? shadowColorArgb;

  final NovelUnderlineStyle underlineStyle;
  final double underlineThickness;

  /// 下划线与文字的距离（Flutter TextStyle 没有 offset，渲染层用它
  /// 调整行高留白；值越大，行内下划线越不贴字）。
  final double underlineSpacing;

  /// 下划线是否延伸（应用到段尾空白；渲染层以 decoration 的方式尽力实现）。
  final bool underlineExtend;

  // ── 页眉页脚 ──────────────────────────────────────────────────────────

  final bool showHeader;

  /// 页眉左/中/右槽，长度恒为 3。
  final List<NovelChromeSlot> headerSlots;

  /// 页脚左/中/右槽；null 时由旧版 [footerLeft]/[footerRight] 派生。
  final List<NovelChromeSlot>? _footerSlots;

  final String headerCustomText;
  final String footerCustomText;
  final double headerFontSize;
  final double footerFontSize;

  // ── 背景图 / 纹理 ─────────────────────────────────────────────────────

  /// 本地背景图路径；空 = 不铺图。
  final String? backgroundImagePath;

  final NovelBackgroundFit backgroundImageFit;

  /// 背景图不透明度 0~100（叠加在背景色上）。
  final int backgroundImageOpacity;

  final NovelBackgroundAlign backgroundImageAlign;

  final NovelBackgroundTexture backgroundTexture;

  // ── 简繁 / 双栏 ───────────────────────────────────────────────────────

  final NovelChineseConvert chineseConvert;

  /// 宽窗口（≥1100 且横向）时可选双栏分页；标题页不拆。
  final bool twoColumn;

  // ── 菜单外观与布局 ────────────────────────────────────────────────────

  /// 底栏 / 浮动行每行放几个图标（2–8）。
  final int menuIconItemsPerRow;

  /// 底栏 / 浮动行的行数（1–2）。
  final int menuIconRowCount;

  /// 底栏圆角（0–32）。0 = 直角，32 = 胶囊感。
  final int menuBottomRadius;

  /// 图标下面是否带文字标签。
  final bool menuShowIconText;

  /// 紧凑标题栏：顶栏只留「更多」，把书名与章节名让出来。
  final bool titleBarCompact;

  /// 顶栏按钮配置（顺序 + 启用）；null = [novelDefaultTitleBarMenu]。
  final List<NovelMenuButtonItem>? _titleBarMenu;

  /// 底栏按钮配置；null = [novelDefaultBottomBarMenu]。
  final List<NovelMenuButtonItem>? _bottomBarMenu;

  /// 浮动行按钮配置；null = 空（不渲染）。
  final List<NovelMenuButtonItem>? _floatingBarMenu;

  List<NovelMenuButtonItem> get titleBarMenu =>
      _titleBarMenu ?? novelDefaultTitleBarMenu;

  List<NovelMenuButtonItem> get bottomBarMenu =>
      _bottomBarMenu ?? novelDefaultBottomBarMenu;

  List<NovelMenuButtonItem> get floatingBarMenu =>
      _floatingBarMenu ?? novelDefaultFloatingMenu;

  /// 取某一处菜单栏的配置。
  List<NovelMenuButtonItem> menuBarItems(NovelMenuBar bar) => switch (bar) {
    NovelMenuBar.titleBar => titleBarMenu,
    NovelMenuBar.bottomBar => bottomBarMenu,
    NovelMenuBar.floatingBar => floatingBarMenu,
  };

  /// 换某一处菜单栏的配置（其余两处不动）。
  NovelReaderSettings withMenuBar(
    NovelMenuBar bar,
    List<NovelMenuButtonItem> items,
  ) => switch (bar) {
    NovelMenuBar.titleBar => copyWith(titleBarMenu: items),
    NovelMenuBar.bottomBar => copyWith(bottomBarMenu: items),
    NovelMenuBar.floatingBar => copyWith(floatingBarMenu: items),
  };

  /// 底栏圆角 → BorderRadius（走统一阶梯之外的显式像素，因为它是用户可调项）。
  double get menuBottomRadiusValue => menuBottomRadius
      .clamp(minMenuBottomRadius, maxMenuBottomRadius)
      .toDouble();

  /// 段首缩进串。
  String get indent => '　' * indentCount;

  /// 页脚三槽；未显式设置时由旧版左右槽派生（老 JSON 只有左右两槽）。
  List<NovelChromeSlot> get footerSlots =>
      _footerSlots ??
      <NovelChromeSlot>[
        _fromLegacyLeft(footerLeft),
        NovelChromeSlot.none,
        _fromLegacyRight(footerRight),
      ];

  /// 九宫格点击区；未显式设置时用默认映射。长度恒为 9。
  List<NovelClickAction> get clickZones =>
      _clickZones ?? novelDefaultClickZones;

  /// 实际生效的动画风格：关掉过渡动画就是 [NovelPageAnimStyle.none]。
  NovelPageAnimStyle get effectivePageAnimStyle =>
      pageAnimation ? pageAnimStyle : NovelPageAnimStyle.none;

  /// 取某格的动作（越界返回无动作）。
  NovelClickAction clickZoneAction(NovelClickZone zone) {
    final zones = clickZones;
    final index = zone.index;
    return index >= 0 && index < zones.length
        ? zones[index]
        : NovelClickAction.none;
  }

  /// 标题实际字号。
  double get effectiveTitleFontSize =>
      titleSizeRelative ? fontSize + titleSize : titleSize;

  /// 当前生效的背景（自定义色优先）。
  NovelReaderBackground get background {
    final custom = customBackgroundArgb;
    if (custom != null) {
      return NovelReaderBackground('自定义', custom, dark: _isDarkColor(custom));
    }
    final index = backgroundIndex.clamp(0, novelReaderBackgrounds.length - 1);
    return novelReaderBackgrounds[index];
  }

  int get backgroundColorArgb => background.argb;

  bool get darkBackground => background.dark;

  /// 正文颜色：深底浅字 / 浅底深字。
  int get textColorArgb => darkBackground ? 0xFFD9D9D9 : 0xFF232323;

  /// 页脚、次级文案颜色。
  int get secondaryTextColorArgb => darkBackground ? 0xFF9A9A9A : 0xFF6D6D6D;

  NovelChromeSlot slotAt(List<NovelChromeSlot> slots, int index) =>
      index >= 0 && index < slots.length ? slots[index] : NovelChromeSlot.none;

  NovelReaderSettings copyWith({
    double? fontSize,
    String? fontFamily,
    double? lineHeight,
    double? paragraphSpacing,
    double? horizontalPadding,
    int? backgroundIndex,
    int? customBackgroundArgb,
    bool clearCustomBackground = false,
    int? dimBrightness,
    NovelPageMode? pageMode,
    bool? pageAnimation,
    NovelPageAnimStyle? pageAnimStyle,
    int? pageAnimationMs,
    List<NovelClickAction>? clickZones,
    NovelLongPressAction? longPressAction,
    NovelDoubleTapAction? doubleTapAction,
    bool? swipeDownBookmark,
    int? autoPageSeconds,
    bool? showFooter,
    NovelFooterLeft? footerLeft,
    NovelFooterRight? footerRight,
    bool? eyeProtection,
    bool? autoBrightness,
    bool? textAlignJustify,
    double? letterSpacing,
    bool? textBold,
    bool? textItalic,
    int? indentCount,
    bool? lineHeightIncludesPadding,
    NovelTitleMode? titleMode,
    double? titleSize,
    bool? titleSizeRelative,
    double? titleTopSpacing,
    double? titleBottomSpacing,
    bool? titleSegment,
    String? titleSegmentDivider,
    double? titleSegmentScale,
    double? shadowRadius,
    double? shadowOffsetX,
    double? shadowOffsetY,
    int? shadowColorArgb,
    bool clearShadowColor = false,
    NovelUnderlineStyle? underlineStyle,
    double? underlineThickness,
    double? underlineSpacing,
    bool? underlineExtend,
    bool? showHeader,
    List<NovelChromeSlot>? headerSlots,
    List<NovelChromeSlot>? footerSlots,
    String? headerCustomText,
    String? footerCustomText,
    double? headerFontSize,
    double? footerFontSize,
    String? backgroundImagePath,
    bool clearBackgroundImage = false,
    NovelBackgroundFit? backgroundImageFit,
    int? backgroundImageOpacity,
    NovelBackgroundAlign? backgroundImageAlign,
    NovelBackgroundTexture? backgroundTexture,
    NovelChineseConvert? chineseConvert,
    bool? twoColumn,
    int? menuIconItemsPerRow,
    int? menuIconRowCount,
    int? menuBottomRadius,
    bool? menuShowIconText,
    bool? titleBarCompact,
    List<NovelMenuButtonItem>? titleBarMenu,
    List<NovelMenuButtonItem>? bottomBarMenu,
    List<NovelMenuButtonItem>? floatingBarMenu,
  }) {
    final legacyLeft = footerLeft ?? this.footerLeft;
    final legacyRight = footerRight ?? this.footerRight;
    final nextFooterSlots =
        footerSlots ??
        (footerLeft == null && footerRight == null
            ? _footerSlots
            : <NovelChromeSlot>[
                _fromLegacyLeft(legacyLeft),
                this.footerSlots[1],
                _fromLegacyRight(legacyRight),
              ]);
    return NovelReaderSettings(
      fontSize: _clampDouble(
        fontSize ?? this.fontSize,
        minFontSize,
        maxFontSize,
      ),
      fontFamily: fontFamily ?? this.fontFamily,
      lineHeight: _clampDouble(
        lineHeight ?? this.lineHeight,
        minLineHeight,
        maxLineHeight,
      ),
      paragraphSpacing: _clampDouble(
        paragraphSpacing ?? this.paragraphSpacing,
        minParagraphSpacing,
        maxParagraphSpacing,
      ),
      horizontalPadding: _clampDouble(
        horizontalPadding ?? this.horizontalPadding,
        minHorizontalPadding,
        maxHorizontalPadding,
      ),
      backgroundIndex: backgroundIndex ?? this.backgroundIndex,
      customBackgroundArgb: clearCustomBackground
          ? null
          : (customBackgroundArgb ?? this.customBackgroundArgb),
      dimBrightness: (dimBrightness ?? this.dimBrightness).clamp(20, 100),
      pageMode: pageMode ?? this.pageMode,
      pageAnimation: pageAnimation ?? this.pageAnimation,
      pageAnimStyle: pageAnimStyle ?? this.pageAnimStyle,
      pageAnimationMs: (pageAnimationMs ?? this.pageAnimationMs).clamp(80, 600),
      clickZones: clickZones == null
          ? _clickZones
          : normalizeClickZones(clickZones),
      longPressAction: longPressAction ?? this.longPressAction,
      doubleTapAction: doubleTapAction ?? this.doubleTapAction,
      swipeDownBookmark: swipeDownBookmark ?? this.swipeDownBookmark,
      autoPageSeconds: (autoPageSeconds ?? this.autoPageSeconds).clamp(
        minAutoPageSeconds,
        maxAutoPageSeconds,
      ),
      showFooter: showFooter ?? this.showFooter,
      footerLeft: legacyLeft,
      footerRight: legacyRight,
      eyeProtection: eyeProtection ?? this.eyeProtection,
      autoBrightness: autoBrightness ?? this.autoBrightness,
      textAlignJustify: textAlignJustify ?? this.textAlignJustify,
      letterSpacing: _clampDouble(
        letterSpacing ?? this.letterSpacing,
        minLetterSpacing,
        maxLetterSpacing,
      ),
      textBold: textBold ?? this.textBold,
      textItalic: textItalic ?? this.textItalic,
      indentCount: (indentCount ?? this.indentCount).clamp(
        minIndentCount,
        maxIndentCount,
      ),
      lineHeightIncludesPadding:
          lineHeightIncludesPadding ?? this.lineHeightIncludesPadding,
      titleMode: titleMode ?? this.titleMode,
      titleSize: _clampDouble(
        titleSize ?? this.titleSize,
        minTitleSize,
        (titleSizeRelative ?? this.titleSizeRelative)
            ? maxTitleSizeRelative
            : maxTitleSizeAbsolute,
      ),
      titleSizeRelative: titleSizeRelative ?? this.titleSizeRelative,
      titleTopSpacing: _clampDouble(
        titleTopSpacing ?? this.titleTopSpacing,
        minTitleSpacing,
        maxTitleSpacing,
      ),
      titleBottomSpacing: _clampDouble(
        titleBottomSpacing ?? this.titleBottomSpacing,
        minTitleSpacing,
        maxTitleSpacing,
      ),
      titleSegment: titleSegment ?? this.titleSegment,
      titleSegmentDivider: titleSegmentDivider ?? this.titleSegmentDivider,
      titleSegmentScale: _clampDouble(
        titleSegmentScale ?? this.titleSegmentScale,
        minTitleSegmentScale,
        maxTitleSegmentScale,
      ),
      shadowRadius: _clampDouble(
        shadowRadius ?? this.shadowRadius,
        minShadowRadius,
        maxShadowRadius,
      ),
      shadowOffsetX: _clampDouble(
        shadowOffsetX ?? this.shadowOffsetX,
        minShadowOffset,
        maxShadowOffset,
      ),
      shadowOffsetY: _clampDouble(
        shadowOffsetY ?? this.shadowOffsetY,
        minShadowOffset,
        maxShadowOffset,
      ),
      shadowColorArgb: clearShadowColor
          ? null
          : (shadowColorArgb ?? this.shadowColorArgb),
      underlineStyle: underlineStyle ?? this.underlineStyle,
      underlineThickness: _clampDouble(
        underlineThickness ?? this.underlineThickness,
        minUnderlineThickness,
        maxUnderlineThickness,
      ),
      underlineSpacing: _clampDouble(
        underlineSpacing ?? this.underlineSpacing,
        minUnderlineSpacing,
        maxUnderlineSpacing,
      ),
      underlineExtend: underlineExtend ?? this.underlineExtend,
      showHeader: showHeader ?? this.showHeader,
      headerSlots: _normalizeSlots(headerSlots ?? this.headerSlots),
      footerSlots: nextFooterSlots == null
          ? null
          : _normalizeSlots(nextFooterSlots),
      headerCustomText: headerCustomText ?? this.headerCustomText,
      footerCustomText: footerCustomText ?? this.footerCustomText,
      headerFontSize: _clampDouble(
        headerFontSize ?? this.headerFontSize,
        minChromeFontSize,
        maxChromeFontSize,
      ),
      footerFontSize: _clampDouble(
        footerFontSize ?? this.footerFontSize,
        minChromeFontSize,
        maxChromeFontSize,
      ),
      backgroundImagePath: clearBackgroundImage
          ? null
          : (backgroundImagePath ?? this.backgroundImagePath),
      backgroundImageFit: backgroundImageFit ?? this.backgroundImageFit,
      backgroundImageOpacity:
          (backgroundImageOpacity ?? this.backgroundImageOpacity).clamp(
            minBackgroundImageOpacity,
            maxBackgroundImageOpacity,
          ),
      backgroundImageAlign: backgroundImageAlign ?? this.backgroundImageAlign,
      backgroundTexture: backgroundTexture ?? this.backgroundTexture,
      chineseConvert: chineseConvert ?? this.chineseConvert,
      twoColumn: twoColumn ?? this.twoColumn,
      menuIconItemsPerRow: (menuIconItemsPerRow ?? this.menuIconItemsPerRow)
          .clamp(minMenuIconItemsPerRow, maxMenuIconItemsPerRow),
      menuIconRowCount: (menuIconRowCount ?? this.menuIconRowCount).clamp(
        minMenuIconRowCount,
        maxMenuIconRowCount,
      ),
      menuBottomRadius: (menuBottomRadius ?? this.menuBottomRadius).clamp(
        minMenuBottomRadius,
        maxMenuBottomRadius,
      ),
      menuShowIconText: menuShowIconText ?? this.menuShowIconText,
      titleBarCompact: titleBarCompact ?? this.titleBarCompact,
      titleBarMenu: titleBarMenu ?? _titleBarMenu,
      bottomBarMenu: bottomBarMenu ?? _bottomBarMenu,
      floatingBarMenu: floatingBarMenu ?? _floatingBarMenu,
    );
  }

  /// 选一个内置背景（清掉自定义色）。
  NovelReaderSettings useBackground(int index) =>
      copyWith(backgroundIndex: index, clearCustomBackground: true);

  /// 用自定义色作为背景（长按色板触发）。
  NovelReaderSettings useCustomBackground(int argb) =>
      copyWith(customBackgroundArgb: argb);

  Map<String, Object?> toJson() => <String, Object?>{
    'fontSize': fontSize,
    'fontFamily': fontFamily,
    'lineHeight': lineHeight,
    'paragraphSpacing': paragraphSpacing,
    'horizontalPadding': horizontalPadding,
    'backgroundIndex': backgroundIndex,
    if (customBackgroundArgb != null)
      'customBackgroundArgb': customBackgroundArgb,
    'dimBrightness': dimBrightness,
    'pageMode': pageMode.name,
    'pageAnimation': pageAnimation,
    'pageAnimStyle': pageAnimStyle.name,
    'pageAnimationMs': pageAnimationMs,
    'clickZones': <String>[for (final action in clickZones) action.name],
    'longPressAction': longPressAction.name,
    'doubleTapAction': doubleTapAction.name,
    'swipeDownBookmark': swipeDownBookmark,
    'autoPageSeconds': autoPageSeconds,
    'showFooter': showFooter,
    // 旧键继续写：老版本读到新 JSON 也不至于丢页脚。
    'footerLeft': _toLegacyLeft(slotAt(footerSlots, 0)).name,
    'footerRight': _toLegacyRight(slotAt(footerSlots, 2)).name,
    'eyeProtection': eyeProtection,
    'autoBrightness': autoBrightness,
    'textAlignJustify': textAlignJustify,
    'letterSpacing': letterSpacing,
    'textBold': textBold,
    'textItalic': textItalic,
    'indentCount': indentCount,
    'lineHeightIncludesPadding': lineHeightIncludesPadding,
    'titleMode': titleMode.name,
    'titleSize': titleSize,
    'titleSizeRelative': titleSizeRelative,
    'titleTopSpacing': titleTopSpacing,
    'titleBottomSpacing': titleBottomSpacing,
    'titleSegment': titleSegment,
    'titleSegmentDivider': titleSegmentDivider,
    'titleSegmentScale': titleSegmentScale,
    'shadowRadius': shadowRadius,
    'shadowOffsetX': shadowOffsetX,
    'shadowOffsetY': shadowOffsetY,
    if (shadowColorArgb != null) 'shadowColorArgb': shadowColorArgb,
    'underlineStyle': underlineStyle.name,
    'underlineThickness': underlineThickness,
    'underlineSpacing': underlineSpacing,
    'underlineExtend': underlineExtend,
    'showHeader': showHeader,
    'headerSlots': <String>[for (final slot in headerSlots) slot.name],
    'footerSlots': <String>[for (final slot in footerSlots) slot.name],
    'headerCustomText': headerCustomText,
    'footerCustomText': footerCustomText,
    'headerFontSize': headerFontSize,
    'footerFontSize': footerFontSize,
    if (backgroundImagePath != null) 'backgroundImagePath': backgroundImagePath,
    'backgroundImageFit': backgroundImageFit.name,
    'backgroundImageOpacity': backgroundImageOpacity,
    'backgroundImageAlign': backgroundImageAlign.name,
    'backgroundTexture': backgroundTexture.name,
    'chineseConvert': chineseConvert.name,
    'twoColumn': twoColumn,
    'menuIconItemsPerRow': menuIconItemsPerRow,
    'menuIconRowCount': menuIconRowCount,
    'menuBottomRadius': menuBottomRadius,
    'menuShowIconText': menuShowIconText,
    'titleBarCompact': titleBarCompact,
    'titleBarMenu': NovelMenuButtonItem.listToJson(titleBarMenu),
    'bottomBarMenu': NovelMenuButtonItem.listToJson(bottomBarMenu),
    'floatingBarMenu': NovelMenuButtonItem.listToJson(floatingBarMenu),
  };

  static NovelReaderSettings fromJson(Map<String, Object?> json) {
    final mode = _enumByName(
      NovelPageMode.values,
      json['pageMode'],
      NovelPageMode.scroll,
    );
    final custom = json['customBackgroundArgb'];
    final shadow = json['shadowColorArgb'];
    final titleSizeRelative = json['titleSizeRelative'] is bool
        ? json['titleSizeRelative']! as bool
        : true;
    final legacyLeft = _footerLeft(json['footerLeft']);
    final legacyRight = _footerRight(json['footerRight']);
    final legacySlots = <NovelChromeSlot>[
      _fromLegacyLeft(legacyLeft),
      NovelChromeSlot.none,
      _fromLegacyRight(legacyRight),
    ];
    return NovelReaderSettings(
      fontSize: _clampDouble(
        _double(json['fontSize'], 20),
        minFontSize,
        maxFontSize,
      ),
      fontFamily: '${json['fontFamily'] ?? ''}',
      lineHeight: _clampDouble(
        _double(json['lineHeight'], 1.8),
        minLineHeight,
        maxLineHeight,
      ),
      paragraphSpacing: _clampDouble(
        _double(json['paragraphSpacing'], 12),
        minParagraphSpacing,
        maxParagraphSpacing,
      ),
      horizontalPadding: _clampDouble(
        _double(json['horizontalPadding'], 24),
        minHorizontalPadding,
        maxHorizontalPadding,
      ),
      backgroundIndex:
          ((json['backgroundIndex'] is num)
                  ? (json['backgroundIndex']! as num).round()
                  : novelReaderDefaultBackground)
              .clamp(0, novelReaderBackgrounds.length - 1),
      customBackgroundArgb: custom is num ? custom.toInt() : null,
      dimBrightness:
          ((json['dimBrightness'] is num)
                  ? (json['dimBrightness']! as num).round()
                  : 100)
              .clamp(20, 100),
      pageMode: mode,
      pageAnimation: json['pageAnimation'] is bool
          ? json['pageAnimation']! as bool
          : true,
      pageAnimStyle: _enumByName(
        NovelPageAnimStyle.values,
        json['pageAnimStyle'],
        NovelPageAnimStyle.slide,
      ),
      pageAnimationMs:
          ((json['pageAnimationMs'] is num)
                  ? (json['pageAnimationMs']! as num).round()
                  : 260)
              .clamp(80, 600),
      clickZones: _parseClickZones(json['clickZones']),
      longPressAction: _enumByName(
        NovelLongPressAction.values,
        json['longPressAction'],
        NovelLongPressAction.selectText,
      ),
      doubleTapAction: _enumByName(
        NovelDoubleTapAction.values,
        json['doubleTapAction'],
        NovelDoubleTapAction.none,
      ),
      swipeDownBookmark: json['swipeDownBookmark'] is bool
          ? json['swipeDownBookmark']! as bool
          : false,
      autoPageSeconds:
          ((json['autoPageSeconds'] is num)
                  ? (json['autoPageSeconds']! as num).round()
                  : 15)
              .clamp(minAutoPageSeconds, maxAutoPageSeconds),
      showFooter: json['showFooter'] is bool
          ? json['showFooter']! as bool
          : true,
      footerLeft: legacyLeft,
      footerRight: legacyRight,
      eyeProtection: json['eyeProtection'] is bool
          ? json['eyeProtection']! as bool
          : false,
      autoBrightness: json['autoBrightness'] is bool
          ? json['autoBrightness']! as bool
          : false,
      textAlignJustify: _bool(json['textAlignJustify'], false),
      letterSpacing: _clampDouble(
        _double(json['letterSpacing'], 0),
        minLetterSpacing,
        maxLetterSpacing,
      ),
      textBold: _bool(json['textBold'], false),
      textItalic: _bool(json['textItalic'], false),
      indentCount:
          ((json['indentCount'] is num)
                  ? (json['indentCount']! as num).round()
                  : 2)
              .clamp(minIndentCount, maxIndentCount),
      lineHeightIncludesPadding: _bool(json['lineHeightIncludesPadding'], true),
      titleMode: _enumByName(
        NovelTitleMode.values,
        json['titleMode'],
        NovelTitleMode.left,
      ),
      titleSize: _clampDouble(
        _double(json['titleSize'], 6),
        minTitleSize,
        titleSizeRelative ? maxTitleSizeRelative : maxTitleSizeAbsolute,
      ),
      titleSizeRelative: titleSizeRelative,
      titleTopSpacing: _clampDouble(
        _double(json['titleTopSpacing'], 4),
        minTitleSpacing,
        maxTitleSpacing,
      ),
      titleBottomSpacing: _clampDouble(
        _double(json['titleBottomSpacing'], 18),
        minTitleSpacing,
        maxTitleSpacing,
      ),
      titleSegment: _bool(json['titleSegment'], false),
      titleSegmentDivider: '${json['titleSegmentDivider'] ?? '·'}',
      titleSegmentScale: _clampDouble(
        _double(json['titleSegmentScale'], 0.7),
        minTitleSegmentScale,
        maxTitleSegmentScale,
      ),
      shadowRadius: _clampDouble(
        _double(json['shadowRadius'], 0),
        minShadowRadius,
        maxShadowRadius,
      ),
      shadowOffsetX: _clampDouble(
        _double(json['shadowOffsetX'], 0),
        minShadowOffset,
        maxShadowOffset,
      ),
      shadowOffsetY: _clampDouble(
        _double(json['shadowOffsetY'], 1),
        minShadowOffset,
        maxShadowOffset,
      ),
      shadowColorArgb: shadow is num ? shadow.toInt() : null,
      underlineStyle: _enumByName(
        NovelUnderlineStyle.values,
        json['underlineStyle'],
        NovelUnderlineStyle.none,
      ),
      underlineThickness: _clampDouble(
        _double(json['underlineThickness'], 1),
        minUnderlineThickness,
        maxUnderlineThickness,
      ),
      underlineSpacing: _clampDouble(
        _double(json['underlineSpacing'], 2),
        minUnderlineSpacing,
        maxUnderlineSpacing,
      ),
      underlineExtend: _bool(json['underlineExtend'], false),
      showHeader: _bool(json['showHeader'], false),
      headerSlots: _slots(json['headerSlots'], const <NovelChromeSlot>[
        NovelChromeSlot.none,
        NovelChromeSlot.chapter,
        NovelChromeSlot.none,
      ]),
      footerSlots: json['footerSlots'] == null
          ? null
          : _slots(json['footerSlots'], legacySlots),
      headerCustomText: '${json['headerCustomText'] ?? ''}',
      footerCustomText: '${json['footerCustomText'] ?? ''}',
      headerFontSize: _clampDouble(
        _double(json['headerFontSize'], 12),
        minChromeFontSize,
        maxChromeFontSize,
      ),
      footerFontSize: _clampDouble(
        _double(json['footerFontSize'], 12),
        minChromeFontSize,
        maxChromeFontSize,
      ),
      backgroundImagePath: _stringOrNull(json['backgroundImagePath']),
      backgroundImageFit: _enumByName(
        NovelBackgroundFit.values,
        json['backgroundImageFit'],
        NovelBackgroundFit.cover,
      ),
      backgroundImageOpacity:
          ((json['backgroundImageOpacity'] is num)
                  ? (json['backgroundImageOpacity']! as num).round()
                  : 100)
              .clamp(minBackgroundImageOpacity, maxBackgroundImageOpacity),
      backgroundImageAlign: _enumByName(
        NovelBackgroundAlign.values,
        json['backgroundImageAlign'],
        NovelBackgroundAlign.center,
      ),
      backgroundTexture: _enumByName(
        NovelBackgroundTexture.values,
        json['backgroundTexture'],
        NovelBackgroundTexture.none,
      ),
      chineseConvert: _enumByName(
        NovelChineseConvert.values,
        json['chineseConvert'],
        NovelChineseConvert.none,
      ),
      twoColumn: _bool(json['twoColumn'], false),
      menuIconItemsPerRow:
          ((json['menuIconItemsPerRow'] is num)
                  ? (json['menuIconItemsPerRow']! as num).round()
                  : 5)
              .clamp(minMenuIconItemsPerRow, maxMenuIconItemsPerRow),
      menuIconRowCount:
          ((json['menuIconRowCount'] is num)
                  ? (json['menuIconRowCount']! as num).round()
                  : 1)
              .clamp(minMenuIconRowCount, maxMenuIconRowCount),
      menuBottomRadius:
          ((json['menuBottomRadius'] is num)
                  ? (json['menuBottomRadius']! as num).round()
                  : 32)
              .clamp(minMenuBottomRadius, maxMenuBottomRadius),
      menuShowIconText: _bool(json['menuShowIconText'], false),
      titleBarCompact: _bool(json['titleBarCompact'], false),
      // 缺键 = 走默认；显式空列表 = 用户把这一行清空了，两者必须区分开。
      titleBarMenu: json.containsKey('titleBarMenu')
          ? NovelMenuButtonItem.listFromJson(json['titleBarMenu'])
          : null,
      bottomBarMenu: json.containsKey('bottomBarMenu')
          ? NovelMenuButtonItem.listFromJson(json['bottomBarMenu'])
          : null,
      floatingBarMenu: json.containsKey('floatingBarMenu')
          ? NovelMenuButtonItem.listFromJson(json['floatingBarMenu'])
          : null,
    );
  }

  static NovelFooterLeft _footerLeft(Object? raw) {
    if (raw is String) {
      for (final value in NovelFooterLeft.values) {
        if (value.name == raw) return value;
      }
    }
    return NovelFooterLeft.chapter;
  }

  static NovelFooterRight _footerRight(Object? raw) {
    if (raw is String) {
      for (final value in NovelFooterRight.values) {
        if (value.name == raw) return value;
      }
    }
    return NovelFooterRight.pageAndPercent;
  }

  static NovelChromeSlot _fromLegacyLeft(NovelFooterLeft value) =>
      switch (value) {
        NovelFooterLeft.chapter => NovelChromeSlot.chapter,
        NovelFooterLeft.book => NovelChromeSlot.book,
        NovelFooterLeft.none => NovelChromeSlot.none,
      };

  static NovelChromeSlot _fromLegacyRight(NovelFooterRight value) =>
      switch (value) {
        NovelFooterRight.pageAndPercent => NovelChromeSlot.pageAndPercent,
        NovelFooterRight.page => NovelChromeSlot.page,
        NovelFooterRight.percent => NovelChromeSlot.percent,
        NovelFooterRight.none => NovelChromeSlot.none,
      };

  static NovelFooterLeft _toLegacyLeft(NovelChromeSlot slot) => switch (slot) {
    NovelChromeSlot.chapter => NovelFooterLeft.chapter,
    NovelChromeSlot.book => NovelFooterLeft.book,
    _ => NovelFooterLeft.none,
  };

  static NovelFooterRight _toLegacyRight(NovelChromeSlot slot) =>
      switch (slot) {
        NovelChromeSlot.pageAndPercent => NovelFooterRight.pageAndPercent,
        NovelChromeSlot.page => NovelFooterRight.page,
        NovelChromeSlot.percent => NovelFooterRight.percent,
        _ => NovelFooterRight.none,
      };

  static List<NovelChromeSlot> _normalizeSlots(List<NovelChromeSlot> slots) {
    final result = List<NovelChromeSlot>.filled(3, NovelChromeSlot.none);
    for (var i = 0; i < 3 && i < slots.length; i++) {
      result[i] = slots[i];
    }
    return List<NovelChromeSlot>.unmodifiable(result);
  }

  /// 解析九宫格：缺键返回 null（走默认），坏值逐格降级为无动作。
  static List<NovelClickAction>? _parseClickZones(Object? raw) {
    if (raw is! List) return null;
    final result = <NovelClickAction>[];
    for (final item in raw) {
      result.add(
        _enumByName(NovelClickAction.values, item, NovelClickAction.none),
      );
    }
    return normalizeClickZones(result);
  }

  static List<NovelChromeSlot> _slots(
    Object? raw,
    List<NovelChromeSlot> fallback,
  ) {
    if (raw is List) {
      final result = <NovelChromeSlot>[];
      for (final item in raw) {
        result.add(
          _enumByName(NovelChromeSlot.values, item, NovelChromeSlot.none),
        );
      }
      if (result.isNotEmpty) return _normalizeSlots(result);
    }
    return _normalizeSlots(fallback);
  }

  String serialize() => jsonEncode(toJson());

  static NovelReaderSettings deserialize(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return fromJson(decoded);
    } on Object {
      // 坏数据回退默认值，不让设置把阅读器卡死。
    }
    return const NovelReaderSettings();
  }

  static double _double(Object? value, double fallback) =>
      value is num ? value.toDouble() : fallback;

  static bool _bool(Object? value, bool fallback) =>
      value is bool ? value : fallback;

  static String? _stringOrNull(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return value;
  }

  static double _clampDouble(double value, double min, double max) =>
      value.clamp(min, max);

  static T _enumByName<T extends Enum>(
    List<T> values,
    Object? raw,
    T fallback,
  ) {
    if (raw is String) {
      for (final value in values) {
        if (value.name == raw) return value;
      }
    }
    return fallback;
  }

  static bool _isDarkColor(int argb) {
    final r = (argb >> 16) & 0xFF;
    final g = (argb >> 8) & 0xFF;
    final b = argb & 0xFF;
    // ITU-R BT.601 亮度，> 0.55 视为浅底。
    return (0.299 * r + 0.587 * g + 0.114 * b) / 255 <= 0.55;
  }
}

/// 设置读写端口：由阅读页用模块 kv 实现，测试可用内存实现。
abstract interface class NovelReaderSettingsStore {
  Future<NovelReaderSettings> load();
  Future<void> save(NovelReaderSettings settings);
}

/// 每书覆盖允许的字段：背景 / 字体 / 翻页方式 / 动画 / 点击区。
///
/// 只放「这本书看起来不一样」的项；行距、页眉页脚这类排版细节仍走全局，
/// 免得覆盖面越滚越大、用户搞不清哪项是哪层生效的。
const List<String> novelBookOverrideFields = <String>[
  'fontSize',
  'fontFamily',
  'backgroundIndex',
  'customBackgroundArgb',
  'backgroundImagePath',
  'backgroundImageFit',
  'backgroundImageOpacity',
  'backgroundImageAlign',
  'pageMode',
  'pageAnimation',
  'pageAnimStyle',
  'pageAnimationMs',
  'clickZones',
];

/// 算出 [effective] 里与 [global] 不同的可覆盖字段（部分 JSON）。
///
/// 这是「每书覆盖只存差异」的唯一实现：整份复制会让用户以后改全局时，
/// 每书那份旧快照把改动吃掉。空 map 表示与全局完全一致。
Map<String, Object?> diffNovelReaderSettings(
  NovelReaderSettings global,
  NovelReaderSettings effective,
) {
  final globalJson = global.toJson();
  final effectiveJson = effective.toJson();
  final result = <String, Object?>{};
  for (final field in novelBookOverrideFields) {
    final before = globalJson[field];
    final after = effectiveJson[field];
    if (!_novelJsonEquals(before, after)) result[field] = after;
  }
  return result;
}

/// 算出两份设置之间的全部字段差异（部分 JSON，不限于可覆盖字段）。
///
/// 设置面板展示的是「每书 > 全局」叠加后的生效值；用户在面板里改一项时，
/// 只有这一项该写进全局，不能把整份生效值（含每书覆盖）当新全局。
Map<String, Object?> diffNovelReaderSettingsAllFields(
  NovelReaderSettings before,
  NovelReaderSettings after,
) {
  final beforeJson = before.toJson();
  final afterJson = after.toJson();
  final result = <String, Object?>{};
  for (final entry in afterJson.entries) {
    if (!_novelJsonEquals(beforeJson[entry.key], entry.value)) {
      result[entry.key] = entry.value;
    }
  }
  return result;
}

/// 把一份部分 JSON 叠到设置上（缺的字段沿用 [base]）。
NovelReaderSettings applyNovelReaderSettingsJson(
  NovelReaderSettings base,
  Map<String, Object?> partial,
) {
  if (partial.isEmpty) return base;
  return NovelReaderSettings.fromJson(<String, Object?>{
    ...base.toJson(),
    ...partial,
  });
}

/// 把每书覆盖叠到全局设置上（每书 > 全局 > 默认）。///
/// [override] 只含差异字段；不在 [novelBookOverrideFields] 里的键一律忽略，
/// 坏值由 [NovelReaderSettings.fromJson] 逐项回退默认并 clamp。
NovelReaderSettings mergeNovelBookOverride(
  NovelReaderSettings global,
  Map<String, Object?> override,
) {
  if (override.isEmpty) return global;
  final merged = <String, Object?>{...global.toJson()};
  for (final field in novelBookOverrideFields) {
    if (override.containsKey(field)) merged[field] = override[field];
  }
  return NovelReaderSettings.fromJson(merged);
}

/// 解析一条覆盖 JSON（kv 里存的是 `{bookId: {...}}` 的其中一个值）。
Map<String, Object?> parseNovelBookOverride(Object? raw) {
  if (raw is Map) {
    return <String, Object?>{
      for (final entry in raw.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }
  return const <String, Object?>{};
}

bool _novelJsonEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_novelJsonEquals(a[i], b[i])) return false;
    }
    return true;
  }
  // 菜单配置是 List<Map>，Map 的 == 是引用比较，必须逐键比内容。
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (!b.containsKey(entry.key)) return false;
      if (!_novelJsonEquals(entry.value, b[entry.key])) return false;
    }
    return true;
  }
  return a == b;
}

/// 每书覆盖存储：一条 kv 存 `{bookId: 部分 JSON}`。
///
/// 与全局设置分两个键存，互不覆盖；[prefs] 为空时读写都落在内存里。
class NovelBookSettingsStore {
  NovelBookSettingsStore(this.prefs);

  final NovelPrefsApi? prefs;

  static const String key = novelPrefReaderBookSettings;

  final Map<String, Map<String, Object?>> _memory =
      <String, Map<String, Object?>>{};

  Future<Map<String, Object?>> load(String bookId) async {
    final all = await _readAll();
    return Map<String, Object?>.unmodifiable(
      all[bookId] ?? const <String, Object?>{},
    );
  }

  /// 保存这本书的差异；空 map 等于清掉覆盖。
  Future<void> save(String bookId, Map<String, Object?> partial) async {
    final all = await _readAll();
    if (partial.isEmpty) {
      all.remove(bookId);
    } else {
      all[bookId] = <String, Object?>{
        for (final field in novelBookOverrideFields)
          if (partial.containsKey(field)) field: partial[field],
      };
    }
    await _writeAll(all);
  }

  Future<void> clear(String bookId) async {
    final all = await _readAll();
    all.remove(bookId);
    await _writeAll(all);
  }

  /// 有覆盖的书 id（设置页提示「这本书有独立设置」用）。
  Future<Set<String>> bookIds() async => (await _readAll()).keys.toSet();

  /// 读全量覆盖表。
  ///
  /// 恒返回**新** map：调用方会就地增删再交给 [_writeAll]，
  /// 若直接把内部缓存交出去，`_memory..clear()..addAll(同一个 map)` 会把
  /// 刚写进去的内容一起清掉（写一次就丢一次）。
  Future<Map<String, Map<String, Object?>>> _readAll() async {
    final api = prefs;
    if (api == null) return _copyAll(_memory);
    try {
      final raw = await api.read(key);
      if (raw == null || raw.isEmpty) return _copyAll(_memory);
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return _copyAll(_memory);
      final result = <String, Map<String, Object?>>{};
      for (final entry in decoded.entries) {
        final bookId = entry.key;
        if (bookId is! String || bookId.isEmpty) continue;
        result[bookId] = parseNovelBookOverride(entry.value);
      }
      _memory
        ..clear()
        ..addAll(result);
      return _copyAll(result);
    } on Object {
      return _copyAll(_memory);
    }
  }

  static Map<String, Map<String, Object?>> _copyAll(
    Map<String, Map<String, Object?>> source,
  ) => <String, Map<String, Object?>>{
    for (final entry in source.entries)
      entry.key: Map<String, Object?>.from(entry.value),
  };

  Future<void> _writeAll(Map<String, Map<String, Object?>> all) async {
    _memory
      ..clear()
      ..addAll(all);
    final api = prefs;
    if (api == null) return;
    try {
      await api.write(key, jsonEncode(all));
    } on Object {
      // 写失败不影响本次阅读。
    }
  }
}

/// 模块 kv 版设置存储；[prefs] 为空时读写都落在内存里（测试/依赖未注入）。
class PrefsNovelReaderSettingsStore implements NovelReaderSettingsStore {
  PrefsNovelReaderSettingsStore(this.prefs);

  final NovelPrefsApi? prefs;

  static const String key = novelPrefReaderSettings;

  NovelReaderSettings _memory = const NovelReaderSettings();

  @override
  Future<NovelReaderSettings> load() async {
    final api = prefs;
    if (api == null) return _memory;
    try {
      final raw = await api.read(key);
      if (raw == null || raw.isEmpty) {
        // 老版本只存了字号：首次升级时迁移过来，避免字号静默回落到默认 20。
        final legacy = double.tryParse(
          await api.read(novelPrefReaderFontSize) ?? '',
        );
        if (legacy != null) {
          return NovelReaderSettings(
            fontSize: legacy.clamp(
              NovelReaderSettings.minFontSize,
              NovelReaderSettings.maxFontSize,
            ),
          );
        }
        return const NovelReaderSettings();
      }
      return NovelReaderSettings.deserialize(raw);
    } on Object {
      return const NovelReaderSettings();
    }
  }

  @override
  Future<void> save(NovelReaderSettings settings) async {
    _memory = settings;
    final api = prefs;
    if (api == null) return;
    try {
      await api.write(key, settings.serialize());
    } on Object {
      // 写失败不影响本次阅读；下次进入仍是上一次成功保存的设置。
    }
  }
}

/// 内存版（测试用）。
class MemoryNovelReaderSettingsStore implements NovelReaderSettingsStore {
  MemoryNovelReaderSettingsStore([
    this._settings = const NovelReaderSettings(),
  ]);

  NovelReaderSettings _settings;

  @override
  Future<NovelReaderSettings> load() async => _settings;

  @override
  Future<void> save(NovelReaderSettings settings) async => _settings = settings;
}
