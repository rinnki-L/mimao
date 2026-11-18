/// 身份快照/仓库测试——calculateMid 黄金值用独立 Python（hashlib + int(hex,16)）
/// 交叉计算；仓库走临时目录（无插件依赖）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/client/kugou_identity.dart';

void main() {
  test('calculateMid：MD5 hex → 十进制大整数（Node calculateMid 同构）', () {
    expect(
      kugouCalculateMid('550e8400-e29b-41d4-a716-446655440000'),
      '308741372901437977228425563242293240765',
    );
    // 交叉验证：md5 hex 已单独核对（Python hashlib）。
    expect(
      kugouCalculateMid('550e8400-e29b-41d4-a716-446655440000'),
      BigInt.parse('e8456cee7fd2348cfa239342b10a23bd', radix: 16).toString(),
    );
  });

  test('guid：UUID v4 形状（版本位 4、变体位 8/9/a/b）', () {
    final guid = kugouNewGuid();
    expect(
      RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      ).hasMatch(guid),
      isTrue,
      reason: '实际值：$guid',
    );
  });

  test('匿名身份：mid = calculateMid(guid)，dfid 占位为 -，mac 沿上游常量', () {
    final identity = KugouIdentity.anonymous();
    expect(identity.mid, kugouCalculateMid(identity.guid));
    expect(identity.dfid, '-');
    expect(identity.uuid, '-');
    expect(identity.mac, '02:00:00:00:00:00');
    expect(identity.hasAccount, isFalse);
    expect(identity.isUsable, isTrue, reason: 'dfid=- 非空，可用');
    expect(identity.needsDeviceRegistration, isTrue);
  });

  test('身份可用性校验：mid/dfid 空、账号字段不一致都判不可用', () {
    KugouIdentity build({
      String mid = 'm',
      String dfid = 'd',
      int userId = 0,
      String token = '',
      String t1 = '',
    }) => KugouIdentity(
      userId: userId,
      token: token,
      t1: t1,
      mid: mid,
      dfid: dfid,
      uuid: '-',
      guid: 'g',
      mac: '',
      deviceName: '',
      renderFingerprint: '',
    );
    expect(build().isUsable, isTrue);
    expect(build(mid: '').isUsable, isFalse);
    expect(build(dfid: '').isUsable, isFalse);
    // userid=0 但 token 非空 → 不一致。
    expect(build(token: 't').isUsable, isFalse);
    // userid 非零但 token 空 → 不一致。
    expect(build(userId: 1).isUsable, isFalse);
    expect(build(userId: 1, token: 't').isUsable, isTrue);
    // userid=0 但残留 t1 → 不一致（Rust send_endpoint 断言）。
    expect(build(t1: 'stale').isUsable, isFalse);
  });

  test('withoutAccount 剥掉账号字段但保留设备字段', () {
    final base = KugouIdentity(
      userId: 42,
      token: 'tok',
      t1: 't1',
      mid: 'm',
      dfid: 'd',
      uuid: '-',
      guid: 'g',
      mac: '',
      deviceName: '',
      renderFingerprint: '',
    );
    final anonymous = base.withoutAccount();
    expect(anonymous.userId, 0);
    expect(anonymous.token, isEmpty);
    expect(anonymous.t1, isEmpty);
    expect(anonymous.guid, base.guid);
    expect(anonymous.dfid, base.dfid);
    expect(anonymous.mid, base.mid);
  });

  test('JSON roundtrip：字段无损', () {
    final identity = KugouIdentity.anonymous();
    final restored = KugouIdentity.fromJson(
      Map<String, Object?>.from(
        jsonDecode(jsonEncode(identity.toJson())) as Map,
      ),
    );
    expect(restored.userId, identity.userId);
    expect(restored.mid, identity.mid);
    expect(restored.dfid, identity.dfid);
    expect(restored.guid, identity.guid);
    expect(restored.mac, identity.mac);
  });

  test('身份仓库：save→load roundtrip；缺失/损坏容错为 null', () async {
    final dir = await Directory.systemTemp.createTemp('mimao_music_identity_');
    try {
      final store = KugouIdentityStore(dir);
      expect(await store.load(), isNull, reason: '未保存过');

      final identity = KugouIdentity.anonymous().withDfid('registered');
      await store.save(identity);
      final loaded = await store.load();
      expect(loaded!.dfid, 'registered');
      expect(loaded.guid, identity.guid);

      await store.delete();
      expect(await store.load(), isNull);
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('身份仓库：损坏文件容错为 null（不挡模块初始化）', () async {
    final dir = await Directory.systemTemp.createTemp('mimao_music_identity_');
    try {
      final store = KugouIdentityStore(dir);
      await Directory(dir.path).create(recursive: true);
      File(
        '${dir.path}${Platform.pathSeparator}music_identity.json',
      ).writeAsStringSync('{ not json');
      expect(await store.load(), isNull);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
