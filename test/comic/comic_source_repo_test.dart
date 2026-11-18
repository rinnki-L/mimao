// ignore_for_file: deprecated_member_use — 见 test/comic/comic_pages_test.dart 同款说明。
// 源管理页「源仓库」区块的 widget 测试：浏览 → 勾选 → 导入选中。
//
// 用真实 ComicSourceCatalog + 假 HTTP 客户端（清单走真解析/拼接逻辑），
// 仓库写操作用记录型假仓库，全离线、不依赖 DLL。
library;

import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/comic/comic_db.dart';
import 'package:mimao/comic/data/comic_data_source.dart';
import 'package:mimao/comic/data/comic_models.dart';
import 'package:mimao/comic/engine/engine.dart';
import 'package:mimao/comic/pages/comic_module_settings.dart';
import 'package:mimao/comic/pages/comic_source_page.dart';
import 'package:mimao/comic/search_history_service.dart';

const String _indexUrl = 'https://rules.test/list/index.json';

/// 记录 importSource 收到的 URL；每次导入追加一条来源。
class _RecordingRepo implements ComicSourceRepository {
  final List<String> importedUrls = <String>[];

  /// 非空 URL 时抛错（导入失败容错测试）。
  String? throwOnImport;

  final List<ComicSourceInfo> _sources = <ComicSourceInfo>[
    const ComicSourceInfo(
      id: 'existing',
      name: '已有源',
      url: 'https://x.test/e.js',
    ),
  ];

  List<ComicSourceInfo> get snapshot =>
      List<ComicSourceInfo>.unmodifiable(_sources);

  @override
  Future<List<ComicSourceInfo>> listSources() async => snapshot;

  @override
  Future<List<ComicSourceInfo>> importSource(String url) async {
    if (throwOnImport != null && throwOnImport == url) {
      throw StateError('脚本下载失败');
    }
    importedUrls.add(url);
    final name = url.split('/').last;
    _sources.add(ComicSourceInfo(id: name, name: name, url: url));
    return snapshot;
  }

  @override
  Future<List<ComicSourceInfo>> setEnabled(String id, bool enabled) async =>
      snapshot;

  @override
  Future<List<ComicSourceInfo>> deleteSource(String id) async {
    _sources.removeWhere((s) => s.id == id);
    return snapshot;
  }
}

const String _indexBody =
    '[{"name":"拷贝漫画","fileName":"copy_manga.js","key":"copy_manga",'
    '"version":"1.4.3"},'
    '{"name":"酷漫","fileName":"kuman.js","key":"kuman","version":"1.0",'
    '"description":"备用"}]';

Widget _app(Widget home) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: ThemeData(
    useMaterial3: true,
    colorSchemeSeed: const Color(0xFF7C6BFF),
  ),
  home: home,
);

void _usePhoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _browse(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('comic-repo-url')), _indexUrl);
  await tester.tap(find.byKey(const Key('comic-repo-browse')));
  await tester.pumpAndSettle();
}

void main() {
  ComicSourceCatalog catalogWith(String body) => ComicSourceCatalog(
    client: _FakeClient(<String, String>{_indexUrl: body}),
  );

  testWidgets('catalog 为 null：不渲染仓库区块', (tester) async {
    _usePhoneSize(tester);
    await tester.pumpWidget(
      _app(ComicSourcePage(repository: _RecordingRepo())),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('comic-repo-browse')), findsNothing);
    expect(find.text('从 URL 导入源'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('浏览仓库：列出清单源并显示版本/描述', (tester) async {
    _usePhoneSize(tester);
    final repo = _RecordingRepo();
    await tester.pumpWidget(
      _app(ComicSourcePage(repository: repo, catalog: catalogWith(_indexBody))),
    );
    await tester.pumpAndSettle();

    await _browse(tester);

    expect(
      find.byKey(const Key('comic-repo-check-copy_manga')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('comic-repo-check-kuman')), findsOneWidget);
    expect(find.text('拷贝漫画'), findsOneWidget);
    expect(find.textContaining('v1.4.3'), findsOneWidget);
    expect(find.textContaining('备用'), findsOneWidget);
    expect(find.textContaining('发现 2 个源'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('非法清单地址：不发请求并提示', (tester) async {
    _usePhoneSize(tester);
    final repo = _RecordingRepo();
    await tester.pumpWidget(
      _app(ComicSourcePage(repository: repo, catalog: catalogWith(_indexBody))),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('comic-repo-url')),
      'https://user:pw@rules.test/index.json',
    );
    await tester.tap(find.byKey(const Key('comic-repo-browse')));
    await tester.pumpAndSettle();

    expect(repo.importedUrls, isEmpty);
    expect(find.textContaining('仓库地址不合法'), findsOneWidget);
    expect(find.byKey(const Key('comic-repo-check-copy_manga')), findsNothing);
  });

  testWidgets('清单读取失败：显示原因且不发起导入', (tester) async {
    _usePhoneSize(tester);
    final repo = _RecordingRepo();
    await tester.pumpWidget(
      _app(ComicSourcePage(repository: repo, catalog: catalogWith('not json'))),
    );
    await tester.pumpAndSettle();

    await _browse(tester);

    expect(find.textContaining('不是合法 JSON'), findsOneWidget);
    expect(find.byKey(const Key('comic-repo-import-selected')), findsNothing);
    expect(repo.importedUrls, isEmpty);
  });

  testWidgets('空清单：显示空态，无导入按钮', (tester) async {
    _usePhoneSize(tester);
    await tester.pumpWidget(
      _app(
        ComicSourcePage(
          repository: _RecordingRepo(),
          catalog: catalogWith('[]'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _browse(tester);

    expect(find.byKey(const Key('comic-repo-empty')), findsOneWidget);
    expect(find.byKey(const Key('comic-repo-import-selected')), findsNothing);
  });

  testWidgets('全选并导入选中：逐条走 importSource，列表与回调更新', (tester) async {
    _usePhoneSize(tester);
    final repo = _RecordingRepo();
    final imported = <String>[];
    await tester.pumpWidget(
      _app(
        ComicSourcePage(
          repository: repo,
          catalog: catalogWith(_indexBody),
          onImport: imported.add,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _browse(tester);
    await tester.tap(find.byKey(const Key('comic-repo-select-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('comic-repo-import-selected')));
    await tester.pumpAndSettle();

    expect(repo.importedUrls, <String>[
      'https://rules.test/list/copy_manga.js',
      'https://rules.test/list/kuman.js',
    ]);
    expect(imported, repo.importedUrls);
    expect(find.text('已导入 3 个来源'), findsOneWidget);
    expect(find.textContaining('导入 2 个源'), findsOneWidget);
  });

  testWidgets('单个勾选导入：只导入所选那条', (tester) async {
    _usePhoneSize(tester);
    final repo = _RecordingRepo();
    await tester.pumpWidget(
      _app(ComicSourcePage(repository: repo, catalog: catalogWith(_indexBody))),
    );
    await tester.pumpAndSettle();

    await _browse(tester);
    await tester.tap(find.byKey(const Key('comic-repo-check-kuman')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('comic-repo-import-selected')));
    await tester.pumpAndSettle();

    expect(repo.importedUrls, <String>['https://rules.test/list/kuman.js']);
    expect(find.text('已导入 2 个来源'), findsOneWidget);
  });

  testWidgets('导入失败：显示失败源与原因，已成功的照常计入', (tester) async {
    _usePhoneSize(tester);
    final repo = _RecordingRepo()
      ..throwOnImport = 'https://rules.test/list/kuman.js';
    await tester.pumpWidget(
      _app(ComicSourcePage(repository: repo, catalog: catalogWith(_indexBody))),
    );
    await tester.pumpAndSettle();

    await _browse(tester);
    await tester.tap(find.byKey(const Key('comic-repo-select-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('comic-repo-import-selected')));
    await tester.pumpAndSettle();

    expect(repo.importedUrls, <String>[
      'https://rules.test/list/copy_manga.js',
    ]);
    expect(find.textContaining('导入 1 个，失败 1 个'), findsOneWidget);
    // 失败原因带上源名与异常文本（经 comic-repo-message 精确取，避免撞上
    // 列表里同名的标题 Text）。
    final message = tester.widget<Text>(
      find.byKey(const Key('comic-repo-message')),
    );
    expect(message.data, contains('酷漫'));
    expect(message.data, contains('脚本下载失败'));
    // 失败后按钮恢复可用。
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('comic-repo-import-selected')),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('浏览后改动清单地址：导入被拒并提示重新浏览', (tester) async {
    _usePhoneSize(tester);
    final repo = _RecordingRepo();
    await tester.pumpWidget(
      _app(ComicSourcePage(repository: repo, catalog: catalogWith(_indexBody))),
    );
    await tester.pumpAndSettle();

    await _browse(tester);
    await tester.tap(find.byKey(const Key('comic-repo-select-all')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('comic-repo-url')),
      'https://other.test/list/index.json',
    );
    await tester.tap(find.byKey(const Key('comic-repo-import-selected')));
    await tester.pumpAndSettle();

    expect(repo.importedUrls, isEmpty);
    expect(find.textContaining('清单地址已改动'), findsOneWidget);
  });

  testWidgets('浏览在途时手动导入入口禁用，结束后恢复', (tester) async {
    _usePhoneSize(tester);
    final client = _FakeClient(<String, String>{_indexUrl: _indexBody});
    final gate = Completer<void>();
    client.gate = gate;
    await tester.pumpWidget(
      _app(
        ComicSourcePage(
          repository: _RecordingRepo(),
          catalog: ComicSourceCatalog(client: client),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('comic-repo-url')), _indexUrl);
    await tester.tap(find.byKey(const Key('comic-repo-browse')));
    await tester.pump(); // fetch 挂在 gate 上，保持 in-flight

    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('import-source-button')))
          .onPressed,
      isNull,
    );
    expect(
      tester.widget<TextField>(find.byKey(const Key('comic-repo-url'))).enabled,
      isFalse,
    );

    gate.complete();
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('import-source-button')))
          .onPressed,
      isNotNull,
    );
    expect(
      tester.widget<TextField>(find.byKey(const Key('comic-repo-url'))).enabled,
      isTrue,
    );
  });

  testWidgets('设置抽屉路径打开源管理：导入回调透传模块层', (tester) async {
    _usePhoneSize(tester);
    final repo = _RecordingRepo();
    final imported = <String>[];
    final db = ComicDb.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(
      _app(
        ComicModuleSettings(
          sourceRepository: repo,
          sourceCatalog: catalogWith(_indexBody),
          searchHistory: ComicSearchHistoryService(db),
          onImportSource: imported.add,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('comic-settings-open-sources')));
    await tester.pumpAndSettle();
    await _browse(tester);
    await tester.tap(find.byKey(const Key('comic-repo-select-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('comic-repo-import-selected')));
    await tester.pumpAndSettle();

    expect(imported, <String>[
      'https://rules.test/list/copy_manga.js',
      'https://rules.test/list/kuman.js',
    ]);
  });
}

/// 按 URL 返回预置正文并记录抓取地址的假客户端。
class _FakeClient implements ComicHttpClient {
  _FakeClient(this.bodies);

  final Map<String, String> bodies;
  final List<String> fetched = <String>[];

  /// 非空时 fetch 挂起直到 complete——测试用它在途态。
  Completer<void>? gate;

  @override
  Future<ComicHttpResponse> fetch(
    String url, {
    ComicFetchOptions options = const ComicFetchOptions(),
  }) async {
    fetched.add(url);
    final pending = gate;
    if (pending != null) await pending.future;
    final body = bodies[url];
    if (body == null) {
      return const ComicHttpResponse(statusCode: 404, body: 'not found');
    }
    return ComicHttpResponse(statusCode: 200, body: body, url: url);
  }

  @override
  Future<void> setCookies(String url, Map<String, String> cookies) async {}

  @override
  List<Map<String, String>> getCookies(String url) =>
      const <Map<String, String>>[];

  @override
  Future<void> deleteCookies(String url) async {}
}
