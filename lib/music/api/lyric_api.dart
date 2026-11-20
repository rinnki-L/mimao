/// 歌词端点组接口——lyric 下载的组装面（规格第 4 节：每组产出
/// `Music<Group>Api` 接口 + `Kugou<Group>Api` 实现）。
library;

import 'package:mimao/music/api/lyric.dart';
import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/models/lyric_models.dart';

/// 歌词端点组（lyric.rs）。
abstract interface class MusicLyricApi {
  /// 下载歌词文档（base64 原文 + 格式标记）；文档解码归 C++ 歌词服务，
  /// 客户端不在这一层解 base64。
  Future<MusicLyricDownload> downloadLyric(MusicLyricDownloadQuery query);
}

/// 酷狗实现：委托给组内端点函数（一端点一文件的翻译层）。
class KugouLyricApi implements MusicLyricApi {
  KugouLyricApi(this.session);

  final MusicSession session;

  @override
  Future<MusicLyricDownload> downloadLyric(MusicLyricDownloadQuery query) =>
      fetchLyricDownload(session, query);
}
