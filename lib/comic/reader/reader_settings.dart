// 阅读设置的纯数据模型——可序列化到 SettingsRepository 的 kv，不认识 Widget。
//
// 对齐 Venera Next 的设置项，但只保留"用 Flutter 原生能力就能做、且用户
// 肉眼可见价值高"的那些。长按/双击缩放、每屏图数、翻页动画等全部覆盖，
// 避免依赖 photo_view / scrollable_positioned_list 等第三方库。

import 'dart:convert';

import 'reader_view_mode.dart';

/// 一次阅读设置的完整快照（不可变；改设置用 copyWith 产生新对象）。
class ReaderSettings {
  const ReaderSettings({
    this.mode = ReaderViewMode.waterfallTopToBottom,
    this.autoLayout = false,
    this.imagesPerPage = 1,
    this.singleImageOnFirstPage = true,
    this.tapToTurnPages = true,
    this.reverseTapToTurnPages = false,
    this.pageAnimation = true,
    this.doubleTapToZoom = true,
    this.longPressToZoom = true,
    this.showPageNumber = true,
    this.scrollSpeed = 1.0,
    this.preloadCount = 3,
    this.limitImageWidth = true,
    this.sideMargin = 0,
    this.autoReadingInterval = 8,
    this.dimBrightness = 100,
  });

  final ReaderViewMode mode;

  /// 按图片宽高比自动切换阅读模式（只影响本次打开，不改保存的默认模式）。
  final bool autoLayout;
  final int imagesPerPage; // 分页模式每屏图数 1~5；连续/瀑布强制为 1
  final bool singleImageOnFirstPage;
  final bool tapToTurnPages;
  final bool reverseTapToTurnPages;
  final bool pageAnimation;
  final bool doubleTapToZoom;
  final bool longPressToZoom;
  final bool showPageNumber;
  final double scrollSpeed; // 连续模式滚轮/自动滚速度系数 0.5~3
  final int preloadCount; // 预加载图片数 1~16
  final bool limitImageWidth; // 纵向连续/瀑布限制长条图宽度
  final int sideMargin; // 纵向条漫左右留白百分比 0~30（每侧）
  final int autoReadingInterval; // 自动翻页秒数 1~20
  final int dimBrightness; // 阅读内遮罩亮度 20~100（100 = 不压暗）

  ReaderSettings copyWith({
    ReaderViewMode? mode,
    bool? autoLayout,
    int? imagesPerPage,
    bool? singleImageOnFirstPage,
    bool? tapToTurnPages,
    bool? reverseTapToTurnPages,
    bool? pageAnimation,
    bool? doubleTapToZoom,
    bool? longPressToZoom,
    bool? showPageNumber,
    double? scrollSpeed,
    int? preloadCount,
    bool? limitImageWidth,
    int? sideMargin,
    int? autoReadingInterval,
    int? dimBrightness,
  }) => ReaderSettings(
    mode: mode ?? this.mode,
    autoLayout: autoLayout ?? this.autoLayout,
    imagesPerPage: imagesPerPage ?? this.imagesPerPage,
    singleImageOnFirstPage:
        singleImageOnFirstPage ?? this.singleImageOnFirstPage,
    tapToTurnPages: tapToTurnPages ?? this.tapToTurnPages,
    reverseTapToTurnPages: reverseTapToTurnPages ?? this.reverseTapToTurnPages,
    pageAnimation: pageAnimation ?? this.pageAnimation,
    doubleTapToZoom: doubleTapToZoom ?? this.doubleTapToZoom,
    longPressToZoom: longPressToZoom ?? this.longPressToZoom,
    showPageNumber: showPageNumber ?? this.showPageNumber,
    scrollSpeed: scrollSpeed ?? this.scrollSpeed,
    preloadCount: preloadCount ?? this.preloadCount,
    limitImageWidth: limitImageWidth ?? this.limitImageWidth,
    sideMargin: sideMargin ?? this.sideMargin,
    autoReadingInterval: autoReadingInterval ?? this.autoReadingInterval,
    dimBrightness: dimBrightness ?? this.dimBrightness,
  );

  /// 该模式下每屏实际图数：连续/瀑布恒为 1。
  int get effectiveImagesPerPage =>
      mode.isContinuous || mode.isWaterfall ? 1 : imagesPerPage.clamp(1, 5);

  Map<String, Object?> toJson() => <String, Object?>{
    'mode': mode.name,
    'autoLayout': autoLayout,
    'imagesPerPage': imagesPerPage,
    'singleImageOnFirstPage': singleImageOnFirstPage,
    'tapToTurnPages': tapToTurnPages,
    'reverseTapToTurnPages': reverseTapToTurnPages,
    'pageAnimation': pageAnimation,
    'doubleTapToZoom': doubleTapToZoom,
    'longPressToZoom': longPressToZoom,
    'showPageNumber': showPageNumber,
    'scrollSpeed': scrollSpeed,
    'preloadCount': preloadCount,
    'limitImageWidth': limitImageWidth,
    'sideMargin': sideMargin,
    'autoReadingInterval': autoReadingInterval,
    'dimBrightness': dimBrightness,
  };

  static ReaderSettings fromJson(Map<String, Object?> json) {
    ReaderViewMode mode;
    try {
      mode = ReaderViewMode.values.byName(
        (json['mode'] as String?) ?? ReaderViewMode.waterfallTopToBottom.name,
      );
    } on ArgumentError {
      mode = ReaderViewMode.waterfallTopToBottom;
    }
    return ReaderSettings(
      mode: mode,
      autoLayout: _bool(json['autoLayout'], false),
      imagesPerPage: _int(json['imagesPerPage'], 1, 1, 5),
      singleImageOnFirstPage: _bool(json['singleImageOnFirstPage'], true),
      tapToTurnPages: _bool(json['tapToTurnPages'], true),
      reverseTapToTurnPages: _bool(json['reverseTapToTurnPages'], false),
      pageAnimation: _bool(json['pageAnimation'], true),
      doubleTapToZoom: _bool(json['doubleTapToZoom'], true),
      longPressToZoom: _bool(json['longPressToZoom'], true),
      showPageNumber: _bool(json['showPageNumber'], true),
      scrollSpeed: _double(json['scrollSpeed'], 1.0, 0.5, 3),
      preloadCount: _int(json['preloadCount'], 3, 1, 16),
      limitImageWidth: _bool(json['limitImageWidth'], true),
      sideMargin: _int(json['sideMargin'], 0, 0, 30),
      autoReadingInterval: _int(json['autoReadingInterval'], 8, 1, 20),
      dimBrightness: _int(json['dimBrightness'], 100, 20, 100),
    );
  }

  String serialize() => jsonEncode(toJson());

  static ReaderSettings deserialize(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return fromJson(decoded);
    } on Object {
      // 坏数据回退默认值，不让设置把阅读器卡死。
    }
    return const ReaderSettings();
  }

  static bool _bool(Object? value, bool fallback) =>
      value is bool ? value : fallback;

  static int _int(Object? value, int fallback, int min, int max) {
    final v = value is num ? value.round() : fallback;
    return v.clamp(min, max);
  }

  static double _double(
    Object? value,
    double fallback,
    double min,
    double max,
  ) {
    final v = value is num ? value.toDouble() : fallback;
    return v.clamp(min, max);
  }
}

/// 设置读写端口：由集成层用 SettingsRepository 实现，测试可用内存实现。
abstract interface class ReaderSettingsStore {
  Future<ReaderSettings> load();
  Future<void> save(ReaderSettings settings);
}

/// 内存版（测试用）。
class MemoryReaderSettingsStore implements ReaderSettingsStore {
  MemoryReaderSettingsStore([this._settings = const ReaderSettings()]);

  ReaderSettings _settings;

  @override
  Future<ReaderSettings> load() async => _settings;

  @override
  Future<void> save(ReaderSettings settings) async => _settings = settings;
}
