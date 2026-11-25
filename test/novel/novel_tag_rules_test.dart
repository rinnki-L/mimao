// 标签分组规则：正则匹配 / 只加不减地应用到书架 / 导入导出。
//
// 全程离线：内存 drift，不碰插件与网络。
import 'dart:convert';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/novel_db.dart';
import 'package:mimao/novel/tags/novel_tag_rule_service.dart';
import 'package:mimao/novel/tags/novel_tag_rules.dart';

NovelTagRule _rule(
  String name,
  String pattern, {
  int? color,
  bool enabled = true,
  int order = 0,
  int? id,
}) => NovelTagRule(
  id: id,
  name: name,
  pattern: pattern,
  colorArgb: color,
  enabled: enabled,
  sortOrder: order,
);

String _payload(String title, {String kind = '', String author = ''}) =>
    jsonEncode(
      NovelSummary(
        id: title,
        title: title,
        kind: kind,
        author: author,
      ).toJson(),
    );

void main() {
  group('匹配', () {
    test('分类标签命中（逗号/顿号/斜杠都算分隔）', () {
      final tags = splitNovelKindTags('玄幻，修真/都市、系统');
      expect(tags, <String>['玄幻', '修真', '都市', '系统']);
      expect(
        matchNovelTagRule(
          rules: <NovelTagRule>[_rule('修仙', r'修[真仙]')],
          kind: '玄幻，修真',
        )?.name,
        '修仙',
      );
    });

    test('没有分类标签时按书名匹配', () {
      expect(
        matchNovelTagRule(
          rules: <NovelTagRule>[_rule('系统流', '系统')],
          title: '我的系统能升级',
        )?.name,
        '系统流',
      );
    });

    test('停用与坏正则被跳过，按顺序取第一条命中', () {
      final rules = <NovelTagRule>[
        _rule('停用', '玄幻', enabled: false, order: 0),
        _rule('坏正则', '([', order: 1),
        _rule('第一条', '玄幻', order: 2),
        _rule('第二条', '玄幻', order: 3),
      ];
      expect(matchNovelTagRule(rules: rules, kind: '玄幻')?.name, '第一条');
      expect(matchNovelTagRule(rules: rules, kind: '都市'), isNull);
    });

    test('大小写不敏感', () {
      expect(
        matchNovelTagRule(
          rules: <NovelTagRule>[_rule('SciFi', 'scifi')],
          kind: 'SciFi',
        )?.name,
        'SciFi',
      );
    });
  });

  group('导入导出', () {
    test('数组 / 单对象 / tagGroupRules 包壳都能读', () {
      const array = '[{"name":"仙侠","pattern":"仙"}]';
      expect(decodeNovelTagRules(array).single.name, '仙侠');
      const single = '{"name":"都市","pattern":"都市"}';
      expect(decodeNovelTagRules(single).single.name, '都市');
      const wrapped =
          '{"tagGroupRules":[{"name":"科幻","pattern":"星"}],'
          '"version":1}';
      expect(decodeNovelTagRules(wrapped).single.name, '科幻');
    });

    test('坏正则 / 缺字段条目跳过，全空报错', () {
      const text = '[{"name":"坏","pattern":"(["},{"name":"好","pattern":"好"}]';
      expect(decodeNovelTagRules(text).single.name, '好');
      expect(
        () => decodeNovelTagRules('[{"name":"只有名字"}]'),
        throwsA(isA<FormatException>()),
      );
    });

    test('往返保留配色与启停', () {
      final rules = <NovelTagRule>[
        _rule('仙侠', '仙', color: 0xFF3366AA, enabled: false, order: 2),
      ];
      final decoded = decodeNovelTagRules(encodeNovelTagRules(rules)).single;
      expect(decoded.name, '仙侠');
      expect(decoded.colorArgb, 0xFF3366AA);
      expect(decoded.enabled, isFalse);
      expect(decoded.sortOrder, 2);
    });
  });

  group('存储与应用', () {
    late NovelDb db;
    late NovelTagRuleService service;

    setUp(() {
      db = NovelDb.forTesting(NativeDatabase.memory());
      service = NovelTagRuleService(db);
    });

    tearDown(() => db.close());

    Future<void> insertCollect(
      String id, {
      String kind = '',
      String group = '',
    }) => db
        .into(db.novelCollectEntries)
        .insert(
          NovelCollectEntriesCompanion.insert(
            id: id,
            title: id,
            payload: Value(_payload(id, kind: kind)),
            groupName: Value(group.isEmpty ? null : group),
            collectedAt: DateTime(2026, 11, 25),
          ),
        );

    test('新建 / 排序 / 启停 / 删除', () async {
      final a = await service.save(_rule('甲', '甲'));
      final b = await service.save(_rule('乙', '乙'));
      expect((await service.loadAll()).map((r) => r.name), <String>['甲', '乙']);
      expect(b.sortOrder, greaterThan(a.sortOrder));

      await service.setEnabled(a.id!, false);
      expect((await service.loadAll()).first.enabled, isFalse);

      expect(await service.delete(b.id!), isTrue);
      expect((await service.loadAll()).map((r) => r.name), <String>['甲']);
    });

    test('应用到书架：空分组才写，已有分组保留（只加不减）', () async {
      await insertCollect('玄幻书', kind: '玄幻');
      await insertCollect('我的玄幻', kind: '玄幻', group: '手工分组');
      await insertCollect('都市书', kind: '都市');
      await service.save(_rule('修仙', '玄幻'));

      final result = await service.applyToShelf();
      expect(result.matched, 2);
      expect(result.updated, 1);
      expect(result.kept, 1);
      expect(result.affectedNames, <String>['修仙']);

      final rows = await db.select(db.novelCollectEntries).get();
      final byId = <String, String?>{
        for (final row in rows) row.id: row.groupName,
      };
      expect(byId['玄幻书'], '修仙');
      expect(byId['我的玄幻'], '手工分组');
      expect(byId['都市书'], isNull);
    });

    test('停用的规则不参与应用；没有规则时不改动任何行', () async {
      await insertCollect('玄幻书', kind: '玄幻');
      await service.save(_rule('修仙', '玄幻', enabled: false));
      final result = await service.applyToShelf();
      expect(result.matched, 0);
      expect(
        (await db.select(db.novelCollectEntries).get()).single.groupName,
        isNull,
      );
    });

    test('重复应用幂等：第二次全部算「保留」', () async {
      await insertCollect('玄幻书', kind: '玄幻');
      await service.save(_rule('修仙', '玄幻'));
      expect((await service.applyToShelf()).updated, 1);
      final second = await service.applyToShelf();
      expect(second.updated, 0);
      expect(second.kept, 1);
    });

    test('replaceAll 整体替换规则', () async {
      await service.save(_rule('旧', '旧'));
      await service.replaceAll(<NovelTagRule>[_rule('新', '新')]);
      expect((await service.loadAll()).map((r) => r.name), <String>['新']);
    });

    test('坏 payload 的书不会阻断整次应用', () async {
      await db
          .into(db.novelCollectEntries)
          .insert(
            NovelCollectEntriesCompanion.insert(
              id: '坏数据',
              title: '坏数据',
              payload: const Value('{not json'),
              collectedAt: DateTime(2026, 11, 25),
            ),
          );
      await insertCollect('玄幻书', kind: '玄幻');
      await service.save(_rule('修仙', '玄幻'));
      final result = await service.applyToShelf();
      expect(result.matched, 1);
      expect(result.updated, 1);
    });
  });
}
