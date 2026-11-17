// 边界铁律哨兵（docs/architecture.md §2）——M1 的第一个测试。
//
// 扫描 lib/**/*.dart 的 import/export 目标，把四条"约定"变成机器断言。
// 不依赖 lint（上游镜像含相对导入，开 always_use_package_imports 会误伤一片）。
//
// 约定：本文与架构文档里的"模块目录"一律指 lib/anime、lib/comic、lib/music、
// lib/novel 四条具体路径；不存在 lib/modules/ 这一层（那是 Kazumi 的按域划分）。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const moduleDirs = <String>{'anime', 'comic', 'music', 'novel'};
const libRoot = 'lib';

void main() {
  final dartFiles = <_DartFile>[];

  setUpAll(() {
    final dir = Directory(libRoot);
    if (!dir.existsSync()) {
      fail('找不到 $libRoot/ 目录——哨兵必须在仓库根运行');
    }
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is File && p.extension(entity.path) == '.dart') {
        final rel = p.relative(entity.path, from: libRoot);
        dartFiles.add(_DartFile(rel: rel, source: entity.readAsStringSync()));
      }
    }
    expect(dartFiles, isNotEmpty, reason: 'lib/ 下没有 dart 文件');
  });

  group('四条铁律', () {
    test('① core/ 永不 import shell/ 与四个模块目录', () {
      _assertNoImports(
        dartFiles,
        (area) => area == 'core',
        forbidden: {'shell', ...moduleDirs},
        law: '①',
      );
    });

    test('② 四个模块目录互不 import', () {
      for (final file in dartFiles) {
        final area = _areaOf(file.rel);
        if (!moduleDirs.contains(area)) continue;
        for (final target in _importAreas(file)) {
          expect(
            moduleDirs.contains(target) && target != area,
            isFalse,
            reason: '铁律②：${file.rel}（$area）不得 import 模块 $target',
          );
        }
      }
    });

    test('③ 四个模块目录不 import shell/（只准 import core/）', () {
      _assertNoImports(
        dartFiles,
        (area) => moduleDirs.contains(area),
        forbidden: {'shell'},
        law: '③',
      );
    });

    test('④ shell/ 中仅 app_registry.dart 允许 import 四个模块目录', () {
      for (final file in dartFiles) {
        if (_areaOf(file.rel) != 'shell') continue;
        final importsModules = _importAreas(file).any(moduleDirs.contains);
        if (importsModules) {
          expect(
            p.normalize(file.rel),
            p.normalize('shell/app_registry.dart'),
            reason:
                '铁律④：只有 shell/app_registry.dart 能 import 模块，'
                '但 ${file.rel} 也 import 了；请改走 app_registry 查表',
          );
        }
      }
    });
  });

  test('lib/ 根一眼装得下（终态 ≤6 目录 + 1 文件；M1 仅 shell/core/main.dart）', () {
    final top = Directory(libRoot)
        .listSync()
        .where(
          (e) =>
              e is Directory || (e is File && p.extension(e.path) == '.dart'),
        )
        .map((e) => p.basename(e.path))
        .toSet();
    expect(top, containsAll(<String>{'shell', 'core', 'main.dart'}));
    expect(
      top.length,
      lessThanOrEqualTo(7),
      reason:
          'lib/ 根出现超出预期的顶层项：$top——按「少一层是一层」纪律，'
          '新目录只能对应一个里程碑',
    );
  });
}

/// 对 area 命中的文件断言：其 import 目标不含 forbidden 中任一项。
void _assertNoImports(
  List<_DartFile> files,
  bool Function(String area) select, {
  required Set<String> forbidden,
  required String law,
}) {
  for (final file in files) {
    final area = _areaOf(file.rel);
    if (!select(area)) continue;
    for (final target in _importAreas(file)) {
      expect(
        forbidden.contains(target),
        isFalse,
        reason: '铁律$law：${file.rel}（$area）不得 import $target',
      );
    }
  }
}

/// 把一条 import URI 解析成 lib/ 下的顶层区域名（core/shell/anime/…或 '(root)'/'(外部)'）。
String _targetArea(_DartFile file, String uri) {
  if (uri.startsWith('dart:')) return '(外部)';
  const pkg = 'package:mimao/';
  late String path;
  if (uri.startsWith(pkg)) {
    path = uri.substring(pkg.length);
  } else if (uri.startsWith('package:')) {
    return '(外部)';
  } else {
    // 相对导入：相对该文件在 lib/ 下的位置解析
    path = p.normalize(p.join(p.dirname(file.rel), uri));
  }
  if (path.startsWith('../') || path == '..') return '(外部)';
  final segments = p.split(path);
  return segments.isEmpty || segments.first.isEmpty ? '(root)' : segments.first;
}

/// 抽取一个文件所有 import/export 的顶层区域。part 指令是同库内文件，不参与边界。
Set<String> _importAreas(_DartFile file) {
  // 用 \x22 代表双引号：raw 字符串里直接写转义双引号会提前终止字符串（Dart 语法坑）。
  final re = RegExp(
    r"^\s*(?:import|export)\s+['\x22]([^'\x22]+)['\x22]",
    multiLine: true,
  );
  return re
      .allMatches(file.source)
      .map((m) => _targetArea(file, m.group(1)!))
      .toSet();
}

/// 文件在 lib/ 下的顶层区域；根目录的 main.dart 记为 '(root)'。
String _areaOf(String rel) {
  final segments = p.split(rel);
  return segments.length == 1 ? '(root)' : segments.first;
}

class _DartFile {
  final String rel;
  final String source;

  const _DartFile({required this.rel, required this.source});
}
