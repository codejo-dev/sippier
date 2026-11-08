import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'audio_devices.dart';
import 'bindings.dart';
import 'events.dart';

/// Thrown when a native call returns an errno value.
class SippierCoreException implements Exception {
  SippierCoreException(this.function, this.code);

  final String function;
  final int code;

  @override
  String toString() => '$function failed (errno $code)';
}

/// The native SIP core. There is one per process, so this is a singleton.
class SippierCore {
  SippierCore._();

  static final instance = SippierCore._();

  static const maxAccounts = 16;
  static final _eAlready = Platform.isMacOS || Platform.isIOS
      ? 37
      : Platform.isWindows
      ? 103 // MinGW-w64
      : 114;

  final _events = StreamController<CoreEvent>.broadcast();
  NativeCallable<EventCallbackNative>? _callable;

  Stream<CoreEvent> get events => _events.stream;

  /// Starts baresip with its log file in [configDir]. After a hot restart
  /// the native side is still running, so leftover accounts are removed and
  /// the callback is swapped.
  void init(String configDir) {
    _callable ??= NativeCallable<EventCallbackNative>.listener(_onEvent);
    final err = using(
      (arena) => sc_init(
        configDir.toNativeUtf8(allocator: arena),
        _callable!.nativeFunction,
      ),
    );
    if (err == _eAlready) {
      for (var i = 0; i < maxAccounts; i++) {
        sc_account_remove(i);
      }
      return;
    }
    _check('sc_init', err);
  }

  void shutdown() {
    sc_shutdown();
    _callable?.close();
    _callable = null;
  }

  /// Adds an account from a baresip account line and returns its id. The
  /// password never goes into the line, so it can't end up in logs.
  int addAccount(String accountLine, String password) {
    final id = using(
      (arena) => sc_account_add(
        accountLine.toNativeUtf8(allocator: arena),
        password.toNativeUtf8(allocator: arena),
      ),
    );
    if (id < 0) throw SippierCoreException('sc_account_add', -id);
    return id;
  }

  void removeAccount(int id) =>
      _check('sc_account_remove', sc_account_remove(id));

  /// Replaces an account's settings. An empty password keeps the current
  /// one. On failure the account no longer exists.
  void updateAccount(int id, String accountLine, String password) {
    _check(
      'sc_account_update',
      using(
        (arena) => sc_account_update(
          id,
          accountLine.toNativeUtf8(allocator: arena),
          password.toNativeUtf8(allocator: arena),
        ),
      ),
    );
  }

  void register(int id, {bool enable = true}) =>
      _check('sc_account_register', sc_account_register(id, enable ? 1 : 0));

  /// Starts a call and returns its call id.
  String call(int accountId, String uri) {
    return using((arena) {
      const idSize = 256;
      final idOut = arena<Uint8>(idSize).cast<Utf8>();
      _check(
        'sc_call',
        sc_call(accountId, uri.toNativeUtf8(allocator: arena), idOut, idSize),
      );
      return idOut.toDartString();
    });
  }

  void answer(String callId) => _withId('sc_answer', callId, sc_answer);

  void hangup(String callId) => _withId('sc_hangup', callId, sc_hangup);

  void hold(String callId, bool hold) =>
      _withId('sc_hold', callId, (id) => sc_hold(id, hold ? 1 : 0));

  void mute(String callId, bool mute) =>
      _withId('sc_mute', callId, (id) => sc_mute(id, mute ? 1 : 0));

  void sendDtmf(String callId, String key) => _withId(
    'sc_send_dtmf',
    callId,
    (id) => sc_send_dtmf(id, key.codeUnitAt(0)),
  );

  /// Plays a key's DTMF tone locally (sendDtmf plays it too).
  void playKeyTone(String key) => sc_play_key_tone(key.codeUnitAt(0));

  void setSipTrace(bool enable) => sc_set_sip_trace(enable ? 1 : 0);

  /// Sets the DNS servers (IP or IP:port). Required on Android.
  void setDnsServers(List<String> servers) => _check(
    'sc_set_dns_servers',
    using(
      (arena) =>
          sc_set_dns_servers(servers.join(',').toNativeUtf8(allocator: arena)),
    ),
  );

  /// The audio devices and the system defaults. Empty lists where the
  /// platform routes audio itself (Android).
  AudioDevices audioDevices() {
    final json = _takeString(sc_audio_devices());
    return json == null
        ? const AudioDevices()
        : AudioDevices.fromJson(jsonDecode(json) as Map<String, dynamic>);
  }

  /// Microphone and speaker for calls and the device for ringing, as
  /// [AudioDevice.id]s; null follows the system default. Running calls
  /// switch at once.
  void setAudioDevices({String? input, String? output, String? ringer}) =>
      _check(
        'sc_set_audio_devices',
        using(
          (arena) => sc_set_audio_devices(
            (input ?? '').toNativeUtf8(allocator: arena),
            (output ?? '').toNativeUtf8(allocator: arena),
            (ringer ?? '').toNativeUtf8(allocator: arena),
          ),
        ),
      );

  /// Names of the built-in ringtones, the first being the default.
  List<String> ringtones() {
    final json = _takeString(sc_ringtones());
    return json == null ? const [] : (jsonDecode(json) as List).cast<String>();
  }

  /// Loops a built-in ringtone on the ringing device until [ringStop].
  void ringStart(String tone) => _check(
    'sc_ring_start',
    using((arena) => sc_ring_start(tone.toNativeUtf8(allocator: arena))),
  );

  void ringStop() => sc_ring_stop();

  /// Android battery saver, from an alarm: registers accounts that are past
  /// half of the expiry their provider granted. Returns the milliseconds
  /// until the next call.
  int keepalive() => sc_keepalive();

  /// Seconds the provider granted the account's last registration, or 0
  /// before the first one.
  int accountExpires(int id) => sc_account_expires(id);

  /// The device's network or its addresses changed: rebinds the SIP
  /// transports, moves running calls and registers enabled accounts again.
  void networkChanged() => _check('sc_network_changed', sc_network_changed());

  /// Copies and frees a string the core allocated.
  static String? _takeString(Pointer<Utf8> s) {
    if (s == nullptr) return null;
    final text = s.toDartString();
    sc_string_free(s);
    return text;
  }

  void _withId(String name, String callId, int Function(Pointer<Utf8>) fn) =>
      _check(name, using((arena) => fn(callId.toNativeUtf8(allocator: arena))));

  void _onEvent(Pointer<Utf8> json) {
    final text = json.toDartString();
    sc_string_free(json);
    _events.add(CoreEvent.fromJson(jsonDecode(text) as Map<String, dynamic>));
  }

  static void _check(String name, int err) {
    if (err != 0) throw SippierCoreException(name, err);
  }
}
