/// 播放模式：随机 / 单曲循环 / 列表循环。
///
/// - [shuffle]：随机切歌（不会立刻重复当前曲）；
/// - [repeatOne]：单曲循环（播完/切歌都重播当前曲）；
/// - [listLoop]：列表循环（按队列顺序切歌，队尾回绕到队首；默认）。
enum PlayMode { shuffle, repeatOne, listLoop }
