/// 歌单封面上传端点测试：PNG 帧校验、日期校验和、裸 URL/头/参数、
/// IsSuccess 语义。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/playlist_pic_upload.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import 'package:mimao/music/models/playlist_write_models.dart';
import '../capture_adapter.dart';
import 'playlist_write_test_support.dart';

/// 合法 PNG 帧：8 字节签名 + IHDR 长度 13 + "IHDR" + 补足到 ≥33 字节。
Uint8List validPng([int size = 40]) {
  final png = Uint8List(size)
    ..[0] = 0x89
    ..[1] =
        0x50 // P
    ..[2] =
        0x4E // N
    ..[3] =
        0x47 // G
    ..[4] = 0x0D
    ..[5] = 0x0A
    ..[6] = 0x1A
    ..[7] = 0x0A
    ..[11] =
        13 // IHDR 长度（大端）低字节
    ..[12] =
        0x49 // I
    ..[13] =
        0x48 // H
    ..[14] =
        0x44 // D
    ..[15] = 0x52; // R
  return png;
}

String checksumFor(String date) =>
    md5.convert(utf8.encode('${date}hewry678WEK23D')).toString();

void main() {
  test('装配：裸 HTTP 上传主机、四参数、octet-stream 头、body 为 PNG 原字节', () async {
    final png = validPng();
    final adapter = CaptureAdapter(
      jsonBytes('{"IsSuccess":1,"FileName":"20261121-abc_1.png"}'),
    );
    final session = fakePlaylistWriteSession(
      playlistWriteClient(adapter),
      KugouIdentity.anonymous(),
    );

    final cover = await fetchPlaylistPicUpload(
      session,
      PlaylistPicUploadQuery(png: png, localDate: '20261121'),
    );

    expect(cover.fileName, '20261121-abc_1.png');
    expect(cover.reference, 'custom/20261121-abc_1.png');

    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(
      request.path.startsWith('http://imgphp.kugou.com/imageupload/stream.php'),
      isTrue,
    );
    expect(request.data, png);
    expect(request.headers['Content-Type'], 'application/octet-stream');
    // 账号无关：无身份/设备默认头（上游 image_request 断言同款）。
    for (final header in [
      'authorization',
      'cookie',
      'mid',
      'dfid',
      'x-router',
    ]) {
      expect(request.headers.containsKey(header), isFalse, reason: header);
    }
    expect(request.query['type'], 'custom');
    expect(request.query['extendName'], '.png');
    expect(request.query['md5'], checksumFor('20261121'));
    expect(request.query['jsonResponse'], '1');
  });

  test('校验和按本地日历日计算（旧校验和用本地时间，不是 UTC）', () async {
    final adapter = CaptureAdapter(
      jsonBytes('{"IsSuccess":1,"FileName":"a.png"}'),
    );
    final session = fakePlaylistWriteSession(
      playlistWriteClient(adapter),
      KugouIdentity.anonymous(),
    );
    await fetchPlaylistPicUpload(
      session,
      PlaylistPicUploadQuery(png: validPng(), localDate: '20260101'),
    );
    expect(adapter.requests.single.query['md5'], checksumFor('20260101'));
  });

  test('PNG 帧校验：坏签名 / 过短 / 超 8MB / IHDR 长度错 → input', () async {
    final adapter = CaptureAdapter(
      jsonBytes('{"IsSuccess":1,"FileName":"a.png"}'),
    );
    final session = fakePlaylistWriteSession(
      playlistWriteClient(adapter),
      KugouIdentity.anonymous(),
    );

    Future<void> expectInput(Uint8List png) => expectLater(
      fetchPlaylistPicUpload(
        session,
        PlaylistPicUploadQuery(png: png, localDate: '20261121'),
      ),
      throwsA(kugouError('input')),
    );

    final badSignature = validPng()..[0] = 0x88;
    await expectInput(badSignature);
    await expectInput(Uint8List.fromList(validPng().sublist(0, 32)));
    await expectInput(Uint8List(8 * 1024 * 1024 + 1));
    final badIhdrLength = validPng()..[11] = 14;
    await expectInput(badIhdrLength);
    expect(adapter.requests, isEmpty);
  });

  test('localDate 非法 → input（校验和在帧校验之前）', () async {
    final adapter = CaptureAdapter(
      jsonBytes('{"IsSuccess":1,"FileName":"a.png"}'),
    );
    final session = fakePlaylistWriteSession(
      playlistWriteClient(adapter),
      KugouIdentity.anonymous(),
    );
    await expectLater(
      fetchPlaylistPicUpload(
        session,
        PlaylistPicUploadQuery(png: validPng(), localDate: '2026-11-21'),
      ),
      throwsA(kugouError('input')),
    );
    await expectLater(
      fetchPlaylistPicUpload(
        session,
        PlaylistPicUploadQuery(png: validPng(), localDate: '20261301'),
      ),
      throwsA(kugouError('input')),
    );
    expect(adapter.requests, isEmpty);
  });

  test('IsSuccess 语义：false → business；缺省/非法 → decode；字符串/数字宽容', () async {
    final session = fakePlaylistWriteSession(
      playlistWriteClient(
        CaptureAdapter(jsonBytes('{"IsSuccess":false,"FileName":"a.png"}')),
      ),
      KugouIdentity.anonymous(),
    );
    await expectLater(
      fetchPlaylistPicUpload(
        session,
        PlaylistPicUploadQuery(png: validPng(), localDate: '20261121'),
      ),
      throwsA(kugouError('business')),
    );

    Future<MusicUploadedPlaylistCover> upload(String body) =>
        fetchPlaylistPicUpload(
          fakePlaylistWriteSession(
            playlistWriteClient(CaptureAdapter(jsonBytes(body))),
            KugouIdentity.anonymous(),
          ),
          PlaylistPicUploadQuery(png: validPng(), localDate: '20261121'),
        );

    await expectLater(
      upload('{"FileName":"a.png"}'),
      throwsA(kugouError('decode')),
    );
    await expectLater(
      upload('{"IsSuccess":2,"FileName":"a.png"}'),
      throwsA(kugouError('decode')),
    );
    final fromText = await upload('{"IsSuccess":"true","FileName":123}');
    expect(fromText.fileName, '123');
    expect(fromText.reference, 'custom/123');
  });
}
