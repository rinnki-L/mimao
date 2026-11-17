// 本地漫画单测：导入元数据读写、幂等刷新、本地来源校验、投影可见。
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/comic/comic_models.dart';
import 'package:mimao/comic/local_comic_service.dart';
import 'package:mimao/core/contract.dart';

import 'comic_test_env.dart';

void main() {
  late ComicTestEnv env;
  late ComicLocalService local;

  setUp(() {
    env = ComicTestEnv.create();
    local = ComicLocalService(env.comicDb, env.library);
  });

  tearDown(() => env.close());

  test('导入本地文件夹写入元数据并投影到书架', () async {
    final ref = ComicRef.local('folder-a');
    final entry = await local.import(
      ref: ref,
      title: '本地漫画A',
      folderPath: '/comics/a',
      coverPath: '/comics/a/cover.jpg',
      pageCount: 42,
      payload: '{"scanner":"local-v1"}',
      importedAt: DateTime(2026, 11, 17, 9),
    );

    expect(entry.ref.sourceName, ComicRef.localSource);
    final found = await local.find(ref);
    expect(found, isNotNull);
    expect(found!.title, '本地漫画A');
    expect(found.folderPath, '/comics/a');
    expect(found.coverPath, '/comics/a/cover.jpg');
    expect(found.pageCount, 42);
    expect(found.payload, '{"scanner":"local-v1"}');

    final view = (await env.library.timeline()).single;
    expect(view.id, 'folder-a');
    expect(view.title, '本地漫画A');
    expect(view.type, MediaType.comic);
    expect(view.progressText, '尚未阅读');
  });

  test('同 id 重复导入幂等刷新元数据', () async {
    final ref = ComicRef.local('folder-a');
    await local.import(
      ref: ref,
      title: '旧标题',
      folderPath: '/comics/a',
      importedAt: DateTime(2026, 1, 1),
    );
    await local.import(
      ref: ref,
      title: '新标题',
      folderPath: '/comics/a',
      pageCount: 100,
      importedAt: DateTime(2026, 11, 17),
    );

    final all = await local.all();
    expect(all, hasLength(1));
    expect(all.single.title, '新标题');
    expect(all.single.pageCount, 100);
  });

  test('非 local 来源被拒绝', () async {
    expect(
      () => local.import(
        ref: const ComicRef(id: 'x', sourceName: 'online'),
        title: 'X',
        folderPath: '/x',
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('remove 删除内部元数据行', () async {
    final ref = ComicRef.local('folder-a');
    await local.import(ref: ref, title: '本地漫画A', folderPath: '/comics/a');

    await local.remove(ref);

    expect(await local.find(ref), isNull);
    expect(await local.all(), isEmpty);
  });
}
