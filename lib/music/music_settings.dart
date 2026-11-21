/// 音乐模块的少量本地设置（当前只有听歌上报开关）。
///
/// 与身份文件同款：JSON 落盘在应用支持目录、构造不碰 path_provider（工厂
/// [MusicFileSettings.openDefault] 才解析），读取失败回默认值，写盘失败只
/// 影响持久化、本次会话的开关仍然生效。测试注入内存 fake 即可，不碰插件。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 音乐本地设置读取/写入缝。
abstract interface class MusicSettings {
  /// 是否允许听歌上报（CSCC）。默认 true；[ensureLoaded] 之前返回内存值。
  bool get listenReportEnabled;

  /// 首次读盘（单次并发合并；失败吞掉回默认值）。
  Future<void> ensureLoaded();

  /// 写入开关（先改内存，再尽力落盘）。
  Future<void> setListenReportEnabled(bool value);
}

/// 生产实现：`<应用支持目录>/music_settings/settings.json`。
class MusicFileSettings implements MusicSettings {
  MusicFileSettings(this.directory);

  /// 默认位置；与音乐身份文件同根（应用支持目录）。
  static Future<MusicFileSettings> openDefault() async {
    final support = await getApplicationSupportDirectory();
    return MusicFileSettings(
      Directory('${support.path}${Platform.pathSeparator}music_settings'),
    );
  }

  final Directory directory;

  File get _file =>
      File('${directory.path}${Platform.pathSeparator}settings.json');

  bool _listenReportEnabled = true;
  bool _loaded = false;
  Future<void>? _loading;

  @override
  bool get listenReportEnabled => _listenReportEnabled;

  @override
  Future<void> ensureLoaded() {
    if (_loaded) return Future<void>.value();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    try {
      if (await _file.exists()) {
        final decoded = jsonDecode(await _file.readAsString());
        if (decoded is Map) {
          final value = decoded['listenReportEnabled'];
          if (value is bool) _listenReportEnabled = value;
        }
      }
    } on Object {
      // 设置文件损坏/不可读：回默认值，不影响模块启动。
    } finally {
      _loaded = true;
    }
  }

  @override
  Future<void> setListenReportEnabled(bool value) async {
    _listenReportEnabled = value;
    try {
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      const encoder = JsonEncoder.withIndent('  ');
      await _file.writeAsString(
        '${encoder.convert(<String, Object?>{'listenReportEnabled': value})}\n',
        flush: true,
      );
    } on Object {
      // 写盘失败不挡开关；下次启动回默认值。
    }
  }
}