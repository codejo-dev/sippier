// ignore_for_file: non_constant_identifier_names

/// Raw FFI bindings for native/sippier_core/include/sippier_core.h. The
/// library is built and bundled by hook/build.dart.
@DefaultAsset('package:sippier_core/src/bindings.dart')
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';

typedef EventCallbackNative = Void Function(Pointer<Utf8> json);

@Native<
  Int Function(Pointer<Utf8>, Pointer<NativeFunction<EventCallbackNative>>)
>()
external int sc_init(
  Pointer<Utf8> configDir,
  Pointer<NativeFunction<EventCallbackNative>> cb,
);

@Native<Void Function()>()
external void sc_shutdown();

@Native<Void Function(Pointer<Utf8>)>()
external void sc_string_free(Pointer<Utf8> s);

@Native<Int Function(Pointer<Utf8>, Pointer<Utf8>)>()
external int sc_account_add(Pointer<Utf8> aor, Pointer<Utf8> password);

@Native<Int Function(Int)>()
external int sc_account_remove(int acc);

@Native<Int Function(Int, Pointer<Utf8>, Pointer<Utf8>)>()
external int sc_account_update(
  int acc,
  Pointer<Utf8> aor,
  Pointer<Utf8> password,
);

@Native<Int Function(Int, Int)>()
external int sc_account_register(int acc, int enable);

@Native<Int Function(Int, Pointer<Utf8>, Pointer<Utf8>, Int)>()
external int sc_call(
  int acc,
  Pointer<Utf8> uri,
  Pointer<Utf8> idOut,
  int idOutSize,
);

@Native<Int Function(Pointer<Utf8>)>()
external int sc_answer(Pointer<Utf8> callId);

@Native<Int Function(Pointer<Utf8>)>()
external int sc_hangup(Pointer<Utf8> callId);

@Native<Int Function(Pointer<Utf8>, Int)>()
external int sc_hold(Pointer<Utf8> callId, int hold);

@Native<Int Function(Pointer<Utf8>, Int)>()
external int sc_mute(Pointer<Utf8> callId, int mute);

@Native<Int Function(Pointer<Utf8>, Char)>()
external int sc_send_dtmf(Pointer<Utf8> callId, int key);

@Native<Void Function(Char)>()
external void sc_play_key_tone(int key);

@Native<Void Function(Int)>()
external void sc_set_sip_trace(int enable);

@Native<Int Function(Pointer<Utf8>)>()
external int sc_set_dns_servers(Pointer<Utf8> servers);

@Native<Pointer<Utf8> Function()>()
external Pointer<Utf8> sc_audio_devices();

@Native<Int Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>)>()
external int sc_set_audio_devices(
  Pointer<Utf8> input,
  Pointer<Utf8> output,
  Pointer<Utf8> ringer,
);

@Native<Pointer<Utf8> Function()>()
external Pointer<Utf8> sc_ringtones();

@Native<Int Function(Pointer<Utf8>)>()
external int sc_ring_start(Pointer<Utf8> tone);

@Native<Void Function()>()
external void sc_ring_stop();

@Native<Int Function()>()
external int sc_keepalive();

@Native<Int Function(Int)>()
external int sc_account_expires(int acc);

@Native<Int Function()>()
external int sc_network_changed();
