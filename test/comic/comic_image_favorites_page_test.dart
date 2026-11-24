// 图片收藏页：三态、缩略图、取消收藏。

// ignore_for_file: deprecated_member_use — 见 lib/main.dart 文件头同款说明。

import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/comic/comic_db.dart';
import 'package:mimao/comic/image_favorite_service.dart';
import 'package:mimao/comic/pages/comic_image_favorites_page.dart';
import 'package:mimao/comic/reader/reader_cache.dart';

/// 1×1 PNG，能被 MemoryImage 解码。
final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8AAAwAB/AF+kLQIAAAAAElFTkSuQmCC',
);

ImageFavoriteInput _input({int page = 2, String comicId = 'c1'}) =>
    ImageFavoriteInput(
      sourceName: 'src',
      comicId: comicId,
      comicTitle: '测试漫画',
      chapterId: 'ep-1',
      chapterNumber: 1,
      chapterTitle: '第 1 章',
      page: page,
      pageCount: 10,
      imageUrl: 'https://img/$comicId/$page.jpg',
    );

void main() {
  late ComicDb db;
  late ComicImageFavoriteService service;
  late ReaderImageCache cache;

  setUp(() {
    db = ComicDb.forTesting(NativeDatabase.memory());
    service = ComicImageFavoriteService(db);
    cache = ReaderImageCache(
      loader: (_) async => _png,
      disk: MemoryByteStore(),
    );
  });

  tearDown(() => db.close());

  Widget app({Future<void> Function(ImageFavorite)? onOpen}) => MaterialApp(
    home: ComicImageFavoritesPage(
      service: service,
      cache: cache,
      onOpen: onOpen,
    ),
  );

  testWidgets('空态说明为什么空与下一步', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('image-favorites-empty')), findsOneWidget);
    expect(find.textContaining('还没有收藏的图片'), findsOneWidget);
    expect(find.textContaining('点顶栏的星标'), findsOneWidget);
  });

  testWidgets('有收藏时渲染网格与章节页码', (tester) async {
    await service.toggle(_input(page: 2));
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('image-favorites-grid')), findsOneWidget);
    expect(find.text('测试漫画'), findsWidgets);
    expect(find.textContaining('第 1 章 · 第 2 页'), findsOneWidget);
  });

  testWidgets('点缩略图触发回跳回调', (tester) async {
    await service.toggle(_input(page: 2));
    ImageFavorite? opened;
    await tester.pumpWidget(app(onOpen: (favorite) async => opened = favorite));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('image-favorite-src-c1-ep-1-2')));
    await tester.pumpAndSettle();

    expect(opened, isNotNull);
    expect(opened!.page, 2);
  });

  testWidgets('长按取消收藏：确认后从列表移除', (tester) async {
    await service.toggle(_input(page: 2));
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.longPress(
      find.byKey(const Key('image-favorite-src-c1-ep-1-2')),
    );
    await tester.pumpAndSettle();
    expect(find.text('取消收藏这张图？'), findsOneWidget);

    await tester.tap(find.text('取消收藏'));
    await tester.pumpAndSettle();

    expect(await service.count(), 0);
    expect(find.byKey(const Key('image-favorites-empty')), findsOneWidget);
  });

  testWidgets('取消对话框点「保留」不删除', (tester) async {
    await service.toggle(_input(page: 2));
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.longPress(
      find.byKey(const Key('image-favorite-src-c1-ep-1-2')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('保留'));
    await tester.pumpAndSettle();

    expect(await service.count(), 1);
  });
}
