// 点击区：九宫格默认映射、几何分区、动作分发与未知动作降级。

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/reader/novel_click_actions.dart';

/// 记录调用了哪些动作的假执行器。
class _Recorder implements NovelClickActionHandler {
  final List<String> calls = <String>[];

  @override
  void openMenu() => calls.add('menu');

  @override
  void turnPreviousPage() => calls.add('previousPage');

  @override
  void turnNextPage() => calls.add('nextPage');

  @override
  void openPreviousChapter() => calls.add('previousChapter');

  @override
  void openNextChapter() => calls.add('nextChapter');

  @override
  void toggleTts() => calls.add('ttsToggle');

  @override
  void toggleAutoPage() => calls.add('autoPage');

  @override
  void addBookmark() => calls.add('addBookmark');

  @override
  void openCatalog() => calls.add('catalog');

  @override
  void openSearch() => calls.add('search');

  @override
  void openContentEdit() => calls.add('editContent');

  @override
  void toggleReplace() => calls.add('replaceToggle');

  @override
  void syncProgress() => calls.add('syncProgress');
}

void main() {
  group('九宫格默认映射', () {
    test('默认只开中间一行：左=上一页、中=菜单、右=下一页', () {
      expect(novelDefaultClickZones.length, NovelClickZone.values.length);
      expect(
        novelDefaultClickZones[NovelClickZone.centerLeft.index],
        NovelClickAction.previousPage,
      );
      expect(
        novelDefaultClickZones[NovelClickZone.center.index],
        NovelClickAction.menu,
      );
      expect(
        novelDefaultClickZones[NovelClickZone.centerRight.index],
        NovelClickAction.nextPage,
      );
    });

    test('上/下两行默认无动作', () {
      for (final zone in <NovelClickZone>[
        NovelClickZone.topLeft,
        NovelClickZone.topCenter,
        NovelClickZone.topRight,
        NovelClickZone.bottomLeft,
        NovelClickZone.bottomCenter,
        NovelClickZone.bottomRight,
      ]) {
        expect(novelDefaultClickZones[zone.index], NovelClickAction.none);
      }
    });

    test('normalizeClickZones 补齐到 9 格、截断多余项', () {
      final short = normalizeClickZones(<NovelClickAction>[
        NovelClickAction.catalog,
      ]);
      expect(short.length, 9);
      expect(short.first, NovelClickAction.catalog);
      expect(short.skip(1), everyElement(NovelClickAction.none));

      final long = normalizeClickZones(
        List<NovelClickAction>.filled(20, NovelClickAction.menu),
      );
      expect(long.length, 9);
    });

    test('动作枚举名就是落库键，改名会破坏兼容', () {
      // 落库靠 enum.name；这里锁住几个关键名字，防止有人「顺手重命名」。
      expect(NovelClickAction.previousPage.name, 'previousPage');
      expect(NovelClickAction.nextPage.name, 'nextPage');
      expect(NovelClickAction.ttsToggle.name, 'ttsToggle');
      expect(NovelClickZone.center.name, 'center');
    });
  });

  group('几何分区', () {
    test('三等分命中 9 格', () {
      const w = 300.0;
      const h = 300.0;
      expect(clickZoneAt(10, 10, w, h), NovelClickZone.topLeft);
      expect(clickZoneAt(150, 10, w, h), NovelClickZone.topCenter);
      expect(clickZoneAt(290, 10, w, h), NovelClickZone.topRight);
      expect(clickZoneAt(10, 150, w, h), NovelClickZone.centerLeft);
      expect(clickZoneAt(150, 150, w, h), NovelClickZone.center);
      expect(clickZoneAt(290, 150, w, h), NovelClickZone.centerRight);
      expect(clickZoneAt(10, 290, w, h), NovelClickZone.bottomLeft);
      expect(clickZoneAt(150, 290, w, h), NovelClickZone.bottomCenter);
      expect(clickZoneAt(290, 290, w, h), NovelClickZone.bottomRight);
    });

    test('恰好在右/下边缘不越界', () {
      expect(clickZoneAt(300, 300, 300, 300), NovelClickZone.bottomRight);
      expect(clickZoneAt(0, 0, 300, 300), NovelClickZone.topLeft);
    });

    test('尺寸为 0 时退到中心格，不抛异常', () {
      expect(clickZoneAt(10, 10, 0, 0), NovelClickZone.center);
      expect(clickZoneAt(10, 10, -5, 100), NovelClickZone.center);
    });
  });

  group('动作分发', () {
    test('每个已实现动作都落到对应方法', () {
      final cases = <NovelClickAction, String>{
        NovelClickAction.menu: 'menu',
        NovelClickAction.previousPage: 'previousPage',
        NovelClickAction.nextPage: 'nextPage',
        NovelClickAction.previousChapter: 'previousChapter',
        NovelClickAction.nextChapter: 'nextChapter',
        NovelClickAction.ttsToggle: 'ttsToggle',
        NovelClickAction.autoPage: 'autoPage',
        NovelClickAction.addBookmark: 'addBookmark',
        NovelClickAction.catalog: 'catalog',
        NovelClickAction.search: 'search',
        NovelClickAction.editContent: 'editContent',
        NovelClickAction.replaceToggle: 'replaceToggle',
        NovelClickAction.syncProgress: 'syncProgress',
      };
      for (final entry in cases.entries) {
        final recorder = _Recorder();
        final handled = dispatchClickAction(entry.key, recorder);
        // 未实现动作的 requires 会让 available=false，分发器拒绝执行。
        if (entry.key.available) {
          expect(handled, isTrue, reason: '${entry.key.name} 应该被执行');
          expect(recorder.calls, <String>[entry.value]);
        } else {
          expect(handled, isFalse, reason: '${entry.key.name} 还没实现');
          expect(recorder.calls, isEmpty);
        }
      }
    });

    test('无动作不调用任何方法', () {
      final recorder = _Recorder();
      expect(dispatchClickAction(NovelClickAction.none, recorder), isFalse);
      expect(recorder.calls, isEmpty);
    });

    test('书签 / 正文编辑 / 替换已实现，未实现的同步进度降级为无动作', () {
      final recorder = _Recorder();
      expect(NovelClickAction.addBookmark.available, isTrue);
      expect(
        dispatchClickAction(NovelClickAction.addBookmark, recorder),
        isTrue,
      );
      expect(recorder.calls, <String>['addBookmark']);

      // 区 6 落地后这两个动作可分发；页面按注入的仓库决定是否真正可用。
      for (final action in <NovelClickAction>[
        NovelClickAction.editContent,
        NovelClickAction.replaceToggle,
      ]) {
        expect(action.available, isTrue);
        expect(dispatchClickAction(action, recorder), isTrue);
      }
      expect(recorder.calls, <String>[
        'addBookmark',
        'editContent',
        'replaceToggle',
      ]);

      expect(NovelClickAction.syncProgress.available, isFalse);
      expect(NovelClickAction.syncProgress.unavailableHint, startsWith('需先完成'));
      expect(
        dispatchClickAction(NovelClickAction.syncProgress, recorder),
        isFalse,
      );
    });

    test('未知动作（反序列化失败降级）也是无动作', () {
      // 旧数据里存了不认识的 enum 名 → fromJson 落到 none。
      final recorder = _Recorder();
      expect(dispatchClickAction(NovelClickAction.none, recorder), isFalse);
      expect(recorder.calls, isEmpty);
    });
  });

  group('长按 / 双击分发', () {
    test('长按默认选文不拦截，交回 SelectionArea', () {
      final recorder = _Recorder();
      expect(
        dispatchLongPressAction(NovelLongPressAction.selectText, recorder),
        isFalse,
      );
      expect(recorder.calls, isEmpty);
    });

    test('长按配成其它动作时接管', () {
      final recorder = _Recorder();
      expect(
        dispatchLongPressAction(NovelLongPressAction.menu, recorder),
        isTrue,
      );
      expect(recorder.calls, <String>['menu']);
    });

    test('双击默认无动作；加书签已实现，其它动作照常分发', () {
      final recorder = _Recorder();
      expect(
        dispatchDoubleTapAction(NovelDoubleTapAction.none, recorder),
        isFalse,
      );
      expect(
        dispatchDoubleTapAction(NovelDoubleTapAction.addBookmark, recorder),
        isTrue,
      );
      expect(recorder.calls, <String>['addBookmark']);

      expect(
        dispatchDoubleTapAction(NovelDoubleTapAction.nextPage, recorder),
        isTrue,
      );
      expect(recorder.calls, <String>['addBookmark', 'nextPage']);
    });
  });
}
