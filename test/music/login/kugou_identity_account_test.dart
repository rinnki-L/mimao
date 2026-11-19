/// 身份账号字段测试：withAccount/withoutAccount、旧 JSON 兼容、仓库往返。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/client/kugou_identity.dart';

void main() {
  test('withAccount 只改账号字段，设备字段逐项保留', () {
    final device = KugouIdentity.anonymous().withDfid('dfid-1');
    final account = device.withAccount(
      userId: 42,
      token: 'token-value',
      nickname: '小明',
      avatarUrl: 'https://img/avatar.png',
    );

    expect(account.userId, 42);
    expect(account.token, 'token-value');
    expect(account.t1, isEmpty);
    expect(account.nickname, '小明');
    expect(account.avatarUrl, 'https://img/avatar.png');
    expect(account.hasAccount, isTrue);
    expect(account.isUsable, isTrue);
    expect(account.guid, device.guid);
    expect(account.mid, device.mid);
    expect(account.dfid, device.dfid);
    expect(account.uuid, device.uuid);
    expect(account.mac, device.mac);
    expect(account.deviceName, device.deviceName);
    expect(account.renderFingerprint, device.renderFingerprint);
  });

  test('accountLabel：有昵称用昵称，否则回退用户 id', () {
    final base = KugouIdentity.anonymous();
    expect(base.accountLabel, '用户 0');
    final anonymous = base.withAccount(userId: 7, token: 't');
    expect(anonymous.accountLabel, '用户 7');
    final named = base.withAccount(userId: 7, token: 't', nickname: '阿七');
    expect(named.accountLabel, '阿七');
  });

  test('withoutAccount 同时清空 nickname/avatarUrl，保留设备字段', () {
    final account = KugouIdentity.anonymous()
        .withDfid('dfid-1')
        .withAccount(
          userId: 42,
          token: 't',
          t1: 't1-value',
          nickname: '小明',
          avatarUrl: 'https://img/avatar.png',
        );
    final anonymous = account.withoutAccount();
    expect(anonymous.userId, 0);
    expect(anonymous.token, isEmpty);
    expect(anonymous.t1, isEmpty);
    expect(anonymous.nickname, isEmpty);
    expect(anonymous.avatarUrl, isEmpty);
    expect(anonymous.hasAccount, isFalse);
    expect(anonymous.isUsable, isTrue);
    expect(anonymous.guid, account.guid);
    expect(anonymous.mid, account.mid);
    expect(anonymous.dfid, account.dfid);
  });

  test('JSON：账号字段往返无损；旧版无 nickname/avatarUrl 键仍可读', () {
    final account = KugouIdentity.anonymous().withAccount(
      userId: 42,
      token: 't',
      nickname: '小明',
      avatarUrl: 'https://img/avatar.png',
    );
    final restored = KugouIdentity.fromJson(
      Map<String, Object?>.from(
        jsonDecode(jsonEncode(account.toJson())) as Map,
      ),
    );
    expect(restored.userId, 42);
    expect(restored.token, 't');
    expect(restored.nickname, '小明');
    expect(restored.avatarUrl, 'https://img/avatar.png');

    // 骨架期写入的身份文件没有这两个键。
    final legacy = KugouIdentity.fromJson(<String, Object?>{
      'userId': 0,
      'token': '',
      't1': '',
      'mid': 'm',
      'dfid': 'd',
      'uuid': '-',
      'guid': 'g',
      'mac': '',
      'deviceName': '',
      'renderFingerprint': '',
    });
    expect(legacy.nickname, isEmpty);
    expect(legacy.avatarUrl, isEmpty);
    expect(legacy.isUsable, isTrue);
  });

  test('身份仓库：账号字段落盘后可读回', () async {
    final dir = await Directory.systemTemp.createTemp('mimao_music_identity_');
    try {
      final store = KugouIdentityStore(dir);
      final account = KugouIdentity.anonymous().withAccount(
        userId: 42,
        token: '{{SECRET_ck8ixm0t}}',
        nickname: '小明',
        avatarUrl: 'https://img/avatar.png',
      );
      await store.save(account);
      final loaded = await store.load();
      expect(loaded!.userId, 42);
      expect(loaded.token, account.token);
      expect(loaded.nickname, '小明');
      expect(loaded.avatarUrl, 'https://img/avatar.png');
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
