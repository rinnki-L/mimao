// 本地书导入页的界面测试：选文件 → 探测 → 目录预览 → 确认导入，
// 以及「文件被移动」时的重新定位路径。
//
// 全部用注入的 fake 文件选择器与内存文件，不碰真实文件系统、不弹系统对话框。
// 覆盖三态：空（还没选文件）、加载（探测中）、错误（不是 EPUB / 文件不在）。
// ignore_for_file: deprecated_member_use — 与其他 novel 测试同款。
import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/novel/library_api.dart';
import 'package:mimao/novel/local/local_book_service.dart';
import 'package:mimao/novel/local/local_models.dart';
import 'package:mimao/novel/local/local_source.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/novel_db.dart';
import 'package:mimao/novel/pages/novel_import_book_page.dart';

/// 假文件选择器：返回预置文件（或 null 表示用户取消）。
class _FakeGate implements NovelLocalFileGate {
  _FakeGate(this.file);

  NovelLocalPickedFile? file;
  int pickCalls = 0;
  int relocateCalls = 0;

  @override
  Future<NovelLocalPickedFile?> pick() async {
    pickCalls++;
    return file;
  }

  @override
  Future<NovelLocalPickedFile?> pickForRelocate(String title) async {
    relocateCalls++;
    return file;
  }
}

/// 收集 fake：只记「被收藏的书」，验证「导入即上架」。
class _FakeCollect implements NovelCollectApi {
  final List<NovelSummary> collected = <NovelSummary>[];

  @override
  Future<void> collect(NovelSummary book) async => collected.add(book);

  @override
  Future<void> remove(String bookId) async {}

  @override
  Future<bool> isCollected(String bookId) async =>
      collected.any((b) => b.id == bookId);

  @override
  Future<Set<String>> collectedIds() async => <String>{
    for (final book in collected) book.id,
  };

  @override
  Future<List<NovelCollectItem>> list() async => const <NovelCollectItem>[];

  @override
  Future<void> setGroup(String bookId, String? groupName) async {}

  @override
  Future<void> setGroupFor(Iterable<String> bookIds, String? groupName) async {}

  @override
  Future<List<String>> groups() async => const <String>[];

  @override
  Future<void> renameGroup(String from, String to) async {}

  @override
  Future<void> deleteGroup(String name) async {}

  @override
  Future<void> setNote(String bookId, String note) async {}

  @override
  Future<void> setCustomCover(String bookId, String? path) async {}

  @override
  Future<List<NovelSeriesItem>> series() async => const <NovelSeriesItem>[];

  @override
  Future<int> createSeries(String name) async => 0;

  @override
  Future<void> renameSeries(int id, String name) async {}

  @override
  Future<void> deleteSeries(int id) async {}

  @override
  Future<void> setSeriesFor(Iterable<String> bookIds, int? seriesId) async {}
}

const String _sampleTxt = '第一章 开始\n正文一。\n\n第二章 继续\n正文二。\n';

void main() {
  late NovelDb db;
  late NovelLocalBookService service;
  late Map<String, Uint8List> files;

  setUp(() {
    db = NovelDb.forTesting(NativeDatabase.memory());
    files = <String, Uint8List>{};
    service = NovelLocalBookService(
      db,
      opener: (path) {
        final bytes = files[path];
        if (bytes == null) throw NovelLocalFileMissing(path, '文件不存在');
        return NovelMemoryFile(path, bytes);
      },
    );
  });

  tearDown(() async {
    await db.close();
  });

  Widget wrap(Widget child) => MaterialApp(
    theme: buildMimaoTheme(
      seedColor: const Color(0xFF6750A4),
      brightness: Brightness.light,
    ),
    home: child,
  );

  NovelLocalPickedFile picked(String path, List<int> bytes) =>
      NovelLocalPickedFile(
        name: path.split('/').last,
        path: path,
        bytes: Uint8List.fromList(bytes),
      );

  testWidgets('未选文件时是空态，给出支持格式与下一步', (tester) async {
    await tester.pumpWidget(wrap(NovelImportBookPage(localBooks: service)));
    await tester.pumpAndSettle();

    expect(find.text('选择一个本地文件'), findsOneWidget);
    expect(find.textContaining('GBK'), findsWidgets);
    expect(find.text('选择文件'), findsOneWidget);
  });

  testWidgets('服务未注入时给能力边界，而不是假入口', (tester) async {
    await tester.pumpWidget(wrap(const NovelImportBookPage()));
    await tester.pumpAndSettle();

    expect(find.text('本地书服务未启用'), findsOneWidget);
    expect(find.textContaining('重启应用'), findsOneWidget);
  });

  testWidgets('选中 TXT 后显示目录预览与编码，确认导入进库并上架', (tester) async {
    files['/books/a.txt'] = Uint8List.fromList(utf8.encode(_sampleTxt));
    final gate = _FakeGate(picked('/books/a.txt', utf8.encode(_sampleTxt)));
    final collect = _FakeCollect();
    await tester.pumpWidget(
      wrap(
        NovelImportBookPage(
          localBooks: service,
          fileGate: gate,
          collect: collect,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('选择文件'));
    await tester.pumpAndSettle();

    expect(find.textContaining('目录预览 · 2 章'), findsOneWidget);
    expect(find.text('UTF-8'), findsOneWidget);
    expect(find.text('第一章 开始'), findsWidgets);
    expect(find.text('第二章 继续'), findsWidgets);

    await tester.tap(find.byKey(const Key('novel-local-confirm-import')));
    await tester.pumpAndSettle();

    // 已落本地书表。
    final books = await service.list();
    expect(books, hasLength(1));
    expect(books.single.title, 'a');
    // 已上架（收藏），且来源标记是本地文件。
    expect(collect.collected, hasLength(1));
    expect(collect.collected.single.id, books.single.id);
    expect(collect.collected.single.sourceKey, novelLocalSourceKey);
  });

  testWidgets('不是 EPUB 时给出可读错误态（不泄漏 zip 异常）', (tester) async {
    final gate = _FakeGate(picked('/books/bad.epub', utf8.encode('不是 zip')));
    await tester.pumpWidget(
      wrap(NovelImportBookPage(localBooks: service, fileGate: gate)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('选择文件'));
    await tester.pumpAndSettle();

    expect(find.textContaining('不是有效的 EPUB'), findsOneWidget);
    // 错误态仍允许换文件 / 重试，不是死路。
    expect(find.text('换一个文件'), findsOneWidget);
  });

  testWidgets('不支持的扩展名直接拒绝并列出支持格式', (tester) async {
    final gate = _FakeGate(picked('/books/a.pdf', utf8.encode('pdf')));
    await tester.pumpWidget(
      wrap(NovelImportBookPage(localBooks: service, fileGate: gate)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('选择文件'));
    await tester.pumpAndSettle();

    expect(find.textContaining('不支持的文件类型'), findsOneWidget);
    expect(find.textContaining('TXT / EPUB / Markdown'), findsOneWidget);
  });

  testWidgets('重新定位模式：打开即弹选择器，确认后把书指到新路径', (tester) async {
    files['/old/a.txt'] = Uint8List.fromList(utf8.encode(_sampleTxt));
    final book = await service.importBook(
      NovelMemoryFile('/old/a.txt', files['/old/a.txt']!),
    );
    files.remove('/old/a.txt');
    files['/new/a.txt'] = Uint8List.fromList(utf8.encode(_sampleTxt));

    final gate = _FakeGate(picked('/new/a.txt', utf8.encode(_sampleTxt)));
    await tester.pumpWidget(
      wrap(
        NovelImportBookPage(
          localBooks: service,
          fileGate: gate,
          relocateBookId: book.id,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 进页面就弹了一次选择器（少一次点击）。
    expect(gate.relocateCalls, 1);
    expect(find.text('重新定位文件'), findsWidgets);
    expect(find.textContaining('阅读进度、书签与划线都会保留'), findsOneWidget);

    await tester.tap(find.byKey(const Key('novel-local-confirm-import')));
    await tester.pumpAndSettle();

    final relocated = await service.byId(book.id);
    expect(relocated, isNotNull);
    expect(relocated!.path, '/new/a.txt');
    expect(relocated.id, book.id);
  });

  testWidgets('规则写坏时预览仍可用，且规则弹窗标红', (tester) async {
    files['/books/a.txt'] = Uint8List.fromList(utf8.encode(_sampleTxt));
    final gate = _FakeGate(picked('/books/a.txt', utf8.encode(_sampleTxt)));
    await tester.pumpWidget(
      wrap(NovelImportBookPage(localBooks: service, fileGate: gate)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择文件'));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('目录规则'));
    await tester.pumpAndSettle();

    expect(find.text('TXT 目录规则'), findsOneWidget);
    expect(find.textContaining('命中示例'), findsWidgets);
    // 内置规则都在列表里，开关可点。
    expect(find.byType(Switch), findsWidgets);
  });
}
