// 首页模块配置：默认排布、开关、排序、增删、旧配置补齐与坏数据回落。
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/home/home_module_config.dart';

void main() {
  test('默认配置等于改造前首页排布且全部启用', () {
    const config = NovelHomeModuleConfig(NovelHomeModuleConfig.defaults);
    expect(config.modules.map((m) => m.kind).toList(), <NovelHomeModuleKind>[
      NovelHomeModuleKind.recent,
      NovelHomeModuleKind.stats,
      NovelHomeModuleKind.goal,
      NovelHomeModuleKind.source,
      NovelHomeModuleKind.capability,
      NovelHomeModuleKind.shelfStrip,
      NovelHomeModuleKind.webdav,
    ]);
    expect(config.enabledModules, hasLength(7));
  });

  test('开关与排序往返一致', () {
    var config = const NovelHomeModuleConfig(NovelHomeModuleConfig.defaults);
    config = config.setEnabled('stats', false);
    config = config.move(0, 3);
    final decoded = NovelHomeModuleConfig.decode(config.encode());
    expect(decoded.modules.first.kind, NovelHomeModuleKind.stats);
    expect(decoded.modules.first.enabled, isFalse);
    expect(decoded.enabledModules, hasLength(6));
    expect(decoded.indexOf('stats'), 0);
  });

  test('自定义分组卡片可多张、按分组去重、可删', () {
    var config = const NovelHomeModuleConfig(NovelHomeModuleConfig.defaults);
    config = config.addCustomGroup('科幻');
    config = config.addCustomGroup('武侠');
    config = config.addCustomGroup('科幻');
    final custom = config.modules
        .where((m) => m.kind == NovelHomeModuleKind.customGroup)
        .toList();
    expect(custom, hasLength(2));
    expect(custom.map((m) => m.groupName).toList(), <String>['科幻', '武侠']);

    config = config.removeModule(custom.first.id);
    expect(
      config.modules.where((m) => m.kind == NovelHomeModuleKind.customGroup),
      hasLength(1),
    );

    // 内置模块不可删。
    expect(
      config.removeModule('recent').modules,
      hasLength(config.modules.length),
    );
    expect(
      config.removeModule('does-not-exist').modules,
      hasLength(config.modules.length),
    );
  });

  test('空白分组名不建卡片', () {
    var config = const NovelHomeModuleConfig(NovelHomeModuleConfig.defaults);
    expect(config.addCustomGroup('   ').modules, hasLength(7));
  });

  test('旧配置缺模块时补齐到末尾', () {
    final decoded = NovelHomeModuleConfig.decode(
      '{"modules":[{"kind":"recent"},{"kind":"goal","enabled":false}]}',
    );
    expect(decoded.modules.first.kind, NovelHomeModuleKind.recent);
    expect(decoded.modules[1].kind, NovelHomeModuleKind.goal);
    expect(decoded.modules[1].enabled, isFalse);
    expect(decoded.modules, hasLength(7));
  });

  test('未知模块与无分组的自定义卡被丢弃，坏 JSON 回默认', () {
    final decoded = NovelHomeModuleConfig.decode(
      '{"modules":[{"kind":"banner"},{"kind":"customGroup"}]}',
    );
    expect(decoded.modules, hasLength(7));
    expect(NovelHomeModuleConfig.decode('{oops').modules, hasLength(7));
    expect(NovelHomeModuleConfig.decode(null).modules, hasLength(7));
  });

  test('move 越界不改变配置', () {
    const config = NovelHomeModuleConfig(NovelHomeModuleConfig.defaults);
    expect(config.move(-1, 2).modules, config.modules);
    expect(config.move(99, 2).modules, config.modules);
    expect(config.move(2, 2).modules, config.modules);
  });
}
