/// 快捷键动作的接收能力：由播放器 UI 实现（P 线）。
///
/// 刻意不往冻结的 [MusicPlayerUi] 契约里加方法——既有测试里有 5 个假实现，
/// 加方法会迫使它们全部补实现。这里用独立窄接口 + 运行时 cast：真播放器
/// 实现了就派发，测试假件没实现则快捷键静默无动作（不影响既有测试）。
library;

import 'package:mimao/music/hotkey/music_hotkey_model.dart';

abstract interface class MusicHotKeyActionHandler {
  /// 处理一个快捷键动作。
  Future<void> handleHotKeyAction(MusicHotKeyAction action);
}
