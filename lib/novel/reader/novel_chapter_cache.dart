// 阅读会话内的相邻章正文缓存（LRU）。
//
// 目标：换章不再先清屏再等网络。打开一章后按「后 2 章、前 1 章」预取，
// 命中时同帧切换；未命中时保留当前正文、底部显示加载条，正文到了再原子
// 替换。缓存只在一次阅读会话内有效，落盘仍由引擎的 NovelCache 负责，
// 所以这里不做过期策略，只按字符预算淘汰。
//
// 预取/读取共用 [load]，同一章并发请求会合并成一次网络抓取。

import 'dart:collection';

import 'package:mimao/novel/engine/online_engine.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/source/novel_source_model.dart';

class NovelChapterCache {
  NovelChapterCache({this.maxChars = 1500000, this.maxEntries = 12});

  /// 正文字符预算；中文一章约 3k~8k 字，足够放几十章。
  final int maxChars;

  /// 条目上限，避免极短章节把表撑大。
  final int maxEntries;

  final LinkedHashMap<String, NovelContent> _entries =
      LinkedHashMap<String, NovelContent>();
  final Map<String, Future<NovelContent>> _inflight =
      <String, Future<NovelContent>>{};
  int _chars = 0;

  static String keyOf(NovelChapter chapter) {
    if (chapter.id.isNotEmpty) return chapter.id;
    if (chapter.url.isNotEmpty) return chapter.url;
    return '${chapter.index}';
  }

  NovelContent? get(NovelChapter chapter) => _entries[keyOf(chapter)];

  bool contains(NovelChapter chapter) => _entries.containsKey(keyOf(chapter));

  void put(NovelChapter chapter, NovelContent content) {
    final key = keyOf(chapter);
    final previous = _entries.remove(key);
    if (previous != null) _chars -= _charCount(previous);
    _entries[key] = content;
    _chars += _charCount(content);
    _trim();
  }

  /// 读缓存；未命中走引擎抓取并写回。并发同章只发一次请求。
  Future<NovelContent> load({
    required NovelOnlineEngine engine,
    required NovelBookSource source,
    required NovelRef ref,
    required NovelChapter chapter,
  }) {
    final cached = get(chapter);
    if (cached != null) return Future<NovelContent>.value(cached);
    final key = keyOf(chapter);
    final running = _inflight[key];
    if (running != null) return running;
    final future = engine.contentFor(source, ref, chapter).then((
      NovelContent content,
    ) {
      put(chapter, content);
      return content;
    });
    _inflight[key] = future;
    return future.whenComplete(() {
      _inflight.remove(key);
    });
  }

  /// 预取，不关心结果；失败静默（真正打开时还会再请求一次）。
  void prefetch({
    required NovelOnlineEngine engine,
    required NovelBookSource source,
    required NovelRef ref,
    required NovelChapter chapter,
  }) {
    if (chapter.isVolume || contains(chapter)) return;
    unawaitedIgnore(
      load(engine: engine, source: source, ref: ref, chapter: chapter),
    );
  }

  void clear() {
    _entries.clear();
    _inflight.clear();
    _chars = 0;
  }

  void _trim() {
    while (_entries.length > maxEntries && _entries.length > 1) {
      _removeOldest();
    }
    while (_chars > maxChars && _entries.length > 1) {
      _removeOldest();
    }
  }

  void _removeOldest() {
    final key = _entries.keys.first;
    final content = _entries.remove(key);
    if (content != null) _chars -= _charCount(content);
  }

  static int _charCount(NovelContent content) {
    var total = content.title.length;
    for (final paragraph in content.paragraphs) {
      total += paragraph.length;
    }
    return total;
  }

  static void unawaitedIgnore(Future<Object?> future) {
    future.then<void>((_) {}, onError: (Object _, StackTrace __) {});
  }
}
