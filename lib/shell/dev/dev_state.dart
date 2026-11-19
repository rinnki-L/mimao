import 'package:mimao/core/contract.dart';
import 'package:mimao/shell/app_registry.dart';
import 'package:mimao/shell/dev/dev_databases.dart';
import 'package:mimao/shell/shell_store.dart';

/// `/state` 端点快照：壳级导航态 + 模块注册表 + 可查库名。
///
/// 「现在 app 停在哪」的权威来源是 [shellStore]（壳的模块切换不走 Navigator）；
/// Navigator 层的栈深另见 /route（dev_route.dart）。模块内部 store 不在此列——
/// 那需要 import 模块目录，违反铁律④；模块态数据走 /db SQL 直查。
Map<String, Object?> devStateSnapshot() => <String, Object?>{
  'shell': <String, Object?>{
    'activeModule': shellStore.activeModule?.name,
    'showLibrary': shellStore.showLibrary,
    'settingsOpen': shellStore.settingsOpen,
    'themeSeed': shellStore.themeSeed,
    'onEntryPage': shellStore.onEntryPage,
  },
  'modules': <String, Object?>{
    for (final MediaType type in MediaType.values)
      type.name: appModules.containsKey(type),
  },
  'modulesError': appModulesError,
  'databases': devDatabaseNames(),
};
