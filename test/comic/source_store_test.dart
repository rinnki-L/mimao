/// 源导入/存储往返测试：导入、重复覆盖、删除 + 版本管理。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:mimao/comic/engine/engine.dart';

import 'fixtures.dart';

void main() {
  group('源导入', () {
    test('① 单条脚本文本导入：解析出 key/name/version', () {
      final result = ComicSourceImporter().parseSingle(fixtureSourceScript);
      expect(result.failures, isEmpty);
      expect(result.sources, hasLength(1));
      final source = result.sources.single;
      expect(source.key, 'fixture');
      expect(source.name, 'Fixture Manga');
      expect(source.version, '1.2.0');
      expect(source.script, fixtureSourceScript);
    });

    test('② 非源脚本 / 空内容被拒绝', () {
      final importer = ComicSourceImporter();
      expect(importer.parseSingle(fixtureNotASource).sources, isEmpty);
      expect(importer.parseSingle('  ').failures, isNotEmpty);
    });

    test('③ JSON 数组批量导入 + 重复 key 覆盖（保留最后一条）', () {
      final payload = [
        <String, dynamic>{
          'key': 'a',
          'name': 'A one',
          'script': fixtureSourceScript,
        },
        <String, dynamic>{
          'key': 'a',
          'name': 'A two',
          'script': fixtureSourceScript,
        },
        <String, dynamic>{'key': 'b', 'script': fixtureSourceScript},
      ];
      final result = ComicSourceImporter().parseJson(jsonEncode(payload));
      expect(result.failures, isEmpty);
      expect(result.sources.length, 2);
      expect(result.duplicateCount, 1);
      expect(result.sources.firstWhere((s) => s.key == 'a').name, 'A two');
    });

    test('④ 版本比较', () {
      expect(ComicSourceScript.compareVersion('1.2.0', '1.3.0'), lessThan(0));
      expect(ComicSourceScript.compareVersion('2.0', '1.9.9'), greaterThan(0));
      expect(ComicSourceScript.compareVersion('1.2.0', '1.2.0'), 0);
    });
  });

  group('源存储往返', () {
    late Directory tempDir;
    late ComicSourceStore store;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('mimao_comic_store_');
      store = ComicSourceStore(tempDir);
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('⑤ 保存→读回往返，脚本正文逐字一致', () async {
      final source = ComicSourceImporter()
          .parseSingle(fixtureSourceScript)
          .sources
          .single;
      await store.save(source);
      expect(await store.exists('fixture'), isTrue);

      final loaded = await store.loadAll();
      expect(loaded, hasLength(1));
      expect(loaded.single.key, 'fixture');
      expect(loaded.single.script, fixtureSourceScript);
      expect(loaded.single.version, '1.2.0');
    });

    test('⑥ 重复保存同名覆盖 + 清单不重复', () async {
      await store.save(
        const ComicSourceScript(
          key: 'a',
          script: 'class A extends ComicSource {}',
          version: '1.0.0',
        ),
      );
      await store.save(
        const ComicSourceScript(
          key: 'a',
          script: 'class A extends ComicSource { version = "2.0.0"; }',
          version: '2.0.0',
        ),
      );
      final loaded = await store.loadAll();
      expect(loaded, hasLength(1));
      expect(loaded.single.version, '2.0.0');
      expect(loaded.single.script, contains('2.0.0'));
    });

    test('⑦ 删除：删脚本与清单条目，返回是否真删', () async {
      await store.save(
        const ComicSourceScript(
          key: 'gone',
          script: 'class G extends ComicSource {}',
        ),
      );
      expect(await store.delete('gone'), isTrue);
      expect(await store.exists('gone'), isFalse);
      expect(await store.loadAll(), isEmpty);
      // 再删一次返回 false。
      expect(await store.delete('gone'), isFalse);
    });

    test('⑧ 目录不存在时 loadAll 返回空、不抛异常', () async {
      final emptyStore = ComicSourceStore(
        Directory('${tempDir.path}${Platform.pathSeparator}no_such'),
      );
      final result = await emptyStore.loadAllDetailed();
      expect(result.isEmpty, isTrue);
    });
  });
}
