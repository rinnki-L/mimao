// 阅读器控制器：每书设置进入即套用，改全局不污染每书覆盖。

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/library_api.dart';
import 'package:mimao/novel/reader/novel_reader_controller.dart';
import 'package:mimao/novel/reader/novel_menu_actions.dart';
import 'package:mimao/novel/reader/novel_reader_settings.dart';

class _MemoryPrefs implements NovelPrefsApi {
  _MemoryPrefs([Map<String, String>? seed])
    : values = seed ?? <String, String>{};

  final Map<String, String> values;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

Future<NovelReaderController> _controllerFor(
  _MemoryPrefs prefs, {
  String bookId = 'book-a',
}) async {
  final controller = NovelReaderController(bookId: bookId, prefs: prefs);
  await controller.init();
  return controller;
}

void main() {
  test('进入某本书时自动套用这本书的覆盖（每书 > 全局）', () async {
    final prefs = _MemoryPrefs(<String, String>{
      novelPrefReaderSettings: const NovelReaderSettings(
        fontSize: 22,
        backgroundIndex: 1,
      ).serialize(),
      novelPrefReaderBookSettings: jsonEncode(<String, Object?>{
        'book-a': <String, Object?>{'fontSize': 30, 'backgroundIndex': 0},
        'book-b': <String, Object?>{'fontSize': 16},
      }),
    });

    final a = await _controllerFor(prefs);
    expect(a.settings.fontSize, 30);
    expect(a.settings.backgroundIndex, 0);
    expect(a.hasBookOverride, isTrue);
    // 全局设置本身没被改写。
    expect(a.globalSettings.fontSize, 22);
    expect(a.globalSettings.backgroundIndex, 1);
    a.dispose();

    // 另一本书只吃到自己的覆盖。
    final b = await _controllerFor(prefs, bookId: 'book-b');
    expect(b.settings.fontSize, 16);
    expect(b.settings.backgroundIndex, 1);
    b.dispose();

    // 没有覆盖的书完全跟随全局。
    final c = await _controllerFor(prefs, bookId: 'book-c');
    expect(c.settings.fontSize, 22);
    expect(c.hasBookOverride, isFalse);
    c.dispose();
  });

  test('只改这本：覆盖只存差异，全局不动', () async {
    final prefs = _MemoryPrefs(<String, String>{
      novelPrefReaderSettings: const NovelReaderSettings(
        fontSize: 22,
      ).serialize(),
    });
    final controller = await _controllerFor(prefs);

    controller.applySettings(
      controller.settings.copyWith(fontSize: 30),
      scope: NovelSettingsScope.book,
    );

    expect(controller.settings.fontSize, 30);
    expect(controller.globalSettings.fontSize, 22);
    expect(controller.bookOverride.keys, <String>['fontSize']);
    controller.dispose();
  });

  test('改全局：只把真正改动写进全局，本书覆盖值不泄漏', () async {
    final prefs = _MemoryPrefs(<String, String>{
      novelPrefReaderSettings: const NovelReaderSettings(
        fontSize: 22,
        backgroundIndex: 1,
      ).serialize(),
      novelPrefReaderBookSettings: jsonEncode(<String, Object?>{
        'book-a': <String, Object?>{'fontSize': 30},
      }),
    });
    final controller = await _controllerFor(prefs);
    expect(controller.settings.fontSize, 30);

    // 面板展示的是 30（每书覆盖），用户只改背景 → 全局字号必须还是 22。
    controller.applySettings(controller.settings.copyWith(backgroundIndex: 4));

    expect(controller.globalSettings.fontSize, 22);
    expect(controller.globalSettings.backgroundIndex, 4);
    // 这本书字号仍是自己的 30，背景跟随新的全局 4。
    expect(controller.settings.fontSize, 30);
    expect(controller.settings.backgroundIndex, 4);
    expect(controller.bookOverride.keys, <String>['fontSize']);
    controller.dispose();
  });

  test('「只改这本」下改菜单外观不会静默丢失（落全局）', () async {
    final prefs = _MemoryPrefs();
    final controller = await _controllerFor(prefs);

    controller.applySettings(
      controller.settings.copyWith(
        menuShowIconText: true,
        bottomBarMenu: const <NovelMenuButtonItem>[
          NovelMenuButtonItem(novelMenuActionCatalog),
        ],
      ),
      scope: NovelSettingsScope.book,
    );

    // 菜单布局不是每书可覆盖字段：必须落到全局，不能凭空消失。
    expect(controller.globalSettings.menuShowIconText, isTrue);
    expect(controller.globalSettings.bottomBarMenu.length, 1);
    expect(controller.settings.menuShowIconText, isTrue);
    // 覆盖里不该出现菜单字段（保持「只存差异」的语义）。
    expect(controller.bookOverride.containsKey('menuShowIconText'), isFalse);
    expect(controller.bookOverride.containsKey('bottomBarMenu'), isFalse);

    // 落盘后重新进书，菜单改动仍在（回归：曾按 scope 跳过写全局而丢失）。
    await Future<void>.delayed(const Duration(milliseconds: 400));
    controller.dispose();
    final again = await _controllerFor(prefs);
    expect(again.globalSettings.menuShowIconText, isTrue);
    expect(again.settings.menuShowIconText, isTrue);
    expect(again.settings.bottomBarMenu.length, 1);
    again.dispose();
  });

  test('清掉本书覆盖后完全回到全局', () async {
    final prefs = _MemoryPrefs(<String, String>{
      novelPrefReaderSettings: const NovelReaderSettings(
        fontSize: 22,
      ).serialize(),
      novelPrefReaderBookSettings: jsonEncode(<String, Object?>{
        'book-a': <String, Object?>{'fontSize': 30},
      }),
    });
    final controller = await _controllerFor(prefs);
    expect(controller.settings.fontSize, 30);

    controller.clearBookOverride();
    expect(controller.hasBookOverride, isFalse);
    expect(controller.settings.fontSize, 22);
    controller.dispose();
  });

  test('设置落盘后重新进书仍生效（覆盖持久化）', () async {
    final prefs = _MemoryPrefs();
    final first = await _controllerFor(prefs);
    first.applySettings(
      first.settings.copyWith(
        fontSize: 28,
        backgroundIndex: 0,
        pageMode: NovelPageMode.page,
      ),
      scope: NovelSettingsScope.book,
    );
    // 等防抖计时器（300ms）写完。
    await Future<void>.delayed(const Duration(milliseconds: 400));
    first.dispose();

    final second = await _controllerFor(prefs);
    expect(second.settings.fontSize, 28);
    expect(second.settings.backgroundIndex, 0);
    expect(second.settings.pageMode, NovelPageMode.page);
    // 全局仍是默认值。
    expect(second.globalSettings.fontSize, 20);
    second.dispose();
  });
}
