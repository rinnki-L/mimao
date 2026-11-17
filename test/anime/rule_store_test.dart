import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/anime/engine/rule.dart';
import 'package:mimao/anime/engine/rule_store.dart';

import 'fixtures.dart';

void main() {
  late Directory directory;
  late RuleStore store;

  final demoRule = AnimeRule.fromJson(
    jsonDecode(demoRuleJson) as Map<String, dynamic>,
  );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('mimao_rules_test_');
    store = RuleStore(directory);
  });

  tearDown(() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test('保存 → 读取 → 存在性 → 删除', () async {
    expect(await store.exists('demo03'), isFalse);
    expect(await store.loadAll(), isEmpty);

    final file = await store.save(demoRule);
    expect(await file.exists(), isTrue);
    expect(file.path.toLowerCase().endsWith('.json'), isTrue);
    expect(await store.exists('demo03'), isTrue);

    final loaded = await store.loadAll();
    expect(loaded, hasLength(1));
    expect(loaded.single.name, 'demo03');
    expect(loaded.single.search.title, demoRule.search.title);
    expect(loaded.single.detail.roads, demoRule.detail.roads);

    expect(await store.delete('demo03'), isTrue);
    expect(await store.delete('demo03'), isFalse);
    expect(await store.loadAll(), isEmpty);
  });

  test('同名保存覆盖文件，不产生第二份', () async {
    await store.save(demoRule);
    final updated = AnimeRule.fromJson(<String, dynamic>{
      ...demoRule.toJson(),
      'version': '2.0',
    });
    await store.save(updated);

    final loaded = await store.loadAll();
    expect(loaded, hasLength(1));
    expect(loaded.single.version, '2.0');
    expect(
      directory.listSync().whereType<File>().where(
        (file) => file.path.toLowerCase().endsWith('.json'),
      ),
      hasLength(1),
    );
  });

  test('规则名含中文/斜杠/星号也能安全落盘并读回', () async {
    final rule = AnimeRule.fromJson(<String, dynamic>{
      ...demoRule.toJson(),
      'name': '樱花/动漫*测试',
    });

    await store.save(rule);
    final files = directory
        .listSync()
        .whereType<File>()
        .map((file) => file.uri.pathSegments.last)
        .toList();
    expect(files, hasLength(1));
    expect(files.single, isNot(contains('/')));
    expect(files.single, isNot(contains('*')));

    final loaded = await store.loadAll();
    expect(loaded.single.name, '樱花/动漫*测试');
  });

  test('坏文件被跳过，好文件照常加载，并给出诊断', () async {
    await store.save(demoRule);
    await File(
      '${directory.path}${Platform.pathSeparator}broken.json',
    ).writeAsString('{ not json');
    await File(
      '${directory.path}${Platform.pathSeparator}array.json',
    ).writeAsString('[1,2,3]');

    final result = await store.loadAllDetailed();
    expect(result.rules, hasLength(1));
    expect(result.rules.single.name, 'demo03');
    expect(result.failures, hasLength(2));
  });

  test('saveAll 批量保存', () async {
    final mxdm = AnimeRule.fromJson(
      jsonDecode(kazumiMxdmRuleJson) as Map<String, dynamic>,
    );
    final files = await store.saveAll(<AnimeRule>[demoRule, mxdm]);

    expect(files, hasLength(2));
    expect((await store.loadAll()).map((rule) => rule.name).toSet(), {
      'demo03',
      'MXdm',
    });
  });
}
