/// 搜索选源范围：全部启用源 / 指定分组 / 手选源（多选）。
///
/// 纯领域对象：不碰 UI、不碰 IO。页面把已加载的书源列表交给 [select] 得到
/// 本次要搜的源；范围本身可序列化成 (mode, groups, sourceKeys) 供页面状态
/// 与测试共用，不依赖具体书源实例。
library;

import 'package:mimao/novel/source/novel_source_model.dart';

/// 未分组书源在分组选择里的展示名（定义在书源模型里，与
/// [NovelBookSource.groupLabel] 同源，这里再导出方便搜索侧引用）。
export 'package:mimao/novel/source/novel_source_model.dart'
    show novelUngroupedLabel;

/// 该源是否参与在线搜索：启用、文本类型、配置了搜索地址且不是占位符 `-`。
bool isSearchableNovelSource(NovelBookSource source) {
  final searchUrl = source.searchUrl.trim();
  return source.enabled &&
      source.type == 0 &&
      searchUrl.isNotEmpty &&
      searchUrl != '-';
}

/// 书源参与搜索的稳定键（与 [NovelBookSource.key] 同义，集中一处便于测试）。
String novelSearchSourceKey(NovelBookSource source) => source.key;

/// 选源模式。
enum NovelSearchScopeMode {
  /// 全部可搜索的启用源（默认）。
  all,

  /// 只搜指定分组。
  group,

  /// 只搜手选的源。
  manual,
}

/// 搜索范围。不可变；变更走 [withMode] / [toggleGroup] / [toggleSource]。
class NovelSearchScope {
  const NovelSearchScope({
    this.mode = NovelSearchScopeMode.all,
    this.groups = const <String>{},
    this.sourceKeys = const <String>{},
  });

  final NovelSearchScopeMode mode;

  /// [NovelSearchScopeMode.group] 下选中的分组；空集按「所有分组」处理。
  final Set<String> groups;

  /// [NovelSearchScopeMode.manual] 下选中的书源主键；空集按「全部」处理。
  final Set<String> sourceKeys;

  /// 该模式是否把范围收窄到了用户明确选过的子集（用于 UI 文案与提示）。
  bool get isNarrowed => switch (mode) {
    NovelSearchScopeMode.all => false,
    NovelSearchScopeMode.group => groups.isNotEmpty,
    NovelSearchScopeMode.manual => sourceKeys.isNotEmpty,
  };

  /// 该分组是否被选中；[NovelSearchScopeMode.group] 且未选任何分组时视为全选。
  bool includesGroup(String group) => groups.isEmpty || groups.contains(group);

  bool includesSource(String key) =>
      sourceKeys.isEmpty || sourceKeys.contains(key);

  NovelSearchScope withMode(NovelSearchScopeMode value) =>
      NovelSearchScope(mode: value, groups: groups, sourceKeys: sourceKeys);

  NovelSearchScope toggleGroup(String group) {
    final next = <String>{...groups};
    if (!next.remove(group)) next.add(group);
    return NovelSearchScope(
      mode: NovelSearchScopeMode.group,
      groups: next,
      sourceKeys: sourceKeys,
    );
  }

  NovelSearchScope toggleSource(String key) {
    final next = <String>{...sourceKeys};
    if (!next.remove(key)) next.add(key);
    return NovelSearchScope(
      mode: NovelSearchScopeMode.manual,
      groups: groups,
      sourceKeys: next,
    );
  }

  /// 从全部已加载书源里挑出可搜索的源，并按「权重高→名称」稳定排序。
  ///
  /// 分组/手选模式下若一项都没勾选，回落到全部——与 UI 上「不选即全部」
  /// 的直觉一致，也避免手选清空后搜索变成空操作。
  List<NovelBookSource> select(Iterable<NovelBookSource> sources) {
    final searchable = <NovelBookSource>[
      for (final source in sources)
        if (isSearchableNovelSource(source)) source,
    ];
    final filtered = switch (mode) {
      NovelSearchScopeMode.all => searchable,
      NovelSearchScopeMode.group => <NovelBookSource>[
        for (final source in searchable)
          if (_matchesAnyGroup(source, groups)) source,
      ],
      NovelSearchScopeMode.manual => <NovelBookSource>[
        for (final source in searchable)
          if (sourceKeys.isEmpty || sourceKeys.contains(source.key)) source,
      ],
    };
    filtered.sort((a, b) {
      final weight = b.weight.compareTo(a.weight);
      if (weight != 0) return weight;
      return a.name.compareTo(b.name);
    });
    return List<NovelBookSource>.unmodifiable(filtered);
  }

  /// UI 文案：`全部源` / `分组：玄幻 · 都市` / `手选 3 个源`。
  String describe({int? total}) {
    final suffix = total == null ? '' : '（$total）';
    return switch (mode) {
      NovelSearchScopeMode.all => '全部源$suffix',
      NovelSearchScopeMode.group =>
        groups.isEmpty
            ? '全部分组$suffix'
            : '分组：${(groups.toList()..sort()).join(' · ')}$suffix',
      NovelSearchScopeMode.manual =>
        sourceKeys.isEmpty ? '全部源$suffix' : '手选 ${sourceKeys.length} 个源$suffix',
    };
  }

  static bool _matchesAnyGroup(NovelBookSource source, Set<String> groups) {
    if (groups.isEmpty) return true;
    final sourceGroups = source.groups;
    if (sourceGroups.isEmpty) return groups.contains(novelUngroupedLabel);
    return sourceGroups.any(groups.contains);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NovelSearchScope &&
          other.mode == mode &&
          _setEquals(other.groups, groups) &&
          _setEquals(other.sourceKeys, sourceKeys));

  @override
  int get hashCode => Object.hash(
    mode,
    Object.hashAllUnordered(groups),
    Object.hashAllUnordered(sourceKeys),
  );
}

/// 全部可搜索书源涉及的分组，去重后按拼音无关的字典序；「未分组」排在最后。
List<String> novelSourceGroups(Iterable<NovelBookSource> sources) {
  final groups = <String>{};
  var hasUngrouped = false;
  for (final source in sources) {
    if (!isSearchableNovelSource(source)) continue;
    final labels = source.groups;
    if (labels.isEmpty) {
      hasUngrouped = true;
    } else {
      groups.addAll(labels);
    }
  }
  final sorted = groups.toList()..sort();
  if (hasUngrouped) sorted.add(novelUngroupedLabel);
  return List<String>.unmodifiable(sorted);
}

bool _setEquals<T>(Set<T> a, Set<T> b) =>
    a.length == b.length && a.containsAll(b);
