// ignore_for_file: deprecated_member_use — 与音乐模块页测试同款说明。
/// 歌单详情页写能力（L2）测试：编辑信息 / 更换封面 / 曲目管理（多选删除
/// + 上移下移排序）/ 添加歌曲，与各写入口的可见性、busy 防重。
///
/// 全 fake：图片选择注入 fake picker 返回内存 PNG 字节；搜索注入 fake；
/// 无网络、无真实文件。SnackBar 触发过的用例末尾越过自动关闭计时器。
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/models/playlist_models.dart';
import 'package:mimao/music/models/playlist_write_models.dart';
import 'package:mimao/music/pages/music_playlist_detail_page.dart';

import 'fakes.dart';

Widget _app(Widget home) =>
    MaterialApp(debugShowCheckedModeBanner: false, home: home);

Future<void> _drainSnackBar(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

Future<void> _pumpDetail(
  WidgetTester tester, {
  required FakePlaylistReadApi read,
  required FakePlayerUi player,
  FakePlaylistWriteApi? write,
  FakePlaylistImagePicker? imagePicker,
  FakeSongSearch? search,
  Key? key,
  int? cloudListId = 77,
  String globalId = '',
  String? title = '云单',
  int? revision,
  int? sortIndex,
  MusicPlaylistKind? kind,
  String? description,
  String? tags,
  bool? editable = true,
}) async {
  await tester.pumpWidget(
    _app(
      MusicPlaylistDetailPage(
        // 同一测试里连续换配置重灌时必须换 key：同类型 Widget 复用 State
        // 会跳过 initState，新配置不会触发加载。
        key: key,
        read: read,
        player: player,
        globalId: globalId,
        cloudListId: cloudListId,
        title: title,
        write: write,
        editable: editable,
        revision: revision,
        sortIndex: sortIndex,
        kind: kind,
        description: description,
        tags: tags,
        searchSongs: search?.call,
        imagePicker: imagePicker,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 打开 AppBar「歌单管理」菜单。
Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byTooltip('歌单管理'));
  await tester.pumpAndSettle();
}

void main() {
  late FakePlaylistReadApi read;
  late FakePlaylistWriteApi write;
  late FakePlayerUi player;

  setUp(() {
    read = FakePlaylistReadApi();
    write = FakePlaylistWriteApi();
    player = FakePlayerUi();
  });

  // ── 编辑信息 ────────────────────────────────────────────────────────────

  testWidgets('编辑信息：sheet 三字段提交 playlistUpdate，版本/归属正确，头部即时更新', (tester) async {
    read.trackAllNewPages = <List<MusicPlaylistTrack>>[
      <MusicPlaylistTrack>[testTrack(id: '1', title: '云单曲目')],
    ];

    await _pumpDetail(
      tester,
      read: read,
      player: player,
      write: write,
      revision: 5,
      sortIndex: 2,
      description: '旧简介',
      tags: '旧标签',
    );
    await _openMenu(tester);
    await tester.tap(find.text('编辑信息'));
    await tester.pumpAndSettle();

    // sheet 预填旧值；标题(0)/简介(1)/标签(2) 顺序固定。
    await tester.enterText(find.byType(TextField).at(0), '新标题');
    await tester.enterText(find.byType(TextField).at(1), '新简介');
    await tester.enterText(find.byType(TextField).at(2), '流行,摇滚');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final query = write.updateQueries.single;
    expect(query.cloudListId, 77);
    expect(query.totalRevision, 5); // 构造传入的 revision（云端没给）
    expect(query.sortIndex, 2);
    expect(query.kind, MusicPlaylistKind.owned); // 缺省 owned
    expect(query.title, '新标题');
    expect(query.description, '新简介');
    expect(query.tags, '流行,摇滚');
    // 头部即时反映新标题/简介（不等远端刷新）。
    expect(find.text('新标题'), findsWidgets);
    expect(find.text('新简介'), findsOneWidget);
    expect(find.text('歌单信息已更新'), findsOneWidget);
    // 写成功后轻量刷新曲目（不清空）。
    expect(read.trackAllNewQueries.length, 2);
    expect(find.text('云单曲目'), findsOneWidget);
    await _drainSnackBar(tester);
  });

  testWidgets('编辑信息：优先用 playlistTrackAllNew 返回的最新 revision', (tester) async {
    read.trackAllNewRevision = 9;
    read.trackAllNewPages = <List<MusicPlaylistTrack>>[
      <MusicPlaylistTrack>[testTrack(id: '1', title: '云单曲目')],
    ];

    await _pumpDetail(
      tester,
      read: read,
      player: player,
      write: write,
      revision: 5,
      sortIndex: 2,
    );
    await _openMenu(tester);
    await tester.tap(find.text('编辑信息'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '新标题');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(write.updateQueries.single.totalRevision, 9);
    await _drainSnackBar(tester);
  });

  testWidgets('编辑信息失败：SnackBar，头部标题不变、列表不清空', (tester) async {
    read.trackAllNewPages = <List<MusicPlaylistTrack>>[
      <MusicPlaylistTrack>[testTrack(id: '1', title: '云单曲目')],
    ];
    write.updateError = const KugouApiException('business', '版本已过期');

    await _pumpDetail(
      tester,
      read: read,
      player: player,
      write: write,
      revision: 5,
      sortIndex: 2,
    );
    await _openMenu(tester);
    await tester.tap(find.text('编辑信息'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '新标题');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('保存失败：版本已过期'), findsOneWidget);
    expect(find.text('云单'), findsWidgets); // 标题未被覆盖
    expect(find.text('云单曲目'), findsOneWidget); // 列表仍在
    await _drainSnackBar(tester);
  });

  testWidgets('缺少 revision/sortIndex：编辑/封面入口置灰并说明，不发出写请求', (tester) async {
    read.trackAllNewPages = <List<MusicPlaylistTrack>>[
      <MusicPlaylistTrack>[testTrack(id: '1', title: '云单曲目')],
    ];

    await _pumpDetail(tester, read: read, player: player, write: write);
    await _openMenu(tester);

    expect(find.text('缺少云端版本信息'), findsNWidgets(2));
    final infoItem = tester.widget<PopupMenuItem<String>>(
      find.ancestor(
        of: find.text('编辑信息'),
        matching: find.byType(PopupMenuItem<String>),
      ),
    );
    expect(infoItem.enabled, isFalse);
    // searchSongs 未接线 → 加歌入口隐藏；曲目管理仍可用。
    expect(find.text('添加歌曲'), findsNothing);
    expect(find.text('管理曲目'), findsOneWidget);

    // 收起菜单（点空白处），确认没有误发请求。
    await tester.tapAt(const Offset(20, 400));
    await tester.pumpAndSettle();
    expect(write.updateQueries, isEmpty);
    expect(write.picQueries, isEmpty);
  });

  // ── 更换封面 ────────────────────────────────────────────────────────────

  testWidgets(
    '更换封面：PNG 字节 → playlistPicUpload(localDate yyyyMMdd) → coverReference 更新',
    (tester) async {
      final png = fakePlaylistPngBytes();
      final picker = FakePlaylistImagePicker(bytes: png);
      read.trackAllNewRevision = 7;
      read.trackAllNewPages = <List<MusicPlaylistTrack>>[
        <MusicPlaylistTrack>[testTrack(id: '1', title: '云单曲目')],
      ];

      await _pumpDetail(
        tester,
        read: read,
        player: player,
        write: write,
        imagePicker: picker,
        sortIndex: 2,
        description: '旧简介',
        tags: '旧标签',
      );
      await _openMenu(tester);
      await tester.tap(find.text('更换封面'));
      await tester.pumpAndSettle();

      expect(picker.calls, 1);
      // 上传请求带原始 PNG 字节 + 本地日历日（yyyyMMdd）。
      expect(write.picQueries.single.png, orderedEquals(png));
      expect(write.picQueries.single.localDate, matches(RegExp(r'^\d{8}$')));
      // 拿 fileName 拼 custom/<fileName> 提交 playlistUpdate，保留简介/标签。
      final query = write.updateQueries.single;
      expect(query.cloudListId, 77);
      expect(query.totalRevision, 7); // 云端返回的最新 revision
      expect(query.sortIndex, 2);
      expect(query.coverReference, 'custom/cover-test.png');
      expect(query.title, '云单'); // 已知标题原样保留
      expect(query.description, '旧简介');
      expect(query.tags, '旧标签');
      expect(find.text('封面已更新'), findsOneWidget);
      await _drainSnackBar(tester);
    },
  );

  testWidgets('非 PNG 字节：直接拒绝，不发起上传', (tester) async {
    final picker = FakePlaylistImagePicker(
      bytes: Uint8List.fromList(List<int>.filled(64, 0x41)),
    );

    await _pumpDetail(
      tester,
      read: read,
      player: player,
      write: write,
      imagePicker: picker,
      revision: 5,
      sortIndex: 2,
    );
    await _openMenu(tester);
    await tester.tap(find.text('更换封面'));
    await tester.pumpAndSettle();

    expect(picker.calls, 1);
    expect(find.text('请选择有效的 PNG 封面'), findsOneWidget);
    expect(write.picQueries, isEmpty);
    expect(write.updateQueries, isEmpty);
    await _drainSnackBar(tester);
  });

  testWidgets('取消选择：picker 返回 null，不发起任何请求', (tester) async {
    final picker = FakePlaylistImagePicker(); // bytes == null → 取消

    await _pumpDetail(
      tester,
      read: read,
      player: player,
      write: write,
      imagePicker: picker,
      revision: 5,
      sortIndex: 2,
    );
    await _openMenu(tester);
    await tester.tap(find.text('更换封面'));
    await tester.pumpAndSettle();

    expect(picker.calls, 1);
    expect(write.picQueries, isEmpty);
    expect(write.updateQueries, isEmpty);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('封面上传失败：SnackBar 提示，不清列表', (tester) async {
    final picker = FakePlaylistImagePicker(bytes: fakePlaylistPngBytes());
    write.picUploadError = const KugouApiException('business', '图片服务不可用');

    await _pumpDetail(
      tester,
      read: read,
      player: player,
      write: write,
      imagePicker: picker,
      revision: 5,
      sortIndex: 2,
    );
    await _openMenu(tester);
    await tester.tap(find.text('更换封面'));
    await tester.pumpAndSettle();

    expect(find.text('封面上传失败：图片服务不可用'), findsOneWidget);
    expect(write.updateQueries, isEmpty); // 上传失败不再提交 playlistUpdate
    expect(find.text('云单曲目'), findsNothing); // 本用例没灌曲目数据
    await _drainSnackBar(tester);
  });

  // ── 曲目管理：多选删除 ──────────────────────────────────────────────────

  testWidgets('多选删除：fileIds 按勾选提交；fileId 为空的行不可选', (tester) async {
    read.trackAllNewPages = <List<MusicPlaylistTrack>>[
      <MusicPlaylistTrack>[
        testTrack(id: '1', title: '曲目一', fileId: 11),
        testTrack(id: '2', title: '曲目二', fileId: 12),
        testTrack(id: '3', title: '无文件行', fileId: null),
      ],
    ];

    await _pumpDetail(tester, read: read, player: player, write: write);
    await _openMenu(tester);
    await tester.tap(find.text('管理曲目'));
    await tester.pumpAndSettle();

    // 进入选择模式：三行各一个 Checkbox；无 fileId 行禁用。
    final checkboxes = tester.widgetList<Checkbox>(find.byType(Checkbox));
    expect(checkboxes.length, 3);
    expect(checkboxes.elementAt(2).onChanged, isNull);

    await tester.tap(find.text('曲目一'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('曲目二'));
    await tester.pumpAndSettle();
    expect(find.text('已选 2 首'), findsOneWidget);

    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    // 二次确认前不调用写端点。
    expect(write.tracksDelQueries, isEmpty);
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(write.tracksDelQueries.single.cloudListId, 77);
    expect(write.tracksDelQueries.single.fileIds, <int>[11, 12]);
    expect(find.text('已删除 2 首歌曲'), findsOneWidget);
    // 删除后清空选择但留在管理模式。
    expect(find.text('已选 0 首'), findsOneWidget);
    await _drainSnackBar(tester);
  });

  testWidgets('删除歌曲失败：SnackBar，列表保留', (tester) async {
    read.trackAllNewPages = <List<MusicPlaylistTrack>>[
      <MusicPlaylistTrack>[testTrack(id: '1', title: '曲目一', fileId: 11)],
    ];
    write.tracksDelError = const KugouApiException('business', '删除失败');

    await _pumpDetail(tester, read: read, player: player, write: write);
    await _openMenu(tester);
    await tester.tap(find.text('管理曲目'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('曲目一'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(find.text('删除失败：删除失败'), findsOneWidget);
    expect(find.text('曲目一'), findsOneWidget); // 列表未清空
    await _drainSnackBar(tester);
  });

  // ── 曲目管理：上移下移排序 ──────────────────────────────────────────────

  testWidgets('上移提交 playlistTracksSort：revision + 全量 positions；成功后刷新', (
    tester,
  ) async {
    read.trackAllNewRevision = 7;
    read.trackAllNewPages = <List<MusicPlaylistTrack>>[
      <MusicPlaylistTrack>[
        testTrack(id: '1', title: '曲目一', fileId: 11),
        testTrack(id: '2', title: '曲目二', fileId: 12),
        testTrack(id: '3', title: '曲目三', fileId: 13),
      ],
    ];

    await _pumpDetail(tester, read: read, player: player, write: write);
    await _openMenu(tester);
    await tester.tap(find.text('管理曲目'));
    await tester.pumpAndSettle();

    // 第二行上移 → 新序 [二, 一, 三]，positions 0 起始连续编号。
    await tester.tap(find.byTooltip('上移').at(1));
    await tester.pumpAndSettle();

    final query = write.tracksSortQueries.single;
    expect(query.cloudListId, 77);
    expect(query.revision, 7);
    expect(query.positions.map((p) => p.fileId).toList(), <int>[12, 11, 13]);
    expect(query.positions.map((p) => p.position).toList(), <int>[0, 1, 2]);
    // 提交后刷新曲目（初始加载 + 排序刷新两次）。
    expect(read.trackAllNewQueries.length, 2);
  });

  testWidgets('排序 busy 防重：请求进行中上移按钮禁用', (tester) async {
    final hold = Completer<MusicCloudTrackChange>();
    write.tracksSortHold = hold;
    read.trackAllNewRevision = 7;
    read.trackAllNewPages = <List<MusicPlaylistTrack>>[
      <MusicPlaylistTrack>[
        testTrack(id: '1', title: '曲目一', fileId: 11),
        testTrack(id: '2', title: '曲目二', fileId: 12),
      ],
    ];

    await _pumpDetail(tester, read: read, player: player, write: write);
    await _openMenu(tester);
    await tester.tap(find.text('管理曲目'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('上移').at(1));
    // 忙指示是持续动画（CircularProgressIndicator），不能 pumpAndSettle，
    // 用固定时长推进一帧即可。
    await tester.pump(const Duration(milliseconds: 300));
    expect(write.tracksSortQueries.length, 1);

    // 第一笔排序未返回：所有上移按钮禁用，不会重复提交。
    final upButtons = tester.widgetList<IconButton>(
      find.ancestor(
        of: find.byTooltip('上移'),
        matching: find.byType(IconButton),
      ),
    );
    expect(upButtons.every((button) => button.onPressed == null), isTrue);
    await tester.tap(find.byTooltip('上移').at(1));
    await tester.pump(const Duration(milliseconds: 300));
    expect(write.tracksSortQueries.length, 1);

    hold.complete(const MusicCloudTrackChange());
    await tester.pumpAndSettle();
    expect(write.tracksSortQueries.length, 1); // 仍然只有一笔
  });

  testWidgets('排序失败：SnackBar + 刷新回滚展示顺序，不清空列表', (tester) async {
    read.trackAllNewRevision = 7;
    read.trackAllNewPages = <List<MusicPlaylistTrack>>[
      <MusicPlaylistTrack>[
        testTrack(id: '1', title: '曲目一', fileId: 11),
        testTrack(id: '2', title: '曲目二', fileId: 12),
      ],
    ];
    write.tracksSortError = const KugouApiException('business', '排序冲突');

    await _pumpDetail(tester, read: read, player: player, write: write);
    await _openMenu(tester);
    await tester.tap(find.text('管理曲目'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('上移').at(1));
    await tester.pumpAndSettle();

    expect(find.text('排序失败：排序冲突'), findsOneWidget);
    // 刷新后回到服务端顺序（fake 页表未变），两行都在。
    expect(find.text('曲目一'), findsOneWidget);
    expect(find.text('曲目二'), findsOneWidget);
    expect(read.trackAllNewQueries.length, 2);
  });

  // ── 添加歌曲 ────────────────────────────────────────────────────────────

  testWidgets('添加歌曲：搜索多选后 playlistTracksAdd 收到 title/hash/albumId/songId', (
    tester,
  ) async {
    final search = FakeSongSearch(
      pages: <List<MusicSong>>[
        <MusicSong>[
          testSong(id: '501', title: '歌曲一'),
          testSong(id: '502', title: '歌曲二'),
        ],
      ],
    );
    read.trackAllNewPages = <List<MusicPlaylistTrack>>[
      <MusicPlaylistTrack>[testTrack(id: '1', title: '云单曲目')],
    ];

    await _pumpDetail(
      tester,
      read: read,
      player: player,
      write: write,
      search: search,
    );
    await _openMenu(tester);
    await tester.tap(find.text('添加歌曲'));
    await tester.pumpAndSettle();

    // 加歌页：搜索 → 勾选两首 → 完成。
    await tester.enterText(find.byType(TextField), '周杰伦');
    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();

    expect(search.calls.single.keyword, '周杰伦');
    expect(search.calls.single.page, 1);
    expect(search.calls.single.pageSize, 30);
    expect(find.text('歌曲一'), findsOneWidget);
    expect(find.text('歌曲二'), findsOneWidget);

    // 未选中时完成按钮禁用。
    final done = tester.widget<TextButton>(
      find.widgetWithText(TextButton, '完成(0)'),
    );
    expect(done.onPressed, isNull);

    await tester.tap(find.text('歌曲一'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('歌曲二'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('完成(2)'));
    await tester.pumpAndSettle();

    // 回到详情页：加歌请求字段逐项对齐 PlaylistTrackInput。
    final query = write.tracksAddQueries.single;
    expect(query.cloudListId, 77);
    expect(query.tracks.length, 2);
    expect(query.tracks[0].title, '歌曲一');
    expect(query.tracks[0].hash, 'h501'.padLeft(32, '0'));
    expect(query.tracks[0].albumId, 42);
    expect(query.tracks[0].songId, 501);
    expect(query.tracks[1].songId, 502);
    expect(find.text('已添加 2 首歌曲'), findsOneWidget);
    // 返回后刷新曲目（初始 + 刷新两次）。
    expect(read.trackAllNewQueries.length, 2);
    await _drainSnackBar(tester);
  });

  testWidgets('加歌失败：SnackBar 提示，曲目列表保留', (tester) async {
    final search = FakeSongSearch(
      pages: <List<MusicSong>>[
        <MusicSong>[testSong(id: '501', title: '歌曲一')],
      ],
    );
    read.trackAllNewPages = <List<MusicPlaylistTrack>>[
      <MusicPlaylistTrack>[testTrack(id: '1', title: '云单曲目')],
    ];
    write.tracksAddError = const KugouApiException('business', '加歌上限');

    await _pumpDetail(
      tester,
      read: read,
      player: player,
      write: write,
      search: search,
    );
    await _openMenu(tester);
    await tester.tap(find.text('添加歌曲'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '关键词');
    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('歌曲一'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('完成(1)'));
    await tester.pumpAndSettle();

    expect(find.text('添加失败：加歌上限'), findsOneWidget);
    expect(find.text('云单曲目'), findsOneWidget); // 原曲目仍在
    await _drainSnackBar(tester);
  });

  // ── 写入口可见性 ────────────────────────────────────────────────────────

  testWidgets('非 editable / write 未接线 / 公开歌单：不显示写入口', (tester) async {
    read.trackAllNewPages = <List<MusicPlaylistTrack>>[
      <MusicPlaylistTrack>[testTrack(id: '1', title: '云单曲目')],
    ];

    // editable == false。
    await _pumpDetail(
      tester,
      read: read,
      player: player,
      write: write,
      editable: false,
      key: const ValueKey<String>('variant-editable-false'),
    );
    expect(find.byTooltip('歌单管理'), findsNothing);
    expect(find.byTooltip('删除歌单'), findsNothing);

    // write 未接线。
    await _pumpDetail(
      tester,
      read: read,
      player: player,
      write: null,
      key: const ValueKey<String>('variant-no-write'),
    );
    expect(find.byTooltip('歌单管理'), findsNothing);
    expect(find.byTooltip('删除歌单'), findsNothing);

    // 公开歌单（无 cloudListId）：即使 editable/write 齐备也不出写入口。
    read.trackAllPages = <List<MusicPlaylistTrack>>[
      <MusicPlaylistTrack>[testTrack(id: '2', title: '公开曲目')],
    ];
    read.details = <MusicPlaylistDetail>[testDetail(globalId: 'g-9')];
    await _pumpDetail(
      tester,
      read: read,
      player: player,
      write: write,
      cloudListId: null,
      globalId: 'g-9',
      title: '公开歌单',
      key: const ValueKey<String>('variant-public'),
    );
    expect(find.byTooltip('歌单管理'), findsNothing);
    expect(find.byTooltip('删除歌单'), findsNothing);
    expect(find.text('公开曲目'), findsOneWidget);
  });
}
