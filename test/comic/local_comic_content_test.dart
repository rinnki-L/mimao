// 本地漫画内容读取单测：下载清单详情/页序、旧文件夹扫描、自然排序、URL
// 解码、remove 清理与坏 payload 回退。全部走内存库 + 系统临时目录。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/comic/comic_models.dart';
import 'package:mimao/comic/local_comic_content.dart';
import 'package:mimao/comic/local_comic_manifest.dart';
import 'package:mimao/comic/local_comic_service.dart';
import 'package:path/path.dart' as p;

import 'comic_test_env.dart';

void main() {
  late ComicTestEnv env;
  late ComicLocalService local;
  late ComicLocalContent content;
  final tempDirs = <Directory>[];

  setUp(() {
    env = ComicTestEnv.create();
    local = ComicLocalService(env.comicDb, env.library);
    content = ComicLocalContent(local);
  });

  tearDown(() async {
    for (final dir in tempDirs) {
      if (await dir.exists()) await dir.delete(recursive: true);
    }
    tempDirs.clear();
    await env.close();
  });

  Directory newRoot() {
    final dir = Directory.systemTemp.createTempSync('mimao-local-');
    tempDirs.add(dir);
    return dir;
  }

  void writeBytes(String path) {
    File(path)
      ..createSync(recursive: true)
      ..writeAsBytesSync(const <int>[1, 2, 3]);
  }

  String fileUri(String path) => File(path).uri.toString();

  test('下载清单：详情字段与章节 URL + 阅读页自然序', () async {
    final root = newRoot();
    writeBytes(p.join(root.path, 'cover.jpg'));
    for (final name in <String>['1.jpg', '2.jpg', '10.jpg', 'notes.txt']) {
      writeBytes(p.join(root.path, 'ch1', name));
    }
    for (final name in <String>['1.png', '2.webp']) {
      writeBytes(p.join(root.path, 'ch2', name));
    }

    const manifest = LocalComicManifest(
      sourceName: 'demo',
      sourceTitle: '演示源',
      detailUrl: 'https://example.com/detail/1',
      description: '测试简介',
      cover: 'cover.jpg',
      chapters: <LocalComicChapterInfo>[
        LocalComicChapterInfo(id: 'c1', title: '第一章', dir: 'ch1', pages: 3),
        LocalComicChapterInfo(id: 'c2', title: '第二章', dir: 'ch2', pages: 2),
      ],
    );
    final ref = ComicRef.local('downloaded');
    final entry = await local.import(
      ref: ref,
      title: '下载漫画',
      folderPath: root.path,
      pageCount: manifest.pageCount,
      payload: manifest.encode(),
    );

    final detail = await content.detail(entry);
    expect(detail.title, '下载漫画');
    expect(detail.sourceName, '演示源');
    expect(detail.detailUrl, 'https://example.com/detail/1');
    expect(detail.description, '测试简介');
    expect(detail.coverUrl, p.join(root.path, 'cover.jpg'));
    expect(detail.chapters, hasLength(2));
    expect(detail.chapters[0].number, 1);
    expect(detail.chapters[0].title, '第一章');
    expect(detail.chapters[0].url, localChapterUrl(0));
    expect(detail.chapters[1].number, 2);
    expect(detail.chapters[1].title, '第二章');
    expect(detail.chapters[1].url, localChapterUrl(1));

    final chapters = await content.readerChapters(entry);
    expect(chapters, hasLength(2));
    expect(chapters[0].title, '第一章');
    expect(chapters[0].imageUrls, <String>[
      fileUri(p.join(root.path, 'ch1', '1.jpg')),
      fileUri(p.join(root.path, 'ch1', '2.jpg')),
      fileUri(p.join(root.path, 'ch1', '10.jpg')),
    ]);
    expect(chapters[1].imageUrls, <String>[
      fileUri(p.join(root.path, 'ch2', '1.png')),
      fileUri(p.join(root.path, 'ch2', '2.webp')),
    ]);
  });

  test('旧文件夹：子目录自然排序成章 + 单章根目录 + cover 排除', () async {
    // (a) 子目录章节，第1话里放 cover.jpg、第2话里放 .txt 验证过滤。
    final multi = newRoot();
    writeBytes(p.join(multi.path, '第1话', '1.jpg'));
    writeBytes(p.join(multi.path, '第1话', 'cover.jpg'));
    writeBytes(p.join(multi.path, '第2话', '1.jpg'));
    writeBytes(p.join(multi.path, '第2话', 'notes.txt'));

    final refA = ComicRef.local('legacy-multi');
    final entryA = await local.import(
      ref: refA,
      title: '旧漫画',
      folderPath: multi.path,
    );
    final detailA = await content.detail(entryA);
    expect(detailA.chapters.map((c) => c.title).toList(), <String>[
      '第1话',
      '第2话',
    ]);
    expect(detailA.chapters.map((c) => c.number).toList(), <int>[1, 2]);
    final pagesA = await content.readerChapters(entryA);
    expect(pagesA, hasLength(2));
    expect(pagesA[0].imageUrls, <String>[
      fileUri(p.join(multi.path, '第1话', '1.jpg')),
    ]);
    expect(pagesA[1].imageUrls, <String>[
      fileUri(p.join(multi.path, '第2话', '1.jpg')),
    ]);

    // (b) 图片直接在根目录：整根算单章，cover.jpg / .txt 不进页表。
    final single = newRoot();
    for (final name in <String>['1.jpg', '2.jpg', 'cover.jpg', 'notes.txt']) {
      writeBytes(p.join(single.path, name));
    }
    final refB = ComicRef.local('legacy-single');
    final entryB = await local.import(
      ref: refB,
      title: '单章漫画',
      folderPath: single.path,
    );
    final detailB = await content.detail(entryB);
    expect(detailB.chapters, hasLength(1));
    expect(detailB.chapters.single.title, '单章漫画');
    final pagesB = await content.readerChapters(entryB);
    expect(pagesB, hasLength(1));
    expect(pagesB.single.imageUrls, <String>[
      fileUri(p.join(single.path, '1.jpg')),
      fileUri(p.join(single.path, '2.jpg')),
    ]);
  });

  test('compareNatural 数值段按数字比较且相等时稳定', () {
    expect(compareNatural('2.jpg', '10.jpg'), lessThan(0));
    expect(compareNatural('10.jpg', '2.jpg'), greaterThan(0));
    expect(compareNatural('第1话', '第2话'), lessThan(0));
    expect(compareNatural('1.jpg', '1.jpg'), 0);
    expect(compareNatural('第1话', '第1话'), 0);
  });

  test('tryDecodeLocalChapterUrl 只认 mimao-local 单段数字', () {
    expect(tryDecodeLocalChapterUrl('mimao-local:///2'), 2);
    expect(tryDecodeLocalChapterUrl('mimao-local:///0'), 0);
    expect(tryDecodeLocalChapterUrl('https://example.com/2'), isNull);
    expect(tryDecodeLocalChapterUrl('mimao-local:///abc'), isNull);
    expect(tryDecodeLocalChapterUrl('mimao-local:///1/2'), isNull);
    expect(tryDecodeLocalChapterUrl('not a url'), isNull);
  });

  test('remove 删磁盘目录与元数据行，目录缺失也不抛', () async {
    final root = newRoot();
    writeBytes(p.join(root.path, '1.jpg'));
    final ref = ComicRef.local('to-remove');
    await local.import(ref: ref, title: '待删', folderPath: root.path);

    await content.remove(ref);
    expect(await Directory(root.path).exists(), isFalse);
    expect(await content.find(ref), isNull);
    expect(await local.find(ref), isNull);

    // 目录被外部先删掉：remove 仍正常删行、不抛异常。
    final root2 = newRoot();
    writeBytes(p.join(root2.path, '1.jpg'));
    final ref2 = ComicRef.local('missing-dir');
    await local.import(ref: ref2, title: '缺目录', folderPath: root2.path);
    await Directory(root2.path).delete(recursive: true);
    await expectLater(content.remove(ref2), completes);
    expect(await local.find(ref2), isNull);
  });

  test('坏 payload 回退文件夹扫描，不抛异常', () async {
    final root = newRoot();
    for (final name in <String>['1.jpg', '2.jpg']) {
      writeBytes(p.join(root.path, name));
    }
    final ref = ComicRef.local('bad-payload');
    final entry = await local.import(
      ref: ref,
      title: '坏清单',
      folderPath: root.path,
      payload: '{not-json',
    );

    final detail = await content.detail(entry);
    expect(detail.chapters, hasLength(1));
    expect(detail.chapters.single.title, '坏清单');
    expect(detail.sourceName, '本地');
    final pages = await content.readerChapters(entry);
    expect(pages.single.imageUrls, <String>[
      fileUri(p.join(root.path, '1.jpg')),
      fileUri(p.join(root.path, '2.jpg')),
    ]);
  });
}
