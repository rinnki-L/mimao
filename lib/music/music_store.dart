/// 音乐模块的 MobX store（docs/architecture.md §5：music 自写 MobX）。
///
/// 骨架期只管搜索链路：关键词 → [MusicApi.searchSongs] → 结果/错误态。
/// 歌单/播放队列/收藏等状态随后续切片在同文件生长。
library;

import 'package:mimao/music/api/music_api.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mobx/mobx.dart';

part 'music_store.g.dart';

class MusicStore = _MusicStore with _$MusicStore;

abstract class _MusicStore with Store {
  _MusicStore(this._api);

  final MusicApi _api;

  /// 搜索结果（每次搜索覆盖；骨架期不做追加分页，翻页随后续切片）。
  @observable
  ObservableList<MusicSong> results = ObservableList<MusicSong>();

  /// 最近一次成功搜索的关键词（回显用）。
  @observable
  String lastKeyword = '';

  @observable
  bool isLoading = false;

  /// 搜索失败的展示文案；null 表示无错误。
  @observable
  String? error;

  /// 是否已发起过至少一次搜索（区分「还没搜」与「搜到 0 条」）。
  @observable
  bool searched = false;

  @action
  Future<void> search(String keyword) async {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) return;
    isLoading = true;
    error = null;
    searched = true;
    try {
      final page = await _api.searchSongs(keyword: trimmed, page: 1);
      results.clear();
      results.addAll(page.items);
      lastKeyword = trimmed;
    } on Object catch (e) {
      results.clear();
      error = '搜索失败：$e';
    } finally {
      isLoading = false;
    }
  }

  @action
  void clearError() {
    error = null;
  }
}
