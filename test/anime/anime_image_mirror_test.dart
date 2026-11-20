// 图片加速（直连/镜像）纯函数 + 控制器 + Bangumi 服务的离线单测。

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/anime/data/bangumi_api.dart';
import 'package:mimao/anime/pages/anime_image_mirror.dart';
import 'package:mimao/core/db.dart';
import 'package:mimao/core/settings.dart';

const cover = 'https://lain.bgm.tv/pic/cover/l/13/c5/400602.jpg';

void main() {
  group('applyAnimeImageAcceleration 纯函数', () {
    test('直连时原样返回', () {
      expect(
        applyAnimeImageAcceleration(cover, mode: AnimeImageAcceleration.direct),
        cover,
      );
    });

    test('镜像时改写成 wsrv.nl 代理，目标 URL 被 URI 编码', () {
      final result = applyAnimeImageAcceleration(
        cover,
        mode: AnimeImageAcceleration.mirror,
      );
      expect(result, startsWith(animeImageMirrorTemplate));
      final encoded = result.substring(animeImageMirrorTemplate.length);
      expect(Uri.decodeComponent(encoded), cover);
    });

    test('幂等：已镜像的地址不再二次包裹', () {
      final once = applyAnimeImageAcceleration(
        cover,
        mode: AnimeImageAcceleration.mirror,
      );
      expect(
        applyAnimeImageAcceleration(once, mode: AnimeImageAcceleration.mirror),
        once,
      );
    });

    test('assets / 空串 / 非 http(s) 地址原样返回', () {
      for (final url in <String>['', '   ', 'assets/mimao.png', 'ftp://x/y']) {
        expect(
          applyAnimeImageAcceleration(url, mode: AnimeImageAcceleration.mirror),
          url.trim(),
        );
      }
    });

    test('gif 追加 n=-1（对齐 Kazumi）', () {
      final result = applyAnimeImageAcceleration(
        'https://lain.bgm.tv/a.gif',
        mode: AnimeImageAcceleration.mirror,
      );
      expect(result, endsWith('&n=-1'));
    });

    test('isBangumiImage 识别 bgm 图床与 api image 端点', () {
      expect(isBangumiImage(Uri.parse(cover)), isTrue);
      expect(
        isBangumiImage(
          Uri.parse('https://api.bgm.tv/v0/subjects/400602/image?type=large'),
        ),
        isTrue,
      );
      expect(isBangumiImage(Uri.parse('https://other.com/a.jpg')), isFalse);
      expect(
        isBangumiImage(Uri.parse('https://api.bgm.tv/v0/subjects/400602')),
        isFalse,
      );
    });
  });

  group('AnimeImageAccelerationController 持久化', () {
    test('无 settings 时只维护内存态，set 立即生效', () async {
      final controller = AnimeImageAccelerationController();
      expect(controller.value, AnimeImageAcceleration.mirror);
      await controller.set(AnimeImageAcceleration.direct);
      expect(controller.value, AnimeImageAcceleration.direct);
      expect(controller.accelerate(cover), cover);
    });

    test('load 从设置库读初值，set 写入设置库', () async {
      final db = AppDb.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final settings = SettingsRepository(db);
      await settings.set(animeImageAccelerationKey, 'direct');

      final controller = AnimeImageAccelerationController(settings: settings);
      await controller.load();
      expect(controller.value, AnimeImageAcceleration.direct);
      expect(controller.accelerate(cover), cover);

      await controller.set(AnimeImageAcceleration.mirror);
      final reloaded = AnimeImageAccelerationController(settings: settings);
      await reloaded.load();
      expect(reloaded.value, AnimeImageAcceleration.mirror);
    });

    test('未知持久化值回退默认模式', () async {
      final db = AppDb.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final settings = SettingsRepository(db);
      await settings.set(animeImageAccelerationKey, 'bogus');
      final controller = AnimeImageAccelerationController(settings: settings);
      await controller.load();
      expect(controller.value, AnimeImageAcceleration.defaultMode);
    });
  });

  group('Bangumi API 纯函数', () {
    test('searchUrl 带 limit/offset，searchBody 只取动画', () {
      expect(
        BangumiEndpoints.searchUrl(
          BangumiEndpoints.mirror,
          limit: 5,
          offset: 10,
        ),
        'https://api.bgmapi.com/v0/search/subjects?limit=5&offset=10',
      );
      final body = BangumiEndpoints.searchBody('芙莉莲');
      expect(body['keyword'], '芙莉莲');
      expect((body['filter'] as Map)['type'], <int>[2]);
    });

    test('BangumiSubject 解析：中文名优先，封面 large 优先', () {
      final subject = BangumiSubject.fromJson(<String, dynamic>{
        'id': 400602,
        'name': '葬送のフリーレン',
        'name_cn': '葬送的芙莉莲',
        'images': <String, dynamic>{
          'large': 'https://lain.bgm.tv/l.jpg',
          'common': 'https://lain.bgm.tv/c.jpg',
        },
      });
      expect(subject.displayName, '葬送的芙莉莲');
      expect(subject.coverUrl, 'https://lain.bgm.tv/l.jpg');
    });

    test('BangumiSubject 解析评分/首播/标签', () {
      final subject = BangumiSubject.fromJson(<String, dynamic>{
        'id': 1,
        'name': 'A',
        'name_cn': '',
        'summary': '简介',
        'date': '2023-09-29',
        'rating': <String, dynamic>{'score': 8.7},
        'tags': <dynamic>[
          <String, dynamic>{'name': '奇幻'},
          <String, dynamic>{'name': '治愈'},
        ],
      });
      expect(subject.summary, '简介');
      expect(subject.airDate, '2023-09-29');
      expect(subject.rating, 8.7);
      expect(subject.tags, <String>['奇幻', '治愈']);
      expect(subject.searchKeyword, 'A');
    });
  });
}
