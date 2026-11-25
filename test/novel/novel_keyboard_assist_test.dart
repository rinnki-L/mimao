// 键盘辅助：默认表 == 改造前的写死键位 / 组合键解析与归一 / 配置往返。
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/library_api.dart'
    show NovelPrefsApi, novelPrefKeyboardAssist;
import 'package:mimao/novel/reader/novel_click_actions.dart';
import 'package:mimao/novel/reader/novel_keyboard_assist.dart';

class _MemoryPrefs implements NovelPrefsApi {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

void main() {
  test('默认键位就是改造前写死的那套（←→↑↓ / PageUp/Down / 空格）', () {
    final map = <String, NovelClickAction>{
      for (final item in novelDefaultKeyboardBindings) item.keys: item.action,
    };
    expect(map['ArrowLeft'], NovelClickAction.previousPage);
    expect(map['ArrowRight'], NovelClickAction.nextPage);
    expect(map['ArrowUp'], NovelClickAction.previousPage);
    expect(map['ArrowDown'], NovelClickAction.nextPage);
    expect(map['PageUp'], NovelClickAction.previousPage);
    expect(map['PageDown'], NovelClickAction.nextPage);
    expect(map['Space'], NovelClickAction.autoPage);
    // 全部可解析。
    for (final item in novelDefaultKeyboardBindings) {
      expect(novelShortcutFor(item.keys), isNotNull, reason: item.keys);
    }
  });

  test('组合键解析：修饰键 + 键名，大小写不敏感', () {
    final shortcut = novelShortcutFor('ctrl+SHIFT+ArrowRight');
    expect(shortcut, isNotNull);
    expect(shortcut!.trigger, LogicalKeyboardKey.arrowRight);
    expect(shortcut.control, isTrue);
    expect(shortcut.shift, isTrue);
    expect(shortcut.alt, isFalse);

    expect(novelShortcutFor('Space')!.trigger, LogicalKeyboardKey.space);
    expect(novelShortcutFor('f5')!.trigger, LogicalKeyboardKey.f5);
    expect(novelShortcutFor('A')!.trigger, LogicalKeyboardKey.keyA);
    expect(novelShortcutFor('7')!.trigger, LogicalKeyboardKey.digit7);
  });

  test('认不出的键位返回 null', () {
    expect(novelShortcutFor(''), isNull);
    expect(novelShortcutFor('Ctrl+Foo'), isNull);
    expect(novelShortcutFor('Ctrl'), isNull);
    expect(novelShortcutFor('Ctrl+Shift'), isNull);
    expect(novelShortcutFor('ArrowRight+Ctrl'), isNull);
  });

  test('按键事件归一成规范键位串', () {
    expect(novelKeySpecOf(LogicalKeyboardKey.arrowRight), 'ArrowRight');
    expect(
      novelKeySpecOf(LogicalKeyboardKey.keyK, control: true, shift: true),
      'Ctrl+Shift+k',
    );
    expect(novelKeySpecOf(LogicalKeyboardKey.f12), 'F12');
    expect(novelKeySpecOf(LogicalKeyboardKey.audioVolumeUp), isNull);
  });

  test('归一：丢停用/无动作/未实现/认不出的键，同键位只留第一条', () {
    final normalized = normalizedNovelKeyboardBindings(<NovelKeyboardBinding>[
      const NovelKeyboardBinding(
        keys: 'ArrowRight',
        action: NovelClickAction.nextPage,
      ),
      const NovelKeyboardBinding(
        keys: 'arrowright',
        action: NovelClickAction.menu,
      ),
      const NovelKeyboardBinding(
        keys: 'ArrowLeft',
        action: NovelClickAction.none,
      ),
      const NovelKeyboardBinding(
        keys: 'ArrowUp',
        action: NovelClickAction.syncProgress,
      ),
      const NovelKeyboardBinding(
        keys: 'Q',
        action: NovelClickAction.previousPage,
        enabled: false,
      ),
      const NovelKeyboardBinding(
        keys: 'Ctrl+Foo',
        action: NovelClickAction.menu,
      ),
      const NovelKeyboardBinding(keys: 'F5', action: NovelClickAction.catalog),
    ]);
    expect(normalized.map((b) => b.keys), <String>['ArrowRight', 'F5']);
    expect(normalized.first.action, NovelClickAction.nextPage);
  });

  test('配置 JSON 往返（含 showHints）', () {
    const config = NovelKeyboardConfig(
      bindings: <NovelKeyboardBinding>[
        NovelKeyboardBinding(keys: 'F5', action: NovelClickAction.catalog),
      ],
      showHints: true,
    );
    final decoded = NovelKeyboardConfig.decode(config.encode());
    expect(decoded.showHints, isTrue);
    expect(decoded.bindings.single.keys, 'F5');
    expect(decoded.bindings.single.action, NovelClickAction.catalog);
  });

  test('空/坏配置回退默认，不让一条坏数据卡住阅读器', () {
    expect(
      NovelKeyboardConfig.decode(null).bindings.length,
      novelDefaultKeyboardBindings.length,
    );
    expect(NovelKeyboardConfig.decode('not json').showHints, isFalse);
    expect(
      NovelKeyboardConfig.decode('{"bindings":"x"}').bindings.length,
      novelDefaultKeyboardBindings.length,
    );
    // 空列表也回退默认（否则用户「清空」后键盘全失效且无从恢复）。
    expect(
      NovelKeyboardConfig.decode('{"bindings":[]}').bindings.length,
      novelDefaultKeyboardBindings.length,
    );
  });

  test('store：写入后读回；prefs 缺失时走内存', () async {
    final prefs = _MemoryPrefs();
    final store = NovelKeyboardAssistStore(prefs);
    expect((await store.load()).showHints, isFalse);
    await store.save(
      const NovelKeyboardConfig(
        bindings: <NovelKeyboardBinding>[
          NovelKeyboardBinding(keys: 'Space', action: NovelClickAction.catalog),
        ],
        showHints: true,
      ),
    );
    expect(prefs.values.containsKey(novelPrefKeyboardAssist), isTrue);
    final loaded = await store.load();
    expect(loaded.showHints, isTrue);
    expect(loaded.bindings.single.action, NovelClickAction.catalog);

    final memoryOnly = NovelKeyboardAssistStore(null);
    await memoryOnly.save(const NovelKeyboardConfig(showHints: true));
    expect((await memoryOnly.load()).showHints, isTrue);
  });

  test('可选动作列表：排除「无动作」与未实现动作', () {
    final actions = novelKeyboardAssignableActions();
    expect(actions, isNot(contains(NovelClickAction.none)));
    expect(actions, isNot(contains(NovelClickAction.syncProgress)));
    expect(actions, contains(NovelClickAction.nextPage));
    expect(actions, contains(NovelClickAction.catalog));
  });
}
