// 阅读设置序列化：新增字段（自动版式 / 条漫边距）能往返，坏数据回退默认。

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/comic/reader/reader_settings.dart';

void main() {
  test('autoLayout / sideMargin 往返保留', () {
    const settings = ReaderSettings(
      autoLayout: true,
      sideMargin: 18,
      preloadCount: 5,
    );
    final restored = ReaderSettings.deserialize(settings.serialize());
    expect(restored.autoLayout, isTrue);
    expect(restored.sideMargin, 18);
    expect(restored.preloadCount, 5);
  });

  test('旧版设置没有 autoLayout 时按关闭处理', () {
    final restored = ReaderSettings.deserialize(
      '{"mode":"galleryLeftToRight"}',
    );
    expect(restored.autoLayout, isFalse);
    expect(restored.sideMargin, 0);
  });

  test('越界边距被钳制', () {
    final restored = ReaderSettings.deserialize('{"sideMargin":99}');
    expect(restored.sideMargin, 30);
  });
}
