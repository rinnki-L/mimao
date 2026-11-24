// 章节加载端口：瀑布流控制器唯一需要的 I/O 抽象。
//
// 控制器本身是纯 Dart（不认识源引擎 / 网络 / Widget），集成层用真实源把
// [ReaderChapterSource] 实现出来，单测注入假实现即可控制"何时返回、何时失败、
// 何时被取消"。
//
// [ReaderLoadScope] 是每次加载的取消令牌：跳章 / revision++ 时控制器取消旧
// scope，迟到的结果据此丢弃，不会插进已经翻页的流里。

import 'reader_models.dart';

/// 一次加载请求的作用域，用来取消迟到的异步结果。
class ReaderLoadScope {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;
}

/// 章节数据源：控制器唯一需要的 I/O。
///
/// 实现方（集成层）必须保证：
/// - [chapterId] 在 await 前同步返回，供控制器做"源切换 / 章节重排"的身份校验；
/// - [load] 在 [scope] 取消后尽快返回或抛错，避免无谓的网络/解析。
abstract interface class ReaderChapterSource {
  /// 总章数（含空章）。
  int get chapterCount;

  /// 1 基章号 → 稳定 epId；必须在 await 前同步返回。
  String chapterId(int chapter);

  /// 加载第 [chapter]（1 基）章的图片地址；[scope] 取消时应尽快抛错或返回空。
  Future<List<String>> load(int chapter, ReaderLoadScope scope);
}

/// 可选能力：直接返回带请求头的图片请求（防盗链 Referer/Cookie 等）。
///
/// 源引擎支持 `comic.onImageLoad` 时，生产适配层实现本接口；阅读器把
/// [ImageRequest] 原样存进章节流并交给图片缓存。未实现时控制器自动把
/// [ReaderChapterSource.load] 的地址包成无头请求。
abstract interface class ReaderImageRequestSource {
  /// 加载第 [chapter] 章的图片请求；[scope] 取消时应尽快抛错或返回空。
  Future<List<ImageRequest>> loadRequests(int chapter, ReaderLoadScope scope);
}
