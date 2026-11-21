// ignore_for_file: deprecated_member_use — 与页面测试同款说明。
/// 歌曲资料面板（L6）测试：权益/资料/歌手图片三段独立成功、失败互不阻塞
/// 与重试、空数据整段隐藏、audioId 缺省不查资料、图片点击全屏预览、
/// ext 未接线不弹。全部走 fake（无网络、无真实计时器）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/models/playback_ext_models.dart';
import 'package:mimao/music/pages/music_song_info_sheet.dart';

import 'fake_apis.dart';

Widget _wrap({required FakePlaybackExtApi? ext, MusicSong? song}) =>
    MaterialApp(
      theme: buildMimaoTheme(
        seedColor: const Color(0xFF3B82F6),
        brightness: Brightness.light,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => showMusicSongInfoSheet(
                context,
                song:
                    song ??
                    MusicSong(
                      id: 's1',
                      audioId: 9001,
                      hash: kValidHash,
                      title: '曲目一',
                      artists: const <MusicArtistRef>[
                        MusicArtistRef(id: 42, name: '歌手A'),
                      ],
                      albumId: '7',
                      albumTitle: '测试专辑',
                      durationMs: 213000,
                      coverUrl: '',
                    ),
                ext: ext,
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );

/// audioId 缺省的歌曲（krm_audio 规格为「为空不查」）。
MusicSong _songWithoutAudioId() => MusicSong(
  id: 's0',
  audioId: null,
  hash: kValidHash,
  title: '无AudioId歌',
  artists: const <MusicArtistRef>[],
  albumId: '7',
  albumTitle: '',
  coverUrl: '',
);

/// 点按钮弹出面板并等待三段查询落定。
Future<void> _openSheet(WidgetTester tester, FakePlaybackExtApi? ext) async {
  await tester.pumpWidget(_wrap(ext: ext));
  await tester.tap(find.text('打开'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('三段成功：权益展示主档位/可用音质/预览区间；资料展示词曲/发行/BPM；图片出缩略图', (tester) async {
    final ext = FakePlaybackExtApi(
      privileges: <MusicResourcePrivileges>[privilegeFixture()],
      presentations: <MusicSongPresentation>[presentationFixture()],
      portraitGroups: portraitGroupsFixture(count: 2),
    );
    await _openSheet(tester, ext);

    expect(find.text('权益'), findsOneWidget);
    expect(find.text('主档位'), findsOneWidget);
    expect(find.text('flac · 900kbps · flac'), findsOneWidget);
    expect(find.text('可用音质'), findsOneWidget);
    expect(find.text('320 · 320kbps · mp3'), findsOneWidget);
    expect(find.text('预览区间'), findsOneWidget);
    expect(find.text('0:30 – 1:00'), findsOneWidget);

    expect(find.text('资料'), findsOneWidget);
    expect(find.text('作词'), findsOneWidget);
    expect(find.text('词人甲'), findsOneWidget);
    expect(find.text('作曲'), findsOneWidget);
    expect(find.text('作曲乙'), findsOneWidget);
    expect(find.text('语言'), findsOneWidget);
    expect(find.text('国语'), findsOneWidget);
    expect(find.text('发行时间'), findsOneWidget);
    expect(find.text('2024-01-01'), findsOneWidget);
    expect(find.text('BPM'), findsOneWidget);
    expect(find.text('96'), findsOneWidget);

    expect(find.text('歌手图片'), findsOneWidget);
    expect(find.byKey(const Key('music-portrait-thumb-0')), findsOneWidget);
    expect(find.byKey(const Key('music-portrait-thumb-1')), findsOneWidget);
  });

  testWidgets('权益段带资源异常码/文案时展示，不视为空段', (tester) async {
    final ext = FakePlaybackExtApi(
      privileges: <MusicResourcePrivileges>[
        privilegeFixture(
          resourceError: 321,
          resourceMessage: '资源授权异常',
          preview: const MusicPreviewRange(), // 全空区间不展示预览行
          variants: const <MusicQualityVariant>[], // 无音质行 → 「可用音质」隐藏
        ),
      ],
      presentations: const <MusicSongPresentation>[],
      portraitGroups: const <List<MusicAuthorImages>>[],
    );
    await _openSheet(tester, ext);

    expect(find.text('权益'), findsOneWidget);
    expect(find.text('资源异常'), findsOneWidget);
    expect(find.text('资源授权异常'), findsOneWidget);
    // 空 preview / 空 variants / 无图片：对应行与空段隐藏。
    expect(find.text('预览区间'), findsNothing);
    expect(find.text('可用音质'), findsNothing);
    expect(find.text('资料'), findsNothing);
    expect(find.text('歌手图片'), findsNothing);
  });

  testWidgets('三段互不阻塞：权益/资料失败各自可重试，图片段照常展示', (tester) async {
    final ext = FakePlaybackExtApi(
      privileges: <MusicResourcePrivileges>[privilegeFixture()],
      privilegeError: '权益挂了',
      presentations: <MusicSongPresentation>[presentationFixture()],
      krmError: '资料挂了',
      portraitGroups: portraitGroupsFixture(count: 1),
    );
    await _openSheet(tester, ext);

    expect(find.textContaining('权益挂了'), findsOneWidget);
    expect(find.textContaining('资料挂了'), findsOneWidget);
    expect(find.text('重试'), findsNWidgets(2));
    expect(find.text('歌手图片'), findsOneWidget);
    expect(find.byKey(const Key('music-portrait-thumb-0')), findsOneWidget);

    // 一次性失败：逐段重试恢复，互不影响。
    ext.privilegeError = null;
    ext.krmError = null;
    await tester.tap(find.text('重试').first);
    await tester.pumpAndSettle();
    expect(find.text('主档位'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('作词'), findsOneWidget);
    expect(find.text('重试'), findsNothing);
  });

  testWidgets('空数据段整段隐藏：只有头部基础信息', (tester) async {
    final ext = FakePlaybackExtApi();
    await _openSheet(tester, ext);

    expect(find.text('曲目一'), findsOneWidget); // 头部
    expect(find.text('权益'), findsNothing);
    expect(find.text('资料'), findsNothing);
    expect(find.text('歌手图片'), findsNothing);
  });

  testWidgets('audioId 缺省：不查资料段（分段隐藏），权益段照常', (tester) async {
    final noAudioId = FakePlaybackExtApi(
      privileges: <MusicResourcePrivileges>[privilegeFixture()],
      presentations: <MusicSongPresentation>[presentationFixture()],
    );
    await tester.pumpWidget(_wrap(ext: noAudioId, song: _songWithoutAudioId()));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.text('资料'), findsNothing);
    expect(noAudioId.krmLog, isEmpty); // 「为空不查」
    expect(find.text('权益'), findsOneWidget);
    expect(find.text('主档位'), findsOneWidget);
  });

  testWidgets('hash 非法：不查权益与图片段，资料段照常', (tester) async {
    final badHash = FakePlaybackExtApi(
      privileges: <MusicResourcePrivileges>[privilegeFixture()],
      presentations: <MusicSongPresentation>[presentationFixture()],
      portraitGroups: portraitGroupsFixture(),
    );
    await tester.pumpWidget(
      _wrap(
        ext: badHash,
        song: MusicSong(
          id: 's2',
          audioId: 9001,
          hash: 'hash-s2', // 非 32 位十六进制
          title: '曲目二',
          artists: const <MusicArtistRef>[],
          albumId: '7',
          albumTitle: '',
          coverUrl: '',
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.text('权益'), findsNothing);
    expect(find.text('歌手图片'), findsNothing);
    expect(badHash.privilegeLog, isEmpty);
    expect(badHash.imagesLog, isEmpty);
    expect(find.text('资料'), findsOneWidget);
    expect(badHash.krmLog, hasLength(1));
  });

  testWidgets('点击缩略图全屏预览（标题用文件名），关闭退出', (tester) async {
    final ext = FakePlaybackExtApi(portraitGroups: portraitGroupsFixture());
    await _openSheet(tester, ext);

    await tester.tap(find.byKey(const Key('music-portrait-thumb-0')));
    await tester.pumpAndSettle();

    expect(find.text('写真0.jpg'), findsOneWidget); // 预览标题
    expect(find.text('关闭'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(find.text('写真0.jpg'), findsNothing); // 预览已退出
    expect(find.byKey(const Key('music-portrait-thumb-0')), findsOneWidget);
  });

  testWidgets('ext 未接线（null）时不弹面板', (tester) async {
    await tester.pumpWidget(_wrap(ext: null));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.byType(MusicSongInfoSheet), findsNothing);
    expect(find.text('权益'), findsNothing);
  });
}
