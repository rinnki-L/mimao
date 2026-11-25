// 主题包：往返一致、版本校验（过高/非法/缺字段）、预览图容错、差异摘要。
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/reader/novel_click_actions.dart';
import 'package:mimao/novel/reader/novel_keyboard_assist.dart';
import 'package:mimao/novel/reader/novel_reader_settings.dart';
import 'package:mimao/novel/theme/novel_theme_package.dart';

const _settings = NovelReaderSettings(
  fontSize: 24,
  fontFamily: 'SimSun',
  lineHeight: 2.0,
  paragraphSpacing: 16,
  backgroundIndex: 3,
  pageMode: NovelPageMode.page,
  pageAnimStyle: NovelPageAnimStyle.fade,
  letterSpacing: 1.2,
  indentCount: 0,
  chineseConvert: NovelChineseConvert.simplifiedToTraditional,
  twoColumn: true,
  titleMode: NovelTitleMode.center,
);

void main() {
  test('往返：设置逐字段一致、键位与预览图都保留', () {
    final png = Uint8List.fromList(<int>[137, 80, 78, 71, 1, 2, 3]);
    final pack = NovelThemePackage(
      name: '羊皮纸 · 大字',
      settings: _settings,
      exportedAt: DateTime.utc(2026, 11, 25, 8, 30),
      keyBindings: const <NovelKeyboardBinding>[
        NovelKeyboardBinding(keys: 'F5', action: NovelClickAction.catalog),
      ],
      previewPng: png,
    );
    final decoded = NovelThemePackage.decode(pack.encode());
    expect(decoded.name, '羊皮纸 · 大字');
    expect(decoded.version, novelThemePackageVersion);
    expect(decoded.settings.toJson(), _settings.toJson());
    expect(decoded.exportedAt, DateTime.utc(2026, 11, 25, 8, 30));
    expect(decoded.keyBindings.single.keys, 'F5');
    expect(decoded.keyBindings.single.action, NovelClickAction.catalog);
    expect(decoded.previewPng, png);
  });

  test('导出可关闭预览图与键位', () {
    final pack = NovelThemePackage(
      name: 'x',
      settings: _settings,
      keyBindings: const <NovelKeyboardBinding>[
        NovelKeyboardBinding(keys: 'F5', action: NovelClickAction.catalog),
      ],
      previewPng: Uint8List.fromList(<int>[1, 2]),
    );
    final slim = NovelThemePackage.decode(
      pack.encode(includePreview: false, includeKeyBindings: false),
    );
    expect(slim.previewPng, isNull);
    expect(slim.keyBindings, isEmpty);
  });

  test('包版本高于当前支持版本 → 拒绝并给出可读提示', () {
    final json =
        jsonDecode(NovelThemePackage(name: '新', settings: _settings).encode())
            as Map<String, dynamic>;
    json['version'] = novelThemePackageVersion + 1;
    try {
      NovelThemePackage.decode(jsonEncode(json));
      fail('应该抛出版本不兼容');
    } on NovelThemePackageException catch (error) {
      expect(error.error, NovelThemePackageError.versionTooNew);
      expect(error.foundVersion, novelThemePackageVersion + 1);
      expect(error.message, contains('v${novelThemePackageVersion + 1}'));
      expect(error.message, contains('升级应用'));
    }
  });

  test('版本号非法 / 缺失 → 拒绝', () {
    final base =
        jsonDecode(NovelThemePackage(name: 'x', settings: _settings).encode())
            as Map<String, dynamic>;

    final zero = Map<String, dynamic>.from(base)..['version'] = 0;
    expect(
      () => NovelThemePackage.decode(jsonEncode(zero)),
      throwsA(
        isA<NovelThemePackageException>().having(
          (e) => e.error,
          'error',
          NovelThemePackageError.versionTooOld,
        ),
      ),
    );

    final missing = Map<String, dynamic>.from(base)..remove('version');
    expect(
      () => NovelThemePackage.decode(jsonEncode(missing)),
      throwsA(
        isA<NovelThemePackageException>().having(
          (e) => e.error,
          'error',
          NovelThemePackageError.corrupt,
        ),
      ),
    );
  });

  test('不是主题包 / 坏 JSON / 缺 settings 都有各自的错误类型', () {
    expect(
      () => NovelThemePackage.decode('{bad json'),
      throwsA(
        isA<NovelThemePackageException>().having(
          (e) => e.error,
          'error',
          NovelThemePackageError.notJson,
        ),
      ),
    );
    expect(
      () => NovelThemePackage.decode('{"version":1,"settings":{}}'),
      throwsA(
        isA<NovelThemePackageException>().having(
          (e) => e.error,
          'error',
          NovelThemePackageError.notTheme,
        ),
      ),
    );
    expect(
      () => NovelThemePackage.decode(
        '{"format":"$novelThemePackageFormat","version":1}',
      ),
      throwsA(
        isA<NovelThemePackageException>().having(
          (e) => e.error,
          'error',
          NovelThemePackageError.corrupt,
        ),
      ),
    );
  });

  test('坏预览图 / 坏键位条目不影响设置解析', () {
    final text = jsonEncode(<String, Object?>{
      'format': novelThemePackageFormat,
      'version': 1,
      'name': '  ',
      'settings': const NovelReaderSettings(fontSize: 22).toJson(),
      'preview': <String, Object?>{'mime': 'image/png', 'data': '!!!'},
      'keyBindings': <Object?>[
        <String, Object?>{'keys': 'F5', 'action': 'not-an-action'},
        <String, Object?>{'keys': 'F6', 'action': 'catalog'},
      ],
    });
    final pack = NovelThemePackage.decode(text);
    expect(pack.name, '未命名主题');
    expect(pack.settings.fontSize, 22);
    expect(pack.previewPng, isNull);
    expect(pack.keyBindings.single.keys, 'F6');
  });

  test('差异摘要：一致为空，改动项按中文名列', () {
    expect(describeNovelThemeDifferences(_settings, _settings), isEmpty);
    final next = _settings.copyWith(fontSize: 30, backgroundIndex: 5);
    final diff = describeNovelThemeDifferences(_settings, next);
    expect(diff, contains('字号'));
    expect(diff, contains('背景'));
    expect(diff.length, 2);
  });

  test('旧包缺字段按设置默认值兜底（不因缺键失败）', () {
    final text = jsonEncode(<String, Object?>{
      'format': novelThemePackageFormat,
      'version': 1,
      'name': '旧包',
      'settings': <String, Object?>{'fontSize': 18},
    });
    final pack = NovelThemePackage.decode(text);
    expect(pack.settings.fontSize, 18);
    expect(pack.settings.pageMode, NovelPageMode.scroll);
    expect(pack.keyBindings, isEmpty);
  });
}
