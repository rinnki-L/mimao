/// 凭据存储：账号密码不进普通 kv，落系统安全存储。
///
/// 实现策略（都是纯 Dart，零原生构建）：
/// - **Windows**：直连 `crypt32.dll` 的 `CryptProtectData`（DPAPI，当前用户 + 本机
///   作用域），密文落应用支持目录。为什么不用 `flutter_secure_storage`：它的
///   Windows 端是 C++ 插件、要 ATL 头（`atlstr.h`）与 `/WX`，本机 VS 2022 BuildTools
///   没装 ATL 时 `flutter build windows` 直接失败——Windows 是本应用首发平台，
///   这个依赖会把主平台卡死。
/// - **其它平台**：暂时没有系统安全存储实现，退回 [NovelUnavailableCredentialStore]
///   （读永远拿不到、写抛错）。调用方据此把"密码存不下"如实告诉用户，而不是假装存好了。
///
/// 测试一律注入 [NovelMemoryCredentialStore]，不碰任何插件/文件。
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart' show calloc;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

abstract interface class NovelCredentialStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

/// 内存实现（测试用）。
class NovelMemoryCredentialStore implements NovelCredentialStore {
  NovelMemoryCredentialStore([Map<String, String>? seed])
    : _values = <String, String>{...?seed};

  final Map<String, String> _values;

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}

/// 平台没有安全存储实现时用它：读当没有、写明确失败。
class NovelUnavailableCredentialStore implements NovelCredentialStore {
  const NovelUnavailableCredentialStore();

  @override
  Future<String?> read(String key) async => null;

  @override
  Future<void> write(String key, String value) async =>
      throw StateError('本平台还没有接系统安全存储，密码不会被保存');

  @override
  Future<void> delete(String key) async {}
}

/// 按平台挑实现（生产入口）。
NovelCredentialStore defaultNovelCredentialStore() => Platform.isWindows
    ? NovelDpapiCredentialStore()
    : const NovelUnavailableCredentialStore();

// ── Windows DPAPI ──────────────────────────────────────────────────────────

/// `DATA_BLOB`（a.k.a. `CRYPT_INTEGER_BLOB`）。
final class _DataBlob extends Struct {
  @Uint32()
  external int cbData;

  external Pointer<Uint8> pbData;
}

typedef _CryptProtectDataNative =
    Int32 Function(
      Pointer<Void> dataIn,
      Pointer<Void> description,
      Pointer<Void> entropy,
      Pointer<Void> reserved,
      Pointer<Void> prompt,
      Uint32 flags,
      Pointer<Void> dataOut,
    );
typedef _CryptProtectDataDart =
    int Function(
      Pointer<Void>,
      Pointer<Void>,
      Pointer<Void>,
      Pointer<Void>,
      Pointer<Void>,
      int,
      Pointer<Void>,
    );

typedef _CryptUnprotectDataNative =
    Int32 Function(
      Pointer<Void> dataIn,
      Pointer<Void> description,
      Pointer<Void> entropy,
      Pointer<Void> reserved,
      Pointer<Void> prompt,
      Uint32 flags,
      Pointer<Void> dataOut,
    );
typedef _CryptUnprotectDataDart =
    int Function(
      Pointer<Void>,
      Pointer<Void>,
      Pointer<Void>,
      Pointer<Void>,
      Pointer<Void>,
      int,
      Pointer<Void>,
    );

typedef _LocalFreeNative = Pointer<Void> Function(Pointer<Void>);
typedef _LocalFreeDart = Pointer<Void> Function(Pointer<Void>);

/// 不弹任何 UI 的 DPAPI 调用（自动备份/同步在后台跑，绝不能弹系统对话框）。
const int _cryptProtectUiForbidden = 0x1;

/// 每个键一个文件，文件名是键的 base64url（键都是短 ASCII）。
String _fileNameFor(String key) =>
    '${base64Url.encode(utf8.encode(key)).replaceAll('=', '')}.dpapi';

/// Windows 上的 DPAPI 实现：密文只在本机、本用户下可解。
///
/// 语义说明：密钥材料由 Windows 托管，同一用户身份下的其它进程仍可解开——
/// 这是 DPAPI 的既定行为；它挡住的是"数据库/配置文件被拷到别处"。
class NovelDpapiCredentialStore implements NovelCredentialStore {
  NovelDpapiCredentialStore({
    Future<Directory> Function()? supportDirectory,
    DynamicLibrary? crypt32,
    DynamicLibrary? kernel32,
  }) : _supportDirectory = supportDirectory ?? getApplicationSupportDirectory,
       _crypt32 = crypt32,
       _kernel32 = kernel32;

  final Future<Directory> Function() _supportDirectory;
  final DynamicLibrary? _crypt32;
  final DynamicLibrary? _kernel32;
  Future<_Dpapi>? _api;
  Future<Directory>? _dir;

  Future<Directory> _dirOf() async {
    final cached = _dir;
    if (cached != null) return cached;
    final support = await _supportDirectory();
    final dir = Directory(p.join(support.path, 'novel_credentials'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return _dir = Future<Directory>.value(dir);
  }

  Future<_Dpapi> _dpapi() async {
    final cached = _api;
    if (cached != null) return cached;
    final crypt = _crypt32 ?? DynamicLibrary.open('crypt32.dll');
    final kernel = _kernel32 ?? DynamicLibrary.open('kernel32.dll');
    final localFree = kernel.lookupFunction<_LocalFreeNative, _LocalFreeDart>(
      'LocalFree',
    );
    return _api = Future<_Dpapi>.value(
      _Dpapi(
        crypt.lookupFunction<_CryptProtectDataNative, _CryptProtectDataDart>(
          'CryptProtectData',
        ),
        crypt
            .lookupFunction<_CryptUnprotectDataNative, _CryptUnprotectDataDart>(
              'CryptUnprotectData',
            ),
        localFree,
      ),
    );
  }

  Future<File> _fileFor(String key) async =>
      File(p.join((await _dirOf()).path, _fileNameFor(key)));

  @override
  Future<String?> read(String key) async {
    try {
      final file = await _fileFor(key);
      if (!await file.exists()) return null;
      final sealed = await file.readAsBytes();
      return utf8.decode((await _dpapi()).unprotect(sealed));
    } on Object {
      // 目录拿不到、解不开（换了用户/机器，或文件损坏）：一律当"没有"，
      // 让用户重新输一次——读失败不该掀掉整个备份页。
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) async {
    try {
      final sealed = (await _dpapi()).protect(
        Uint8List.fromList(utf8.encode(value)),
      );
      final file = await _fileFor(key);
      await file.writeAsBytes(sealed, flush: true);
    } on Object catch (error) {
      throw StateError('系统安全存储写入失败：$error');
    }
  }

  @override
  Future<void> delete(String key) async {
    try {
      final file = await _fileFor(key);
      if (await file.exists()) await file.delete();
    } on Object {
      // 删不掉不该挡住"保存空密码"这条路径。
    }
  }
}

class _Dpapi {
  _Dpapi(this._protect, this._unprotect, this._localFree);

  final _CryptProtectDataDart _protect;
  final _CryptUnprotectDataDart _unprotect;
  final _LocalFreeDart _localFree;

  Uint8List protect(Uint8List plain) => _run(
    (input, output) => _protect(
      input,
      nullptr,
      nullptr,
      nullptr,
      nullptr,
      _cryptProtectUiForbidden,
      output,
    ),
    plain,
  );

  Uint8List unprotect(Uint8List sealed) => _run(
    (input, output) => _unprotect(
      input,
      nullptr,
      nullptr,
      nullptr,
      nullptr,
      _cryptProtectUiForbidden,
      output,
    ),
    sealed,
  );

  Uint8List _run(
    int Function(Pointer<Void> input, Pointer<Void> output) call,
    Uint8List bytes,
  ) {
    final buffer = calloc<Uint8>(bytes.isEmpty ? 1 : bytes.length);
    final input = calloc<_DataBlob>();
    final output = calloc<_DataBlob>();
    try {
      buffer.asTypedList(bytes.length).setAll(0, bytes);
      input.ref
        ..cbData = bytes.length
        ..pbData = buffer;
      if (call(input.cast(), output.cast()) == 0) {
        throw StateError('DPAPI 调用失败');
      }
      final cb = output.ref.cbData;
      if (output.ref.pbData == nullptr || cb == 0) {
        throw StateError('DPAPI 返回了空数据');
      }
      final result = Uint8List.fromList(output.ref.pbData.asTypedList(cb));
      _localFree(output.ref.pbData.cast());
      return result;
    } finally {
      calloc.free(input);
      calloc.free(output);
      calloc.free(buffer);
    }
  }
}
