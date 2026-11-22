/// 书源仓库的惰性门面：把 [NovelSourceStore] 的解析推迟到第一次真实读写。
///
/// 为什么多一层：registry 装配必须零 I/O（无插件测试环境里 `path_provider`
/// 不可用）。`ComicSourceStore` 是在装配期 `await openDefault()` 的，小说这边
/// 刻意改为惰性——用户不点书源功能就永远不碰应用支持目录，既有测试也无需注入。
library;

import 'novel_source_model.dart';
import 'novel_source_store.dart' show NovelSourceStorage, NovelSourceStore;

class NovelSourceRepository implements NovelSourceStorage {
  NovelSourceRepository(this._open);

  final Future<NovelSourceStore> Function() _open;
  Future<NovelSourceStore>? _resolved;

  Future<NovelSourceStore> _store() => _resolved ??= _open();

  @override
  Future<List<NovelBookSource>> loadAll() async => (await _store()).loadAll();

  @override
  Future<int> saveAll(Iterable<NovelBookSource> sources) async =>
      (await _store()).saveAll(sources);

  @override
  Future<void> setEnabled(String key, bool enabled) async =>
      (await _store()).setEnabled(key, enabled);

  @override
  Future<bool> delete(String key) async => (await _store()).delete(key);
}
