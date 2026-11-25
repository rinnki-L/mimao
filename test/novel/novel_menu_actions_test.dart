// 阅读菜单动作注册表：可用性过滤、顶栏截断、网格排版、配置序列化。

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/reader/novel_click_actions.dart';
import 'package:mimao/novel/reader/novel_menu_actions.dart';

const NovelMenuActionContext _onlineReady = NovelMenuActionContext(
  hasOnlineSource: true,
  bookmarkReady: true,
);

const NovelMenuActionContext _onlineOnly = NovelMenuActionContext(
  hasOnlineSource: true,
);

void main() {
  test('每个动作 id 唯一，且都能按 id 取回', () {
    final ids = <String>{};
    for (final def in novelMenuActionDefs) {
      expect(ids.add(def.id), isTrue, reason: '重复的 id: ${def.id}');
      expect(novelMenuActionById(def.id), same(def));
    }
    expect(novelMenuActionById('不存在的动作'), isNull);
  });

  test('不可用动作被剔除（加书签需要书签库就绪）', () {
    const items = <NovelMenuButtonItem>[
      NovelMenuButtonItem(novelMenuActionSearch),
      NovelMenuButtonItem(novelMenuActionAddBookmark),
    ];
    final without = resolveNovelMenuActions(items: items, context: _onlineOnly);
    expect(without.map((def) => def.id), <String>[novelMenuActionSearch]);

    final withBookmark = resolveNovelMenuActions(
      items: items,
      context: _onlineReady,
    );
    expect(withBookmark.map((def) => def.id), <String>[
      novelMenuActionSearch,
      novelMenuActionAddBookmark,
    ]);
  });

  test('在线专属动作在本地书上被剔除', () {
    const items = <NovelMenuButtonItem>[
      NovelMenuButtonItem(novelMenuActionDownload),
      NovelMenuButtonItem(novelMenuActionRefresh),
      NovelMenuButtonItem(novelMenuActionSwitchSource),
      NovelMenuButtonItem(novelMenuActionMore),
    ];
    final local = resolveNovelMenuActions(
      items: items,
      context: const NovelMenuActionContext(),
    );
    expect(local.map((def) => def.id), <String>[novelMenuActionMore]);

    final online = resolveNovelMenuActions(items: items, context: _onlineOnly);
    expect(online.length, 4);
  });

  test('禁用的动作不渲染，未知 id 静默跳过', () {
    const items = <NovelMenuButtonItem>[
      NovelMenuButtonItem(novelMenuActionSearch, enabled: false),
      NovelMenuButtonItem('不存在的动作'),
      NovelMenuButtonItem(novelMenuActionCatalog),
    ];
    final resolved = resolveNovelMenuActions(
      items: items,
      context: _onlineOnly,
    );
    expect(resolved.map((def) => def.id), <String>[novelMenuActionCatalog]);
  });

  test('顶栏截断到 6 个', () {
    final items = <NovelMenuButtonItem>[
      for (final def in novelMenuActionDefs) NovelMenuButtonItem(def.id),
    ];
    final resolved = resolveNovelTitleBarActions(
      items: items,
      context: _onlineReady,
      compact: false,
    );
    expect(resolved.length, novelTitleBarMaxActions);
    expect(novelTitleBarMaxActions, 6);
  });

  test('顶栏一个都不剩时保留「更多」；紧凑模式只留「更多」', () {
    final empty = resolveNovelTitleBarActions(
      items: const <NovelMenuButtonItem>[],
      context: _onlineOnly,
      compact: false,
    );
    expect(empty.map((def) => def.id), <String>[novelMenuActionMore]);

    final compact = resolveNovelTitleBarActions(
      items: novelDefaultTitleBarMenu,
      context: _onlineOnly,
      compact: true,
    );
    expect(compact.map((def) => def.id), <String>[novelMenuActionMore]);
  });

  test('默认顶栏在本地书上只剩「更多」', () {
    final resolved = resolveNovelTitleBarActions(
      items: novelDefaultTitleBarMenu,
      context: const NovelMenuActionContext(),
      compact: false,
    );
    expect(resolved.map((def) => def.id), <String>[novelMenuActionMore]);
  });

  test('网格排版：每行个数与行数都生效，放不下时收进「更多动作」', () {
    final actions = <NovelMenuActionDef>[
      for (final id in <String>[
        novelMenuActionSearch,
        novelMenuActionCatalog,
        novelMenuActionTts,
        novelMenuActionSettings,
        novelMenuActionPreviousChapter,
        novelMenuActionNextChapter,
        novelMenuActionPreviousPage,
      ])
        novelMenuActionById(id)!,
    ];

    // 每行 3、1 行：7 个动作 → 前 2 个可见 + 1 个「更多动作」入口。
    final tight = layoutNovelMenuRows(
      actions: actions,
      itemsPerRow: 3,
      rowCount: 1,
    );
    expect(tight.rows.length, 1);
    expect(tight.visible.length, 3);
    expect(tight.visible.last.id, novelMenuActionMorePanel);
    expect(tight.overflow.length, 5);

    // 每行 4、2 行：容量 8，7 个全放得下，不出现「更多动作」。
    final roomy = layoutNovelMenuRows(
      actions: actions,
      itemsPerRow: 4,
      rowCount: 2,
    );
    expect(roomy.rows.length, 2);
    expect(roomy.visible.length, 7);
    expect(roomy.overflow, isEmpty);
    expect(
      roomy.visible.map((def) => def.id),
      isNot(contains(novelMenuActionMorePanel)),
    );
  });

  test('网格排版：参数越界被 clamp 到 2–8 / 1–2', () {
    final actions = <NovelMenuActionDef>[
      for (final id in <String>[
        novelMenuActionSearch,
        novelMenuActionCatalog,
        novelMenuActionTts,
        novelMenuActionSettings,
        novelMenuActionPreviousChapter,
      ])
        novelMenuActionById(id)!,
    ];
    final tooSmall = layoutNovelMenuRows(
      actions: actions,
      itemsPerRow: 0,
      rowCount: 0,
    );
    // 每行最少 2 个、最少 1 行：容量 2，5 个动作 → 1 个 + 「更多动作」。
    expect(tooSmall.rows.length, 1);
    expect(tooSmall.rows.first.length, 2);
    expect(tooSmall.visible.last.id, novelMenuActionMorePanel);

    final tooBig = layoutNovelMenuRows(
      actions: actions,
      itemsPerRow: 99,
      rowCount: 99,
    );
    // 每行最多 8 个、最多 2 行：5 个动作全放得下，一行排完。
    expect(tooBig.rows.length, 1);
    expect(tooBig.rows.first.length, 5);
    expect(tooBig.overflow, isEmpty);
  });

  test('按钮配置的 JSON 往返与坏数据降级', () {
    const items = <NovelMenuButtonItem>[
      NovelMenuButtonItem(novelMenuActionSearch),
      NovelMenuButtonItem(novelMenuActionCatalog, enabled: false),
    ];
    final json = NovelMenuButtonItem.listToJson(items);
    expect(NovelMenuButtonItem.listFromJson(json), items);

    // 坏数据：非 Map、缺 id、空 id 一律丢弃；enabled 非 bool 回退 true。
    final messy = NovelMenuButtonItem.listFromJson(<Object?>[
      '不是 Map',
      <String, Object?>{'enabled': true},
      <String, Object?>{'id': '', 'enabled': false},
      <String, Object?>{'id': novelMenuActionTts, 'enabled': 'yes'},
    ]);
    expect(messy, <NovelMenuButtonItem>[
      const NovelMenuButtonItem(novelMenuActionTts),
    ]);
    expect(NovelMenuButtonItem.listFromJson(null), isEmpty);
  });

  test('动作复用点击区枚举：可点击动作都有对应的 NovelClickAction', () {
    // 顶栏专属动作（缓存/刷新/换源/更多）没有点击区动作；
    // 其余动作必须挂上 NovelClickAction，否则点击分发会走不到。
    const topBarOnly = <String>{
      novelMenuActionDownload,
      novelMenuActionRefresh,
      novelMenuActionSwitchSource,
      novelMenuActionMore,
      novelMenuActionMorePanel,
      // 书签列表是页面级入口，不是点击区动作。
      novelMenuActionBookmarkList,
    };
    for (final def in novelMenuActionDefs) {
      if (topBarOnly.contains(def.id)) {
        expect(def.clickAction, isNull, reason: def.id);
      } else {
        expect(def.clickAction, isNotNull, reason: def.id);
      }
    }
    expect(
      novelMenuActionById(novelMenuActionAddBookmark)!.clickAction,
      NovelClickAction.addBookmark,
    );
  });
}
