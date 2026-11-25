/// 页面依赖的在线书源能力面（比 [NovelEngine] 多源列表与发现分类）。
///
/// `NovelEngine` 是窄接口（单源 + 统一 BookSource），页面还需要「按某个已导入
/// 的 legado 源搜索/发现/取详情」这些带 `NovelBookSource` 的入口；两套接口
/// 并存，测试可只实现本接口做页面 fake。
library;

import 'package:mimao/novel/debug/novel_engine_trace.dart';
import 'package:mimao/novel/engine/explore_kinds.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/source/novel_source_model.dart';

abstract interface class NovelOnlineEngine {
  Future<List<NovelSummary>> searchSource(
    NovelBookSource source,
    String keyword, {
    int page = 1,
  });

  Future<List<NovelExploreKind>> exploreKinds(NovelBookSource source);

  Future<List<NovelSummary>> exploreSource(
    NovelBookSource source,
    NovelExploreKind kind, {
    int page = 1,
  });

  Future<NovelDetail> bookDetail(
    NovelBookSource source,
    NovelRef ref, {
    String? titleHint,
    String? authorHint,
  });

  Future<NovelContent> contentFor(
    NovelBookSource source,
    NovelRef ref,
    NovelChapter chapter,
  );

  /// 释放网络/JS 资源（页面不调用；由装配方在退出时调用）。
  void close();
}

/// 可选能力：忽略正文缓存重抓（阅读页「刷新本章」用）。
///
/// 单独成接口而不是给 [NovelOnlineEngine.contentFor] 加参数，
/// 是为了不强迫所有 fake 引擎跟着改签名；页面按类型探测能力。
abstract interface class NovelContentRefresh {
  Future<NovelContent> refreshContent(
    NovelBookSource source,
    NovelRef ref,
    NovelChapter chapter,
  );
}

/// 可选能力：把引擎的执行过程抛给调试观察者（书源调试面板用）。
///
/// 调试会话 `attachTrace(sink)` → 跑流水线 → `attachTrace(null)`；引擎在生产
/// 路径上默认没有 sink，只多一次 null 判断。同一实例既跑真实阅读又跑调试，
/// 所以调出来的现象与真实行为一致（不给调试另写解析路径）。
abstract interface class NovelEngineTraceable {
  /// 挂上/摘掉观察者（null = 摘掉）。
  void attachTrace(NovelTraceSink? sink);

  /// 标记一个新阶段（搜索 / 详情 / 目录 / 正文），后续事件带上相对耗时。
  void beginTracePhase(String phase);
}

/// 可选能力：某书源最近一次非致命警告（如 WebView 降级、字段暂不支持）。
///
/// 引擎实现该接口后，阅读页可在「书籍信息」里展示；不实现也不影响阅读。
abstract interface class NovelEngineWarnings {
  String? warningFor(String sourceKey);
}
