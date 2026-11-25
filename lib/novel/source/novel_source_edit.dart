/// 书源编辑的纯逻辑层：字段规格、表单 ↔ 原始 JSON 双向映射、校验、分组与
/// 权重操作、导出文本。
///
/// 不碰 IO、不碰 UI：编辑器页只负责渲染 [novelSourceFieldSpecs] 与调用这里的
/// 纯函数；管理页的批量启停/移动分组也落在这里，因此行为可单测。
///
/// 一条书源的权威形态始终是 Legado 原始 JSON（[NovelBookSource.raw]），编辑
/// 不引入第二套模型——保存时把改动写回 raw 再落库，引擎读到的就是同一份。
library;

import 'dart:convert';

import 'package:mimao/novel/source/novel_source_model.dart';

/// 编辑表单里一个字段的取值形态。
enum NovelSourceFieldKind {
  /// 单行文本。
  text,

  /// 多行文本（规则表达式、JS）。
  multiline,

  /// 整数。
  integer,
}

/// 表单字段规格：`path` 是 raw JSON 里的键路径（如 `ruleSearch.bookList`）。
class NovelSourceFieldSpec {
  const NovelSourceFieldSpec({
    required this.path,
    required this.label,
    this.hint = '',
    this.kind = NovelSourceFieldKind.text,
  });

  final List<String> path;
  final String label;
  final String hint;
  final NovelSourceFieldKind kind;

  String get key => path.join('.');
}

/// 表单分组：一组相关字段（基本信息 / 搜索 / 发现 / 详情 / 目录 / 正文）。
class NovelSourceFieldSection {
  const NovelSourceFieldSection({
    required this.title,
    required this.fields,
    this.description = '',
  });

  final String title;
  final String description;
  final List<NovelSourceFieldSpec> fields;
}

/// 编辑器表单的完整字段表（顺序即渲染顺序）。
const List<NovelSourceFieldSection>
novelSourceFieldSections = <NovelSourceFieldSection>[
  NovelSourceFieldSection(
    title: '基本信息',
    description: '书源身份与网络参数。名称与地址是必填项。',
    fields: <NovelSourceFieldSpec>[
      NovelSourceFieldSpec(path: <String>['bookSourceName'], label: '书源名称'),
      NovelSourceFieldSpec(
        path: <String>['bookSourceUrl'],
        label: '书源地址',
        hint: 'https://example.com',
      ),
      NovelSourceFieldSpec(
        path: <String>['bookSourceGroup'],
        label: '分组',
        hint: '多个分组用逗号分隔',
      ),
      NovelSourceFieldSpec(
        path: <String>['bookSourceType'],
        label: '类型',
        hint: '0 文本 / 1 音频 / 2 图片 / 3 文件',
        kind: NovelSourceFieldKind.integer,
      ),
      NovelSourceFieldSpec(
        path: <String>['weight'],
        label: '权重',
        hint: '越大越优先；搜索结果与选源排序都用它',
        kind: NovelSourceFieldKind.integer,
      ),
      NovelSourceFieldSpec(
        path: <String>['bookSourceComment'],
        label: '备注',
        kind: NovelSourceFieldKind.multiline,
      ),
      NovelSourceFieldSpec(
        path: <String>['header'],
        label: '请求头',
        hint: 'JSON 对象，如 {"User-Agent":"…"}',
        kind: NovelSourceFieldKind.multiline,
      ),
      NovelSourceFieldSpec(
        path: <String>['loginUrl'],
        label: '登录地址',
        hint: '需要登录的源填这里，可用「登录取 Cookie」',
      ),
      NovelSourceFieldSpec(
        path: <String>['jsLib'],
        label: 'jsLib',
        hint: '公共 JS 库地址或脚本',
        kind: NovelSourceFieldKind.multiline,
      ),
    ],
  ),
  NovelSourceFieldSection(
    title: '搜索',
    description: '搜索地址与结果列表解析规则。搜索地址为空则本源不参与搜索。',
    fields: <NovelSourceFieldSpec>[
      NovelSourceFieldSpec(
        path: <String>['searchUrl'],
        label: '搜索地址',
        hint: '/search?q={{key}}&page={{page}}',
      ),
      NovelSourceFieldSpec(
        path: <String>['ruleSearch', 'bookList'],
        label: '结果列表',
        hint: '列表项选择器；`-` 前缀表示倒序',
      ),
      NovelSourceFieldSpec(path: <String>['ruleSearch', 'name'], label: '书名'),
      NovelSourceFieldSpec(path: <String>['ruleSearch', 'author'], label: '作者'),
      NovelSourceFieldSpec(
        path: <String>['ruleSearch', 'bookUrl'],
        label: '详情地址',
      ),
      NovelSourceFieldSpec(
        path: <String>['ruleSearch', 'coverUrl'],
        label: '封面地址',
      ),
      NovelSourceFieldSpec(
        path: <String>['ruleSearch', 'intro'],
        label: '简介',
        kind: NovelSourceFieldKind.multiline,
      ),
      NovelSourceFieldSpec(path: <String>['ruleSearch', 'kind'], label: '分类'),
      NovelSourceFieldSpec(
        path: <String>['ruleSearch', 'lastChapter'],
        label: '最新章节',
      ),
      NovelSourceFieldSpec(
        path: <String>['ruleSearch', 'wordCount'],
        label: '字数',
      ),
    ],
  ),
  NovelSourceFieldSection(
    title: '发现',
    description: '发现页分类（`分类名::地址` 一行一个）与列表规则；留空时回落搜索规则。',
    fields: <NovelSourceFieldSpec>[
      NovelSourceFieldSpec(
        path: <String>['exploreUrl'],
        label: '发现地址',
        kind: NovelSourceFieldKind.multiline,
      ),
      NovelSourceFieldSpec(
        path: <String>['ruleExplore', 'bookList'],
        label: '结果列表',
      ),
      NovelSourceFieldSpec(path: <String>['ruleExplore', 'name'], label: '书名'),
      NovelSourceFieldSpec(
        path: <String>['ruleExplore', 'bookUrl'],
        label: '详情地址',
      ),
      NovelSourceFieldSpec(
        path: <String>['ruleExplore', 'coverUrl'],
        label: '封面地址',
      ),
    ],
  ),
  NovelSourceFieldSection(
    title: '详情',
    description: '详情页字段；`init` 用于先定位到详情容器。',
    fields: <NovelSourceFieldSpec>[
      NovelSourceFieldSpec(
        path: <String>['ruleBookInfo', 'init'],
        label: '初始化',
      ),
      NovelSourceFieldSpec(path: <String>['ruleBookInfo', 'name'], label: '书名'),
      NovelSourceFieldSpec(
        path: <String>['ruleBookInfo', 'author'],
        label: '作者',
      ),
      NovelSourceFieldSpec(
        path: <String>['ruleBookInfo', 'intro'],
        label: '简介',
        kind: NovelSourceFieldKind.multiline,
      ),
      NovelSourceFieldSpec(
        path: <String>['ruleBookInfo', 'coverUrl'],
        label: '封面地址',
      ),
      NovelSourceFieldSpec(
        path: <String>['ruleBookInfo', 'tocUrl'],
        label: '目录地址',
      ),
      NovelSourceFieldSpec(
        path: <String>['ruleBookInfo', 'lastChapter'],
        label: '最新章节',
      ),
      NovelSourceFieldSpec(
        path: <String>['ruleBookInfo', 'wordCount'],
        label: '字数',
      ),
    ],
  ),
  NovelSourceFieldSection(
    title: '目录',
    description: '章节目录解析；`-` 前缀表示源里章节是最新在前。',
    fields: <NovelSourceFieldSpec>[
      NovelSourceFieldSpec(
        path: <String>['ruleToc', 'chapterList'],
        label: '章节列表',
      ),
      NovelSourceFieldSpec(
        path: <String>['ruleToc', 'chapterName'],
        label: '章节名',
      ),
      NovelSourceFieldSpec(
        path: <String>['ruleToc', 'chapterUrl'],
        label: '章节地址',
      ),
      NovelSourceFieldSpec(
        path: <String>['ruleToc', 'nextTocUrl'],
        label: '下一页目录',
      ),
      NovelSourceFieldSpec(
        path: <String>['ruleToc', 'formatJs'],
        label: '格式化 JS',
        kind: NovelSourceFieldKind.multiline,
      ),
    ],
  ),
  NovelSourceFieldSection(
    title: '正文',
    description: '正文解析；`nextContentUrl` 用于分页正文。',
    fields: <NovelSourceFieldSpec>[
      NovelSourceFieldSpec(
        path: <String>['ruleContent', 'content'],
        label: '正文',
        kind: NovelSourceFieldKind.multiline,
      ),
      NovelSourceFieldSpec(
        path: <String>['ruleContent', 'nextContentUrl'],
        label: '下一页正文',
      ),
      NovelSourceFieldSpec(
        path: <String>['ruleContent', 'title'],
        label: '章节标题',
      ),
      NovelSourceFieldSpec(
        path: <String>['ruleContent', 'webJs'],
        label: 'webJs',
        hint: '桌面端暂不执行（降级为 HTTP 抓取）',
        kind: NovelSourceFieldKind.multiline,
      ),
    ],
  ),
];

/// 全部字段规格（扁平）。
List<NovelSourceFieldSpec> get novelSourceFieldSpecs => <NovelSourceFieldSpec>[
  for (final section in novelSourceFieldSections) ...section.fields,
];

/// 读 raw 里某路径的值（缺失/非标量返回空串；Map/List 返回 JSON 串）。
String readNovelSourceField(Map<String, dynamic> raw, List<String> path) {
  Object? cursor = raw;
  for (final key in path) {
    if (cursor is! Map) return '';
    cursor = cursor[key];
  }
  if (cursor == null) return '';
  if (cursor is Map || cursor is List) return jsonEncode(cursor);
  return '$cursor';
}

/// 写 raw 里某路径的值；空串表示删除该键（保持 raw 干净，避免空规则干扰
/// 「规则缺失走降级」的判断）。返回新的 map，不改入参。
Map<String, dynamic> writeNovelSourceField(
  Map<String, dynamic> raw,
  List<String> path,
  String value,
) {
  final next = <String, dynamic>{
    for (final entry in raw.entries)
      entry.key: entry.value is Map
          ? Map<String, dynamic>.from(entry.value as Map)
          : entry.value,
  };
  if (path.isEmpty) return next;
  var cursor = next;
  for (var i = 0; i < path.length - 1; i++) {
    final key = path[i];
    final child = cursor[key];
    final map = child is Map
        ? Map<String, dynamic>.from(child)
        : <String, dynamic>{};
    cursor[key] = map;
    cursor = map;
  }
  final leaf = path.last;
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    cursor.remove(leaf);
  } else {
    cursor[leaf] = trimmed;
  }
  return next;
}

/// 校验结果的一条问题。[field] 为出错字段路径（顶级问题为空）。
class NovelSourceIssue {
  const NovelSourceIssue({
    required this.message,
    this.field = '',
    this.severity = NovelSourceIssueSeverity.error,
  });

  final String message;
  final String field;
  final NovelSourceIssueSeverity severity;

  bool get isError => severity == NovelSourceIssueSeverity.error;

  @override
  String toString() =>
      '${field.isEmpty ? '' : '$field：'}${severity.label} · $message';
}

enum NovelSourceIssueSeverity {
  error('错误'),
  warning('警告');

  const NovelSourceIssueSeverity(this.label);

  final String label;
}

/// 校验书源 raw JSON：必填项、类型、URL 形态、规则可解析性。
///
/// 只做「离线能判断」的检查（不发请求）——真实可用性靠校验面板跑四步链路。
/// 有 [NovelSourceIssueSeverity.error] 即视为不可保存。
List<NovelSourceIssue> validateNovelSourceRaw(Map<String, dynamic> raw) {
  final issues = <NovelSourceIssue>[];

  void error(String field, String message) =>
      issues.add(NovelSourceIssue(message: message, field: field));
  void warn(String field, String message) => issues.add(
    NovelSourceIssue(
      message: message,
      field: field,
      severity: NovelSourceIssueSeverity.warning,
    ),
  );

  final name = '${raw['bookSourceName'] ?? ''}'.trim();
  if (name.isEmpty) error('bookSourceName', '书源名称不能为空');

  final url = '${raw['bookSourceUrl'] ?? ''}'.trim();
  if (url.isEmpty) {
    error('bookSourceUrl', '书源地址不能为空');
  } else {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.isAbsolute || !uri.hasScheme) {
      error('bookSourceUrl', '书源地址必须是完整 URL（含 http/https）');
    } else if (uri.scheme != 'http' && uri.scheme != 'https') {
      error('bookSourceUrl', '书源地址只支持 http / https');
    }
  }

  final type = raw['bookSourceType'];
  if (type != null && type is! num) {
    error('bookSourceType', '类型必须是数字（0 文本 / 1 音频 / 2 图片 / 3 文件）');
  }

  final weight = raw['weight'];
  if (weight != null && weight is! num) {
    error('weight', '权重必须是整数');
  }

  final header = '${raw['header'] ?? ''}'.trim();
  if (header.isNotEmpty) {
    try {
      final decoded = jsonDecode(header);
      if (decoded is! Map) error('header', '请求头必须是 JSON 对象');
    } on Object {
      error('header', '请求头不是合法 JSON');
    }
  }

  final searchUrl = '${raw['searchUrl'] ?? ''}'.trim();
  if (searchUrl.isEmpty) {
    warn('searchUrl', '没有搜索地址：本源不会参与在线搜索');
  } else if (searchUrl != '-' &&
      !searchUrl.startsWith('/') &&
      !searchUrl.startsWith('http') &&
      !searchUrl.startsWith('@js:') &&
      !searchUrl.startsWith('<js>')) {
    warn('searchUrl', '搜索地址既不是路径也不是完整 URL，确认写法');
  }

  final searchList = readNovelSourceField(raw, <String>[
    'ruleSearch',
    'bookList',
  ]);
  if (searchUrl.isNotEmpty && searchUrl != '-' && searchList.isEmpty) {
    error('ruleSearch.bookList', '有搜索地址但没有结果列表规则，搜索必然空结果');
  }
  if (searchList.isNotEmpty && !_balanced(searchList)) {
    error('ruleSearch.bookList', '选择器括号不配对');
  }

  for (final section in novelSourceFieldSections) {
    for (final spec in section.fields) {
      if (spec.kind != NovelSourceFieldKind.integer) continue;
      final value = readNovelSourceField(raw, spec.path);
      if (value.isEmpty) continue;
      if (int.tryParse(value) == null) {
        error(spec.key, '${spec.label}必须是整数');
      }
    }
  }

  final tocList = readNovelSourceField(raw, <String>['ruleToc', 'chapterList']);
  if (tocList.isEmpty) {
    warn('ruleToc.chapterList', '没有目录规则：详情页拿不到章节列表');
  }
  final content = readNovelSourceField(raw, <String>['ruleContent', 'content']);
  if (content.isEmpty) {
    warn('ruleContent.content', '没有正文规则：阅读页拿不到正文');
  } else if (!_balanced(content)) {
    error('ruleContent.content', '正文规则括号不配对');
  }

  for (final group in <String>['ruleSearch', 'ruleExplore', 'ruleBookInfo']) {
    final value = raw[group];
    if (value == null) continue;
    if (value is! Map) {
      error(group, '$group 必须是 JSON 对象');
    }
  }

  return List<NovelSourceIssue>.unmodifiable(issues);
}

/// 轻量括号配对检查：`[]` / `()` 在忽略引号内的字符后应配平。
///
/// 不追求完整选择器语法——那由引擎在真页面上判定；这里只拦「一眼写错」的
/// 括号漏配，报错信息比引擎的静默空结果可读得多。
bool _balanced(String rule) {
  final stack = <String>[];
  String? quote;
  for (var i = 0; i < rule.length; i++) {
    final char = rule[i];
    if (quote != null) {
      if (char == '\\') {
        i++;
        continue;
      }
      if (char == quote) quote = null;
      continue;
    }
    switch (char) {
      case '"' || '\'':
        quote = char;
      case '[' || '(':
        stack.add(char);
      case ']':
        if (stack.isEmpty || stack.removeLast() != '[') return false;
      case ')':
        if (stack.isEmpty || stack.removeLast() != '(') return false;
    }
  }
  return stack.isEmpty && quote == null;
}

/// 由原始 JSON 建一条书源（编辑保存 / 文本导入共用）。
///
/// 与 [NovelBookSource.fromLegado] 的差别：保留 `enabled` 的现状语义——书源
/// 地址变了要换主键，调用方用 [rekeyed] 处理。
NovelBookSource novelSourceFromRaw(
  Map<String, dynamic> raw, {
  bool enabled = true,
}) {
  final base = NovelBookSource.fromLegado(raw);
  return NovelBookSource(
    key: base.key,
    name: base.name,
    url: base.url,
    type: base.type,
    enabled: enabled,
    raw: raw,
  );
}

/// 导出：把书源还原成 Legado 书源 JSON（数组文本）。
///
/// [pretty] 为 true 时缩进 2 空格（给人看/进文件）；false 压成一行（剪贴板）。
/// `enabled` 同步写进 `enabled` 字段——Legado 的导出文件里也是这个键。
String exportNovelSourcesText(
  Iterable<NovelBookSource> sources, {
  bool pretty = true,
}) {
  final items = <Map<String, dynamic>>[
    for (final source in sources)
      <String, dynamic>{...source.raw, 'enabled': source.enabled},
  ];
  if (pretty) {
    return '${const JsonEncoder.withIndent('  ').convert(items)}\n';
  }
  return jsonEncode(items);
}

/// 单条导出（[pretty] 语义同 [exportNovelSourcesText]）。
String exportNovelSourceText(NovelBookSource source, {bool pretty = true}) =>
    exportNovelSourcesText(<NovelBookSource>[source], pretty: pretty);

/// 重命名分组：把 `from` 从每条书源的 `bookSourceGroup` 换成 `to`。
///
/// [to] 为空表示把该分组从所有书源上摘掉。返回新列表；没有变化的书源原样返回
/// （调用方据此判断是否需要落库）。
List<NovelBookSource> renameNovelSourceGroup(
  Iterable<NovelBookSource> sources, {
  required String from,
  required String to,
}) {
  final fromName = from.trim();
  final toName = to.trim();
  if (fromName.isEmpty) return List<NovelBookSource>.of(sources);
  return <NovelBookSource>[
    for (final source in sources)
      if (source.groups.contains(fromName))
        _withGroups(source, <String>[
          for (final group in source.groups)
            if (group != fromName) group else if (toName.isNotEmpty) toName,
        ])
      else
        source,
  ];
}

/// 删除分组：从所有书源上摘掉该分组名（书源本身保留）。
List<NovelBookSource> deleteNovelSourceGroup(
  Iterable<NovelBookSource> sources,
  String group,
) => renameNovelSourceGroup(sources, from: group, to: '');

/// 批量把书源移到某分组。
///
/// [additive] 为 true 时追加分组（保留原有），false 时替换全部分组；
/// [group] 为空表示清空分组（只在 additive=false 时有意义）。
List<NovelBookSource> moveNovelSourcesToGroup(
  Iterable<NovelBookSource> sources, {
  required Set<String> keys,
  required String group,
  bool additive = true,
}) {
  final target = group.trim();
  return <NovelBookSource>[
    for (final source in sources)
      if (keys.contains(source.key))
        _withGroups(
          source,
          additive
              ? <String>[
                  ...source.groups,
                  if (target.isNotEmpty && !source.groups.contains(target))
                    target,
                ]
              : <String>[if (target.isNotEmpty) target],
        )
      else
        source,
  ];
}

/// 设置权重（写进 raw 的 `weight`，引擎与排序读同一份）。
NovelBookSource setNovelSourceWeight(NovelBookSource source, int weight) =>
    NovelBookSource(
      key: source.key,
      name: source.name,
      url: source.url,
      type: source.type,
      enabled: source.enabled,
      raw: <String, dynamic>{...source.raw, 'weight': weight},
    );

/// 用编辑后的 raw 覆盖一条书源；地址变了主键跟着换。
NovelBookSource applyNovelSourceRaw(
  NovelBookSource source,
  Map<String, dynamic> raw,
) {
  final rebuilt = novelSourceFromRaw(raw, enabled: source.enabled);
  return NovelBookSource(
    key: rebuilt.key,
    name: rebuilt.name,
    url: rebuilt.url,
    type: rebuilt.type,
    enabled: source.enabled,
    raw: raw,
  );
}

NovelBookSource _withGroups(NovelBookSource source, List<String> groups) {
  final unique = <String>[];
  for (final group in groups) {
    final name = group.trim();
    if (name.isEmpty || unique.contains(name)) continue;
    unique.add(name);
  }
  final raw = <String, dynamic>{...source.raw};
  if (unique.isEmpty) {
    raw.remove('bookSourceGroup');
  } else {
    raw['bookSourceGroup'] = unique.join(',');
  }
  return NovelBookSource(
    key: source.key,
    name: source.name,
    url: source.url,
    type: source.type,
    enabled: source.enabled,
    raw: raw,
  );
}
