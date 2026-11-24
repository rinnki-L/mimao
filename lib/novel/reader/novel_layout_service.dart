// 正文排版调度：把 TextPainter 分页从 build 里挪出来。
//
// 旧实现每帧在 LayoutBuilder 里同步跑整章分页，字号/窗口一变就卡一帧；
// 滚动模式也会白跑一遍。现在由阅读页把「可用尺寸 + 样式」交给这里：
// - 翻页模式：post-frame 空闲时排版，结果按 key 缓存（最近 4 章）；
// - 排版期间页面先显示轻量占位，完成后 notify 再换页；
// - 连续改字号只保留最后一次（去抖 + generation token 丢弃过期结果）。
//
// 这是「不阻塞 build」而不是「后台 isolate」：Flutter 的文字排版依赖
// dart:ui，放到 isolate 里反而拿不到字体，这里只做帧外调度。

import 'dart:async';
import 'dart:collection';

import 'package:flutter/painting.dart';
import 'package:flutter/scheduler.dart';
import 'package:mimao/novel/reader/novel_text_pagination.dart';

class NovelLayoutRequest {
  const NovelLayoutRequest({
    required this.key,
    required this.title,
    required this.paragraphs,
    required this.bodyStyle,
    required this.titleStyle,
    required this.maxWidth,
    required this.maxHeight,
    required this.paragraphSpacing,
    required this.titleSpacing,
    required this.textScaler,
    this.titleTopSpacing = 0,
    this.indent = '　　',
    this.bodyTextAlign = TextAlign.start,
    this.titleTextAlign = TextAlign.start,
    this.textHeightBehavior,
    this.kinsoku = true,
    this.columns = 1,
    this.columnGap = 24,
  });

  final String key;
  final String title;
  final List<String> paragraphs;
  final TextStyle bodyStyle;
  final TextStyle titleStyle;
  final double maxWidth;
  final double maxHeight;
  final double paragraphSpacing;
  final double titleSpacing;
  final TextScaler textScaler;
  final double titleTopSpacing;
  final String indent;
  final TextAlign bodyTextAlign;
  final TextAlign titleTextAlign;
  final TextHeightBehavior? textHeightBehavior;
  final bool kinsoku;
  final int columns;
  final double columnGap;
}

class NovelLayoutService {
  NovelLayoutService({
    this.cacheSize = 4,
    this.debounce = const Duration(milliseconds: 80),
  });

  final int cacheSize;
  final Duration debounce;

  final LinkedHashMap<String, List<NovelTextPage>> _cache =
      LinkedHashMap<String, List<NovelTextPage>>();
  Timer? _timer;
  int _generation = 0;

  List<NovelTextPage>? cached(String key) {
    final pages = _cache.remove(key);
    if (pages == null) return null;
    _cache[key] = pages; // 命中即刷新 LRU 顺序。
    return pages;
  }

  /// 调度一次排版；[immediate] 用于首屏（不等去抖）。
  ///
  /// 过期请求不会回调；同一 key 命中缓存时同步回调（仍在当前调用栈之外
  /// 由调用方决定是否 notify）。
  void schedule(
    NovelLayoutRequest request, {
    required void Function(String key, List<NovelTextPage> pages) onReady,
    bool immediate = false,
  }) {
    final generation = ++_generation;
    _timer?.cancel();

    final hit = cached(request.key);
    if (hit != null) {
      // 调用方可能正在 build（LayoutBuilder 里登记尺寸），必须帧后再回调，
      // 否则会出现在 build 期间 notifyListeners 的崩溃。
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (generation != _generation) return;
        onReady(request.key, hit);
      });
      SchedulerBinding.instance.scheduleFrame();
      return;
    }

    _timer = Timer(immediate ? Duration.zero : debounce, () {
      if (generation != _generation) return;
      // 放到帧后执行，先让「排版中」占位有机会绘制。
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (generation != _generation) return;
        final pages = NovelPaginator(
          title: request.title,
          paragraphs: request.paragraphs,
          bodyStyle: request.bodyStyle,
          titleStyle: request.titleStyle,
          maxWidth: request.maxWidth,
          maxHeight: request.maxHeight,
          paragraphSpacing: request.paragraphSpacing,
          titleSpacing: request.titleSpacing,
          titleTopSpacing: request.titleTopSpacing,
          titleBottomSpacing: request.titleSpacing,
          indent: request.indent,
          textScaler: request.textScaler,
          bodyTextAlign: request.bodyTextAlign,
          titleTextAlign: request.titleTextAlign,
          textHeightBehavior: request.textHeightBehavior,
          kinsoku: request.kinsoku,
          columns: request.columns,
          columnGap: request.columnGap,
        ).paginate();
        _cache.remove(request.key);
        _cache[request.key] = pages;
        while (_cache.length > cacheSize) {
          _cache.remove(_cache.keys.first);
        }
        onReady(request.key, pages);
      });
      SchedulerBinding.instance.scheduleFrame();
    });
  }

  void cancel() {
    _generation++;
    _timer?.cancel();
    _timer = null;
  }

  void clearCache() {
    _cache.clear();
    cancel();
  }
}
