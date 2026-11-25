/// 首页模块化配置：模块清单、顺序、显隐，以及自定义分组卡片。
///
/// 与 Widget 无关，编解码可在单测里直接跑。默认顺序/开关刻意等于改造前
/// 首页的排布——用户不动设置时看到的还是原来那几块。
library;

import 'dart:convert';

/// 首页模块种类。
///
/// 新增模块时只在这里加一项并在页面里给对应的 builder；配置里出现未知
/// 模块名（旧版本配置被新版本读到）直接丢弃，不会让首页崩。
enum NovelHomeModuleKind {
  recent,
  stats,
  goal,
  source,
  capability,
  shelfStrip,
  webdav,
  customGroup,
}

extension NovelHomeModuleKindLabel on NovelHomeModuleKind {
  String get label => switch (this) {
    NovelHomeModuleKind.recent => '最近阅读',
    NovelHomeModuleKind.stats => '阅读统计',
    NovelHomeModuleKind.goal => '今日阅读目标',
    NovelHomeModuleKind.source => '书源状态',
    NovelHomeModuleKind.capability => '书源引擎',
    NovelHomeModuleKind.shelfStrip => '我的书架',
    NovelHomeModuleKind.webdav => 'WebDAV 备份',
    NovelHomeModuleKind.customGroup => '自定义分组卡片',
  };

  String get key => name;

  /// 内置模块每个最多出现一次；[customGroup] 可多张（靠 id 区分）。
  bool get isSingleton => this != NovelHomeModuleKind.customGroup;

  static NovelHomeModuleKind? fromKey(String? value) {
    for (final kind in NovelHomeModuleKind.values) {
      if (kind.key == value) return kind;
    }
    return null;
  }
}

/// 首页上的一个模块实例。
class NovelHomeModule {
  const NovelHomeModule({
    required this.kind,
    this.enabled = true,
    this.groupName,
    this.instanceId,
  });

  /// 自定义分组卡片用 [instanceId] 区分多张；内置模块用 [kind.key]。
  String get id => instanceId ?? kind.key;

  final NovelHomeModuleKind kind;
  final bool enabled;

  /// [NovelHomeModuleKind.customGroup] 展示的书架分组名。
  final String? groupName;

  /// 多实例标识（目前只有自定义分组卡片用）。
  final String? instanceId;

  NovelHomeModule copyWith({
    bool? enabled,
    String? groupName,
    String? instanceId,
  }) => NovelHomeModule(
    kind: kind,
    enabled: enabled ?? this.enabled,
    groupName: groupName ?? this.groupName,
    instanceId: instanceId ?? this.instanceId,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind.key,
    if (!enabled) 'enabled': false,
    if (groupName != null && groupName!.isNotEmpty) 'group': groupName,
    if (instanceId != null) 'id': instanceId,
  };

  /// 单个模块的反序列化；未知 kind 返回 null（调用方丢弃）。
  static NovelHomeModule? fromJson(Map<String, Object?> json) {
    final kind = NovelHomeModuleKindLabel.fromKey(json['kind'] as String?);
    if (kind == null) return null;
    final group = '${json['group'] ?? ''}'.trim();
    final instance = '${json['id'] ?? ''}'.trim();
    if (kind == NovelHomeModuleKind.customGroup && group.isEmpty) {
      return null;
    }
    return NovelHomeModule(
      kind: kind,
      enabled: json['enabled'] != false,
      groupName: group.isEmpty ? null : group,
      instanceId: instance.isEmpty ? null : instance,
    );
  }
}

/// 首页模块配置：有序模块列表。
class NovelHomeModuleConfig {
  const NovelHomeModuleConfig(this.modules);

  /// 改造前首页的排布：最近阅读 / 统计 / 目标 / 书源 / 引擎 / 书架横条 / 备份。
  static const List<NovelHomeModule> defaults = <NovelHomeModule>[
    NovelHomeModule(kind: NovelHomeModuleKind.recent),
    NovelHomeModule(kind: NovelHomeModuleKind.stats),
    NovelHomeModule(kind: NovelHomeModuleKind.goal),
    NovelHomeModule(kind: NovelHomeModuleKind.source),
    NovelHomeModule(kind: NovelHomeModuleKind.capability),
    NovelHomeModule(kind: NovelHomeModuleKind.shelfStrip),
    NovelHomeModule(kind: NovelHomeModuleKind.webdav),
  ];

  final List<NovelHomeModule> modules;

  List<NovelHomeModule> get enabledModules =>
      <NovelHomeModule>[for (final m in modules) if (m.enabled) m];

  /// 按 [id] 找模块下标；找不到返回 -1。
  int indexOf(String id) => modules.indexWhere((m) => m.id == id);

  /// 移动模块（拖拽排序 / 上下移按钮共用）。越界下标原样返回。
  NovelHomeModuleConfig move(int from, int to) {
    if (from < 0 || from >= modules.length) return this;
    final target = to.clamp(0, modules.length - 1);
    if (target == from) return this;
    final next = List<NovelHomeModule>.of(modules);
    final item = next.removeAt(from);
    next.insert(target, item);
    return NovelHomeModuleConfig(next);
  }

  NovelHomeModuleConfig setEnabled(String id, bool enabled) {
    final index = indexOf(id);
    if (index < 0) return this;
    final next = List<NovelHomeModule>.of(modules);
    next[index] = next[index].copyWith(enabled: enabled);
    return NovelHomeModuleConfig(next);
  }

  /// 新增一张自定义分组卡片（同分组已有一张时直接返回原配置，避免重复）。
  NovelHomeModuleConfig addCustomGroup(String groupName, {String? instanceId}) {
    final name = groupName.trim();
    if (name.isEmpty) return this;
    if (modules.any(
      (m) =>
          m.kind == NovelHomeModuleKind.customGroup && m.groupName == name,
    )) {
      return this;
    }
    return NovelHomeModuleConfig(<NovelHomeModule>[
      ...modules,
      NovelHomeModule(
        kind: NovelHomeModuleKind.customGroup,
        groupName: name,
        instanceId: instanceId ?? 'group:$name',
      ),
    ]);
  }

  /// 删除一张自定义分组卡片（内置模块不可删，调用后原样返回）。
  NovelHomeModuleConfig removeModule(String id) {
    final index = indexOf(id);
    if (index < 0) return this;
    if (modules[index].kind.isSingleton) return this;
    return NovelHomeModuleConfig(<NovelHomeModule>[
      ...modules.sublist(0, index),
      ...modules.sublist(index + 1),
    ]);
  }

  /// 把配置补齐成完整清单：缺失的内置模块补在末尾（默认启用），
  /// 这样旧配置遇到新增模块也能看到它。
  NovelHomeModuleConfig normalized() {
    final present = <NovelHomeModuleKind>{
      for (final m in modules) m.kind,
    };
    final result = <NovelHomeModule>[...modules];
    for (final kind in NovelHomeModuleKind.values) {
      if (!kind.isSingleton) continue;
      if (present.contains(kind)) continue;
      result.add(NovelHomeModule(kind: kind));
    }
    return NovelHomeModuleConfig(result);
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'modules': <Object?>[for (final m in modules) m.toJson()],
  };

  String encode() => jsonEncode(toJson());

  factory NovelHomeModuleConfig.fromJson(Map<String, Object?> json) {
    final raw = json['modules'];
    final modules = <NovelHomeModule>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is! Map) continue;
        final module = NovelHomeModule.fromJson(
          item.map((key, value) => MapEntry('$key', value)),
        );
        if (module == null) continue;
        modules.add(module);
      }
    }
    return NovelHomeModuleConfig(modules).normalized();
  }

  /// 读取 kv：空/坏数据回默认配置。
  static NovelHomeModuleConfig decode(String? raw) {
    final text = raw?.trim() ?? '';
    if (text.isEmpty || !text.startsWith('{')) {
      return const NovelHomeModuleConfig(defaults);
    }
    try {
      final value = jsonDecode(text);
      if (value is Map) {
        return NovelHomeModuleConfig.fromJson(
          value.map((key, value) => MapEntry('$key', value)),
        );
      }
    } on Object {
      // 坏 JSON 回默认。
    }
    return const NovelHomeModuleConfig(defaults);
  }
}
