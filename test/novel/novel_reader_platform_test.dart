// ignore_for_file: deprecated_member_use — 见 lib/main.dart 文件头说明。
// 阅读页平台接线：Android 能力按设置下发、桌面保持遮罩与隐藏按钮、
// 设置项 JSON 往返、设置面板按平台分端渲染。
//
// 证据边界：全部在 flutter_test（桌面宿主）里用 fake 平台跑，证明的是「页面把期望
// 状态交给了平台」；Android 原生侧是否真改亮度 / 真挡休眠无法在此证明（见 LESSON §七）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/engine/explore_kinds.dart';
import 'package:mimao/novel/engine/online_engine.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/pages/novel_reader_page.dart';
import 'package:mimao/novel/reader/novel_platform.dart';
import 'package:mimao/novel/reader/novel_reader_settings.dart';
import 'package:mimao/novel/reader/novel_reader_settings_sheet.dart';
import 'package:mimao/novel/source/novel_source_model.dart';
import 'package:mimao/novel/source/novel_source_store.dart';

const _source = NovelBookSource(
  key: 'src1',
  name: '测试源',
  url: 'https://site.test',
  type: 0,
  enabled: true,
  raw: <String, dynamic>{},
);

final _chapters = <NovelChapter>[
  const NovelChapter(
    id: 'https://site.test/book/1/1',
    title: '第一章',
    index: 0,
    url: 'https://site.test/book/1/1',
  ),
];

class _Engine implements NovelOnlineEngine {
  @override
  void close() {}

  @override
  Future<List<NovelSummary>> searchSource(
    NovelBookSource source,
    String keyword, {
    int page = 1,
  }) async => const <NovelSummary>[];

  @override
  Future<List<NovelExploreKind>> exploreKinds(NovelBookSource source) async =>
      const <NovelExploreKind>[];

  @override
  Future<List<NovelSummary>> exploreSource(
    NovelBookSource source,
    NovelExploreKind kind, {
    int page = 1,
  }) async => const <NovelSummary>[];

  @override
  Future<NovelDetail> bookDetail(
    NovelBookSource source,
    NovelRef ref, {
    String? titleHint,
    String? authorHint,
  }) async =>
      NovelDetail(ref: ref, title: '长书', author: '作者', chapters: _chapters);

  @override
  Future<NovelContent> contentFor(
    NovelBookSource source,
    NovelRef ref,
    NovelChapter chapter,
  ) async => NovelContent(
    chapterId: chapter.id,
    title: chapter.title,
    paragraphs: <String>[
      for (var i = 0; i < 40; i++)
        '第$i段：${List<String>.filled(120, '字').join()}',
    ],
  );
}

class _FixedStore implements NovelSourceStorage {
  @override
  Future<List<NovelBookSource>> loadAll() async => <NovelBookSource>[_source];

  @override
  Future<int> saveAll(Iterable<NovelBookSource> sources) async => 0;

  @override
  Future<void> setEnabled(String key, bool enabled) async {}

  @override
  Future<bool> delete(String key) async => false;
}

/// 记录调用序列的假平台；[mobile] 为 false 时模拟桌面（能力全关、保留遮罩）。
class _FakePlatform implements NovelPlatform {
  _FakePlatform({this.mobile = true});

  final bool mobile;

  final List<double?> brightnessCalls = <double?>[];
  final List<bool> keepAwakeCalls = <bool>[];
  final List<({bool hideStatusBar, bool hideNavigationBar})> barCalls =
      <({bool hideStatusBar, bool hideNavigationBar})>[];
  final List<NovelScreenOrientation> orientationCalls =
      <NovelScreenOrientation>[];
  final List<bool> volumeCalls = <bool>[];
  int disposeCount = 0;

  @override
  bool get supportsScreenBrightness => mobile;
  @override
  bool get supportsKeepAwake => mobile;
  @override
  bool get supportsSystemBars => mobile;
  @override
  bool get supportsOrientation => mobile;
  @override
  bool get supportsVolumeKeys => mobile;
  @override
  bool get supportsBackgroundTts => false;
  @override
  bool get usesRealBrightness => mobile;

  @override
  Future<void> setBrightness(double? value) async => brightnessCalls.add(value);

  @override
  Future<void> setKeepAwake(bool enabled) async => keepAwakeCalls.add(enabled);

  @override
  Future<void> applySystemBars({
    required bool hideStatusBar,
    required bool hideNavigationBar,
  }) async => barCalls.add((
    hideStatusBar: hideStatusBar,
    hideNavigationBar: hideNavigationBar,
  ));

  @override
  Future<void> setOrientation(NovelScreenOrientation orientation) async =>
      orientationCalls.add(orientation);

  @override
  Future<void> setVolumeKeysEnabled(bool enabled) async =>
      volumeCalls.add(enabled);

  @override
  Future<void> dispose() async => disposeCount++;
}

Widget _reader({
  required NovelPlatform platform,
  required NovelReaderSettingsStore settingsStore,
}) => MaterialApp(
  home: NovelReaderPage(
    bookId: 'book1',
    title: '长书',
    sourceKey: 'src1',
    bookUrl: 'https://site.test/book/1',
    chapterIndex: 0,
    chapters: _chapters,
    onlineEngine: _Engine(),
    sourceStore: _FixedStore(),
    settingsStore: settingsStore,
    platform: platform,
  ),
);

void main() {
  testWidgets('Android：亮度/系统栏/方向按设置下发，自动翻页开关常亮', (tester) async {
    final platform = _FakePlatform();
    await tester.pumpWidget(
      _reader(
        platform: platform,
        settingsStore: MemoryNovelReaderSettingsStore(
          const NovelReaderSettings(dimBrightness: 60),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(platform.brightnessCalls, <double?>[0.6]);
    expect(platform.barCalls, <({bool hideStatusBar, bool hideNavigationBar})>[
      (hideStatusBar: true, hideNavigationBar: true),
    ]);
    expect(platform.orientationCalls, <NovelScreenOrientation>[
      NovelScreenOrientation.system,
    ]);
    expect(platform.volumeCalls, <bool>[false]);

    // Android：真亮度生效 → 页面不画遮罩，并显示「自动亮度」按钮。
    expect(find.byKey(const Key('novel-reader-dim-overlay')), findsNothing);
    expect(
      find.byKey(const Key('novel-reader-auto-brightness')),
      findsOneWidget,
    );

    // 自动翻页开着时常亮，关掉即释放。
    await tester.tap(find.byKey(const Key('novel-reader-auto-page')));
    await tester.pump();
    expect(platform.keepAwakeCalls.last, isTrue);
    await tester.tap(find.byKey(const Key('novel-reader-auto-page')));
    await tester.pump();
    expect(platform.keepAwakeCalls.last, isFalse);

    // 退出阅读页：平台 dispose 被调用（内部负责还原亮度/常亮/系统栏/方向）。
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpAndSettle();
    expect(platform.disposeCount, 1);
  });

  testWidgets('桌面：不显示自动亮度按钮，遮罩滑杆保留', (tester) async {
    final platform = _FakePlatform(mobile: false);
    await tester.pumpWidget(
      _reader(
        platform: platform,
        settingsStore: MemoryNovelReaderSettingsStore(
          const NovelReaderSettings(dimBrightness: 60, volumeKeys: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('novel-reader-auto-brightness')),
      findsNothing,
      reason: '桌面端没有可靠的系统亮度接口，按钮必须隐藏',
    );
    expect(
      find.byKey(const Key('novel-reader-dim-overlay')),
      findsOneWidget,
      reason: '桌面端亮度靠遮罩滑杆',
    );
    // 桌面不建立音量键租约：只会收到一次「显式关闭」，绝不会被打开。
    expect(platform.volumeCalls, isNot(contains(true)));
  });

  test('平台设置项：默认值 / JSON 往返 / 旧 JSON 与非法值回退', () {
    const defaults = NovelReaderSettings();
    expect(defaults.screenOrientation, NovelScreenOrientation.system);
    expect(defaults.keepAwakeOnAutoPage, isTrue);
    expect(defaults.hideStatusBar, isTrue);
    expect(defaults.hideNavigationBar, isTrue);
    expect(defaults.volumeKeys, isFalse);

    final json = const NovelReaderSettings(
      screenOrientation: NovelScreenOrientation.landscape,
      keepAwakeOnAutoPage: false,
      hideStatusBar: false,
      hideNavigationBar: false,
      volumeKeys: true,
    ).toJson();
    final restored = NovelReaderSettings.fromJson(json);
    expect(restored.screenOrientation, NovelScreenOrientation.landscape);
    expect(restored.keepAwakeOnAutoPage, isFalse);
    expect(restored.hideStatusBar, isFalse);
    expect(restored.hideNavigationBar, isFalse);
    expect(restored.volumeKeys, isTrue);

    // 改造前的旧 JSON 没有这些键：回退到「保持现有观感」的默认值。
    final legacy = NovelReaderSettings.fromJson(const <String, Object?>{});
    expect(legacy.screenOrientation, NovelScreenOrientation.system);
    expect(legacy.keepAwakeOnAutoPage, isTrue);
    expect(legacy.hideStatusBar, isTrue);
    expect(legacy.hideNavigationBar, isTrue);
    expect(legacy.volumeKeys, isFalse);

    final bad = NovelReaderSettings.fromJson(<String, Object?>{
      'screenOrientation': 'sideways',
      'volumeKeys': 'yes',
    });
    expect(bad.screenOrientation, NovelScreenOrientation.system);
    expect(bad.volumeKeys, isFalse);
  });

  testWidgets('设置面板：Android 才出现「屏幕与设备」卡，桌面整块不渲染', (tester) async {
    Future<void> pumpSheet(NovelPlatform platform) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NovelReaderSettingsSheet(
              initial: const NovelReaderSettings(),
              info: const NovelReaderBookInfo(),
              onChanged: (value, {scope = NovelSettingsScope.global}) {},
              onClose: () {},
              platform: platform,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('novel-settings-tab-more')));
      await tester.pumpAndSettle();
    }

    await pumpSheet(const NoopNovelPlatform());
    expect(find.text('屏幕与设备'), findsNothing);

    var last = const NovelReaderSettings();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NovelReaderSettingsSheet(
            initial: const NovelReaderSettings(),
            info: const NovelReaderBookInfo(),
            onChanged: (value, {scope = NovelSettingsScope.global}) =>
                last = value,
            onClose: () {},
            platform: _FakePlatform(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('novel-settings-tab-more')));
    await tester.pumpAndSettle();

    expect(find.text('屏幕与设备'), findsOneWidget);
    expect(find.text('仅 Android'), findsOneWidget);
    // 后台朗读只有灰显项（当前未落地），不能给「点了没反应」的开关。
    expect(find.text('后台朗读 + 通知栏控制'), findsOneWidget);

    final volumeSwitch = find.byKey(const Key('novel-settings-volume-keys'));
    await tester.ensureVisible(volumeSwitch);
    await tester.tap(volumeSwitch);
    await tester.pump();
    expect(last.volumeKeys, isTrue);

    final orientation = find.byKey(
      const Key('novel-settings-screen-orientation'),
    );
    await tester.ensureVisible(orientation);
    await tester.tap(orientation);
    await tester.pumpAndSettle();
    await tester.tap(find.text('横屏').last);
    await tester.pumpAndSettle();
    expect(last.screenOrientation, NovelScreenOrientation.landscape);
  });
}
