// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与 music/pages 其它文件同款说明。
/// 账号中心 L3 新增能力测试：写入口的登录态门槛、编辑资料/偏好页导航、
/// 头像两步上传（顺序/fileName/localDate/reviewPending）与前置拦截。
/// 全部走 fake（见 fakes.dart），不联网、无真实计时器。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/models/user_library_models.dart';
import 'package:mimao/music/pages/music_account_center_page.dart';
import 'package:mimao/music/pages/music_profile_image_picker.dart';

import 'fakes.dart';

/// 测试夹具：fake 接口 + 可选注入的选图替身。
class _Harness {
  final FakeUserProfileApi profile = FakeUserProfileApi();
  final FakeUserLibraryApi library = FakeUserLibraryApi();
  final FakePlayerUi player = FakePlayerUi();

  /// null = 不注入（生产会惰性构造 file_picker 实现——测试里绝不触发）。
  FakeProfileImagePicker? picker;

  _Harness() {
    profile
      ..detail = fakeProfile()
      ..tags = fakeTags()
      ..vip = fakeVip()
      ..grade = fakeGrade();
    library
      ..playlists = fakePlaylists(items: <MusicUserPlaylist>[fakePlaylist()])
      ..historyPages.add(fakeHistoryPage())
      ..purchasedAlbumPages.add(
        MusicPage<MusicPurchasedAlbum>(
          page: 1,
          pageSize: 20,
          total: 0,
          items: const <MusicPurchasedAlbum>[],
        ),
      )
      ..purchasedSongPages.add(
        MusicPage<MusicPurchasedSong>(
          page: 1,
          pageSize: 20,
          total: 0,
          items: const <MusicPurchasedSong>[],
        ),
      )
      ..preference = fakePreferences();
  }

  Widget build() => MaterialApp(
    home: MusicAccountCenterPage(
      profile: profile,
      library: library,
      player: player,
      imagePicker: picker,
    ),
  );
}

Future<_Harness> _pump(WidgetTester tester, _Harness harness) async {
  // 视口加高：push 出的编辑/偏好页长表单（保存键）也落在可视区内。
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(harness.build());
  await tester.pump();
  return harness;
}

/// 排干 SnackBar：入场动画走完后自动消失 Timer 才起算，因此先 settle、
/// 再推进 4 秒触发消失、最后收尾退场——避免残留 pending timer，
/// 也保证队列里的下一条 SnackBar 能立即展示。
Future<void> _drainSnack(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.pump(const Duration(seconds: 4));
  await tester.pumpAndSettle();
}

Finder _key(String name) => find.byKey(ValueKey<String>(name));

void main() {
  testWidgets('写入口仅在登录态（资料装载成功）出现', (tester) async {
    await _pump(tester, _Harness());

    expect(_key('account-edit-profile'), findsOneWidget);
    expect(_key('account-change-avatar'), findsOneWidget);
    expect(_key('account-preference'), findsOneWidget);

    final anon = _Harness()..profile.detailError = authenticationError();
    await _pump(tester, anon);
    expect(_key('account-edit-profile'), findsNothing);
    expect(_key('account-change-avatar'), findsNothing);
    expect(_key('account-preference'), findsNothing);
  });

  testWidgets('编辑资料入口 push 编辑页；保存成功 pop(true) 后资料头重拉', (tester) async {
    final h = await _pump(tester, _Harness());
    expect(h.profile.detailCalls, 1);

    await tester.tap(_key('account-edit-profile'));
    await tester.pumpAndSettle();
    expect(_key('profile-save'), findsOneWidget); // 已在编辑页

    await tester.enterText(_key('profile-nickname'), '新昵称');
    await tester.tap(_key('profile-save'));
    await tester.pumpAndSettle();

    expect(h.profile.updateQueries.single.nickname, '新昵称');
    // pop(true) → 账号中心重拉 userDetail。
    expect(h.profile.detailCalls, 2);
  });

  testWidgets('编辑页直接返回（未保存）不触发刷新', (tester) async {
    final h = await _pump(tester, _Harness());

    await tester.tap(_key('account-edit-profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(h.profile.updateQueries, isEmpty);
    expect(h.profile.detailCalls, 1);
  });

  testWidgets('音乐偏好入口 push 偏好页并装载', (tester) async {
    final h = await _pump(tester, _Harness());

    await tester.tap(_key('account-preference'));
    await tester.pumpAndSettle();

    expect(_key('pref-save'), findsOneWidget);
    expect(h.library.preferenceCalls, 1);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
  });

  testWidgets('头像上传两步：顺序、base64/localDate、fileName 透传、刷新', (tester) async {
    final Uint8List bytes = fakePngBytes();
    final h = _Harness()..picker = FakeProfileImagePicker(bytes);
    await _pump(tester, h);
    expect(h.profile.detailCalls, 1);

    await tester.tap(_key('account-change-avatar'));
    await tester.pump();
    await tester.pump();

    expect(h.picker!.calls, 1);
    // 两步顺序：先上传图片拿引用，再提交引用。
    expect(h.profile.avatarCallOrder, <String>['upload', 'submit']);
    final upload = h.profile.avatarUploads.single;
    expect(upload.imageBase64, base64Encode(bytes));
    expect(upload.localDate, matches(RegExp(r'^\d{8}$'))); // yyyyMMdd 本地日期
    // 第二步原样透传上传返回的 fileName。
    expect(h.profile.updateAvatarFileNames, <String>['abc123.png']);
    expect(find.text('头像已更新'), findsOneWidget);
    expect(h.profile.detailCalls, 2); // 资料头已刷新
    await _drainSnack(tester);
  });

  testWidgets('点头像本体同样触发更换头像流程', (tester) async {
    final h = _Harness()..picker = FakeProfileImagePicker(fakePngBytes());
    await _pump(tester, h);

    await tester.tap(_key('account-avatar'));
    await tester.pump();
    await tester.pump();

    expect(h.picker!.calls, 1);
    expect(h.profile.updateAvatarFileNames, <String>['abc123.png']);
    await _drainSnack(tester);
  });

  testWidgets('reviewPending（34236）提示「头像审核中」，仍刷新资料', (tester) async {
    final h = _Harness()..picker = FakeProfileImagePicker(fakePngBytes());
    h.profile.avatarReviewPending = true;
    await _pump(tester, h);

    await tester.tap(_key('account-change-avatar'));
    await tester.pump();
    await tester.pump();

    expect(h.profile.updateAvatarFileNames, hasLength(1));
    expect(find.text('头像审核中'), findsOneWidget);
    expect(h.profile.detailCalls, 2);
    await _drainSnack(tester);
  });

  testWidgets('非图片字节在本地拦截，不发起上传', (tester) async {
    final h = _Harness()
      ..picker = FakeProfileImagePicker(Uint8List.fromList(<int>[1, 2, 3]));
    await _pump(tester, h);

    await tester.tap(_key('account-change-avatar'));
    await tester.pump();
    await tester.pump();

    expect(find.text('请选择 JPEG、PNG 或 GIF 图片'), findsOneWidget);
    expect(h.profile.avatarUploads, isEmpty);
    expect(h.profile.updateAvatarFileNames, isEmpty);
    expect(h.profile.detailCalls, 1);
    await _drainSnack(tester);
  });

  testWidgets('超大文件在本地拦截（8 MB 上限）', (tester) async {
    // 带 PNG 魔数的 8MB+1 字节：命中尺寸校验（先于格式校验）。
    final Uint8List oversized = Uint8List(kAvatarImageByteLimit + 1)
      ..setRange(0, 8, <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
    final h = _Harness()..picker = FakeProfileImagePicker(oversized);
    await _pump(tester, h);

    await tester.tap(_key('account-change-avatar'));
    await tester.pump();
    await tester.pump();

    expect(find.text('头像图片不能超过 8 MB'), findsOneWidget);
    expect(h.profile.avatarUploads, isEmpty);
    expect(h.profile.updateAvatarFileNames, isEmpty);
    await _drainSnack(tester);
  });

  testWidgets('选图取消（null）静默返回，无上传无报错', (tester) async {
    final h = _Harness()..picker = FakeProfileImagePicker(null);
    await _pump(tester, h);

    await tester.tap(_key('account-change-avatar'));
    await tester.pump();
    await tester.pump();

    expect(h.picker!.calls, 1);
    expect(h.profile.avatarUploads, isEmpty);
    expect(h.profile.updateAvatarFileNames, isEmpty);
    expect(find.text('头像已更新'), findsNothing);
    expect(find.textContaining('头像更新失败'), findsNothing);
    expect(h.profile.detailCalls, 1);
  });

  testWidgets('上传失败提示且不执行第二步；失败后可重试', (tester) async {
    final h = _Harness()..picker = FakeProfileImagePicker(fakePngBytes());
    h.profile.avatarUploadError = const KugouApiException('business', '服务繁忙');
    await _pump(tester, h);

    await tester.tap(_key('account-change-avatar'));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('头像更新失败'), findsOneWidget);
    expect(h.profile.updateAvatarFileNames, isEmpty);
    expect(h.profile.detailCalls, 1);
    await _drainSnack(tester);

    h.profile.avatarUploadError = null;
    await tester.tap(_key('account-change-avatar'));
    await tester.pump();
    await tester.pump();
    expect(h.profile.updateAvatarFileNames, <String>['abc123.png']);
    expect(find.text('头像已更新'), findsOneWidget);
    await _drainSnack(tester);
  });

  testWidgets('既有分区仍正常渲染（回归护栏）', (tester) async {
    await _pump(tester, _Harness());

    expect(find.text('示例昵称'), findsOneWidget);
    expect(find.text('歌单一'), findsOneWidget);
    expect(find.text('编辑资料'), findsOneWidget);
    expect(find.text('音乐偏好'), findsOneWidget);
  });
}
