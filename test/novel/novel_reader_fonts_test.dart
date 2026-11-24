// 导入字体仓库：目录布局、导入复制、FontLoader 注册、坏文件容错。
//
// 用临时目录走 [NovelFontRegistry] 的 directory 覆盖，不碰 path_provider 插件。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/reader/novel_reader_fonts.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late NovelFontRegistry registry;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('novel_fonts_');
    registry = NovelFontRegistry(directory: p.join(temp.path, 'reader_fonts'));
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('空目录返回空列表，不抛异常', () async {
    expect(await registry.list(), isEmpty);
  });

  test('导入复制字体文件，列表按文件名给出 family', () async {
    final source = File(p.join(temp.path, 'MyFont.ttf'));
    await source.writeAsBytes(<int>[0, 1, 2, 3]);

    final imported = await registry.importFile(source.path);
    expect(imported, isNotNull);
    expect(imported!.family, 'MyFont');
    expect(imported.label, 'MyFont');

    final dir = await registry.fontDirectory();
    expect(dir, isNotNull);
    // 文件确实落在字体目录里（而不是原地引用）。
    expect(File(p.join(dir!.path, 'MyFont.ttf')).existsSync(), isTrue);

    final listed = await registry.list();
    expect(listed.map((font) => font.family), contains('MyFont'));
  });

  test('非字体扩展名不进列表', () async {
    final dir = await registry.fontDirectory();
    await File(p.join(dir!.path, 'note.txt')).writeAsString('hi');
    await File(p.join(dir.path, 'real.otf')).writeAsBytes(<int>[0]);

    final listed = await registry.list();
    expect(listed.map((font) => font.family), <String>['real']);
  });

  test('源文件不存在时导入返回 null', () async {
    expect(await registry.importFile(p.join(temp.path, 'missing.ttf')), isNull);
  });

  test('目录只落在支持目录下的 reader_fonts（不再多拼一层 mimao）', () async {
    // 这是曾经的真 bug：拼成 mimao/mimao/reader_fonts，别的代码按兄弟目录
    // 读写就永远看不到导入的字体。
    final dir = await registry.fontDirectory();
    expect(dir, isNotNull);
    expect(p.basename(dir!.path), 'reader_fonts');
    // 上一级就是测试给的临时根（不是再套一层同名目录）。
    expect(p.dirname(dir.path), p.normalize(temp.path));
  });
}
