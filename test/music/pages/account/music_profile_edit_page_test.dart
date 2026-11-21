// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与 music/pages 其它文件同款说明。
/// 资料编辑页测试：自装载/预填、只提交改动字段、就地校验（空昵称/签名
/// 超长/生日格式）、清空语义、成功 pop(true) 与失败页内提示。
/// 全部走 fake（见 fakes.dart），不联网、无真实计时器。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/user_models.dart';
import 'package:mimao/music/pages/music_profile_edit_page.dart';

import 'fakes.dart';

/// 探针宿主：从首页 push 编辑页，记录 pop 回执。
class _Probe {
  final FakeUserProfileApi profile = FakeUserProfileApi()
    ..detail = fakeProfile();
  final List<bool?> popped = <bool?>[];

  Widget build({MusicUserProfile? initial}) => MaterialApp(
    home: Builder(
      builder: (BuildContext context) => Center(
        child: TextButton(
          onPressed: () {
            Navigator.of(context)
                .push<bool>(
                  MaterialPageRoute<bool>(
                    builder: (_) => MusicProfileEditPage(
                      profile: profile,
                      initial: initial,
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

/// push 编辑页并等装载完成（视口加高，保证省市/保存键都在可视区内）。
Future<_Probe> _open(
  WidgetTester tester,
  _Probe probe, {
  MusicUserProfile? initial,
}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(probe.build(initial: initial));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return probe;
}

Finder _field(String key) => find.byKey(ValueKey<String>(key));

void main() {
  testWidgets('initial 传入时直接预填，不重复请求 userDetail', (tester) async {
    final probe = _Probe();
    final MusicUserProfile initial = fakeProfile(
      nickname: '预填昵称',
      gender: 1,
      biography: '旧签名',
      birthday: '1998-01-01',
      province: '广东',
      city: '深圳',
    );
    await _open(tester, probe, initial: initial);

    expect(probe.profile.detailCalls, 0);
    expect(find.text('预填昵称'), findsOneWidget);
    expect(find.text('旧签名'), findsOneWidget);
    expect(find.text('1998-01-01'), findsOneWidget);
    expect(find.text('广东'), findsOneWidget);
    expect(find.text('深圳'), findsOneWidget);
    // 性别初始为男（1）。
    final SegmentedButton<int> gender = tester.widget<SegmentedButton<int>>(
      find.descendant(
        of: _field('profile-gender'),
        matching: find.byType(SegmentedButton<int>),
      ),
    );
    expect(gender.selected, <int>{1});
  });

  testWidgets('initial 缺省时自装载 userDetail 并预填', (tester) async {
    final probe = _Probe();
    await _open(tester, probe);

    expect(probe.profile.detailCalls, 1);
    expect(find.text('示例昵称'), findsOneWidget);
    expect(find.text('一句话简介'), findsOneWidget);
  });

  testWidgets('只提交改动字段：改昵称其余不下发，成功 pop(true)', (tester) async {
    final probe = _Probe();
    await _open(
      tester,
      probe,
      initial: fakeProfile(
        gender: 1,
        biography: '旧签名',
        birthday: '1998-01-01',
        province: '广东',
        city: '深圳',
      ),
    );

    await tester.enterText(_field('profile-nickname'), '新昵称');
    await tester.tap(_field('profile-save'));
    await tester.pump();
    await tester.pump();

    expect(probe.profile.updateQueries, hasLength(1));
    final query = probe.profile.updateQueries.single;
    expect(query.nickname, '新昵称');
    expect(query.gender, isNull);
    expect(query.birthday, isNull);
    expect(query.signature, isNull);
    expect(query.province, isNull);
    expect(query.city, isNull);
    expect(probe.popped, <bool?>[true]);
  });

  testWidgets('全字段改动一次提交：昵称/性别/生日/签名/省市', (tester) async {
    final probe = _Probe();
    await _open(tester, probe, initial: fakeProfile());

    await tester.enterText(_field('profile-nickname'), '新昵称');
    await tester.tap(find.text('男'));
    await tester.enterText(_field('profile-birthday'), '1998-02-03');
    await tester.enterText(_field('profile-signature'), '新签名');
    await tester.enterText(_field('profile-province'), '广东');
    await tester.enterText(_field('profile-city'), '深圳');
    await tester.tap(_field('profile-save'));
    await tester.pump();
    await tester.pump();

    final query = probe.profile.updateQueries.single;
    expect(query.nickname, '新昵称');
    expect(query.gender, 1);
    expect(query.birthday, '1998-02-03');
    expect(query.signature, '新签名');
    expect(query.province, '广东');
    expect(query.city, '深圳');
    expect(probe.popped, <bool?>[true]);
  });

  testWidgets('清空签名/生日按空串提交（清除语义），省市清空不下发', (tester) async {
    final probe = _Probe();
    await _open(
      tester,
      probe,
      initial: fakeProfile(
        biography: '旧签名',
        birthday: '1998-01-01',
        province: '广东',
        city: '深圳',
      ),
    );

    await tester.enterText(_field('profile-signature'), '');
    await tester.enterText(_field('profile-birthday'), '');
    await tester.enterText(_field('profile-province'), '');
    await tester.tap(_field('profile-save'));
    await tester.pump();
    await tester.pump();

    final query = probe.profile.updateQueries.single;
    expect(query.signature, '');
    expect(query.birthday, '');
    expect(query.province, isNull); // 端点不允许空省市：视为放弃修改
    expect(query.city, isNull);
    expect(probe.popped, <bool?>[true]);
  });

  testWidgets('空昵称就地校验：不发起请求，修正后可保存', (tester) async {
    final probe = _Probe();
    await _open(tester, probe, initial: fakeProfile());

    await tester.enterText(_field('profile-nickname'), '   ');
    await tester.tap(_field('profile-save'));
    await tester.pump();

    expect(find.text('昵称不能为空'), findsOneWidget);
    expect(probe.profile.updateQueries, isEmpty);

    await tester.enterText(_field('profile-nickname'), '修正昵称');
    await tester.tap(_field('profile-save'));
    await tester.pump();
    await tester.pump();
    expect(probe.profile.updateQueries.single.nickname, '修正昵称');
  });

  testWidgets('签名超长就地校验（按 UTF-16 码元数）', (tester) async {
    final probe = _Probe();
    await _open(tester, probe, initial: fakeProfile());

    await tester.enterText(
      _field('profile-signature'),
      '签' * (kSignatureMaxLength + 1),
    );
    await tester.tap(_field('profile-save'));
    await tester.pump();

    expect(find.text('个性签名最多 120 个字符'), findsOneWidget);
    expect(probe.profile.updateQueries, isEmpty);
  });

  testWidgets('生日格式就地校验：非 yyyy-MM-dd 不下发', (tester) async {
    final probe = _Probe();
    await _open(tester, probe, initial: fakeProfile());

    await tester.enterText(_field('profile-birthday'), '19980102');
    await tester.tap(_field('profile-save'));
    await tester.pump();

    expect(find.text('生日格式应为 yyyy-MM-dd'), findsOneWidget);
    expect(probe.profile.updateQueries, isEmpty);
  });

  testWidgets('无改动提交提示且不发请求', (tester) async {
    final probe = _Probe();
    await _open(tester, probe, initial: fakeProfile());

    await tester.tap(_field('profile-save'));
    await tester.pump();

    expect(find.text('资料没有变化'), findsOneWidget);
    expect(probe.profile.updateQueries, isEmpty);
    expect(probe.popped, isEmpty);
  });

  testWidgets('保存失败页内提示、不退出；修正后重试成功 pop(true)', (tester) async {
    final probe = _Probe();
    probe.profile.updateError = const KugouApiException('business', '服务繁忙');
    await _open(tester, probe, initial: fakeProfile());

    await tester.enterText(_field('profile-nickname'), '新昵称');
    await tester.tap(_field('profile-save'));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('保存失败'), findsOneWidget);
    expect(find.text('新昵称'), findsOneWidget); // 仍在编辑页，输入未丢
    expect(probe.popped, isEmpty);

    probe.profile
      ..updateError = null
      ..updateResult = true;
    await tester.tap(_field('profile-save'));
    await tester.pump();
    await tester.pump();
    expect(probe.profile.updateQueries, hasLength(2));
    expect(probe.popped, <bool?>[true]);
  });

  testWidgets('updated=false 按失败处理（页内提示、不退出）', (tester) async {
    final probe = _Probe();
    probe.profile.updateResult = false;
    await _open(tester, probe, initial: fakeProfile());

    await tester.enterText(_field('profile-nickname'), '新昵称');
    await tester.tap(_field('profile-save'));
    await tester.pump();
    await tester.pump();

    expect(find.text('保存失败，请稍后重试'), findsOneWidget);
    expect(probe.popped, isEmpty);
  });

  testWidgets('装载失败显示错误与重试', (tester) async {
    final probe = _Probe()..profile.detailError = authenticationError();
    await _open(tester, probe);

    expect(find.textContaining('请先登录'), findsOneWidget);

    probe.profile
      ..detailError = null
      ..detail = fakeProfile();
    await tester.tap(find.text('重试'));
    await tester.pump();
    await tester.pump();
    expect(find.text('示例昵称'), findsOneWidget);
  });
}
