// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与 music/pages 其它文件同款说明。
/// 音乐偏好页测试：装载渲染（chips/原始文本/只读）、行编辑编码、只提交
/// 改动字段、空变更拒绝、updated=false 与异常提示、加载失败重试；
/// 官方标签候选（注入 fake 标签组）：归类渲染、点击增删权重行、序列化。
/// 全部走 fake（见 fakes.dart），不联网、无真实计时器。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/discovery_models.dart';
import 'package:mimao/music/models/user_library_models.dart';
import 'package:mimao/music/pages/music_preference_page.dart';

import 'fakes.dart';

/// 风格标签组假数据（形状与 everyday_style_recommend 单测一致）：
/// 语种组（国语 id=1 / 粤语 id=2）、曲风组（流行 id=11）、场景组（深夜
/// id=21，不属于偏好候选，应被忽略）。
List<MusicStyleTagGroup> fakeStyleGroups() => <MusicStyleTagGroup>[
  const MusicStyleTagGroup(
    name: '语种',
    child: <MusicStyleTag>[
      MusicStyleTag(id: '1', name: '国语', selected: 1),
      MusicStyleTag(id: '2', name: '粤语', selected: null),
    ],
  ),
  const MusicStyleTagGroup(
    name: '曲风',
    child: <MusicStyleTag>[MusicStyleTag(id: '11', name: '流行', selected: null)],
  ),
  const MusicStyleTagGroup(
    name: '场景',
    child: <MusicStyleTag>[MusicStyleTag(id: '21', name: '深夜', selected: null)],
  ),
];

/// 探针宿主：从首页 push 偏好页，记录 pop 回执。
class _Probe {
  final FakeUserLibraryApi library = FakeUserLibraryApi();
  final List<bool?> popped = <bool?>[];

  /// 候选标签注入（null = 生产未接线，候选区隐藏）。
  Future<List<MusicStyleTagGroup>> Function()? loadTagGroups;

  Widget build() => MaterialApp(
    home: Builder(
      builder: (BuildContext context) => Center(
        child: TextButton(
          onPressed: () {
            Navigator.of(context)
                .push<bool>(
                  MaterialPageRoute<bool>(
                    builder: (_) => MusicPreferencePage(
                      library: library,
                      loadTagGroups: loadTagGroups,
                    ),
                  ),
                )
                .then((bool? value) => popped.add(value));
          },
          child: const Text('open'),
        ),
      ),
    ),
  );
}

/// push 偏好页并等装载完成（视口加高，长表单整页可见）。
Future<_Probe> _open(WidgetTester tester, _Probe probe) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(probe.build());
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return probe;
}

Finder _key(String name) => find.byKey(ValueKey<String>(name));

void main() {
  testWidgets('装载渲染：可解析权重显示 chips，不可解析显示原始文本，'
      '非文本值只读展示', (tester) async {
    final probe = _Probe();
    probe.library.preference = fakePreferences(
      recommendationMode: '1',
      gender: '2',
      age: '25',
      languages: const MusicWeightPreference(
        encoded: '{"国语":1.5,"流行":2}',
        weights: <String, double>{'国语': 1.5, '流行': 2},
        raw: '{"国语":1.5,"流行":2}',
      ),
      styles: const MusicWeightPreference(
        encoded: 'not-json',
        weights: null,
        raw: 'not-json',
      ),
      recommendation: const MusicWeightPreference(
        encoded: null,
        weights: null,
        raw: 42,
      ),
    );
    await _open(tester, probe);

    expect(probe.library.preferenceCalls, 1);
    // 基础字段预填（EditableText 内容可被 find.text 命中；限定在各字段
    // 子树内——lang 权重行也含文本 '2'，避免跨字段误命中）。
    Finder fieldText(String key, String text) =>
        find.descendant(of: _key(key), matching: find.text(text));
    expect(fieldText('pref-mode', '1'), findsOneWidget);
    expect(fieldText('pref-gender', '2'), findsOneWidget);
    expect(fieldText('pref-age', '25'), findsOneWidget);
    // lang 能解出 weights → chips「标签: 权重」。
    expect(find.text('国语: 1.5'), findsOneWidget);
    expect(find.text('流行: 2'), findsOneWidget);
    // style 是字符串但解不出 weights → 原始文本进输入框。
    expect(find.text('not-json'), findsOneWidget);
    // song_lang 连文本都没有 → 只读原始值，绝不丢远端值。
    expect(find.text('原始值：42'), findsOneWidget);
  });

  testWidgets('行编辑改权重：序列化 key 排序 JSON，只提交改动字段，成功 pop(true)', (tester) async {
    final probe = _Probe();
    probe.library.preference = fakePreferences(
      recommendationMode: '1',
      gender: '2',
      age: '25',
      languages: const MusicWeightPreference(
        encoded: '{"国语":1.5,"流行":2}',
        weights: <String, double>{'国语': 1.5, '流行': 2},
        raw: '{"国语":1.5,"流行":2}',
      ),
    );
    await _open(tester, probe);

    await tester.enterText(_key('pref-lang-weight-0'), '3'); // 国语 1.5 → 3
    await tester.tap(_key('pref-save'));
    await tester.pump();
    await tester.pump();

    expect(probe.library.preferenceUpdateQueries, hasLength(1));
    final query = probe.library.preferenceUpdateQueries.single;
    expect(query.languages, '{"国语":3,"流行":2}');
    expect(query.recommendationMode, isNull); // 未改动不下发
    expect(query.gender, isNull);
    expect(query.age, isNull);
    expect(query.styles, isNull);
    expect(query.recommendation, isNull);
    expect(probe.popped, <bool?>[true]);
  });

  testWidgets('添加标签行参与编码', (tester) async {
    final probe = _Probe();
    probe.library.preference = fakePreferences(
      languages: const MusicWeightPreference(
        encoded: '{"国语":1.5,"流行":2}',
        weights: <String, double>{'国语': 1.5, '流行': 2},
        raw: '{"国语":1.5,"流行":2}',
      ),
    );
    await _open(tester, probe);

    await tester.tap(_key('pref-lang-add'));
    await tester.pump();
    await tester.enterText(_key('pref-lang-label-2'), '电子');
    await tester.enterText(_key('pref-lang-weight-2'), '0.5');
    await tester.tap(_key('pref-save'));
    await tester.pump();
    await tester.pump();

    expect(
      probe.library.preferenceUpdateQueries.single.languages,
      '{"国语":1.5,"流行":2,"电子":0.5}',
    );
  });

  testWidgets('移除标签行参与编码', (tester) async {
    final probe = _Probe();
    probe.library.preference = fakePreferences(
      languages: const MusicWeightPreference(
        encoded: '{"国语":1.5,"流行":2}',
        weights: <String, double>{'国语': 1.5, '流行': 2},
        raw: '{"国语":1.5,"流行":2}',
      ),
    );
    await _open(tester, probe);

    await tester.tap(_key('pref-lang-remove-1')); // 移除「流行」
    await tester.pump();
    await tester.tap(_key('pref-save'));
    await tester.pump();
    await tester.pump();
    expect(
      probe.library.preferenceUpdateQueries.single.languages,
      '{"国语":1.5}',
    );
    expect(probe.popped, <bool?>[true]);
  });

  testWidgets('全部标签删空后提交空对象（空表=清除语义，与远端空表才不算改动）', (tester) async {
    final probe = _Probe();
    probe.library.preference = fakePreferences(
      languages: const MusicWeightPreference(
        encoded: '{"国语":1.5,"流行":2}',
        weights: <String, double>{'国语': 1.5, '流行': 2},
        raw: '{"国语":1.5,"流行":2}',
      ),
    );
    await _open(tester, probe);

    await tester.tap(_key('pref-lang-remove-1'));
    await tester.pump();
    await tester.tap(_key('pref-lang-remove-0'));
    await tester.pump();
    await tester.tap(_key('pref-save'));
    await tester.pump();
    await tester.pump();
    // 远端有 2 个标签 → 删空是真实改动，提交空对象。
    expect(probe.library.preferenceUpdateQueries.single.languages, '{}');
    expect(probe.popped, <bool?>[true]);
  });

  testWidgets('基础字段只提交改动字段；空串是合法值（清除语义）', (tester) async {
    final probe = _Probe();
    probe.library.preference = fakePreferences(
      recommendationMode: '1',
      gender: '2',
      age: '25',
    );
    await _open(tester, probe);

    await tester.enterText(_key('pref-mode'), ''); // 清空模式
    await tester.tap(_key('pref-save'));
    await tester.pump();
    await tester.pump();

    final query = probe.library.preferenceUpdateQueries.single;
    expect(query.recommendationMode, '');
    expect(query.gender, isNull); // '2' 未变不下发
    expect(query.age, isNull); // '25' 未变不下发
    expect(query.languages, isNull);
    expect(query.styles, isNull);
    expect(query.recommendation, isNull);
  });

  testWidgets('空变更不允许提交', (tester) async {
    final probe = _Probe();
    probe.library.preference = fakePreferences();
    await _open(tester, probe);

    await tester.tap(_key('pref-save'));
    await tester.pump();

    expect(find.text('偏好没有变化'), findsOneWidget);
    expect(probe.library.preferenceUpdateQueries, isEmpty);
    expect(probe.popped, isEmpty);
  });

  testWidgets('权重不是数字时就地提示，不发请求', (tester) async {
    final probe = _Probe();
    probe.library.preference = fakePreferences(
      languages: const MusicWeightPreference(
        encoded: '{"国语":1.5}',
        weights: <String, double>{'国语': 1.5},
        raw: '{"国语":1.5}',
      ),
    );
    await _open(tester, probe);

    await tester.enterText(_key('pref-lang-weight-0'), 'abc');
    await tester.tap(_key('pref-save'));
    await tester.pump();

    expect(find.textContaining('权重必须是数字'), findsOneWidget);
    expect(probe.library.preferenceUpdateQueries, isEmpty);
  });

  testWidgets('updated=false 提示失败、不退出', (tester) async {
    final probe = _Probe();
    probe.library
      ..preference = fakePreferences(recommendationMode: '1')
      ..preferenceUpdateResult = false;
    await _open(tester, probe);

    await tester.enterText(_key('pref-mode'), '2');
    await tester.tap(_key('pref-save'));
    await tester.pump();
    await tester.pump();

    expect(find.text('保存失败，请稍后重试'), findsOneWidget);
    expect(probe.popped, isEmpty);
    expect(probe.library.preferenceUpdateQueries, hasLength(1));
  });

  testWidgets('更新异常页内提示、不退出；重试可成功', (tester) async {
    final probe = _Probe();
    probe.library
      ..preference = fakePreferences(recommendationMode: '1')
      ..preferenceUpdateError = const KugouApiException('business', '服务繁忙');
    await _open(tester, probe);

    await tester.enterText(_key('pref-mode'), '2');
    await tester.tap(_key('pref-save'));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('保存失败'), findsOneWidget);
    expect(find.textContaining('服务繁忙'), findsOneWidget);
    expect(probe.popped, isEmpty);

    probe.library.preferenceUpdateError = null;
    await tester.tap(_key('pref-save'));
    await tester.pump();
    await tester.pump();
    expect(probe.library.preferenceUpdateQueries, hasLength(2));
    expect(probe.popped, <bool?>[true]);
  });

  testWidgets('装载失败显示错误与重试', (tester) async {
    final probe = _Probe()
      ..library.preferenceError = const KugouApiException('business', '服务繁忙');
    await _open(tester, probe);

    expect(find.textContaining('服务繁忙'), findsOneWidget);

    probe.library
      ..preferenceError = null
      ..preference = fakePreferences(
        languages: const MusicWeightPreference(
          encoded: '{"国语":1.5}',
          weights: <String, double>{'国语': 1.5},
          raw: '{"国语":1.5}',
        ),
      );
    await tester.tap(find.text('重试'));
    await tester.pump();
    await tester.pump();
    expect(find.text('国语: 1.5'), findsOneWidget);
  });

  testWidgets('候选 chips 按组归类：语种/曲风展示、场景组忽略，'
      '已有权重键命中候选 id 时用候选名回显', (tester) async {
    final probe = _Probe()..loadTagGroups = () async => fakeStyleGroups();
    probe.library.preference = fakePreferences(
      languages: const MusicWeightPreference(
        encoded: '{"1":100}',
        weights: <String, double>{'1': 100},
        raw: '{"1":100}',
      ),
    );
    await _open(tester, probe);

    // 语种候选同时出现在 lang 与 song_lang 两个字段；按字段子树定位。
    Finder candidate(String section, String label) =>
        find.descendant(of: _key('pref-$section'), matching: find.text(label));
    expect(candidate('lang', '国语'), findsOneWidget);
    expect(candidate('lang', '粤语'), findsOneWidget);
    expect(candidate('style', '流行'), findsOneWidget);
    expect(candidate('song_lang', '国语'), findsOneWidget);
    // 场景组不进入偏好候选。
    expect(find.text('深夜'), findsNothing);
    // 权重键 '1' 命中候选 id → chip 用候选名回显；键序/权重格式不变。
    expect(find.text('国语: 100'), findsOneWidget);

    final FilterChip selected = tester.widget<FilterChip>(
      find.ancestor(
        of: candidate('lang', '国语'),
        matching: find.byType(FilterChip),
      ),
    );
    expect(selected.selected, isTrue);
  });

  testWidgets('点击候选 chip 追加权重行：label 写标签 id，默认权重 '
      'lang/style=100、song_lang=50，保存序列化正确', (tester) async {
    final probe = _Probe()..loadTagGroups = () async => fakeStyleGroups();
    probe.library.preference = fakePreferences();
    await _open(tester, probe);

    Future<void> tapCandidate(String wireKey, String id) async {
      final Finder chip = _key('pref-$wireKey-candidate-$id');
      await tester.ensureVisible(chip);
      await tester.pumpAndSettle();
      await tester.tap(chip);
      await tester.pumpAndSettle();
    }

    await tapCandidate('lang', '1'); // 国语
    await tapCandidate('style', '11'); // 流行
    await tapCandidate('song_lang', '2'); // 粤语

    Finder fieldText(String key, String text) =>
        find.descendant(of: _key(key), matching: find.text(text));
    expect(fieldText('pref-lang-label-0', '1'), findsOneWidget);
    expect(fieldText('pref-lang-weight-0', '100'), findsOneWidget);
    expect(fieldText('pref-style-label-0', '11'), findsOneWidget);
    expect(fieldText('pref-style-weight-0', '100'), findsOneWidget);
    expect(fieldText('pref-song_lang-label-0', '2'), findsOneWidget);
    expect(fieldText('pref-song_lang-weight-0', '50'), findsOneWidget);

    await tester.tap(_key('pref-save'));
    await tester.pump();
    await tester.pump();

    final query = probe.library.preferenceUpdateQueries.single;
    expect(query.languages, '{"1":100}');
    expect(query.styles, '{"11":100}');
    expect(query.recommendation, '{"2":50}');
    expect(probe.popped, <bool?>[true]);
  });

  testWidgets('已添加候选再点一次取消：移除对应权重行并按剩余行提交', (tester) async {
    final probe = _Probe()..loadTagGroups = () async => fakeStyleGroups();
    probe.library.preference = fakePreferences(
      languages: const MusicWeightPreference(
        encoded: '{"1":100,"2":50}',
        weights: <String, double>{'1': 100, '2': 50},
        raw: '{"1":100,"2":50}',
      ),
    );
    await _open(tester, probe);

    await tester.tap(_key('pref-lang-candidate-1')); // 取消「国语」
    await tester.pumpAndSettle();
    // 只剩「粤语」一行（行序按初始 key 排序，索引 0）。
    expect(_key('pref-lang-label-1'), findsNothing);
    expect(
      find.descendant(of: _key('pref-lang-label-0'), matching: find.text('2')),
      findsOneWidget,
    );

    await tester.tap(_key('pref-save'));
    await tester.pump();
    await tester.pump();
    expect(probe.library.preferenceUpdateQueries.single.languages, '{"2":50}');
    expect(probe.popped, <bool?>[true]);
  });

  testWidgets('候选加载失败静默隐藏、不影响自由行编辑', (tester) async {
    final probe = _Probe()
      ..loadTagGroups = () async =>
          throw const KugouApiException('decode', '风格推荐响应 data 不是 object');
    probe.library.preference = fakePreferences(
      languages: const MusicWeightPreference(
        encoded: '{"国语":1.5}',
        weights: <String, double>{'国语': 1.5},
        raw: '{"国语":1.5}',
      ),
    );
    await _open(tester, probe);

    expect(_key('pref-lang-candidates'), findsNothing);
    expect(find.text('国语: 1.5'), findsOneWidget); // 原权重 chip 照旧

    // 原有自由入口仍可用：添加自定义标签行并提交。
    await tester.tap(_key('pref-lang-add'));
    await tester.pump();
    await tester.enterText(_key('pref-lang-label-1'), '电子');
    await tester.enterText(_key('pref-lang-weight-1'), '0.5');
    await tester.tap(_key('pref-save'));
    await tester.pump();
    await tester.pump();
    expect(
      probe.library.preferenceUpdateQueries.single.languages,
      '{"国语":1.5,"电子":0.5}',
    );
  });
}
