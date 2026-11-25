// 每书阅读设置：部分覆盖的序列化、合并优先级、菜单布局参数与 kv 存储。

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/library_api.dart';
import 'package:mimao/novel/reader/novel_click_actions.dart';
import 'package:mimao/novel/reader/novel_menu_actions.dart';
import 'package:mimao/novel/reader/novel_reader_settings.dart';

/// 内存版 kv（模拟模块 prefs）。
class _MemoryPrefs implements NovelPrefsApi {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

void main() {
  group('每书覆盖：只存差异', () {
    test('与全局一致时差异为空', () {
      const global = NovelReaderSettings(fontSize: 22);
      expect(diffNovelReaderSettings(global, global), isEmpty);
      // 用 copyWith 造一份值相同的对象，也要判等。
      final same = global.copyWith(fontSize: 22);
      expect(diffNovelReaderSettings(global, same), isEmpty);
    });

    test('只收进改过的可覆盖字段', () {
      const global = NovelReaderSettings(
        fontSize: 22,
        backgroundIndex: 1,
        pageMode: NovelPageMode.scroll,
      );
      final perBook = global.copyWith(
        fontSize: 28,
        backgroundIndex: 3,
        pageMode: NovelPageMode.page,
      );
      final diff = diffNovelReaderSettings(global, perBook);
      expect(diff.keys.toSet(), <String>{
        'fontSize',
        'backgroundIndex',
        'pageMode',
      });
      expect(diff['fontSize'], 28);
      expect(diff['backgroundIndex'], 3);
      expect(diff['pageMode'], 'page');
    });

    test('不在白名单里的字段不进覆盖（行距走全局）', () {
      const global = NovelReaderSettings(lineHeight: 1.8);
      final perBook = global.copyWith(lineHeight: 2.4, fontSize: 26);
      final diff = diffNovelReaderSettings(global, perBook);
      expect(diff.containsKey('lineHeight'), isFalse);
      expect(diff['fontSize'], 26);
    });

    test('点击区差异按内容比较，不是引用比较', () {
      const global = NovelReaderSettings();
      final perBook = global.copyWith(
        clickZones: <NovelClickAction>[
          NovelClickAction.catalog,
          NovelClickAction.none,
          NovelClickAction.none,
          NovelClickAction.previousPage,
          NovelClickAction.menu,
          NovelClickAction.nextPage,
          NovelClickAction.none,
          NovelClickAction.none,
          NovelClickAction.none,
        ],
      );
      final diff = diffNovelReaderSettings(global, perBook);
      expect(diff.keys, <String>['clickZones']);
      expect((diff['clickZones']! as List).first, 'catalog');
    });

    test('部分覆盖序列化成 JSON 后能原样读回', () {
      const global = NovelReaderSettings(fontSize: 20);
      final perBook = global.copyWith(
        fontSize: 30,
        fontFamily: 'KaiTi',
        pageAnimStyle: NovelPageAnimStyle.cover,
      );
      final diff = diffNovelReaderSettings(global, perBook);
      // 模拟落盘再读回（JSON 里 List 会变成 List<dynamic>）。
      final roundTripped = parseNovelBookOverride(
        Map<String, Object?>.from(diff),
      );
      expect(roundTripped['fontSize'], 30);
      expect(roundTripped['fontFamily'], 'KaiTi');
      expect(roundTripped['pageAnimStyle'], 'cover');
    });
  });

  group('合并优先级：每书 > 全局 > 默认', () {
    test('覆盖字段取每书值，未覆盖字段取全局值', () {
      const global = NovelReaderSettings(
        fontSize: 22,
        lineHeight: 2.0,
        backgroundIndex: 1,
      );
      final merged = mergeNovelBookOverride(global, <String, Object?>{
        'fontSize': 30,
      });
      expect(merged.fontSize, 30);
      // 全局值仍在：行距、背景都不受覆盖影响。
      expect(merged.lineHeight, 2.0);
      expect(merged.backgroundIndex, 1);
    });

    test('空覆盖等价于全局', () {
      const global = NovelReaderSettings(fontSize: 25);
      expect(
        mergeNovelBookOverride(global, const <String, Object?>{}).fontSize,
        25,
      );
    });

    test('覆盖里的坏值回退默认并 clamp，不炸整个设置', () {
      const global = NovelReaderSettings(fontSize: 22);
      final merged = mergeNovelBookOverride(global, <String, Object?>{
        'fontSize': 9999, // 越界 → clamp 到上限
        'backgroundIndex': -5, // 越界 → clamp 到 0
        'pageMode': '不认识的模式', // 坏枚举 → 默认 scroll
      });
      expect(merged.fontSize, NovelReaderSettings.maxFontSize);
      expect(merged.backgroundIndex, 0);
      expect(merged.pageMode, NovelPageMode.scroll);
    });

    test('覆盖里非白名单字段被忽略（不污染其他设置）', () {
      const global = NovelReaderSettings(lineHeight: 1.8, fontSize: 22);
      final merged = mergeNovelBookOverride(global, <String, Object?>{
        'lineHeight': 2.6, // 不在白名单
        'fontSize': 24,
      });
      expect(merged.lineHeight, 1.8);
      expect(merged.fontSize, 24);
    });

    test('全局改动后，未覆盖的字段跟着变（覆盖只存差异的意义）', () {
      // 用户先把字号改成 30（只改这本），其余字段没动。
      final override = diffNovelReaderSettings(
        const NovelReaderSettings(),
        const NovelReaderSettings().copyWith(fontSize: 30),
      );
      expect(override.keys, <String>['fontSize']);

      // 之后用户改全局行距与背景，这本书只有字号保持 30。
      const newGlobal = NovelReaderSettings(
        lineHeight: 2.4,
        backgroundIndex: 5,
      );
      final merged = mergeNovelBookOverride(newGlobal, override);
      expect(merged.fontSize, 30);
      expect(merged.lineHeight, 2.4);
      expect(merged.backgroundIndex, 5);
    });
  });

  group('设置面板「只改这本」的全字段差异', () {
    test('只收进真正改动的字段，覆盖值不会泄漏进全局', () {
      const global = NovelReaderSettings(fontSize: 20, backgroundIndex: 1);
      // 面板展示的是叠加后的生效值（字号被这本书覆盖成 30）。
      final effective = mergeNovelBookOverride(global, <String, Object?>{
        'fontSize': 30,
      });
      // 用户在面板里只改了背景。
      final next = effective.copyWith(backgroundIndex: 4);
      final delta = diffNovelReaderSettingsAllFields(effective, next);
      expect(delta.keys, <String>['backgroundIndex']);

      final newGlobal = applyNovelReaderSettingsJson(global, delta);
      expect(newGlobal.backgroundIndex, 4);
      // 关键：全局字号仍是 20，没被这本书的 30 带偏。
      expect(newGlobal.fontSize, 20);
    });
  });

  group('菜单布局参数', () {
    test('默认值：每行 5 个、1 行、圆角 32、不显示图标文字', () {
      const settings = NovelReaderSettings();
      expect(settings.menuIconItemsPerRow, 5);
      expect(settings.menuIconRowCount, 1);
      expect(settings.menuBottomRadius, 32);
      expect(settings.menuShowIconText, isFalse);
      expect(settings.titleBarCompact, isFalse);
    });

    test('越界值被 clamp 到 2–8 / 1–2 / 0–32', () {
      const settings = NovelReaderSettings();
      final low = settings.copyWith(
        menuIconItemsPerRow: 1,
        menuIconRowCount: 0,
        menuBottomRadius: -3,
      );
      expect(low.menuIconItemsPerRow, 2);
      expect(low.menuIconRowCount, 1);
      expect(low.menuBottomRadius, 0);

      final high = settings.copyWith(
        menuIconItemsPerRow: 20,
        menuIconRowCount: 5,
        menuBottomRadius: 100,
      );
      expect(high.menuIconItemsPerRow, 8);
      expect(high.menuIconRowCount, 2);
      expect(high.menuBottomRadius, 32);
    });

    test('三处菜单栏各自存配置，互不影响', () {
      const settings = NovelReaderSettings();
      expect(settings.titleBarMenu, novelDefaultTitleBarMenu);
      expect(settings.bottomBarMenu, novelDefaultBottomBarMenu);
      expect(settings.floatingBarMenu, isEmpty);

      final next = settings
          .withMenuBar(NovelMenuBar.floatingBar, const <NovelMenuButtonItem>[
            NovelMenuButtonItem(novelMenuActionPreviousChapter),
            NovelMenuButtonItem(novelMenuActionNextChapter),
          ]);
      expect(next.floatingBarMenu.length, 2);
      // 顶栏与底栏还是默认。
      expect(next.titleBarMenu, novelDefaultTitleBarMenu);
      expect(next.bottomBarMenu, novelDefaultBottomBarMenu);
    });

    test('菜单配置随设置 JSON 往返，显式清空与缺键能区分', () {
      final settings = const NovelReaderSettings()
          .withMenuBar(NovelMenuBar.bottomBar, const <NovelMenuButtonItem>[
            NovelMenuButtonItem(novelMenuActionCatalog, enabled: false),
            NovelMenuButtonItem(novelMenuActionSearch),
          ]);
      final restored = NovelReaderSettings.deserialize(settings.serialize());
      expect(restored.bottomBarMenu, <NovelMenuButtonItem>[
        const NovelMenuButtonItem(novelMenuActionCatalog, enabled: false),
        const NovelMenuButtonItem(novelMenuActionSearch),
      ]);

      // 显式清空：读回来是空列表，不回落到默认五项。
      final cleared = settings.copyWith(
        bottomBarMenu: const <NovelMenuButtonItem>[],
      );
      final clearedRestored = NovelReaderSettings.deserialize(
        cleared.serialize(),
      );
      expect(clearedRestored.bottomBarMenu, isEmpty);

      // 缺键（老 JSON）：走默认。
      final legacy = NovelReaderSettings.fromJson(<String, Object?>{
        'fontSize': 22,
      });
      expect(legacy.bottomBarMenu, novelDefaultBottomBarMenu);
    });
  });

  group('每书覆盖的 kv 存储', () {
    test('按 bookId 分条存，只落白名单字段', () async {
      final prefs = _MemoryPrefs();
      final store = NovelBookSettingsStore(prefs);

      await store.save('book-a', <String, Object?>{
        'fontSize': 28,
        'lineHeight': 2.5, // 白名单外，应被剔掉
      });
      await store.save('book-b', <String, Object?>{'backgroundIndex': 0});

      final a = await store.load('book-a');
      expect(a['fontSize'], 28);
      expect(a.containsKey('lineHeight'), isFalse);
      expect((await store.load('book-b'))['backgroundIndex'], 0);
      expect(await store.bookIds(), <String>{'book-a', 'book-b'});
      expect(prefs.values.containsKey(NovelBookSettingsStore.key), isTrue);
    });

    test('保存空覆盖等于清掉这一本', () async {
      final store = NovelBookSettingsStore(_MemoryPrefs());
      await store.save('book-a', <String, Object?>{'fontSize': 28});
      expect(await store.load('book-a'), isNotEmpty);

      await store.save('book-a', const <String, Object?>{});
      expect(await store.load('book-a'), isEmpty);
      expect(await store.bookIds(), isEmpty);
    });

    test('坏 JSON 不让阅读器卡死，回退空覆盖', () async {
      final prefs = _MemoryPrefs();
      prefs.values[NovelBookSettingsStore.key] = '{这不是 JSON';
      final store = NovelBookSettingsStore(prefs);
      expect(await store.load('book-a'), isEmpty);
    });

    test('未注入 prefs 时读写落内存（测试/依赖缺失场景）', () async {
      final store = NovelBookSettingsStore(null);
      await store.save('book-a', <String, Object?>{'fontSize': 33});
      expect((await store.load('book-a'))['fontSize'], 33);
    });
  });
}
