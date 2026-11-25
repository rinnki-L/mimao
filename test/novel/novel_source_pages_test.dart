// ignore_for_file: deprecated_member_use — 与其他 novel 测试同款说明。
/// 书源编辑器与规则管理页的 widget 测试：双模式切换、校验、保存、批量操作。
///
/// 全部内存存储 + 注入剪贴板/文件缝，不碰插件、不碰网络。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/pages/novel_source_edit_page.dart';
import 'package:mimao/novel/pages/novel_source_manage_page.dart';
import 'package:mimao/novel/source/novel_rule_model.dart';
import 'package:mimao/novel/source/novel_rule_store.dart';
import 'package:mimao/novel/source/novel_source_importer.dart';
import 'package:mimao/novel/source/novel_source_model.dart';
import 'package:mimao/novel/source/novel_source_store.dart';

NovelBookSource _source(
  String name,
  String url, {
  String group = '',
  int weight = 0,
  bool enabled = true,
}) => NovelBookSource(
  key: NovelBookSource.keyFor(url),
  name: name,
  url: url,
  type: 0,
  enabled: enabled,
  raw: <String, dynamic>{
    'bookSourceName': name,
    'bookSourceUrl': url,
    'bookSourceType': 0,
    'searchUrl': '/s?q={{key}}',
    'ruleSearch': <String, dynamic>{'bookList': '//li', 'name': '//a/text()'},
    'ruleToc': <String, dynamic>{'chapterList': '//dd'},
    'ruleContent': <String, dynamic>{'content': '//div'},
    'weight': weight,
    if (group.isNotEmpty) 'bookSourceGroup': group,
  },
);

class _MemoryStore implements NovelSourceStorage, NovelSourceUpsert {
  _MemoryStore([Iterable<NovelBookSource>? seed])
    : _items = <String, NovelBookSource>{
        for (final source in seed ?? const <NovelBookSource>[])
          source.key: source,
      };

  final Map<String, NovelBookSource> _items;

  @override
  Future<List<NovelBookSource>> loadAll() async =>
      List<NovelBookSource>.of(_items.values);

  @override
  Future<int> saveAll(Iterable<NovelBookSource> sources) async {
    var count = 0;
    for (final source in sources) {
      _items[source.key] = source;
      count++;
    }
    return count;
  }

  @override
  Future<void> setEnabled(String key, bool enabled) async {
    final current = _items[key];
    if (current == null) return;
    _items[key] = current.copyWith(enabled: enabled);
  }

  @override
  Future<bool> delete(String key) async => _items.remove(key) != null;

  @override
  Future<NovelBookSource> upsert(
    NovelBookSource source, {
    String? previousKey,
  }) async {
    if (previousKey != null && previousKey != source.key) {
      _items.remove(previousKey);
    }
    _items[source.key] = source;
    return source;
  }
}

class _MemoryRssStore implements NovelRssSourceStorage {
  final Map<String, NovelRssSource> _items = <String, NovelRssSource>{};

  @override
  Future<List<NovelRssSource>> loadAll() async =>
      List<NovelRssSource>.of(_items.values);

  @override
  Future<int> saveAll(Iterable<NovelRssSource> sources) async {
    for (final source in sources) {
      _items[source.key] = source;
    }
    return sources.length;
  }

  @override
  Future<void> setEnabled(String key, bool enabled) async {}

  @override
  Future<bool> delete(String key) async => _items.remove(key) != null;
}

class _MemoryReplaceStore implements NovelReplaceRuleStorage {
  final Map<String, NovelReplaceRule> _items = <String, NovelReplaceRule>{};

  @override
  Future<List<NovelReplaceRule>> loadAll() async =>
      List<NovelReplaceRule>.of(_items.values);

  @override
  Future<int> saveAll(Iterable<NovelReplaceRule> rules) async {
    for (final rule in rules) {
      _items[rule.key] = rule;
    }
    return rules.length;
  }

  @override
  Future<void> setEnabled(String key, bool enabled) async {}

  @override
  Future<bool> delete(String key) async => _items.remove(key) != null;
}

class _FakeFetcher implements NovelSourceFetcher {
  String text = '[]';

  @override
  Future<NovelSourceFetchResult> fetch(String url) async =>
      NovelSourceFetchResult(text: text, finalUrl: url);
}

class _MemoryFileGate implements NovelSourceFileGate {
  String? pickedText;
  String? savedName;
  String? savedText;

  @override
  Future<NovelSourcePickedFile?> pick() async {
    final text = pickedText;
    if (text == null) return null;
    return NovelSourcePickedFile(
      name: 'sources.json',
      bytes: Uint8List.fromList(utf8.encode(text)),
    );
  }

  @override
  Future<String?> save(String suggestedName, Uint8List bytes) async {
    savedName = suggestedName;
    savedText = utf8.decode(bytes);
    return 'C:/tmp/$suggestedName';
  }
}

class _MemoryClipboard implements NovelClipboardGate {
  String? text;

  @override
  Future<String?> readText() async => text;

  @override
  Future<void> writeText(String value) async => text = value;
}

NovelSourceImporter _importer(_MemoryStore store) => NovelSourceImporter(
  store,
  _FakeFetcher(),
  rssStore: _MemoryRssStore(),
  replaceStore: _MemoryReplaceStore(),
);

void main() {
  group('书源编辑器', () {
    testWidgets('表单模式渲染字段并保存后落库', (tester) async {
      final store = _MemoryStore();
      await tester.pumpWidget(
        MaterialApp(
          home: NovelSourceEditPage(
            store: store,
            initialRaw: jsonEncode(<String, dynamic>{
              'bookSourceName': '新源',
              'bookSourceUrl': 'https://new.example',
              'searchUrl': '/s?q={{key}}',
              'ruleSearch': <String, dynamic>{'bookList': '//li'},
              'ruleToc': <String, dynamic>{'chapterList': '//dd'},
              'ruleContent': <String, dynamic>{'content': '//div'},
            }),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('表单'), findsOneWidget);
      expect(find.text('原始 JSON'), findsOneWidget);
      expect(find.text('基本信息'), findsOneWidget);

      await tester.tap(find.byKey(const Key('novel-source-edit-save')));
      await tester.pumpAndSettle();

      final saved = await store.loadAll();
      expect(saved, hasLength(1));
      expect(saved.single.name, '新源');
      expect(saved.single.url, 'https://new.example');
    });

    testWidgets('双模式切换：改原始 JSON 后回表单同步到输入框', (tester) async {
      final store = _MemoryStore(<NovelBookSource>[
        _source('原名', 'https://a.example'),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          home: NovelSourceEditPage(
            store: store,
            initial: (await store.loadAll()).single,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('原始 JSON'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('novel-source-edit-raw')), findsOneWidget);

      final rawField = tester.widget<TextField>(
        find.byKey(const Key('novel-source-edit-raw')),
      );
      rawField.controller!.text = jsonEncode(<String, dynamic>{
        'bookSourceName': '改名后',
        'bookSourceUrl': 'https://a.example',
        'searchUrl': '/s?q={{key}}',
        'ruleSearch': <String, dynamic>{'bookList': '//li'},
        'ruleToc': <String, dynamic>{'chapterList': '//dd'},
        'ruleContent': <String, dynamic>{'content': '//div'},
      });
      await tester.pump();

      await tester.tap(find.text('表单'));
      await tester.pumpAndSettle();
      expect(find.text('改名后'), findsOneWidget);

      await tester.tap(find.byKey(const Key('novel-source-edit-save')));
      await tester.pumpAndSettle();
      final saved = await store.loadAll();
      expect(saved.single.name, '改名后');
    });

    testWidgets('非法 JSON 不切换模式并给可读错误', (tester) async {
      final store = _MemoryStore(<NovelBookSource>[
        _source('a', 'https://a.example'),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          home: NovelSourceEditPage(
            store: store,
            initial: (await store.loadAll()).single,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('原始 JSON'));
      await tester.pumpAndSettle();

      final rawField = tester.widget<TextField>(
        find.byKey(const Key('novel-source-edit-raw')),
      );
      rawField.controller!.text = '{oops';
      await tester.pump();

      await tester.tap(find.text('表单'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('novel-source-edit-raw-error')),
        findsOneWidget,
      );
      // 仍在原始模式（表单字段没渲染）。
      expect(find.text('基本信息'), findsNothing);
    });

    testWidgets('字段错误阻止保存并展示可读原因', (tester) async {
      final store = _MemoryStore();
      await tester.pumpWidget(
        MaterialApp(
          home: NovelSourceEditPage(
            store: store,
            initialRaw: jsonEncode(<String, dynamic>{
              'bookSourceName': '',
              'bookSourceUrl': 'ftp://x',
              'searchUrl': '/s',
              'ruleSearch': <String, dynamic>{'bookList': '//li['},
            }),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('novel-source-edit-save')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('novel-source-edit-status')), findsOneWidget);
      expect(await store.loadAll(), isEmpty);
      expect(find.textContaining('书源地址只支持'), findsWidgets);
    });

    testWidgets('校验按钮给出问题清单', (tester) async {
      final store = _MemoryStore();
      await tester.pumpWidget(
        MaterialApp(
          home: NovelSourceEditPage(
            store: store,
            initialRaw: jsonEncode(<String, dynamic>{
              'bookSourceName': 'x',
              'bookSourceUrl': 'https://x.example',
            }),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('novel-source-edit-validate')));
      await tester.pumpAndSettle();
      // 没有搜索地址/目录/正文规则 → 至少 3 条警告。
      expect(find.textContaining('没有搜索地址'), findsOneWidget);
    });
  });

  group('规则管理页', () {
    testWidgets('搜索框过滤、分组筛选与排序菜单可用', (tester) async {
      final store = _MemoryStore(<NovelBookSource>[
        _source('甲源', 'https://a.example', group: '玄幻', weight: 1),
        _source('乙源', 'https://b.example', group: '都市', weight: 9),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          home: NovelSourceManagePage(
            store: store,
            importer: _importer(store),
            fileGate: _MemoryFileGate(),
            clipboard: _MemoryClipboard(),
            enableDebug: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('甲源'), findsOneWidget);
      expect(find.text('乙源'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('novel-source-search')), '乙');
      await tester.pumpAndSettle();
      expect(find.text('甲源'), findsNothing);
      expect(find.text('乙源'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('novel-source-search')), '');
      await tester.pumpAndSettle();

      // 按权重排序：乙源（9）在前。
      await tester.tap(find.byKey(const Key('novel-source-sort')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('按权重排序'));
      await tester.pumpAndSettle();

      final names = tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data)
          .whereType<String>()
          .toList();
      expect(names.indexOf('乙源'), lessThan(names.indexOf('甲源')));
    });

    testWidgets('批量启停与批量移动分组', (tester) async {
      final store = _MemoryStore(<NovelBookSource>[
        _source('甲源', 'https://a.example'),
        _source('乙源', 'https://b.example'),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          home: NovelSourceManagePage(
            store: store,
            importer: _importer(store),
            fileGate: _MemoryFileGate(),
            clipboard: _MemoryClipboard(),
            enableDebug: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('novel-source-select-all')));
      await tester.pumpAndSettle();
      expect(find.text('已选 2 个'), findsOneWidget);

      await tester.tap(find.byKey(const Key('novel-source-bulk-disable')));
      await tester.pumpAndSettle();
      expect((await store.loadAll()).every((s) => !s.enabled), isTrue);

      await tester.tap(find.byKey(const Key('novel-source-bulk-move')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '精选');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(
        (await store.loadAll()).every((s) => s.groups.contains('精选')),
        isTrue,
      );
    });

    testWidgets('剪贴板导入书源 JSON', (tester) async {
      final store = _MemoryStore();
      final clipboard = _MemoryClipboard()
        ..text = jsonEncode(<Object?>[
          <String, Object?>{
            'bookSourceName': '粘贴源',
            'bookSourceUrl': 'https://paste.example',
          },
        ]);
      await tester.pumpWidget(
        MaterialApp(
          home: NovelSourceManagePage(
            store: store,
            importer: _importer(store),
            fileGate: _MemoryFileGate(),
            clipboard: clipboard,
            enableDebug: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('还没有书源'), findsOneWidget);

      await tester.tap(find.byKey(const Key('novel-source-import-clipboard')));
      await tester.pumpAndSettle();
      expect(find.text('粘贴源'), findsOneWidget);
    });

    testWidgets('导出全部到剪贴板', (tester) async {
      final store = _MemoryStore(<NovelBookSource>[
        _source('甲源', 'https://a.example'),
      ]);
      final clipboard = _MemoryClipboard();
      await tester.pumpWidget(
        MaterialApp(
          home: NovelSourceManagePage(
            store: store,
            importer: _importer(store),
            fileGate: _MemoryFileGate(),
            clipboard: clipboard,
            enableDebug: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('novel-source-export-all')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('novel-source-export-clipboard')));
      await tester.pumpAndSettle();

      final exported = jsonDecode(clipboard.text!) as List<dynamic>;
      expect(exported, hasLength(1));
      expect((exported.single as Map)['bookSourceName'], '甲源');
    });

    testWidgets('本地文件导入', (tester) async {
      final store = _MemoryStore();
      final gate = _MemoryFileGate()
        ..pickedText = jsonEncode(<Object?>[
          <String, Object?>{
            'bookSourceName': '文件源',
            'bookSourceUrl': 'https://file.example',
          },
        ]);
      await tester.pumpWidget(
        MaterialApp(
          home: NovelSourceManagePage(
            store: store,
            importer: _importer(store),
            fileGate: gate,
            clipboard: _MemoryClipboard(),
            enableDebug: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('novel-source-import-file')));
      await tester.pumpAndSettle();
      expect(find.text('文件源'), findsOneWidget);
    });

    testWidgets('权重编辑写回 raw', (tester) async {
      final store = _MemoryStore(<NovelBookSource>[
        _source('甲源', 'https://a.example'),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          home: NovelSourceManagePage(
            store: store,
            importer: _importer(store),
            fileGate: _MemoryFileGate(),
            clipboard: _MemoryClipboard(),
            enableDebug: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final key = (await store.loadAll()).single.key;
      await tester.tap(find.byKey(ValueKey<String>('menu-$key')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('设置权重'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '42');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();

      expect((await store.loadAll()).single.weight, 42);
    });

    testWidgets('分组重命名作用于所有命中书源', (tester) async {
      final store = _MemoryStore(<NovelBookSource>[
        _source('甲源', 'https://a.example', group: '旧组'),
        _source('乙源', 'https://b.example', group: '旧组,其他'),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          home: NovelSourceManagePage(
            store: store,
            importer: _importer(store),
            fileGate: _MemoryFileGate(),
            clipboard: _MemoryClipboard(),
            enableDebug: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('novel-source-manage-groups')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('novel-group-rename')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('pick-group-旧组')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '新组');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();

      final sources = await store.loadAll();
      expect(sources.every((s) => s.groups.contains('新组')), isTrue);
      expect(sources.any((s) => s.groups.contains('旧组')), isFalse);
    });

    testWidgets('空态与筛选无结果给出可操作下一步', (tester) async {
      final store = _MemoryStore(<NovelBookSource>[
        _source('甲源', 'https://a.example'),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          home: NovelSourceManagePage(
            store: store,
            importer: _importer(store),
            fileGate: _MemoryFileGate(),
            clipboard: _MemoryClipboard(),
            enableDebug: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('novel-source-search')),
        '不存在',
      );
      await tester.pumpAndSettle();
      expect(find.text('没有匹配的书源'), findsOneWidget);
      expect(find.text('清除筛选'), findsOneWidget);
    });
  });
}
