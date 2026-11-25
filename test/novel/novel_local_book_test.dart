// 本地书（TXT / EPUB / Markdown）的纯逻辑单测：编码嗅探、TXT 分章规则、
// EPUB spine 顺序、缺文件错误态。全部用内存文件，不碰真实文件系统路径。
//
// 为什么这些点必须单独测：编码与分章是「导入一次就定死」的事，错了用户只会
// 看到乱码或整本一章，而不会被任何异常提醒；EPUB spine 顺序错了则是章节
// 乱序，肉眼很难在几百章里发现。
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:chinese_codec/chinese_codec.dart' as cc;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/local/local_book_service.dart';
import 'package:mimao/novel/local/local_encoding.dart';
import 'package:mimao/novel/local/local_engine.dart';
import 'package:mimao/novel/local/local_epub.dart';
import 'package:mimao/novel/local/local_models.dart';
import 'package:mimao/novel/local/local_source.dart';
import 'package:mimao/novel/local/local_txt.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/novel_db.dart';
import 'package:mimao/novel/reader/novel_reader_controller.dart';
import 'package:mimao/novel/reader/novel_reader_settings.dart';
import 'package:mimao/novel/source/novel_source_model.dart';
import 'package:mimao/novel/source/novel_source_store.dart';

/// 构造一个最小 EPUB（zip）：container.xml + OPF + N 个 xhtml。
Uint8List buildEpub({
  required String title,
  required String author,
  required List<(String href, String heading, String body)> chapters,
  bool reverseSpine = false,
}) {
  final archive = Archive();
  archive.add(
    ArchiveFile.string(
      'META-INF/container.xml',
      '<?xml version="1.0"?>'
          '<container version="1.0" '
          'xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
          '<rootfiles><rootfile full-path="OEBPS/content.opf" '
          'media-type="application/oebps-package+xml"/></rootfiles></container>',
    ),
  );
  final manifest = StringBuffer();
  final spine = StringBuffer();
  for (var i = 0; i < chapters.length; i++) {
    final item = chapters[i];
    manifest.write(
      '<item id="c$i" href="${item.$1}" media-type="application/xhtml+xml"/>',
    );
    final doc =
        '<?xml version="1.0" encoding="utf-8"?>'
        '<html xmlns="http://www.w3.org/1999/xhtml"><head>'
        '<title>${item.$2}</title></head><body>'
        '<h1>${item.$2}</h1><p>${item.$3}</p>'
        '<img src="pic.png" alt="插图"/></body></html>';
    archive.add(ArchiveFile.string('OEBPS/${item.$1}', doc));
  }
  final order = reverseSpine
      ? chapters.length - 1 - (chapters.length - 1)
      : 0; // 占位，见下方显式构造
  final spineOrder = <int>[for (var i = 0; i < chapters.length; i++) i];
  if (reverseSpine) {
    spineOrder.clear();
    for (var i = chapters.length - 1; i >= 0; i--) {
      spineOrder.add(i);
    }
  }
  for (final index in spineOrder) {
    spine.write('<itemref idref="c$index"/>');
  }
  assert(order == 0);
  archive.add(
    ArchiveFile.string(
      'OEBPS/content.opf',
      '<?xml version="1.0" encoding="utf-8"?>'
          '<package xmlns="http://www.idpf.org/2007/opf" version="3.0">'
          '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
          '<dc:title>$title</dc:title>'
          '<dc:creator>$author</dc:creator></metadata>'
          '<manifest>$manifest</manifest>'
          '<spine>$spine</spine></package>',
    ),
  );
  return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
}

void main() {
  group('编码嗅探', () {
    const text = '第一章 开始\n这是一段中文正文，用来判断编码。\n第二章 继续\n内容。\n';

    test('UTF-8（无 BOM）识别为 utf8，解码无坏字符', () {
      final bytes = Uint8List.fromList(utf8.encode(text));
      final guess = sniffNovelEncoding(bytes);
      expect(guess.encoding, NovelTextEncoding.utf8);
      expect(guess.lossy, isFalse);
      expect(decodeNovelText(bytes, guess.encoding), text);
    });

    test('UTF-8 BOM 剥掉，不留 \\uFEFF 在首章标题里', () {
      final bytes = Uint8List.fromList(<int>[
        0xEF,
        0xBB,
        0xBF,
        ...utf8.encode(text),
      ]);
      final guess = sniffNovelEncoding(bytes);
      expect(guess.encoding, NovelTextEncoding.utf8);
      final decoded = decodeNovelText(bytes, guess.encoding);
      expect(decoded.startsWith('\uFEFF'), isFalse);
      expect(decoded.startsWith('第一章'), isTrue);
    });

    test('UTF-16 LE（带 BOM）识别正确且能解出原文', () {
      final bytes = Uint8List.fromList(<int>[
        0xFF,
        0xFE,
        for (final unit in text.codeUnits) ...<int>[
          unit & 0xFF,
          (unit >> 8) & 0xFF,
        ],
      ]);
      final guess = sniffNovelEncoding(bytes);
      expect(guess.encoding, NovelTextEncoding.utf16le);
      expect(decodeNovelText(bytes, guess.encoding), text);
    });

    test('UTF-16 BE（带 BOM）识别正确', () {
      final bytes = Uint8List.fromList(<int>[
        0xFE,
        0xFF,
        for (final unit in text.codeUnits) ...<int>[
          (unit >> 8) & 0xFF,
          unit & 0xFF,
        ],
      ]);
      final guess = sniffNovelEncoding(bytes);
      expect(guess.encoding, NovelTextEncoding.utf16be);
      expect(decodeNovelText(bytes, guess.encoding), text);
    });

    test('GBK 识别为 GB 系（不是 UTF-8、不是 Big5）', () {
      final bytes = Uint8List.fromList(cc.gbk.encode(text));
      final guess = sniffNovelEncoding(bytes);
      expect(
        guess.encoding,
        anyOf(NovelTextEncoding.gbk, NovelTextEncoding.gb18030),
      );
      expect(guess.lossy, isFalse);
      expect(decodeNovelText(bytes, guess.encoding), text);
    });

    test('GB18030 四字节序列（生僻字）识别为 gb18030', () {
      // U+20BB7（𠮷）在 GB18030 里是 4 字节；GBK 解不出来。
      const rare = '第一章 𠮷\n正文里有一个生僻字。\n';
      final bytes = Uint8List.fromList(cc.gb18030.encode(rare));
      final guess = sniffNovelEncoding(bytes);
      expect(guess.encoding, NovelTextEncoding.gb18030);
      expect(decodeNovelText(bytes, guess.encoding), rare);
    });

    test('Big5 繁体识别为 Big5', () {
      const traditional = '第一章 開始\n這是一段繁體中文正文，用來判斷編碼。\n第二章 繼續\n內容。\n';
      final bytes = Uint8List.fromList(cc.big5.encode(traditional));
      final guess = sniffNovelEncoding(bytes);
      expect(guess.encoding, NovelTextEncoding.big5);
      expect(decodeNovelText(bytes, guess.encoding), traditional);
    });

    test('既不是 UTF-8 也不是任何中文编码时回退 UTF-8 并标 lossy + 警告', () {
      // 0x80/0xFF 在 UTF-8 里非法；这串字节也解不成任何合法中文双字节序列。
      // 刻意不以 0xFF 0xFE 开头——那本身是合法的 UTF-16LE BOM，会被正确识别。
      final bytes = Uint8List.fromList(<int>[
        0x80,
        0x80,
        0xFF,
        0xFF,
        0x80,
        0x80,
        0xFF,
        0x81,
        0x20,
      ]);
      final guess = sniffNovelEncoding(bytes);
      expect(guess.encoding, NovelTextEncoding.utf8);
      expect(guess.lossy, isTrue);
      expect(guess.warning, isNotNull);
      // 宽松解码不抛异常（界面上会显示「�」，但页面不崩）。
      expect(
        () => decodeNovelText(bytes, guess.encoding, lossy: true),
        returnsNormally,
      );
    });

    test('空文件按 UTF-8 处理，不报错', () {
      final guess = sniffNovelEncoding(Uint8List(0));
      expect(guess.encoding, NovelTextEncoding.utf8);
      expect(guess.lossy, isFalse);
    });
  });

  group('TXT 分章', () {
    const sample =
        '作者的话\n这是前言部分。\n\n'
        '第一章 开始\n正文一。\n\n'
        '第二章 继续\n正文二。\n\n'
        '第三章 结束\n正文三。\n';

    test('按「第X章」规则切出 3 章，且标题前的正文成为「前言」', () async {
      final source = NovelMemoryFile.text('book.txt', sample);
      final result = await splitNovelTxt(
        source: source,
        encoding: NovelTextEncoding.utf8,
        rules: novelDefaultTxtRules,
      );
      expect(result.chapters.map((c) => c.title).toList(), <String>[
        '前言',
        '第一章 开始',
        '第二章 继续',
        '第三章 结束',
      ]);
      expect(result.warning, isNull);
      // 区间必须覆盖全文且互不重叠（区间是**字节**偏移，中文 3 字节/字）。
      final totalBytes = utf8.encode(sample).length;
      expect(result.chapters.first.start, 0);
      expect(result.chapters.last.end, totalBytes);
      for (var i = 1; i < result.chapters.length; i++) {
        expect(result.chapters[i].start, result.chapters[i - 1].end);
      }
    });

    test('规则全停用时退回整本一章并给可读警告', () async {
      final source = NovelMemoryFile.text('book.txt', sample);
      final result = await splitNovelTxt(
        source: source,
        encoding: NovelTextEncoding.utf8,
        rules: <NovelTxtRule>[
          for (final rule in novelDefaultTxtRules)
            rule.copyWith(enabled: false),
        ],
      );
      expect(result.chapters, hasLength(1));
      expect(result.chapters.single.title, '全文');
      expect(result.warning, contains('没有可用的目录规则'));
    });

    test('没有命中任何标题时整本一章 + 提示去调规则', () async {
      final source = NovelMemoryFile.text('book.txt', '只有正文，没有章节标题。\n第二行。\n');
      final result = await splitNovelTxt(
        source: source,
        encoding: NovelTextEncoding.utf8,
        rules: novelDefaultTxtRules,
      );
      expect(result.chapters, hasLength(1));
      expect(result.warning, contains('没有匹配到任何章节标题'));
    });

    test('自定义规则（如「卷」）可覆盖默认行为', () async {
      const text = '第一卷 起\n甲。\n第二卷 承\n乙。\n';
      final source = NovelMemoryFile.text('book.txt', text);
      final result = await splitNovelTxt(
        source: source,
        encoding: NovelTextEncoding.utf8,
        rules: const <NovelTxtRule>[
          NovelTxtRule(name: '卷', pattern: r'^第[一二三四五六七八九十]+卷\s'),
        ],
      );
      expect(result.chapters.map((c) => c.title).toList(), <String>[
        '第一卷 起',
        '第二卷 承',
      ]);
      expect(result.usedRule, '卷');
    });

    test('超长行（正文里提到「第一章」）不被误当标题', () async {
      final longLine = '第一章 他这样说道${'，然后继续讲了下去' * 10}'; // 远超 40 字
      final text = '第一章 真标题\n$longLine\n第二章 另一个标题\n正文。\n';
      final source = NovelMemoryFile.text('book.txt', text);
      final result = await splitNovelTxt(
        source: source,
        encoding: NovelTextEncoding.utf8,
        rules: novelDefaultTxtRules,
      );
      expect(result.chapters.map((c) => c.title).toList(), <String>[
        '第一章 真标题',
        '第二章 另一个标题',
      ]);
    });

    test('GBK 编码的 TXT 能正确分章（解码与分章联动）', () async {
      final bytes = Uint8List.fromList(cc.gbk.encode(sample));
      final guess = sniffNovelEncoding(bytes);
      final source = NovelMemoryFile('gbk.txt', bytes);
      final result = await splitNovelTxt(
        source: source,
        encoding: guess.encoding,
        rules: novelDefaultTxtRules,
      );
      expect(result.chapters.map((c) => c.title).toList(), contains('第一章 开始'));
    });

    test('跨读缓冲的行不会丢（分章按块流式读）', () async {
      // 把章节标题推到 256KB 读缓冲边界附近，验证跨块的行被拼回来。
      final padding = '填充正文。' * 12000; // 约 60K 字符
      final text = '$padding\n第一章 边界后的标题\n正文。\n';
      final source = NovelMemoryFile.text('big.txt', text);
      final result = await splitNovelTxt(
        source: source,
        encoding: NovelTextEncoding.utf8,
        rules: novelDefaultTxtRules,
      );
      expect(
        result.chapters.map((c) => c.title).toList(),
        contains('第一章 边界后的标题'),
      );
    });

    test('预览只返回命中样本，不整本扫描', () async {
      final source = NovelMemoryFile.text('book.txt', sample);
      final samples = await previewNovelTxtMatches(
        source: source,
        encoding: NovelTextEncoding.utf8,
        rules: novelDefaultTxtRules,
      );
      expect(samples, <String>['第一章 开始', '第二章 继续', '第三章 结束']);
    });
  });

  group('Markdown 分章', () {
    test('按最浅标题分级切章，标题文字去掉井号', () async {
      const text =
          '# 第一章 开始\n正文一。\n\n## 小节\n细节。\n\n'
          '# 第二章 继续\n正文二。\n';
      final source = NovelMemoryFile.text('book.md', text);
      final result = await splitNovelMarkdown(
        source: source,
        encoding: NovelTextEncoding.utf8,
      );
      expect(result.chapters.map((c) => c.title).toList(), <String>[
        '第一章 开始',
        '第二章 继续',
      ]);
    });

    test('没有标题时整本一章 + 提示', () async {
      final source = NovelMemoryFile.text('book.md', '只是正文，没有标题。\n');
      final result = await splitNovelMarkdown(
        source: source,
        encoding: NovelTextEncoding.utf8,
      );
      expect(result.chapters, hasLength(1));
      expect(result.warning, contains('没有标题'));
    });
  });

  group('EPUB 解析', () {
    test('章节顺序按 spine，不按文件名或 manifest 顺序', () async {
      final bytes = buildEpub(
        title: '测试书',
        author: '某作者',
        chapters: <(String, String, String)>[
          ('a.xhtml', '第一章', '正文一。'),
          ('b.xhtml', '第二章', '正文二。'),
          ('c.xhtml', '第三章', '正文三。'),
        ],
        reverseSpine: true,
      );
      final book = await parseNovelEpub(NovelMemoryFile('t.epub', bytes));
      expect(book.title, '测试书');
      expect(book.author, '某作者');
      expect(book.chapters.map((c) => c.title).toList(), <String>[
        '第三章',
        '第二章',
        '第一章',
      ]);
      expect(book.chapters.map((c) => c.href).toList(), <String>[
        'OEBPS/c.xhtml',
        'OEBPS/b.xhtml',
        'OEBPS/a.xhtml',
      ]);
    });

    test('读正文：段落拆出来，图片降级成占位', () async {
      final bytes = buildEpub(
        title: '测试书',
        author: '',
        chapters: <(String, String, String)>[('a.xhtml', '第一章', '正文一。')],
      );
      final source = NovelMemoryFile('t.epub', bytes);
      final paragraphs = await readNovelEpubChapter(source, 'OEBPS/a.xhtml');
      expect(paragraphs, contains('正文一。'));
      // 图片没有图片块可渲染，降级成 `[alt]` 文本占位（没 alt 时是 [图片]）。
      expect(paragraphs.any((p) => p.contains('[插图]')), isTrue);
    });

    test('不是 zip 时抛可读的格式错误（不是 zip 异常泄漏到界面）', () async {
      final source = NovelMemoryFile.text('bad.epub', '这不是 zip');
      expect(
        () => parseNovelEpub(source),
        throwsA(
          isA<NovelEpubFormatException>().having(
            (e) => e.message,
            'message',
            contains('不是有效的 EPUB'),
          ),
        ),
      );
    });

    test('缺 container.xml 时给出明确原因', () async {
      final archive = Archive()
        ..add(ArchiveFile.string('OEBPS/content.opf', '<package/>'));
      final source = NovelMemoryFile(
        'no-container.epub',
        Uint8List.fromList(ZipEncoder().encodeBytes(archive)),
      );
      expect(
        () => parseNovelEpub(source),
        throwsA(
          isA<NovelEpubFormatException>().having(
            (e) => e.message,
            'message',
            contains('container.xml'),
          ),
        ),
      );
    });

    test('章节里找不到目标 href 时抛 NovelLocalFileMissing（可定位的错误）', () async {
      final bytes = buildEpub(
        title: '书',
        author: '',
        chapters: <(String, String, String)>[('a.xhtml', '第一章', '正文。')],
      );
      final source = NovelMemoryFile('t.epub', bytes);
      expect(
        () => readNovelEpubChapter(source, 'OEBPS/nope.xhtml'),
        throwsA(isA<NovelLocalFileMissing>()),
      );
    });
  });

  group('本地书服务与引擎', () {
    late NovelDb db;
    late NovelLocalBookService service;

    /// 内存文件表：路径 → 字节。服务「按路径重开文件」全走这里。
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

    test('导入 TXT 后落库、目录可用、正文按章可读', () async {
      const text = '第一章 开始\n正文一。\n\n第二章 继续\n正文二。\n';
      files['/books/a.txt'] = Uint8List.fromList(utf8.encode(text));
      final book = await service.importBook(
        NovelMemoryFile('/books/a.txt', files['/books/a.txt']!),
      );
      expect(book.title, 'a');
      expect(book.format, NovelLocalFormat.txt);
      expect(book.encoding, NovelTextEncoding.utf8);
      expect(book.chapterCount, 2);
      expect(book.id, startsWith(novelLocalBookIdPrefix));

      final saved = await service.byId(book.id);
      expect(saved, isNotNull);
      expect(saved!.chapters.map((c) => c.title).toList(), <String>[
        '第一章 开始',
        '第二章 继续',
      ]);

      final paragraphs = await service.readChapter(saved, 0);
      expect(paragraphs.join('\n'), contains('正文一'));
      expect(paragraphs.join('\n'), contains('第一章 开始'));
    });

    test('重复导入同一路径 = 同一本书（id 稳定，不产生第二行）', () async {
      files['/books/a.txt'] = Uint8List.fromList(utf8.encode('第一章 开始\n正文。\n'));
      final first = await service.importBook(
        NovelMemoryFile('/books/a.txt', files['/books/a.txt']!),
      );
      final second = await service.importBook(
        NovelMemoryFile('/books/a.txt', files['/books/a.txt']!),
      );
      expect(second.id, first.id);
      expect(await service.list(), hasLength(1));
    });

    test('文件被删除后读正文抛 NovelLocalFileMissing（可渲染「重新定位」）', () async {
      files['/books/a.txt'] = Uint8List.fromList(utf8.encode('第一章 开始\n正文。\n'));
      final book = await service.importBook(
        NovelMemoryFile('/books/a.txt', files['/books/a.txt']!),
      );
      files.remove('/books/a.txt');
      expect(
        () => service.readChapter(book, 0),
        throwsA(
          isA<NovelLocalFileMissing>().having(
            (e) => e.path,
            'path',
            '/books/a.txt',
          ),
        ),
      );
    });

    test('引擎：本地文件缺失时 contentFor 抛 NovelLocalFileMissing', () async {
      files['/books/a.txt'] = Uint8List.fromList(utf8.encode('第一章 开始\n正文。\n'));
      final book = await service.importBook(
        NovelMemoryFile('/books/a.txt', files['/books/a.txt']!),
      );
      final engine = NovelLocalEngine(local: service);
      final detail = await engine.bookDetail(
        novelLocalBookSource,
        novelLocalRefOf(book),
      );
      files.remove('/books/a.txt');
      // 目录来自库里缓存，所以详情仍能拿到；正文必须去读文件 → 抛可定位错误。
      expect(
        () => engine.contentFor(
          novelLocalBookSource,
          detail.ref,
          detail.chapters.first,
        ),
        throwsA(
          isA<NovelLocalFileMissing>().having(
            (e) => e.path,
            'path',
            '/books/a.txt',
          ),
        ),
      );
    });

    test('重新定位到新路径后能读，且 id 不变', () async {
      files['/books/a.txt'] = Uint8List.fromList(utf8.encode('第一章 开始\n正文。\n'));
      final book = await service.importBook(
        NovelMemoryFile('/books/a.txt', files['/books/a.txt']!),
      );
      files['/moved/a.txt'] = Uint8List.fromList(utf8.encode('第一章 开始\n正文。\n'));
      files.remove('/books/a.txt');
      final relocated = await service.relocate(book.id, '/moved/a.txt');
      expect(relocated.id, book.id);
      expect(relocated.path, '/moved/a.txt');
      final paragraphs = await service.readChapter(relocated, 0);
      expect(paragraphs.join('\n'), contains('正文'));
    });

    test('引擎：详情走本地目录，正文走本地文件，sourceKey 是虚拟本地源', () async {
      files['/books/a.txt'] = Uint8List.fromList(
        utf8.encode('第一章 开始\n正文一。\n\n第二章 继续\n正文二。\n'),
      );
      final book = await service.importBook(
        NovelMemoryFile('/books/a.txt', files['/books/a.txt']!),
      );
      final engine = NovelLocalEngine(local: service);
      final detail = await engine.bookDetail(
        novelLocalBookSource,
        novelLocalRefOf(book),
      );
      expect(detail.title, 'a');
      expect(detail.chapters, hasLength(2));
      expect(detail.ref.sourceKey, novelLocalSourceKey);

      final content = await engine.contentFor(
        novelLocalBookSource,
        detail.ref,
        detail.chapters[1],
      );
      expect(content.title, '第二章 继续');
      expect(content.paragraphs.join('\n'), contains('正文二'));
    });

    test('引擎：本地源不参与搜索/发现（返回空而不是抛）', () async {
      final engine = NovelLocalEngine(local: service);
      expect(await engine.searchSource(novelLocalBookSource, '任意'), isEmpty);
      expect(await engine.exploreKinds(novelLocalBookSource), isEmpty);
    });

    test('引擎：书不在本地库时给出可操作的 StateError', () async {
      final engine = NovelLocalEngine(local: service);
      expect(
        () => engine.bookDetail(
          novelLocalBookSource,
          const NovelRef(id: 'local:missing', sourceKey: novelLocalSourceKey),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('不在本地书库'),
          ),
        ),
      );
    });

    test('虚拟源仓库把本地源追加到列表末尾，且不可删不可停用', () async {
      final inner = _FakeSourceStore();
      final store = NovelLocalSourceStore(inner);
      final sources = await store.loadAll();
      expect(sources.map((s) => s.key), contains(novelLocalSourceKey));
      expect(await store.delete(novelLocalSourceKey), isFalse);
      await store.setEnabled(novelLocalSourceKey, false);
      // 停用请求被吞掉，虚拟源仍是启用状态（阅读器要求源存在）。
      expect(
        (await store.loadAll())
            .firstWhere((s) => s.key == novelLocalSourceKey)
            .enabled,
        isTrue,
      );
    });

    test('TXT 规则表：首次读取自动落内置规则，可停用与恢复默认', () async {
      final rules = NovelTxtRuleService(db);
      final initial = await rules.loadAll();
      expect(initial, hasLength(novelDefaultTxtRules.length));
      expect(initial.every((r) => r.builtin), isTrue);
      expect(initial.first.id, isNot(0));

      await rules.setEnabled(initial.first.id, false);
      final afterDisable = await rules.loadAll();
      expect(
        afterDisable.firstWhere((r) => r.id == initial.first.id).enabled,
        isFalse,
      );

      await rules.restoreDefaults();
      final restored = await rules.loadAll();
      expect(
        restored.firstWhere((r) => r.id == initial.first.id).enabled,
        isTrue,
      );
    });

    test('TXT 规则表：自建规则可增删，正则写坏不影响其它规则', () async {
      final rules = NovelTxtRuleService(db);
      await rules.loadAll();
      final saved = await rules.save(
        const NovelTxtRule(name: '自建', pattern: r'^第.+幕$'),
      );
      expect(saved.id, isNot(0));
      final broken = await rules.save(
        const NovelTxtRule(name: '坏正则', pattern: r'^(unclosed'),
      );
      expect(broken.isValid, isFalse);

      final all = await rules.loadAll();
      expect(all.map((r) => r.name), contains('自建'));
      // 坏规则只是 isValid=false，不影响读取与其它规则。
      expect(all.where((r) => r.isValid).length, greaterThan(1));

      expect(await rules.delete(saved.id), isTrue);
      expect((await rules.loadAll()).map((r) => r.name), isNot(contains('自建')));
    });

    test('重新分章：换规则后目录更新，路径与 id 不变', () async {
      const text = '第一卷 起\n甲。\n第二卷 承\n乙。\n';
      files['/books/a.txt'] = Uint8List.fromList(utf8.encode(text));
      final book = await service.importBook(
        NovelMemoryFile('/books/a.txt', files['/books/a.txt']!),
      );
      // 默认规则里「第X卷」也在列，所以首章就是「第一卷 起」；换成只认「卷」
      // 的规则后，第一章之前没有内容，不会再生成「前言」。
      final before = book.chapters.map((c) => c.title).toList();
      expect(before, contains('第一卷 起'));

      final resplit = await service.resplit(
        book.id,
        rules: const <NovelTxtRule>[
          NovelTxtRule(name: '卷', pattern: r'^第[一二三四五六七八九十]+卷'),
        ],
      );
      expect(resplit.id, book.id);
      expect(resplit.path, '/books/a.txt');
      expect(resplit.chapters.map((c) => c.title).toList(), <String>[
        '第一卷 起',
        '第二卷 承',
      ]);
    });

    test('EPUB 导入后按 spine 顺序出目录，正文可读', () async {
      final bytes = buildEpub(
        title: '电子书',
        author: '作者',
        chapters: <(String, String, String)>[
          ('a.xhtml', '第一章', '正文一。'),
          ('b.xhtml', '第二章', '正文二。'),
        ],
        reverseSpine: true,
      );
      files['/books/e.epub'] = bytes;
      final book = await service.importBook(
        NovelMemoryFile('/books/e.epub', bytes),
      );
      expect(book.title, 'e');
      expect(book.format, NovelLocalFormat.epub);
      expect(book.chapterCount, 2);
      final paragraphs = await service.readChapter(book, 0);
      expect(paragraphs.join('\n'), contains('正文二')); // spine 里 b 在前
    });

    test('阅读控制器：本地文件缺失时置 localFileMissingPath（页面据此给重新定位）', () async {
      files['/books/a.txt'] = Uint8List.fromList(
        utf8.encode('第一章 开始\n正文一。\n\n第二章 继续\n正文二。\n'),
      );
      final book = await service.importBook(
        NovelMemoryFile('/books/a.txt', files['/books/a.txt']!),
      );
      final engine = NovelLocalEngine(local: service);
      // 先确认能正常读到第一章（控制器链路本身没坏）。
      final controller = NovelReaderController(
        bookId: book.id,
        title: book.title,
        sourceKey: novelLocalSourceKey,
        onlineEngine: engine,
        sourceStore: NovelLocalSourceStore(_FakeSourceStore()),
        settingsStore: MemoryNovelReaderSettingsStore(
          const NovelReaderSettings(),
        ),
      );
      addTearDown(controller.dispose);
      await controller.init();
      expect(controller.loadError, isNull);
      expect(controller.localFileMissingPath, isNull);
      expect(controller.content?.paragraphs.join('\n'), contains('正文一'));

      // 文件被移走后再翻章：控制器要记住缺失路径，而不是只给一句「重试」。
      files.remove('/books/a.txt');
      await controller.openChapter(controller.detail!.chapters[1]);
      expect(controller.localFileMissingPath, '/books/a.txt');
      expect(controller.loadError, contains('本地文件已不可读'));
    });

    test('不支持的文件类型直接拒绝，给出支持列表', () async {
      expect(
        () => service.probe(NovelMemoryFile.text('book.pdf', 'x')),
        throwsA(
          isA<NovelEpubFormatException>().having(
            (e) => e.message,
            'message',
            contains('不支持的文件类型'),
          ),
        ),
      );
    });
  });
}

/// 最小书源仓库 fake：验证装饰器只追加虚拟源，不碰真实仓库语义。
class _FakeSourceStore implements NovelSourceStorage {
  _FakeSourceStore();

  final List<Map<String, Object?>> _deleted = <Map<String, Object?>>[];

  @override
  Future<List<NovelBookSource>> loadAll() async => const <NovelBookSource>[];

  @override
  Future<int> saveAll(Iterable<NovelBookSource> sources) async => 0;

  @override
  Future<void> setEnabled(String key, bool enabled) async {}

  @override
  Future<bool> delete(String key) async {
    _deleted.add(<String, Object?>{'key': key});
    return true;
  }
}
