// ignore_for_file: deprecated_member_use — 与音乐模块页测试同款说明。
/// 添加歌曲页（L2）独立测试：搜索装配（keyword/page/pageSize）、多选、
/// 完成带回选中列表、错误重试与加载更多。
///
/// 全 fake（FakeSongSearch），无网络、无真实计时器。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/pages/music_playlist_add_songs_page.dart';

import 'fakes.dart';

Widget _app(Widget home) =>
    MaterialApp(debugShowCheckedModeBanner: false, home: home);

Future<void> _pumpPage(WidgetTester tester, FakeSongSearch search) async {
  await tester.pumpWidget(
    _app(MusicPlaylistAddSongsPage(searchSongs: search.call)),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('初始 idle 提示；空关键词点搜索不发起请求', (tester) async {
    final search = FakeSongSearch();
    await _pumpPage(tester, search);

    expect(find.text('输入关键词搜索要添加的歌曲'), findsOneWidget);
    expect(find.text('完成(0)'), findsOneWidget);
    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();

    expect(search.calls, isEmpty);
    expect(find.text('输入关键词搜索要添加的歌曲'), findsOneWidget);
  });

  testWidgets('搜索请求装配 keyword/page/pageSize 并渲染结果', (tester) async {
    final search = FakeSongSearch(
      pages: <List<MusicSong>>[
        <MusicSong>[testSong(id: '501', title: '歌曲一')],
        <MusicSong>[testSong(id: '502', title: '歌曲二')],
      ],
    );
    await _pumpPage(tester, search);

    await tester.enterText(find.byType(TextField), '周杰伦');
    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();

    expect(search.calls.single.keyword, '周杰伦');
    expect(search.calls.single.page, 1);
    expect(search.calls.single.pageSize, 30);
    expect(find.text('歌曲一'), findsOneWidget);
    expect(find.text('歌曲二'), findsNothing); // 第二页未加载
    expect(find.byType(CheckboxListTile), findsOneWidget);
  });

  testWidgets('多选两首后完成：按展示顺序 pop 选中列表', (tester) async {
    final search = FakeSongSearch(
      pages: <List<MusicSong>>[
        <MusicSong>[
          testSong(id: '501', title: '歌曲一'),
          testSong(id: '502', title: '歌曲二'),
        ],
      ],
    );
    List<MusicSong>? returned;
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  final result = await Navigator.of(context)
                      .push<List<MusicSong>>(
                        MaterialPageRoute<List<MusicSong>>(
                          builder: (_) => MusicPlaylistAddSongsPage(
                            searchSongs: search.call,
                          ),
                        ),
                      );
                  returned = result;
                },
                child: const Text('打开加歌页'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开加歌页'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '关键词');
    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();

    // 未选中时完成禁用。
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '完成(0)'))
          .onPressed,
      isNull,
    );

    await tester.tap(find.text('歌曲二'));
    await tester.pumpAndSettle();
    expect(find.text('完成(1)'), findsOneWidget);
    await tester.tap(find.text('歌曲一'));
    await tester.pumpAndSettle();
    expect(find.text('完成(2)'), findsOneWidget);

    // 再点一次取消勾选（checkbox 可反选）。
    await tester.tap(find.text('歌曲二'));
    await tester.pumpAndSettle();
    expect(find.text('完成(1)'), findsOneWidget);

    await tester.tap(find.text('完成(1)'));
    await tester.pumpAndSettle();

    expect(find.text('打开加歌页'), findsOneWidget); // 已回宿主页
    expect(returned, isNotNull);
    expect(returned!.single.id, '501');
  });

  testWidgets('搜索失败显示错误与重试；重试成功渲染', (tester) async {
    final search = FakeSongSearch(
      error: const KugouApiException('business', '搜索服务不可用'),
    );
    await _pumpPage(tester, search);

    await tester.enterText(find.byType(TextField), '关键词');
    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();
    expect(find.text('搜索服务不可用'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);

    search.error = null;
    search.pages = <List<MusicSong>>[
      <MusicSong>[testSong(id: '501', title: '歌曲一')],
    ];
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(find.text('歌曲一'), findsOneWidget);
    expect(search.calls.length, 2);
  });

  testWidgets('无结果空态', (tester) async {
    final search = FakeSongSearch(pages: <List<MusicSong>>[<MusicSong>[]]);
    await _pumpPage(tester, search);

    await tester.enterText(find.byType(TextField), '不存在的歌');
    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();

    expect(find.text('没有找到相关歌曲'), findsOneWidget);
  });

  testWidgets('加载更多：page 递增追加', (tester) async {
    final search = FakeSongSearch(
      pages: <List<MusicSong>>[
        <MusicSong>[testSong(id: '501', title: '歌曲一')],
        <MusicSong>[testSong(id: '502', title: '歌曲二')],
      ],
    );
    await _pumpPage(tester, search);

    await tester.enterText(find.byType(TextField), '关键词');
    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();
    expect(find.text('歌曲二'), findsNothing);

    await tester.tap(find.text('加载更多'));
    await tester.pumpAndSettle();

    expect(find.text('歌曲二'), findsOneWidget);
    expect(search.calls.length, 2);
    expect(search.calls.last.page, 2);
    expect(search.calls.last.keyword, '关键词'); // 加载更多沿用当前关键词
  });
}
