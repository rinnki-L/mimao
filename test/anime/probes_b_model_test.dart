// B 线（番剧播放增强）· AnimeEpisode 线路字段单测。
// 覆盖：线路字段序列化往返 + 默认值兼容旧构造 + 相等性含线路字段。
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/anime/data/anime_models.dart';

void main() {
  group('AnimeEpisode 线路字段', () {
    test('默认值兼容旧构造：roadIndex=1、roadName 空串', () {
      const episode = AnimeEpisode(
        number: 3,
        title: '第3话',
        url: 'https://a.test/3.m3u8',
      );

      expect(episode.roadIndex, 1);
      expect(episode.roadName, '');
    });

    test('多线路构造：线路字段原样保留', () {
      const episode = AnimeEpisode(
        number: 1,
        title: '第1话',
        url: 'https://a.test/1.m3u8',
        roadIndex: 2,
        roadName: '备用线路',
      );

      expect(episode.roadIndex, 2);
      expect(episode.roadName, '备用线路');
    });

    test('toJson/fromJson 往返：线路字段不丢', () {
      const episode = AnimeEpisode(
        number: 5,
        title: '第5话',
        url: 'https://a.test/5.m3u8',
        duration: '24:00',
        roadIndex: 3,
        roadName: '线路三',
      );

      final json = episode.toJson();
      expect(json['roadIndex'], 3);
      expect(json['roadName'], '线路三');

      final restored = AnimeEpisode.fromJson(json);
      expect(restored, episode);
      expect(restored.roadIndex, 3);
      expect(restored.roadName, '线路三');
      expect(restored.duration, '24:00');
    });

    test('fromJson 兼容旧快照：缺省线路字段给默认值', () {
      final old = AnimeEpisode.fromJson(<String, dynamic>{
        'number': 1,
        'title': '旧快照',
        'url': 'https://a.test/1',
      });

      expect(old.roadIndex, 1);
      expect(old.roadName, '');
      expect(old.duration, isNull);
    });

    test('相等性与 hashCode 包含线路字段', () {
      const a = AnimeEpisode(
        number: 1,
        title: 'x',
        url: 'u',
        roadIndex: 1,
        roadName: 'A',
      );
      const b = AnimeEpisode(
        number: 1,
        title: 'x',
        url: 'u',
        roadIndex: 1,
        roadName: 'A',
      );
      const c = AnimeEpisode(
        number: 1,
        title: 'x',
        url: 'u',
        roadIndex: 2,
        roadName: 'A',
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
    });
  });
}
