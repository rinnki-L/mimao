/// 音乐 API 门面——UI/Store 依赖的唯一数据入口（对齐 anime/comic 的
/// data source 缝：页面不认识 dio/KugouClient，换实现不改 UI）。
///
/// 生产实现 [KugouMusicApi] = 设备身份引导（ensureDevice）+ 各端点函数的组合；
/// 测试提供 fake 实现即可跑通页面/MobX 流程。
library;

import 'package:mimao/music/api/register_dev.dart';
// 别名导入：本类的实例方法 searchSongs 会遮蔽同名顶层端点函数。
import 'package:mimao/music/api/search.dart' as search;
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import 'package:mimao/music/models/music_models.dart';

abstract interface class MusicApi {
  /// 搜索单曲（1 起始页码；pageSize 1..100）。
  Future<MusicPage<MusicSong>> searchSongs({
    required String keyword,
    int page,
    int pageSize,
  });

  /// 确保设备身份可用：首次生成匿名身份（guid/mid）并注册真 dfid，
  /// 每一步都落盘。网络失败按 [KugouApiException] 抛出，下次调用重试。
  Future<KugouIdentity> ensureDevice();

  /// 只读当前身份（不生成/不注册/不联网）；未引导过返回 null。
  /// 设置页展示用。
  Future<KugouIdentity?> currentIdentity();
}

/// 生产实现：把 [KugouClient]、[KugouIdentityStore] 与各端点函数装配起来。
///
/// 身份仓库走工厂**惰性解析**——app_registry 装配音乐模块时不碰
/// path_provider（CI/测试无插件环境也能完成注册），首次调用 API 才解析。
class KugouMusicApi implements MusicApi {
  KugouMusicApi({
    required this.client,
    required Future<KugouIdentityStore> Function() identityStoreFactory,
    RegisterDeviceFn? register,
  }) : _identityStoreFactory = identityStoreFactory,
       _register = register ?? registerDevice;

  final KugouClient client;
  final Future<KugouIdentityStore> Function() _identityStoreFactory;

  /// 可注入的注册函数（测试替换，避免真网络）。
  final RegisterDeviceFn _register;

  KugouIdentityStore? _identityStore;

  Future<KugouIdentityStore> _store() async =>
      _identityStore ??= await _identityStoreFactory();

  KugouIdentity? _identity;

  /// 已缓存则直接用；否则读盘；都没有给全空身份（guid 空 = 未引导）。
  Future<KugouIdentity> _loadIdentity() async {
    final cached = _identity;
    if (cached != null) return cached;
    final identity =
        await (await _store()).load() ?? const KugouIdentity.empty();
    _identity = identity;
    return identity;
  }

  Future<void> _saveIdentity(KugouIdentity identity) async {
    _identity = identity;
    await (await _store()).save(identity);
  }

  @override
  Future<KugouIdentity> ensureDevice() async {
    var identity = await _loadIdentity();
    if (identity.guid.isEmpty || identity.mid.isEmpty) {
      identity = KugouIdentity.anonymous();
      await _saveIdentity(identity);
    }
    if (identity.needsDeviceRegistration) {
      final registered = await _register(client, identity);
      identity = identity.withDfid(registered.dfid);
      await _saveIdentity(identity);
    }
    return identity;
  }

  @override
  Future<KugouIdentity?> currentIdentity() => _loadIdentity().then(
    (identity) => identity.guid.isEmpty ? null : identity,
  );

  @override
  Future<MusicPage<MusicSong>> searchSongs({
    required String keyword,
    int page = 1,
    int pageSize = 30,
  }) async {
    final identity = await ensureDevice();
    final query = search.SearchSongsQuery(
      keyword: keyword,
      page: page,
      pageSize: pageSize,
    );
    return search.searchSongs(client, identity, query);
  }
}
