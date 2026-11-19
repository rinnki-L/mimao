/// 播放线边界哨兵：`lib/music` 不得 import `package:mimao/anime`（铁律②）。
///
/// `test/architecture/boundary_test.dart` 只拦跨模块目录的 import 目标；
/// 播放器接口与番剧刻意重复，这里额外断言播放线没有图省事去借用 anime 内核。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('lib/music 不 import package:mimao/anime', () {
    final offenders = <String>[];
    final root = Directory('lib/music');
    expect(root.existsSync(), isTrue, reason: '哨兵必须在仓库根运行');
    for (final entity in root.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      if (source.contains('package:mimao/anime')) {
        offenders.add(entity.path);
      }
    }
    expect(offenders, isEmpty, reason: '播放线必须自持内核，不得 import anime');
  });
}
