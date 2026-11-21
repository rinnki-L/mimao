// ignore_for_file: deprecated_member_use — 与音乐模块页测试同款说明。
/// 歌单导入（L2）测试：链接导入成功/失败/busy 防重/取消，与列表页向
/// 详情页透传写端点所需的版本事实。
///
/// 全 fake，无网络；SnackBar 触发过的用例末尾越过自动关闭计时器。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/import_playlist.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/playlist_models.dart';
import 'package:mimao/music/models/playlist_write_models.dart';
import 'package:mimao/music/models/user_library_models.dart';
import 'package:mimao/music/pages/music_playlist_list_page.dart';

import 'fakes.dart';

Widget _app(Widget home) =>
    MaterialApp(debugShowCheckedModeBanner: false, home: home);

Future<void> _drainSnackBar(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

void main() {
  late FakeUserLibraryApi library;
  late FakePlaylistReadApi read;
  late FakePlaylistWriteApi write;
  late FakePlayerUi player;

  setUp(() {
    library = FakeUserLibraryApi();
    read = FakePlaylistReadApi();
    write = FakePlaylistWriteApi();
    player = FakePlayerUi();
  });

  Future<void> pumpList(WidgetTester tester) async {
    await tester.pumpWidget(
      _app(
        MusicPlaylistListPage(
          library: library,
          read: read,
          player: player,
          write: write,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 打开导入对话框并输入链接（不点导入）。
  Future<void> openDialogAndType(WidgetTester tester, String url) async {
    await tester.tap(find.byTooltip('导入歌单'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), url);
    // 输入后要过一帧：导入按钮的可用态由 ValueListenableBuilder 驱动。
    await tester.pumpAndSettle();
  }

  testWidgets('导入歌单：链接进入 MusicImportLinkQuery，创建成功后提示并刷新列表', (tester) async {
    library.items.add(testPlaylist(cloudListId: 101, title: '旧歌单'));
    await pumpList(tester);
    expect(library.queries.length, 1);

    await openDialogAndType(tester, 'https://t.kugou.com/abc123');
    await tester.tap(find.text('导入'));
    await tester.pumpAndSettle();

    // 查询对象按动作分支装配：链接导入（不是截图/状态查询）。
    final query = read.importQueries.single;
    expect(query, isA<MusicImportLinkQuery>());
    expect((query as MusicImportLinkQuery).url, 'https://t.kugou.com/abc123');
    // 成功提示 + 重新拉取列表（page 1）。
    expect(find.text('导入任务已创建，处理完成后刷新列表查看'), findsOneWidget);
    expect(library.queries.length, 2);
    expect(library.queries.last.page, 1);
    await _drainSnackBar(tester);
  });

  testWidgets('导入失败：SnackBar 提示错误，列表保持不清空、不刷新', (tester) async {
    library.items.add(testPlaylist(cloudListId: 101, title: '旧歌单'));
    read.importError = const KugouApiException('business', '导入任务创建失败');
    await pumpList(tester);

    await openDialogAndType(tester, 'https://t.kugou.com/abc123');
    await tester.tap(find.text('导入'));
    await tester.pumpAndSettle();

    expect(find.text('导入失败：导入任务创建失败'), findsOneWidget);
    expect(find.text('旧歌单'), findsOneWidget); // 列表未被清空
    expect(library.queries.length, 1); // 没有触发刷新
    await _drainSnackBar(tester);
  });

  testWidgets('导入遇到认证错误：提示登录', (tester) async {
    read.importError = const KugouApiException('authentication', '账号认证无效');
    await pumpList(tester);

    await openDialogAndType(tester, 'https://t.kugou.com/abc123');
    await tester.tap(find.text('导入'));
    await tester.pumpAndSettle();

    expect(find.text('请先登录酷狗账号'), findsOneWidget);
    await _drainSnackBar(tester);
  });

  testWidgets('空链接时导入按钮禁用；取消对话框不调用端点', (tester) async {
    await pumpList(tester);

    await tester.tap(find.byTooltip('导入歌单'));
    await tester.pumpAndSettle();
    final button = tester.widget<FilledButton>(
      find.ancestor(of: find.text('导入'), matching: find.byType(FilledButton)),
    );
    expect(button.onPressed, isNull); // 空输入禁用

    await tester.enterText(find.byType(TextField), 'https://t.kugou.com/x');
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(read.importQueries, isEmpty);
    // 重新打开对话框确认输入保留与否无所谓——关键是没有发出请求。
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('导入 busy 防重：进行中导入按钮禁用，重复点击只发一次请求', (tester) async {
    final hold = Completer<MusicImportOutcome>();
    read.onImport = (_) => hold.future;
    await pumpList(tester);

    await openDialogAndType(tester, 'https://t.kugou.com/abc123');
    await tester.tap(find.text('导入'));
    // 忙指示是持续动画（CircularProgressIndicator），不能 pumpAndSettle；
    // 固定推两帧：第一帧处理 pop，第二帧越过对话框出场动画、忙态生效。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(read.importQueries.length, 1);

    // 进行中：AppBar 导入按钮置灰，点不出第二个对话框。
    expect(find.byType(AlertDialog), findsNothing); // 对话框已收起
    final iconButton = tester.widget<IconButton>(
      find.ancestor(
        of: find.byTooltip('导入歌单'),
        matching: find.byType(IconButton),
      ),
    );
    expect(iconButton.onPressed, isNull);
    await tester.tap(find.byTooltip('导入歌单'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(TextField), findsNothing); // 没有弹出输入框
    expect(read.importQueries.length, 1); // 没有重复提交

    // 完成后提示成功并刷新。
    hold.complete(
      const MusicImportCreatedOutcome(
        MusicImportTask(taskId: 5, title: '', message: ''),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('导入任务已创建，处理完成后刷新列表查看'), findsOneWidget);
    await _drainSnackBar(tester);
  });

  testWidgets('列表页透传版本/归属/简介/标签：详情页编辑入口可用且 kind 为 collected', (tester) async {
    library.items.add(
      testPlaylist(
        cloudListId: 101,
        title: '收藏歌单',
        kind: MusicCloudPlaylistKind.collected,
        revision: 5,
        sortIndex: 3,
        descriptionPresent: true,
        description: '远端简介',
        tagsPresent: true,
        tags: '流行',
      ),
    );
    read.trackAllNewPages = <List<MusicPlaylistTrack>>[
      <MusicPlaylistTrack>[testTrack(id: '1', title: '云单曲目')],
    ];

    await tester.pumpWidget(
      _app(
        MusicPlaylistListPage(
          library: library,
          read: read,
          player: player,
          write: write,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('收藏歌单'));
    await tester.pumpAndSettle();

    // 版本事实齐备 → 编辑信息/更换封面可点（不是置灰说明态）。
    await tester.tap(find.byTooltip('歌单管理'));
    await tester.pumpAndSettle();
    expect(find.text('缺少云端版本信息'), findsNothing);
    final infoItem = tester.widget<PopupMenuItem<String>>(
      find.ancestor(
        of: find.text('编辑信息'),
        matching: find.byType(PopupMenuItem<String>),
      ),
    );
    expect(infoItem.enabled, isTrue);
    await tester.tap(find.text('编辑信息'));
    await tester.pumpAndSettle();

    // sheet 预填了透传的标题/简介/标签；kind 是 collected（收藏歌单）。
    expect(find.text('远端简介'), findsWidgets);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final query = write.updateQueries.single;
    expect(query.cloudListId, 101);
    expect(query.totalRevision, 5); // 列表条目的 revision（云端没给时兜底）
    expect(query.sortIndex, 3);
    expect(query.kind, MusicPlaylistKind.collected);
    expect(query.description, '远端简介');
    expect(query.tags, '流行');
    await _drainSnackBar(tester);
  });
}
