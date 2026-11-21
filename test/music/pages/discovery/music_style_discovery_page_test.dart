// ignore_for_file: deprecated_member_use — 与页面测试同款说明。
/// 风格推荐页 widget 测试（逻辑从发现页内联 section 原样迁移）：
/// 不联网、不碰真实计时器。
///
/// 覆盖：首载标签 chips（selected == 1 服务端预选）与歌曲长条可播放、
/// 点标签带 tagIds 重取、再点已选标签取消、标签重取失败后重试沿用最近
/// tagIds、首载失败重试恢复、标签与歌曲全空时的空态。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/music/models/discovery_models.dart';
import 'package:mimao/music/pages/music_style_discovery_page.dart';

import 'fakes.dart';

Widget _host(Widget page) => MaterialApp(
  theme: buildMimaoTheme(
    seedColor: const Color(0xFF4A6CF7),
    brightness: Brightness.light,
  ),
  home: page,
);

/// 注入桩集合（风格页只要 discovery + player）。
class _Fixture {
  _Fixture({FakeDiscoveryApi? discovery})
    : discovery = discovery ?? FakeDiscoveryApi();

  final FakeDiscoveryApi discovery;
  final FakePlayerUi player = FakePlayerUi();

  Widget get page =>
      MusicStyleDiscoveryPage(discovery: discovery, player: player);
}

/// 首帧装载：pumpWidget + 一次 pump（首载完成）。
Future<_Fixture> _pumpPage(WidgetTester tester, _Fixture fixture) async {
  await tester.pumpWidget(_host(fixture.page));
  await tester.pump();
  return fixture;
}

void main() {
  testWidgets('首载渲染标签 chips（含预选）与歌曲长条，可播放', (tester) async {
    final fixture = await _pumpPage(
      tester,
      _Fixture(
        discovery: FakeDiscoveryApi(
          styleBatches: <MusicStyleRecommendations>[
            fakeStyleRecommendations(
              groups: <MusicStyleTagGroup>[
                fakeStyleGroup(
                  name: '风格',
                  tags: <MusicStyleTag>[
                    fakeStyleTag(id: 'pop', name: '流行', selected: 1),
                    fakeStyleTag(id: 'rock', name: '摇滚'),
                  ],
                ),
              ],
              songs: <MusicDiscoverySong>[
                fakeDiscoverySong(id: '50', hash: 'st50', title: '风格之歌A'),
              ],
            ),
          ],
        ),
      ),
    );

    expect(find.text('风格推荐'), findsOneWidget);
    expect(find.text('风格'), findsOneWidget, reason: '标签组名渲染');
    expect(find.text('流行'), findsOneWidget);
    expect(find.text('摇滚'), findsOneWidget);
    expect(find.text('风格之歌A'), findsOneWidget);

    expect(fixture.discovery.styleCalls, 1);
    // 首载不带 tagIds（用 const 空查询）。
    expect(fixture.discovery.lastStyleQuery?.tagIds, isEmpty);

    // selected == 1 的「流行」预选中，「摇滚」未选中。
    final popChip = tester.widget<FilterChip>(
      find.ancestor(of: find.text('流行'), matching: find.byType(FilterChip)),
    );
    expect(popChip.selected, isTrue);
    final rockChip = tester.widget<FilterChip>(
      find.ancestor(of: find.text('摇滚'), matching: find.byType(FilterChip)),
    );
    expect(rockChip.selected, isFalse);

    // 歌曲长条走与发现页相同的播放链路。
    await tester.tap(find.text('风格之歌A'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(fixture.player.played, hasLength(1));
    expect(fixture.player.played.single.id, '50');
  });

  testWidgets('点标签带 tagIds 重取，歌曲刷新且预选保留', (tester) async {
    final groups = <MusicStyleTagGroup>[
      fakeStyleGroup(
        name: '风格',
        tags: <MusicStyleTag>[
          fakeStyleTag(id: 'pop', name: '流行', selected: 1),
          fakeStyleTag(id: 'rock', name: '摇滚'),
        ],
      ),
    ];
    final fixture = await _pumpPage(
      tester,
      _Fixture(
        discovery: FakeDiscoveryApi(
          styleBatches: <MusicStyleRecommendations>[
            fakeStyleRecommendations(
              groups: groups,
              songs: <MusicDiscoverySong>[
                fakeDiscoverySong(id: '50', hash: 'st50', title: '风格之歌A'),
              ],
            ),
            fakeStyleRecommendations(
              groups: groups,
              songs: <MusicDiscoverySong>[
                fakeDiscoverySong(id: '51', hash: 'st51', title: '风格之歌B'),
              ],
            ),
          ],
        ),
      ),
    );

    await tester.tap(find.text('摇滚'));
    await tester.pump();
    await tester.pump();

    expect(fixture.discovery.styleCalls, 2);
    // 重取 tagIds = 服务端预选（流行）+ 新选（摇滚），顺序与下发一致。
    expect(fixture.discovery.lastStyleQuery?.tagIds, <String>['pop', 'rock']);
    expect(find.text('风格之歌A'), findsNothing);
    expect(find.text('风格之歌B'), findsOneWidget);

    // 重取结果可播放。
    await tester.tap(find.text('风格之歌B'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(fixture.player.played.single.id, '51');
  });

  testWidgets('再点已选标签取消并带剩余 tagIds 重取', (tester) async {
    final groups = <MusicStyleTagGroup>[
      fakeStyleGroup(
        tags: <MusicStyleTag>[
          fakeStyleTag(id: 'pop', name: '流行', selected: 1),
          fakeStyleTag(id: 'rock', name: '摇滚'),
        ],
      ),
    ];
    final fixture = await _pumpPage(
      tester,
      _Fixture(
        discovery: FakeDiscoveryApi(
          styleBatches: <MusicStyleRecommendations>[
            fakeStyleRecommendations(
              groups: groups,
              songs: <MusicDiscoverySong>[
                fakeDiscoverySong(id: '50', hash: 'st50', title: '风格之歌A'),
              ],
            ),
            fakeStyleRecommendations(
              groups: groups,
              songs: <MusicDiscoverySong>[
                fakeDiscoverySong(id: '51', hash: 'st51', title: '风格之歌B'),
              ],
            ),
          ],
        ),
      ),
    );

    await tester.tap(find.text('摇滚'));
    await tester.pump();
    await tester.pump();
    expect(fixture.discovery.lastStyleQuery?.tagIds, <String>['pop', 'rock']);

    await tester.tap(find.text('流行'));
    await tester.pump();
    await tester.pump();
    expect(fixture.discovery.styleCalls, 3);
    expect(fixture.discovery.lastStyleQuery?.tagIds, <String>['rock']);
    expect(find.text('风格之歌B'), findsOneWidget);
  });

  testWidgets('标签重取失败后重试沿用最近一次 tagIds', (tester) async {
    final discovery = FakeDiscoveryApi(
      styleBatches: <MusicStyleRecommendations>[
        fakeStyleRecommendations(
          groups: <MusicStyleTagGroup>[
            fakeStyleGroup(
              tags: <MusicStyleTag>[
                fakeStyleTag(id: 'pop', name: '流行', selected: 1),
                fakeStyleTag(id: 'rock', name: '摇滚'),
              ],
            ),
          ],
          songs: <MusicDiscoverySong>[
            fakeDiscoverySong(id: '50', hash: 'st50', title: '风格之歌A'),
          ],
        ),
      ],
    );
    final fixture = await _pumpPage(tester, _Fixture(discovery: discovery));

    // 首载成功后注入一次失败，点「摇滚」重取报错。
    discovery.styleFailuresLeft = 1;
    await tester.tap(find.text('摇滚'));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('风格推荐挂了'), findsOneWidget);

    // 重试沿用点选时的 tagIds，成功后错误态恢复、选中态保留。
    discovery.styleFailuresLeft = 0;
    await tester.tap(find.text('重试'));
    await tester.pump();
    await tester.pump();

    expect(fixture.discovery.styleCalls, 3);
    expect(fixture.discovery.lastStyleQuery?.tagIds, <String>['pop', 'rock']);
    expect(find.textContaining('风格推荐挂了'), findsNothing);
    final rockChip = tester.widget<FilterChip>(
      find.ancestor(of: find.text('摇滚'), matching: find.byType(FilterChip)),
    );
    expect(rockChip.selected, isTrue);
  });

  testWidgets('首载失败：错误态与重试恢复', (tester) async {
    final fixture = await _pumpPage(
      tester,
      _Fixture(
        discovery: FakeDiscoveryApi(
          styleBatches: <MusicStyleRecommendations>[
            fakeStyleRecommendations(
              songs: <MusicDiscoverySong>[
                fakeDiscoverySong(id: '50', hash: 'st50', title: '风格之歌A'),
              ],
            ),
          ],
          styleFailuresLeft: 1,
        ),
      ),
    );

    expect(find.textContaining('风格推荐挂了'), findsOneWidget);

    await tester.tap(find.text('重试'));
    await tester.pump();
    await tester.pump();

    expect(fixture.discovery.styleCalls, 2);
    expect(find.text('风格之歌A'), findsOneWidget);
    expect(find.textContaining('风格推荐挂了'), findsNothing);
  });

  testWidgets('空数据：标签与歌曲全空时显示空态', (tester) async {
    await _pumpPage(tester, _Fixture());
    expect(find.text('暂无风格推荐'), findsOneWidget);
    expect(find.byType(FilterChip), findsNothing);
    expect(find.byType(ListTile), findsNothing);
  });
}
