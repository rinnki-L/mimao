/// 听歌上报会话缓存测试：复用/过期/失败清除/并发合并/容量淘汰/按身份隔离，
/// 以及 `KugouListenReportApi` 组接口冒烟（实例私有缓存，非全局单例）。
///
/// 用按路径供响应的 [ListenReportAdapter]：缓存命中/重握手会改变请求序号，
/// 按序号供响应会错位。
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/listen_report_api.dart';
import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/user_listen_report.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import 'package:mimao/music/models/user_listen_report_models.dart';

import '../capture_adapter.dart' show jsonBytes;
import 'listen_report_fixtures.dart';

Matcher throwsBusiness(int? code) => throwsA(
  isA<KugouApiException>()
      .having((error) => error.kind, 'kind', 'business')
      .having((error) => error.code, 'code', code),
);

void main() {
  late ListenReportAdapter adapter;
  late KugouClient client;
  late KugouIdentity identity;
  late MusicSession session;
  late SequenceRandom random;
  late MusicListenReportSessionCache cache;
  late int clockMs;

  DateTime clock() => DateTime.fromMillisecondsSinceEpoch(clockMs, isUtc: true);

  setUp(() {
    adapter = ListenReportAdapter();
    client = KugouClient(dio: Dio()..httpClientAdapter = adapter);
    identity = listenReportIdentity();
    session = fakeListenReportSession(identity, client);
    random = SequenceRandom(listenReportEntropy);
    cache = MusicListenReportSessionCache();
    clockMs = listenReportMilliseconds;
    installPathHappyPath(adapter);
  });

  void useIdentity(KugouIdentity value) {
    identity = value;
    session = fakeListenReportSession(value, client);
  }

  Future<MusicListenReportAcceptance> report(MusicListenReportQuery query) =>
      fetchListenReport(
        session,
        query,
        cache: cache,
        clock: clock,
        random: random,
      );

  MusicListenReportQuery startQuery({int song = 1}) => MusicListenReportQuery(
    event: MusicListenReportEvent.start,
    mixsongid: song,
  );

  test('第二次上报复用握手：两次上报共 4 次请求（2 握手 + 2 上报）', () async {
    await report(startQuery(song: 1));
    await report(startQuery(song: 2));

    expect(adapter.requests.length, 4);
    expect(adapter.requests[0].path, qrydidUrl);
    expect(adapter.requests[1].path, genUrl);
    expect(adapter.requests[2].path, postUrl);
    expect(adapter.requests[3].path, postUrl);
    expect(adapter.requests[3].query['cookie'], fixtureCookie);
  });

  test('1799 秒内复用；恰好 1800 秒过期后重新握手', () async {
    await report(startQuery());
    expect(adapter.requests.length, 3);

    clockMs += 1799 * 1000;
    await report(startQuery(song: 2));
    expect(adapter.requests.length, 4, reason: '未过期：只发上报请求');

    clockMs += 1000;
    await report(startQuery(song: 3));
    expect(adapter.requests.length, 7, reason: 'expires == now 即过期：重新握手');
    expect(adapter.requests[4].path, qrydidUrl);
    expect(adapter.requests[5].path, genUrl);
    expect(adapter.requests[6].path, postUrl);
  });

  test('上报失败清缓存：下一次上报重新握手', () async {
    adapter.on(postUrl, jsonBytes('{"status":0,"errcode":1203}'));
    await expectLater(report(startQuery()), throwsBusiness(1203));
    expect(adapter.requests.length, 3);

    adapter.on(postUrl, postOkResponse());
    await report(startQuery());
    expect(adapter.requests.length, 6);
    expect(adapter.requests[3].path, qrydidUrl);
    expect(adapter.requests[5].path, postUrl);
  });

  test('握手失败不缓存：下一次上报完整重来', () async {
    adapter.on(
      genUrl,
      jsonBytes('{"status":1,"errcode":0,"data":"not+base64!"}'),
    );
    await expectLater(
      report(startQuery()),
      throwsA(
        isA<KugouApiException>().having(
          (error) => error.kind,
          'kind',
          'decode',
        ),
      ),
    );
    expect(adapter.requests.length, 2);

    adapter.on(genUrl, genOkResponse(listenReportEntropyHex, listenReportUuid));
    await report(startQuery());
    expect(adapter.requests.length, 5);
    expect(adapter.requests[2].path, qrydidUrl);
    expect(adapter.requests[4].path, postUrl);
  });

  test('并发上报合并初始化：两路并发只握手一次', () async {
    final first = report(startQuery(song: 1));
    final second = report(startQuery(song: 2));
    final results = await Future.wait(<Future<MusicListenReportAcceptance>>[
      first,
      second,
    ]);

    expect(results.map((value) => value.accepted), everyElement(isTrue));
    expect(adapter.requests.length, 4);
    expect(adapter.requests[0].path, qrydidUrl);
    expect(adapter.requests[3].path, postUrl);
  });

  test('缓存 key 按身份派生：换账号后重新握手', () async {
    await report(startQuery());
    expect(adapter.requests.length, 3);

    useIdentity(copyIdentity(listenReportIdentity(), userId: 43));
    await report(startQuery());
    expect(adapter.requests.length, 6, reason: '新身份 → 新 key → 重新握手');
    expect(adapter.requests[3].path, qrydidUrl);
  });

  test('purgeExpired：expires > now 保留，等于/早于 now 清除', () {
    final cache = MusicListenReportSessionCache();
    final base = DateTime.fromMillisecondsSinceEpoch(
      1700000000000,
      isUtc: true,
    );
    MusicListenReportSession sessionAt(int seconds) => MusicListenReportSession(
      cookie: 'c$seconds',
      clienttime: 0,
      serverstr: 's',
      seed: 'seed',
      expiresAt: base.add(Duration(seconds: seconds)),
    );
    cache
      ..put('early', sessionAt(-10))
      ..put('edge', sessionAt(0))
      ..put('later', sessionAt(10));
    cache.purgeExpired(base);
    expect(cache.get('early'), isNull);
    expect(cache.get('edge'), isNull);
    expect(cache.get('later'), isNotNull);
  });

  test('容量 256：超限淘汰最早过期的条目', () {
    final cache = MusicListenReportSessionCache();
    final base = DateTime.fromMillisecondsSinceEpoch(
      1700000000000,
      isUtc: true,
    );
    MusicListenReportSession sessionAt(int seconds) => MusicListenReportSession(
      cookie: 'c$seconds',
      clienttime: 0,
      serverstr: 's',
      seed: 'seed',
      expiresAt: base.add(Duration(seconds: seconds)),
    );
    for (var index = 0; index < 256; index++) {
      cache.put('k$index', sessionAt(index));
    }
    cache.put('new', sessionAt(100000));
    expect(cache.get('k0'), isNull, reason: '最早过期者被淘汰');
    expect(cache.get('k1'), isNotNull);
    expect(cache.get('new'), isNotNull);

    cache.put('new2', sessionAt(200000));
    expect(cache.get('k1'), isNull, reason: '再次淘汰当前最早过期者');
    expect(cache.get('new'), isNotNull);
    expect(cache.get('new2'), isNotNull);
  });

  test('KugouListenReportApi：组接口实例私有缓存，两实例互不影响', () async {
    final MusicListenReportApi api = KugouListenReportApi(session);
    await api.listenReport(startQuery(song: 1), clock: clock, random: random);
    await api.listenReport(startQuery(song: 2), clock: clock, random: random);
    expect(adapter.requests.length, 4, reason: '同实例第二次复用握手');

    final api2 = KugouListenReportApi(session);
    await api2.listenReport(startQuery(song: 3), clock: clock, random: random);
    expect(adapter.requests.length, 7, reason: '新实例缓存为空：重新握手');
    expect(adapter.requests[4].path, qrydidUrl);
    expect(adapter.requests[6].path, postUrl);
  });
}
