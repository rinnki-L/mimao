// 封面镜像工具 + 控制器的离线单测：纯函数不联网 / 控制器用假 SettingsRepository。

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/anime/pages/anime_image_mirror.dart';
import 'package:mimao/core/settings.dart';

import 'package:drift/native.dart';
import 'package:mimao/core/db.dart';

/// 用真实内存 AppDb 驱动 SettingsRepository，验证开关真的落库并可读回。
const cover = 'https://site.example/img/a.jpg?x=1&y=2';

void main() {
  group('applyAnimeImageMirror 纯函数', () {
    test('关闭时原样返回', () {
      expect(applyAnimeImageMirror(cover, enabled: false), cover);
    });

    test('开启时改写成代理地址，目标 URL 被 URI 编码', () {
      final result = applyAnimeImageMirror(cover, enabled: true);
      expect(result, startsWith(animeImageMirrorTemplate));
      final encoded = result.substring(animeImageMirrorTemplate.length);
      expect(Uri.decodeComponent(encoded), cover);
    });

    test('幂等：已镜像的地址不再二次包裹', () {
      final once = applyAnimeImageMirror(cover, enabled: true);
      expect(applyAnimeImageMirror(once, enabled: true), once);
    });

    test('assets / 空串 / 非 http(s) 地址原样返回', () {
      for (final url in <String>['', '   ', 'assets/mimao.png', 'ftp://x/y']) {
        expect(applyAnimeImageMirror(url, enabled: true), url.trim());
      }
    });

    test('自定义模板生效', () {
      const template = 'https://proxy.test/?src=';
      final result = applyAnimeImageMirror(
        cover,
        enabled: true,
        template: template,
      );
      expect(result, startsWith(template));
      expect(Uri.decodeComponent(result.substring(template.length)), cover);
    });
  });

  group('AnimeImageMirrorController 持久化', () {
    test('无 settings 时只维护内存态，set 立即生效', () async {
      final controller = AnimeImageMirrorController();
      // 关 → 开：验证内存态切换与 mirror 跟随。
      await controller.set(false);
      expect(controller.value, isFalse);
      expect(controller.mirror(cover), cover);
      await controller.set(true);
      expect(controller.value, isTrue);
      expect(controller.mirror(cover), isNot(cover));
    });

    test('默认值开启，镜像生效', () {
      final controller = AnimeImageMirrorController();
      expect(controller.value, isTrue);
      expect(controller.mirror(cover), startsWith(animeImageMirrorTemplate));
    });

    test('load 从设置库读初值，set 写入设置库', () async {
      final db = AppDb.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final settings = SettingsRepository(db);
      await settings.setBool(animeImageMirrorKey, false);

      final controller = AnimeImageMirrorController(settings: settings);
      await controller.load();
      expect(controller.value, isFalse);
      expect(controller.mirror(cover), cover, reason: '关闭时不应改写');

      await controller.set(true);
      expect(controller.value, isTrue);
      // 用一个新控制器读回，验证真的持久化了。
      final reloaded = AnimeImageMirrorController(settings: settings);
      await reloaded.load();
      expect(reloaded.value, isTrue);
    });

    test('设置库读取抛异常时保留默认值，不冒泡', () async {
      final db = AppDb.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      // 关掉 DB 后读取会抛，验证 load 吞异常。
      await db.close();
      final controller = AnimeImageMirrorController(
        settings: SettingsRepository(db),
      );
      await controller.load();
      expect(controller.value, animeImageMirrorDefault);
    });
  });
}
