/// 音乐「我的」页的 MobX store（docs/architecture.md §5：music 自写 MobX）。
///
/// 刻意不并入既有 `MusicStore`（那是搜索结果状态），避免与播放线（P）冲突；
/// 本 store 只管收藏/历史两段列表与当前分段。
library;

import 'package:mimao/music/collect_service.dart';
import 'package:mimao/music/history_service.dart';
import 'package:mimao/music/library_api.dart';
import 'package:mobx/mobx.dart';

part 'music_library_store.g.dart';

class MusicLibraryStore = _MusicLibraryStore with _$MusicLibraryStore;

abstract class _MusicLibraryStore with Store {
  _MusicLibraryStore(this._collect, this._history);

  final MusicCollectService _collect;
  final MusicHistoryService _history;

  /// 收藏段（按收藏时间倒序）。
  @observable
  ObservableList<MusicCollectItem> collected =
      ObservableList<MusicCollectItem>();

  /// 历史段（按打开时间倒序）。
  @observable
  ObservableList<MusicHistoryItem> history = ObservableList<MusicHistoryItem>();

  @observable
  bool isLoading = false;

  /// 加载失败的展示文案；null 表示无错误。
  @observable
  String? error;

  /// 当前分段：0 = 收藏，1 = 历史。
  @observable
  int libraryTab = 0;

  /// 列表批量判断收藏态用（搜索页已有自己的缓存，这里供「我的」页复用）。
  @computed
  Set<String> get collectedIds => <String>{
    for (final item in collected) item.ref.id,
  };

  @computed
  bool get isEmpty => collected.isEmpty && history.isEmpty;

  @action
  void selectTab(int index) {
    libraryTab = index;
  }

  @action
  Future<void> refresh() async {
    // 已有数据时静默刷新（播放中每 10 秒进度通知会触发），不闪 loading 占位。
    final hadData = collected.isNotEmpty || history.isNotEmpty;
    if (!hadData) isLoading = true;
    error = null;
    try {
      final collectItems = await _collect.list();
      final historyItems = await _history.recent();
      collected
        ..clear()
        ..addAll(collectItems);
      history
        ..clear()
        ..addAll(historyItems);
    } on Object catch (e) {
      error = '加载失败：$e';
    } finally {
      isLoading = false;
    }
  }
}
