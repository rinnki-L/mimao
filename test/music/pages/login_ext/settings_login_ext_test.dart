// ignore_for_file: deprecated_member_use — 与 fakes.dart 同款说明。
/// 设置页 L5 扩展 widget 测试：扩展入口的出现条件（auth/verify/settings 齐
/// 备才显示）、入口 push 对应页面、「听歌上报」开关与「歌词」开关/显示模式
/// 的读盘初值/写入/失败回滚。
///
/// 既有登录测试（test/music/login/settings_login_test.dart）继续覆盖扫码线。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/lyric/lyric_models.dart';
import 'package:mimao/music/pages/music_module_settings.dart';

import 'fakes.dart';

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: ListView(children: <Widget>[child])),
);

Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

void main() {
  testWidgets('auth/verify/settings 都未接线：不显示任何 L5 入口', (tester) async {
    await tester.pumpWidget(
      _wrap(MusicModuleSettings(api: FakeMusicApi(null), account: null)),
    );
    await tester.pumpAndSettle();

    expect(find.text('更多登录方式'), findsNothing);
    expect(find.text('安全验证'), findsNothing);
    expect(find.text('听歌上报'), findsNothing);

    await _teardown(tester);
  });

  testWidgets('扩展入口出现条件：verify 才有安全验证；auth+verify 才有更多登录方式', (tester) async {
    // 只有 verify（auth 缺失）：只显示「安全验证」。
    await tester.pumpWidget(
      _wrap(
        MusicModuleSettings(api: FakeMusicApi(null), verify: FakeVerifyApi()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('更多登录方式'), findsNothing);
    expect(find.text('安全验证'), findsOneWidget);
    expect(find.text('听歌上报'), findsNothing);

    await _teardown(tester);
  });

  testWidgets('「更多登录方式」push 方法页（手机号/QQ/微信/设备 tab）', (tester) async {
    await tester.pumpWidget(
      _wrap(
        MusicModuleSettings(
          api: FakeMusicApi(null),
          auth: FakeAuthApi(),
          verify: FakeVerifyApi(),
          searchExt: FakeSearchExtApi(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('更多登录方式'), findsOneWidget);
    await tester.tap(find.text('更多登录方式'));
    await tester.pump();
    await tester.pumpAndSettle();

    // 方法页已打开：默认手机号 tab + 四个 tab 标签。
    expect(find.text('发送验证码'), findsOneWidget);
    expect(find.text('QQ扫码'), findsOneWidget);
    expect(find.text('微信扫码'), findsOneWidget);
    expect(find.text('登录设备'), findsOneWidget);

    await _teardown(tester);
  });

  testWidgets('「安全验证」push 安全验证页', (tester) async {
    await tester.pumpWidget(
      _wrap(
        MusicModuleSettings(
          api: FakeMusicApi(null),
          auth: FakeAuthApi(),
          verify: FakeVerifyApi(),
          searchExt: FakeSearchExtApi(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('安全验证'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('验证事件号'), findsOneWidget);
    expect(find.text('查询'), findsOneWidget);

    await _teardown(tester);
  });

  testWidgets('「听歌上报」开关：ensureLoaded 后刷新初值；切换写入并回显', (tester) async {
    final settings = FakeMusicSettings(initial: true);
    await tester.pumpWidget(
      _wrap(MusicModuleSettings(api: FakeMusicApi(null), settings: settings)),
    );
    await tester.pumpAndSettle();

    expect(settings.ensureLoadedCalls, 1);
    expect(find.text('听歌上报'), findsOneWidget);
    // 默认开启。
    final SwitchListTile initialSwitch = tester.widget<SwitchListTile>(
      find.byKey(const Key('music-settings-listen-report')),
    );
    expect(initialSwitch.value, isTrue);

    // 关闭 → 写入 false 并回显。
    await tester.tap(find.byKey(const Key('music-settings-listen-report')));
    await tester.pumpAndSettle();

    expect(settings.savedValues, <bool>[false]);
    final SwitchListTile toggledSwitch = tester.widget<SwitchListTile>(
      find.byKey(const Key('music-settings-listen-report')),
    );
    expect(toggledSwitch.value, isFalse);

    await _teardown(tester);
  });

  testWidgets('「听歌上报」写入失败：回滚开关并提示', (tester) async {
    final settings = FakeMusicSettings(initial: true)
      ..saveError = StateError('disk');
    await tester.pumpWidget(
      _wrap(MusicModuleSettings(api: FakeMusicApi(null), settings: settings)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('music-settings-listen-report')));
    await tester.pumpAndSettle();

    // 失败：开关回滚为 true，页内给出保存失败提示。
    expect(settings.savedValues, isEmpty);
    final SwitchListTile rolledBack = tester.widget<SwitchListTile>(
      find.byKey(const Key('music-settings-listen-report')),
    );
    expect(rolledBack.value, isTrue);
    expect(find.text('听歌上报设置保存失败'), findsOneWidget);

    await _teardown(tester);
  });

  testWidgets('「歌词」开关默认开启；三种显示模式常驻且默认原文', (tester) async {
    final settings = FakeMusicSettings();
    await tester.pumpWidget(
      _wrap(MusicModuleSettings(api: FakeMusicApi(null), settings: settings)),
    );
    await tester.pumpAndSettle();

    expect(find.text('歌词'), findsOneWidget);
    final SwitchListTile lyricSwitch = tester.widget<SwitchListTile>(
      find.byKey(const Key('music-settings-lyric')),
    );
    expect(lyricSwitch.value, isTrue);

    // 三个模式标签都在，默认选中原文。
    expect(find.text('原文'), findsOneWidget);
    expect(find.text('原文+中翻'), findsOneWidget);
    expect(find.text('原文+音译'), findsOneWidget);
    final SegmentedButton<LyricMode> segmented = tester
        .widget<SegmentedButton<LyricMode>>(
          find.byKey(const Key('music-settings-lyric-mode')),
        );
    expect(segmented.selected, <LyricMode>{LyricMode.original});
    expect(segmented.onSelectionChanged, isNotNull);

    await _teardown(tester);
  });

  testWidgets('切换歌词开关：写入开关值；关闭后模式选择器禁用', (tester) async {
    final settings = FakeMusicSettings(lyricEnabled: true);
    await tester.pumpWidget(
      _wrap(MusicModuleSettings(api: FakeMusicApi(null), settings: settings)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('music-settings-lyric')));
    await tester.pumpAndSettle();

    expect(settings.savedLyricValues, <bool>[false]);
    expect(settings.lyricEnabled, isFalse);
    final SwitchListTile lyricSwitch = tester.widget<SwitchListTile>(
      find.byKey(const Key('music-settings-lyric')),
    );
    expect(lyricSwitch.value, isFalse);
    final SegmentedButton<LyricMode> disabled = tester
        .widget<SegmentedButton<LyricMode>>(
          find.byKey(const Key('music-settings-lyric-mode')),
        );
    expect(disabled.onSelectionChanged, isNull);

    // 再打开：写入 true，选择器恢复可用。
    await tester.tap(find.byKey(const Key('music-settings-lyric')));
    await tester.pumpAndSettle();
    expect(settings.savedLyricValues, <bool>[false, true]);
    final SegmentedButton<LyricMode> enabled = tester
        .widget<SegmentedButton<LyricMode>>(
          find.byKey(const Key('music-settings-lyric-mode')),
        );
    expect(enabled.onSelectionChanged, isNotNull);

    await _teardown(tester);
  });

  testWidgets('选择「原文+中翻」：写入模式并回显选中态', (tester) async {
    final settings = FakeMusicSettings();
    await tester.pumpWidget(
      _wrap(MusicModuleSettings(api: FakeMusicApi(null), settings: settings)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('原文+中翻'));
    await tester.pumpAndSettle();

    expect(settings.savedLyricModes, <LyricMode>[
      LyricMode.originalWithTranslation,
    ]);
    expect(settings.lyricMode, LyricMode.originalWithTranslation);
    final SegmentedButton<LyricMode> segmented = tester
        .widget<SegmentedButton<LyricMode>>(
          find.byKey(const Key('music-settings-lyric-mode')),
        );
    expect(segmented.selected, <LyricMode>{LyricMode.originalWithTranslation});

    await _teardown(tester);
  });

  testWidgets('歌词/模式写入失败：回滚并提示', (tester) async {
    final settings = FakeMusicSettings()..saveError = StateError('disk');
    await tester.pumpWidget(
      _wrap(MusicModuleSettings(api: FakeMusicApi(null), settings: settings)),
    );
    await tester.pumpAndSettle();

    // 歌词开关失败：保持开启。
    await tester.tap(find.byKey(const Key('music-settings-lyric')));
    await tester.pumpAndSettle();
    expect(settings.savedLyricValues, isEmpty);
    final SwitchListTile lyricSwitch = tester.widget<SwitchListTile>(
      find.byKey(const Key('music-settings-lyric')),
    );
    expect(lyricSwitch.value, isTrue);
    expect(find.text('歌词设置保存失败'), findsOneWidget);

    // 模式失败：选中态回滚为原文。
    await tester.tap(find.text('原文+音译'));
    await tester.pumpAndSettle();
    expect(settings.savedLyricModes, isEmpty);
    final SegmentedButton<LyricMode> segmented = tester
        .widget<SegmentedButton<LyricMode>>(
          find.byKey(const Key('music-settings-lyric-mode')),
        );
    expect(segmented.selected, <LyricMode>{LyricMode.original});
    expect(find.text('歌词模式保存失败'), findsOneWidget);

    await _teardown(tester);
  });
}
