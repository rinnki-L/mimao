/// 签名黄金向量——期望值由独立 Python 实现（hashlib.md5，与 Dart crypto 包
/// 无共享代码）计算生成，交叉验证 signature.rs 的逐函数翻译。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/client/signature.dart';

void main() {
  test('android：排序 key=value 连接 + 双 salt 包夹（空 body）', () {
    final signature = kugouSignatureAndroid(<String, String>{
      'page': '1',
      'clientver': '11440',
      'appid': '3116',
    }, const <int>[]);
    expect(signature, 'caedc9175097a61c25210db7c4d24f03');
  });

  test('android：中文值按 UTF-8 字节参与签名', () {
    final signature = kugouSignatureAndroid(<String, String>{
      'keyword': '周杰伦',
      'page': '1',
      'pagesize': '30',
      'appid': '3116',
    }, const <int>[]);
    expect(signature, 'b91c53a9f8639497f94db92381733552');
  });

  test('android：body 按实际发送字节参与签名', () {
    final signature = kugouSignatureAndroid(<String, String>{
      'mid': '00000000000000000000000000000000',
      'clienttime': '1700000000',
      'appid': '3116',
    }, '{"a":1}'.codeUnits);
    expect(signature, '73f7d73a1bf4ad5615be9707e42586df');
  });

  test('web：不同 salt 同字节序', () {
    final signature = kugouSignatureWeb(<String, String>{
      'clientver': '11440',
      'appid': '3116',
    }, const <int>[]);
    expect(signature, 'a658fb6460a2bcdfb16c7ff8c195ac1d');
  });

  test('album_cover：CDN salt', () {
    final signature = kugouSignatureAlbumCover(<String, String>{
      'album_audio_id': '12345',
    });
    expect(signature, '3227098bd09c7746a1b44dc498e7b8d4');
  });

  test('tracker_key：hash + lite salt + mid + userid 串接', () {
    expect(
      kugouTrackerKey(
        'ABCDEF0123456789',
        '12345678901234567890123456789012',
        42,
      ),
      '8c4269fdaa3e5e5f98b72e962b7b839c',
    );
  });

  test('cloud_key：云盘 salt', () {
    expect(
      kugouCloudKey('ABCDEF0123456789'),
      'c08c28c8e84d6df2711ec5fc7d51eaa2',
    );
  });
}
