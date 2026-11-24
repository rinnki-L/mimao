// 阅读设置的纯数据模型：可序列化到模块 kv，不认识 Widget。
//
// 对照「阅读（legado）」的阅读界面：字号 / 字体 / 背景预设 / 行距 / 段距 /
// 左右边距 / 翻页方式 / 自动翻页间隔 / 阅读亮度。背景色是用户自选色板，
// 属于「覆盖在阅读画布上的自定义颜色」，不走 ColorScheme 角色（与漫画阅读器
// 的亮度遮罩同款例外）。

import 'dart:convert';

import 'package:mimao/novel/library_api.dart'
    show NovelPrefsApi, novelPrefReaderFontSize, novelPrefReaderSettings;

/// 翻页方式：上下滚动（默认）/ 左右翻页。
enum NovelPageMode { scroll, page }

/// 页脚左槽内容（对照 legado 的 tipFooterLeft）。
enum NovelFooterLeft {
  chapter('章节标题'),
  book('书名'),
  none('无');

  const NovelFooterLeft(this.label);

  final String label;
}

/// 页脚右槽内容（对照 legado 的 tipFooterRight）。
enum NovelFooterRight {
  pageAndPercent('页码 + 进度'),
  page('页码'),
  percent('进度'),
  none('无');

  const NovelFooterRight(this.label);

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
/// app 其余界面仍锁 [MimaoFonts.family]。
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
    this.pageAnimationMs = 260,
    this.autoPageSeconds = 15,
    this.showFooter = true,
    this.footerLeft = NovelFooterLeft.chapter,
    this.footerRight = NovelFooterRight.pageAndPercent,
    this.eyeProtection = false,
    this.autoBrightness = false,
  });

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

  /// 正文字号（逻辑像素，与截图里的 20 对齐）。
  final double fontSize;

  /// 正文字体族；空串 = 跟随 app 默认（雅黑）。
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

  /// 翻页动画时长（毫秒，对应 legado 的「翻页动画速度」）。
  final int pageAnimationMs;

  /// 自动翻页间隔（秒）。
  final int autoPageSeconds;

  /// 是否显示页脚（章节名 + 页码 + 全书进度）。
  final bool showFooter;

  /// 页脚左槽：章节标题 / 书名 / 无。
  final NovelFooterLeft footerLeft;

  /// 页脚右槽：页码 + 进度 / 页码 / 进度 / 无。
  final NovelFooterRight footerRight;

  /// 护眼模式（暖色滤光层）。
  final bool eyeProtection;

  /// 自动亮度（仅 Android 有意义；桌面端隐藏该按钮）。
  final bool autoBrightness;

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

  NovelReaderSettings copyWith({
    double? fontSize,
    String? fontFamily,
    double? lineHeight,
    double? paragraphSpacing,
    double? horizontalPadding,
    int? backgroundIndex,
    int? dimBrightness,
    NovelPageMode? pageMode,
    bool? pageAnimation,
    int? pageAnimationMs,
    int? autoPageSeconds,
    bool? showFooter,
    NovelFooterLeft? footerLeft,
    NovelFooterRight? footerRight,
    bool? eyeProtection,
    bool? autoBrightness,
  }) => NovelReaderSettings(
    fontSize: _clampDouble(fontSize ?? this.fontSize, minFontSize, maxFontSize),
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
    customBackgroundArgb: customBackgroundArgb,
    dimBrightness: (dimBrightness ?? this.dimBrightness).clamp(20, 100),
    pageMode: pageMode ?? this.pageMode,
    pageAnimation: pageAnimation ?? this.pageAnimation,
    pageAnimationMs: (pageAnimationMs ?? this.pageAnimationMs).clamp(80, 600),
    autoPageSeconds: (autoPageSeconds ?? this.autoPageSeconds).clamp(
      minAutoPageSeconds,
      maxAutoPageSeconds,
    ),
    showFooter: showFooter ?? this.showFooter,
    footerLeft: footerLeft ?? this.footerLeft,
    footerRight: footerRight ?? this.footerRight,
    eyeProtection: eyeProtection ?? this.eyeProtection,
    autoBrightness: autoBrightness ?? this.autoBrightness,
  );

  /// 选一个内置背景（清掉自定义色）。
  NovelReaderSettings useBackground(int index) => NovelReaderSettings(
    fontSize: fontSize,
    fontFamily: fontFamily,
    lineHeight: lineHeight,
    paragraphSpacing: paragraphSpacing,
    horizontalPadding: horizontalPadding,
    backgroundIndex: index,
    customBackgroundArgb: null,
    dimBrightness: dimBrightness,
    pageMode: pageMode,
    pageAnimation: pageAnimation,
    pageAnimationMs: pageAnimationMs,
    autoPageSeconds: autoPageSeconds,
    showFooter: showFooter,
    footerLeft: footerLeft,
    footerRight: footerRight,
    eyeProtection: eyeProtection,
    autoBrightness: autoBrightness,
  );

  /// 用自定义色作为背景（长按色板触发）。
  NovelReaderSettings useCustomBackground(int argb) => NovelReaderSettings(
    fontSize: fontSize,
    fontFamily: fontFamily,
    lineHeight: lineHeight,
    paragraphSpacing: paragraphSpacing,
    horizontalPadding: horizontalPadding,
    backgroundIndex: backgroundIndex,
    customBackgroundArgb: argb,
    dimBrightness: dimBrightness,
    pageMode: pageMode,
    pageAnimation: pageAnimation,
    pageAnimationMs: pageAnimationMs,
    autoPageSeconds: autoPageSeconds,
    showFooter: showFooter,
    footerLeft: footerLeft,
    footerRight: footerRight,
    eyeProtection: eyeProtection,
    autoBrightness: autoBrightness,
  );

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
    'pageAnimationMs': pageAnimationMs,
    'autoPageSeconds': autoPageSeconds,
    'showFooter': showFooter,
    'footerLeft': footerLeft.name,
    'footerRight': footerRight.name,
    'eyeProtection': eyeProtection,
    'autoBrightness': autoBrightness,
  };

  static NovelReaderSettings fromJson(Map<String, Object?> json) {
    NovelPageMode mode;
    try {
      mode = NovelPageMode.values.byName(
        (json['pageMode'] as String?) ?? NovelPageMode.scroll.name,
      );
    } on ArgumentError {
      mode = NovelPageMode.scroll;
    }
    final custom = json['customBackgroundArgb'];
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
      pageAnimationMs:
          ((json['pageAnimationMs'] is num)
                  ? (json['pageAnimationMs']! as num).round()
                  : 260)
              .clamp(80, 600),
      autoPageSeconds:
          ((json['autoPageSeconds'] is num)
                  ? (json['autoPageSeconds']! as num).round()
                  : 15)
              .clamp(minAutoPageSeconds, maxAutoPageSeconds),
      showFooter: json['showFooter'] is bool
          ? json['showFooter']! as bool
          : true,
      footerLeft: _footerLeft(json['footerLeft']),
      footerRight: _footerRight(json['footerRight']),
      eyeProtection: json['eyeProtection'] is bool
          ? json['eyeProtection']! as bool
          : false,
      autoBrightness: json['autoBrightness'] is bool
          ? json['autoBrightness']! as bool
          : false,
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

  static double _clampDouble(double value, double min, double max) =>
      value.clamp(min, max);

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
