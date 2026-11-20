// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 但 Kazumi/Venera 上游镜像全部用它；为保持类型一致与 patch 可重放，M1 继续用。
// 最小公共词表契约测试：壳靠这张表渲染，不认识任何模块内部类型。
// 顺带覆盖 MediaTypeX 的 getter（demo 01/02 的行为在此固化）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/core/contract.dart';

void main() {
  test('三种媒体的 label / icon / tagline 齐全且非空', () {
    for (final type in MediaType.values) {
      expect(type.label, isNotEmpty);
      expect(type.icon, isA<IconData>());
      expect(type.outlinedIcon, isA<IconData>());
      expect(type.tagline, isNotEmpty);
    }
  });

  test('label 映射固定（界面文案不可随意漂移）', () {
    expect(MediaType.comic.label, '漫画');
    expect(MediaType.novel.label, '小说');
    expect(MediaType.music.label, '音乐');
  });
}
