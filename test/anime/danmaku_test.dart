// 弹幕（danmaku）单测：模型序列化、宽容解码、本地缓存、弹幕源接口槽。
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/anime/anime_models.dart';
import 'package:mimao/anime/danmaku.dart';

import 'anime_test_env.dart';

class _FakeDanmakuSource implements DanmakuSource {
  _FakeDanmakuSource(this.comments);

  final List<DanmakuComment> comments;
  int calls = 0;

  @override
  Future<List<DanmakuComment>> fetch({
    required AnimeRef ref,
    required int episode,
  }) async {
    calls++;
    return comments;
  }
}

void main() {
  late AnimeTestEnv env;

  const ref = AnimeRef(id: 'kazumi:1001', sourceName: '樱花动漫');

  setUp(() => env = AnimeTestEnv.create());
  tearDown(() => env.close());

  test('弹幕模型 JSON 往返保留时间/文本/模式/颜色/字号', () {
    const comment = DanmakuComment(
      time: Duration(minutes: 1, seconds: 2, milliseconds: 300),
      text: '前方高能',
      mode: DanmakuMode.top,
      color: 0xFF0000,
      fontSize: 30,
    );

    final decoded = DanmakuComment.fromJson(comment.toJson());

    expect(decoded.time, comment.time);
    expect(decoded.text, '前方高能');
    expect(decoded.mode, DanmakuMode.top);
    expect(decoded.color, 0xFF0000);
    expect(decoded.fontSize, 30);
  });

  test('解码宽容：未知字段忽略、可选字段取默认；缺时间/文本报格式错', () {
    final decoded = DanmakuComment.fromJson(<String, Object?>{
      'timeMs': 1500,
      'text': '默认样式',
      'mode': '不存在的模式',
      'futureField': true,
    });

    expect(decoded.time, const Duration(milliseconds: 1500));
    expect(decoded.mode, DanmakuMode.scroll);
    expect(decoded.color, 0xFFFFFF);
    expect(decoded.fontSize, 25);

    expect(
      () => DanmakuComment.fromJson(<String, Object?>{'text': '缺时间'}),
      throwsFormatException,
    );
    expect(
      () => DanmakuComment.fromJson(<String, Object?>{'timeMs': 100}),
      throwsFormatException,
    );
  });

  test('缓存按（作品, 源, 话）读写往返，不同源互不覆盖', () async {
    final service = AnimeDanmakuService(env.animeDb);
    const other = AnimeRef(id: 'kazumi:1001', sourceName: '另一个源');
    const comments = [
      DanmakuComment(time: Duration(seconds: 1), text: '一'),
      DanmakuComment(
        time: Duration(seconds: 2),
        text: '二',
        mode: DanmakuMode.bottom,
      ),
    ];
    final fetchedAt = DateTime(2026, 11, 17, 9);

    await service.writeCache(ref, 1, comments, fetchedAt: fetchedAt);
    await service.writeCache(other, 1, const [
      DanmakuComment(time: Duration(seconds: 3), text: '别的源'),
    ], fetchedAt: fetchedAt);

    final cached = await service.readCache(ref, 1);
    expect(cached, isNotNull);
    expect(cached!.fetchedAt, fetchedAt);
    expect(cached.comments.map((c) => c.text), ['一', '二']);
    expect(cached.comments.last.mode, DanmakuMode.bottom);

    final otherCached = await service.readCache(other, 1);
    expect(otherCached!.comments.single.text, '别的源');
    expect(await service.readCache(ref, 2), isNull);
  });

  test('新鲜缓存不触网；过期或被 refresh 时调用源并覆盖缓存', () async {
    final source = _FakeDanmakuSource(const [
      DanmakuComment(time: Duration(seconds: 9), text: '来自弹幕源'),
    ]);
    final service = AnimeDanmakuService(
      env.animeDb,
      source: source,
      maxCacheAge: const Duration(days: 7),
    );
    await service.writeCache(ref, 1, const [
      DanmakuComment(time: Duration(seconds: 1), text: '旧缓存'),
    ], fetchedAt: DateTime(2026, 11, 10));

    final fresh = await service.load(ref, 1, now: DateTime(2026, 11, 12));
    expect(fresh.single.text, '旧缓存');
    expect(source.calls, 0);

    final stale = await service.load(ref, 1, now: DateTime(2026, 11, 20));
    expect(stale.single.text, '来自弹幕源');
    expect(source.calls, 1);

    final refreshed = await service.load(
      ref,
      1,
      refresh: true,
      now: DateTime(2026, 11, 21),
    );
    expect(refreshed.single.text, '来自弹幕源');
    expect(source.calls, 2);

    final cached = await service.readCache(ref, 1);
    expect(cached!.fetchedAt, DateTime(2026, 11, 21));
  });

  test('源缺失时回退缓存；无缓存返回空列表', () async {
    final service = AnimeDanmakuService(env.animeDb);
    expect(await service.load(ref, 3), isEmpty);

    await service.writeCache(ref, 3, const [
      DanmakuComment(time: Duration(seconds: 1), text: '离线弹幕'),
    ], fetchedAt: DateTime(2026, 1, 1));
    final loaded = await service.load(ref, 3, now: DateTime(2026, 11, 17));
    expect(loaded.single.text, '离线弹幕');
  });
}
