// TDLib JSON interface via dart:ffi (td_json_client_*).
// FFI binding pattern derived from i-Naji/tdlib (BSD-3-Clause): see upstream
// https://github.com/i-Naji/tdlib — vendored here to decouple runtime from
// the Flutter plugin; generated TD types live in lib/td_api_generated/.

import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:fladder/td_api_generated/td_api.dart' as td;

/// Global native TDLib JSON engine (replaces the legacy Flutter tdlib plugin runtime).
class OxTdJsonFfi {
  OxTdJsonFfi._(this._lib) {
    _tdJsonClientCreate = _lib
        .lookup<ffi.NativeFunction<_TdJsonClientCreateNative>>('td_json_client_create')
        .asFunction();
    _tdJsonClientSend = _lib
        .lookup<ffi.NativeFunction<_TdJsonClientSendNative>>('td_json_client_send')
        .asFunction();
    _tdJsonClientReceive = _lib
        .lookup<ffi.NativeFunction<_TdJsonClientReceiveNative>>('td_json_client_receive')
        .asFunction();
    _tdJsonClientDestroy = _lib
        .lookup<ffi.NativeFunction<_TdJsonClientDestroyNative>>('td_json_client_destroy')
        .asFunction();
  }

  static OxTdJsonFfi? _instance;

  static OxTdJsonFfi get instance {
    final i = _instance;
    if (i == null) {
      throw StateError('OxTdJsonFfi not installed. Call OxTdJsonFfi.install() first.');
    }
    return i;
  }

  /// Loads [lib] and sets [instance] for the current isolate.
  static void install(ffi.DynamicLibrary lib) {
    _instance = OxTdJsonFfi._(lib);
  }

  /// Convenience for Android / desktop: open [libraryFileName] (e.g. libtdjson.so).
  static void installFile(String libraryFileName) {
    install(ffi.DynamicLibrary.open(libraryFileName));
  }

  final ffi.DynamicLibrary _lib;

  late final _TdJsonClientCreateDart _tdJsonClientCreate;
  late final _TdJsonClientSendDart _tdJsonClientSend;
  late final _TdJsonClientReceiveDart _tdJsonClientReceive;
  late final _TdJsonClientDestroyDart _tdJsonClientDestroy;

  int tdJsonClientCreate() => _tdJsonClientCreate().address;

  void tdJsonClientSend(int clientId, String jsonRequest) {
    // Request string: we allocate with toNativeUtf8 (malloc); TDLib copies internally — free in finally.
    final req = jsonRequest.toNativeUtf8();
    try {
      _tdJsonClientSend(ffi.Pointer.fromAddress(clientId), req);
    } finally {
      malloc.free(req);
    }
  }

  /// Returns the next JSON update or `null` on timeout.
  ///
  /// **Pointer ownership:** `td_json_client_receive` returns a pointer into TDLib-owned memory.
  /// Only [toDartString] (copy) is used here — **do not** `malloc.free` the result; TDLib reuses/frees
  /// that storage on the next receive/send for this client on the same thread (per TDLib JSON API).
  String? tdJsonClientReceive(int clientId, double timeout) {
    final res = _tdJsonClientReceive(ffi.Pointer.fromAddress(clientId), timeout);
    if (res.address == ffi.nullptr.address) {
      return null;
    }
    return res.toDartString();
  }

  void tdJsonClientDestroy(int clientId) {
    _tdJsonClientDestroy(ffi.Pointer.fromAddress(clientId));
  }
}

// --- Top-level API matching historical td_json_client usage in Oxplayer ---

int tdJsonClientCreate() => OxTdJsonFfi.instance.tdJsonClientCreate();

void tdJsonClientSend(int clientId, td.TdFunction request, [Object? extra]) {
  OxTdJsonFfi.instance.tdJsonClientSend(clientId, jsonEncode(request.toJson(extra)));
}

String? tdJsonClientReceive(int clientId, [double timeout = 8]) =>
    OxTdJsonFfi.instance.tdJsonClientReceive(clientId, timeout);

void tdJsonClientDestroy(int clientId) =>
    OxTdJsonFfi.instance.tdJsonClientDestroy(clientId);

void initOxTdJsonPlugin() {
  if (kIsWeb) return;
  if (Platform.isAndroid || Platform.isLinux || Platform.isWindows) {
    OxTdJsonFfi.installFile('libtdjson.so');
    return;
  }
  OxTdJsonFfi.install(ffi.DynamicLibrary.process());
}

typedef _TdJsonClientCreateNative = ffi.Pointer<ffi.Void> Function();
typedef _TdJsonClientCreateDart = ffi.Pointer<ffi.Void> Function();

typedef _TdJsonClientSendNative = ffi.Void Function(
  ffi.Pointer<ffi.Void> client,
  ffi.Pointer<Utf8> request,
);
typedef _TdJsonClientSendDart = void Function(
  ffi.Pointer<ffi.Void> client,
  ffi.Pointer<Utf8> request,
);

typedef _TdJsonClientReceiveNative = ffi.Pointer<Utf8> Function(
  ffi.Pointer<ffi.Void> client,
  ffi.Double timeout,
);
typedef _TdJsonClientReceiveDart = ffi.Pointer<Utf8> Function(
  ffi.Pointer<ffi.Void> client,
  double timeout,
);

typedef _TdJsonClientDestroyNative = ffi.Void Function(ffi.Pointer<ffi.Void> client);
typedef _TdJsonClientDestroyDart = void Function(ffi.Pointer<ffi.Void> client);
