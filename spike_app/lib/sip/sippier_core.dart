import 'dart:async';
import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

typedef _EventCbNative = Void Function(Pointer<Utf8>);

/// Thrown when a native call returns an errno value.
class SippierCoreException implements Exception {
  SippierCoreException(this.function, this.code);

  final String function;
  final int code;

  @override
  String toString() => '$function failed (errno $code)';
}

/// Dart bindings for libsippier_core (see native/sippier_core/include).
class SippierCore {
  SippierCore(String libraryPath) : _lib = DynamicLibrary.open(libraryPath);

  /// errno EALREADY on Apple platforms.
  static const _eAlready = 37;
  static const _maxAccounts = 16;

  final DynamicLibrary _lib;
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  NativeCallable<_EventCbNative>? _callable;

  Stream<Map<String, dynamic>> get events => _events.stream;

  late final _init = _lib.lookupFunction<
      Int32 Function(Pointer<Utf8>, Pointer<NativeFunction<_EventCbNative>>),
      int Function(Pointer<Utf8>,
          Pointer<NativeFunction<_EventCbNative>>)>('sc_init');
  late final _shutdown =
      _lib.lookupFunction<Void Function(), void Function()>('sc_shutdown');
  late final _stringFree = _lib.lookupFunction<Void Function(Pointer<Utf8>),
      void Function(Pointer<Utf8>)>('sc_string_free');
  late final _accountAdd = _lib.lookupFunction<
      Int32 Function(Pointer<Utf8>, Pointer<Utf8>),
      int Function(Pointer<Utf8>, Pointer<Utf8>)>('sc_account_add');
  late final _accountRemove = _lib.lookupFunction<Int32 Function(Int32),
      int Function(int)>('sc_account_remove');
  late final _accountUpdate = _lib.lookupFunction<
      Int32 Function(Int32, Pointer<Utf8>, Pointer<Utf8>),
      int Function(int, Pointer<Utf8>, Pointer<Utf8>)>('sc_account_update');
  late final _accountRegister = _lib.lookupFunction<Int32 Function(Int32, Int32),
      int Function(int, int)>('sc_account_register');
  late final _call = _lib.lookupFunction<
      Int32 Function(Int32, Pointer<Utf8>, Pointer<Utf8>, Int32),
      int Function(int, Pointer<Utf8>, Pointer<Utf8>, int)>('sc_call');
  late final _answer = _lib.lookupFunction<Int32 Function(Pointer<Utf8>),
      int Function(Pointer<Utf8>)>('sc_answer');
  late final _hangup = _lib.lookupFunction<Int32 Function(Pointer<Utf8>),
      int Function(Pointer<Utf8>)>('sc_hangup');
  late final _hold = _lib.lookupFunction<Int32 Function(Pointer<Utf8>, Int32),
      int Function(Pointer<Utf8>, int)>('sc_hold');
  late final _mute = _lib.lookupFunction<Int32 Function(Pointer<Utf8>, Int32),
      int Function(Pointer<Utf8>, int)>('sc_mute');
  late final _sendDtmf = _lib.lookupFunction<
      Int32 Function(Pointer<Utf8>, Uint8),
      int Function(Pointer<Utf8>, int)>('sc_send_dtmf');
  late final _setSipTrace = _lib.lookupFunction<Void Function(Int32),
      void Function(int)>('sc_set_sip_trace');

  /// Starts baresip. After a hot restart the native side is still running,
  /// so leftover accounts are removed and the callback is swapped.
  void init(String configDir) {
    _callable ??= NativeCallable<_EventCbNative>.listener(_onEvent);
    final err = using((arena) => _init(
        configDir.toNativeUtf8(allocator: arena), _callable!.nativeFunction));
    if (err == _eAlready) {
      for (var i = 0; i < _maxAccounts; i++) {
        _accountRemove(i);
      }
      return;
    }
    _check('sc_init', err);
  }

  void shutdown() {
    _shutdown();
    _callable?.close();
    _callable = null;
  }

  /// Adds an account and returns its id. The password never goes into the
  /// account line, so it can't end up in baresip's logs.
  int addAccount(String aor, String password) {
    final id = using((arena) => _accountAdd(
        aor.toNativeUtf8(allocator: arena),
        password.toNativeUtf8(allocator: arena)));
    if (id < 0) throw SippierCoreException('sc_account_add', -id);
    return id;
  }

  void removeAccount(int id) => _check('sc_account_remove', _accountRemove(id));

  /// Replaces an account's settings. An empty password keeps the current
  /// one on the native side. On failure the account no longer exists.
  void updateAccount(int id, String aor, String password) {
    final err = using((arena) => _accountUpdate(
        id,
        aor.toNativeUtf8(allocator: arena),
        password.toNativeUtf8(allocator: arena)));
    _check('sc_account_update', err);
  }

  void register(int id, {bool enable = true}) =>
      _check('sc_account_register', _accountRegister(id, enable ? 1 : 0));

  /// Starts a call and returns its call id.
  String call(int accountId, String uri) {
    return using((arena) {
      const idSize = 256;
      final idOut = arena<Uint8>(idSize).cast<Utf8>();
      _check('sc_call',
          _call(accountId, uri.toNativeUtf8(allocator: arena), idOut, idSize));
      return idOut.toDartString();
    });
  }

  void answer(String callId) => _withId('sc_answer', callId, _answer);

  void hangup(String callId) => _withId('sc_hangup', callId, _hangup);

  void hold(String callId, bool hold) => _withId(
      'sc_hold', callId, (id) => _hold(id, hold ? 1 : 0));

  void mute(String callId, bool mute) => _withId(
      'sc_mute', callId, (id) => _mute(id, mute ? 1 : 0));

  void sendDtmf(String callId, String key) => _withId(
      'sc_send_dtmf', callId, (id) => _sendDtmf(id, key.codeUnitAt(0)));

  void setSipTrace(bool enable) => _setSipTrace(enable ? 1 : 0);

  void _withId(String name, String callId, int Function(Pointer<Utf8>) fn) {
    final err = using((arena) => fn(callId.toNativeUtf8(allocator: arena)));
    _check(name, err);
  }

  void _onEvent(Pointer<Utf8> json) {
    final text = json.toDartString();
    _stringFree(json);
    _events.add(jsonDecode(text) as Map<String, dynamic>);
  }

  static void _check(String name, int err) {
    if (err != 0) throw SippierCoreException(name, err);
  }
}
