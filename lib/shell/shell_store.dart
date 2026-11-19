import 'package:mimao/core/contract.dart';
import 'package:mobx/mobx.dart';

part 'shell_store.g.dart';

/// 壳级状态（demo 02 ShellStore 的升级版；拍板项 2 临时决定：接受 MobX）。
///
/// 壳不碰任何业务，只记"现在在哪个入口 / 是否打开设置"这类导航态。
class ShellStore = _ShellStore with _$ShellStore;

abstract class _ShellStore with Store {
  /// null = 入口拼贴页；非 null = 已钻进该模块层（另外三个入口消失）。
  @observable
  MediaType? activeModule;

  /// 统一书架/"我的"时间线页——入口页顶栏进入（放置方式仍待拍板，暂定顶栏入口）。
  @observable
  bool showLibrary = false;

  @observable
  bool settingsOpen = false;

  /// MD3 种子色：基础色板名（violet/green/ochre/blue/rose/teal/orange/slate），
  /// 或动态取色写入的 "dyn:<8 位 ARGB hex>"。解析见 MimaoApp.seed。
  @observable
  String themeSeed = 'violet';

  /// 系统强调色变化计数：每次系统色变就 ++，供 MimaoApp 的 Observer 建立
  /// 重建依赖（读一次即订阅），从而在 'system' 模式下重新取色。
  @observable
  int systemAccentEpoch = 0;

  @computed
  bool get onEntryPage => activeModule == null && !showLibrary;

  @action
  void openModule(MediaType type) {
    activeModule = type;
    showLibrary = false;
    settingsOpen = false;
  }

  @action
  void openLibrary() {
    showLibrary = true;
    activeModule = null;
    settingsOpen = false;
  }

  @action
  void goHome() {
    activeModule = null;
    showLibrary = false;
  }

  @action
  void openSettings() => settingsOpen = true;

  @action
  void closeSettings() => settingsOpen = false;

  @action
  void setThemeSeed(String seed) => themeSeed = seed;

  /// 系统强调色变化：递增 epoch 触发主题重建（MimaoApp 的 Observer 订阅它）。
  @action
  void bumpSystemAccent() => systemAccentEpoch++;
}

/// 最简做法：全局单例。Kazumi 用 flutter_modular 做 DI，M1 不需要（拍板项 3）。
final shellStore = ShellStore();
