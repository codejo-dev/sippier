import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sippier_core/sippier_core.dart';

import '../data/account_store.dart';
import '../data/audio_settings.dart';
import '../data/call_history.dart';
import '../l10n/app_localizations.dart';
import '../platform_bridge.dart';
import '../providers.dart';
import 'phone_state.dart';

/// App-side phone: saved accounts, registration status and active calls,
/// fed by events from the native core.
class PhoneController extends Notifier<PhoneState> {
  final _core = SippierCore.instance;

  /// Account id -> core account id.
  final _coreIds = <String, int>{};

  /// Last status sent to the menu bar / Android notification.
  String? _reportedStatus;

  /// Accounts the core stopped after an auth failure. They only register
  /// again when the user saves or re-enables them.
  final _authStopped = <String>{};

  AccountStore get _store => ref.read(accountStoreProvider);
  PlatformBridge get _platform => ref.read(platformProvider);
  AppLocalizations get _l => ref.read(l10nProvider);

  @override
  PhoneState build() {
    final sub = _core.events
        .where((e) => e is SipEvent)
        .cast<SipEvent>()
        .listen(_onEvent);
    ref.onDispose(sub.cancel);
    listenSelf((_, next) => _reportStatus(next));
    ref.listen(audioSettingsProvider, (_, next) => _applyAudio(next));
    ref.listen(stayAwakeProvider, (_, _) {
      _reportedStatus = null;
      _reportStatus(state);
    });
    // the system's language changed: the menu bar or tray in the new one
    ref.listen(l10nProvider, (_, _) => _reportStatus(state));

    final accounts = _store.load();
    Future.microtask(_start);
    return PhoneState(
      accounts: accounts,
      status: {
        for (final a in accounts)
          a.id: AccountStatus(a.enabled ? RegState.idle : RegState.disabled),
      },
    );
  }

  Future<void> _start() async {
    try {
      _core.init(ref.read(appDirProvider));
    } on SippierCoreException catch (e) {
      state = state.copyWith(error: _l.errorCoreStart('$e'));
      return;
    }

    _applyAudio(ref.read(audioSettingsProvider));
    final dns = await _platform.dnsServers();
    if (dns.isNotEmpty) _core.setDnsServers(dns);
    _platform
      ..onDnsServersChanged = _onDnsServers
      ..onNetworkChanged = (() {
        if (state.ready) _guard(_core.networkChanged);
      })
      // Notification buttons (Android)
      ..onAnswer = ((id) {
        final call = _call(id);
        if (call != null) answer(call);
      })
      ..onHangup = ((id) => _guard(() => _core.hangup(id)))
      ..onQuit = quit
      ..onKeepAlive = _core.keepalive;

    for (final a in state.accounts) {
      final password = await _store.password(a.id);
      _guard(() => _addToCore(a, password));
    }
    state = state.copyWith(ready: true);
  }

  void shutdown() => _core.shutdown();

  /// Android: new DNS servers (network change, or the app's network was
  /// unblocked). Registrations that failed for lack of DNS retry now.
  void _onDnsServers(List<String> servers) {
    if (servers.isEmpty || !state.ready) return;
    _guard(() => _core.setDnsServers(servers));
    for (final a in state.accounts) {
      final coreId = _coreIds[a.id];
      if (coreId != null &&
          a.enabled &&
          !_authStopped.contains(a.id) &&
          state.statusOf(a.id).state == RegState.failed) {
        _guard(() => _core.register(coreId));
      }
    }
  }

  /// Unregisters, stops the core and ends the app (Android "Quit").
  Future<void> quit() async {
    _core.shutdown();
    await _platform.quit();
  }

  /// Menu bar (macOS) or tray (Windows) text and icon, background service
  /// and its notification (Android).
  void _reportStatus(PhoneState s) {
    final enabled = [
      for (final a in s.accounts)
        if (a.enabled) a,
    ];
    final registered = [
      for (final a in enabled)
        if (s.statusOf(a.id).state == RegState.registered) a,
    ];
    final l = _l;
    final text = s.calls.isNotEmpty
        ? l.statusInCall
        : enabled.isEmpty
        ? l.statusNoAccounts
        : registered.length == enabled.length
        ? (enabled.length == 1
              ? l.statusRegisteredOne(enabled.first.label)
              : l.statusRegisteredAll(enabled.length))
        : l.statusRegisteredSome(registered.length, enabled.length);
    final stayAwake = ref.read(stayAwakeProvider);
    final key =
        '$text|${l.trayOpen}|${registered.isNotEmpty}|${enabled.isNotEmpty}|'
        '$stayAwake';
    if (key == _reportedStatus) return;
    _reportedStatus = key;
    unawaited(
      _platform.updateStatus(
        text: text,
        registered: registered.isNotEmpty,
        background: enabled.isNotEmpty,
        inCall: s.calls.isNotEmpty,
        stayAwake: stayAwake,
        openLabel: l.trayOpen,
        quitLabel: l.trayQuit,
      ),
    );
  }

  void clearError() => state = state.copyWith(clearError: true);

  // Accounts

  /// Seconds the provider granted the account's last registration, or null
  /// before the first one.
  int? grantedExpires(String accountId) {
    final coreId = _coreIds[accountId];
    final s = coreId == null ? 0 : _core.accountExpires(coreId);
    return s > 0 ? s : null;
  }

  bool hasCalls(String accountId) =>
      state.calls.any((c) => c.accountId == accountId);

  /// Adds or updates an account. An empty password keeps the saved one.
  Future<void> saveAccount(AccountEntry entry, String password) async {
    final existing = state.account(entry.id);
    if (existing != null && hasCalls(entry.id)) {
      _error(_l.errorEndCallsFirst(existing.label));
      return;
    }
    final accounts = [
      for (final a in state.accounts) a.id == entry.id ? entry : a,
      if (existing == null) entry,
    ];

    // App-side changes only (the ringtone): no need to register again
    if (existing != null &&
        password.isEmpty &&
        existing.enabled == entry.enabled &&
        existing.settings.toAccountLine() == entry.settings.toAccountLine()) {
      _setAccounts(accounts);
      return;
    }

    if (password.isNotEmpty) await _store.setPassword(entry.id, password);
    _authStopped.remove(entry.id);
    _setAccounts(accounts);
    _setStatus(
      entry.id,
      AccountStatus(entry.enabled ? RegState.idle : RegState.disabled),
    );

    _guard(() {
      final coreId = _coreIds[entry.id];
      if (coreId == null) {
        _addToCore(entry, password);
        return;
      }
      try {
        _core.updateAccount(coreId, entry.settings.toAccountLine(), password);
      } on SippierCoreException {
        _coreIds.remove(entry.id); // the core dropped it
        rethrow;
      }
      if (entry.enabled) _core.register(coreId);
    });
  }

  void setEnabled(AccountEntry entry, bool enabled) {
    _authStopped.remove(entry.id);
    final updated = entry.copyWith(enabled: enabled);
    _setAccounts([
      for (final a in state.accounts) a.id == entry.id ? updated : a,
    ]);
    _setStatus(
      entry.id,
      AccountStatus(enabled ? RegState.registering : RegState.disabled),
    );
    final coreId = _coreIds[entry.id];
    if (coreId != null) _guard(() => _core.register(coreId, enable: enabled));
  }

  Future<void> removeAccount(AccountEntry entry) async {
    final coreId = _coreIds.remove(entry.id);
    if (coreId != null) _guard(() => _core.removeAccount(coreId));
    _setAccounts([
      for (final a in state.accounts)
        if (a.id != entry.id) a,
    ]);
    state = state.copyWith(status: {...state.status}..remove(entry.id));
    await _store.deletePassword(entry.id);
  }

  void _addToCore(AccountEntry entry, String password) {
    final coreId = _core.addAccount(entry.settings.toAccountLine(), password);
    _coreIds[entry.id] = coreId;
    if (entry.enabled) _core.register(coreId);
  }

  void _setAccounts(List<AccountEntry> accounts) {
    state = state.copyWith(accounts: accounts);
    unawaited(_store.save(accounts));
  }

  /// Desktop plays the call's account's ringtone in the core; the platform
  /// side shows the call (window, Android's ringing notification).
  void _startRinging(ActiveCall call) {
    unawaited(_platform.startRinging());
    if (Platform.isAndroid) return;
    final tone =
        state.account(call.accountId)?.ringtone ??
        ref.read(audioSettingsProvider).ringtone ??
        defaultRingtone(_core.ringtones());
    _guard(() => _core.ringStart(coreRingtone(tone, ref.read(appDirProvider))));
  }

  void _stopRinging() {
    unawaited(_platform.stopRinging());
    if (!Platform.isAndroid) _core.ringStop();
  }

  void _applyAudio(AudioSettings s) {
    if (Platform.isAndroid) return; // the system routes audio
    _guard(
      () => _core.setAudioDevices(
        input: s.input,
        output: s.output,
        ringer: s.ringer,
      ),
    );
  }

  void _setStatus(String accountId, AccountStatus status) =>
      state = state.copyWith(status: {...state.status, accountId: status});

  // Calls

  Future<void> dial(String accountId, String number) async {
    final coreId = _coreIds[accountId];
    final target = number.trim();
    if (coreId == null || target.isEmpty) return;
    if (!await _microphoneAllowed()) return;

    await _platform.setInCall(true);
    _guard(() {
      final id = _core.call(coreId, target);
      _markOthersHeld(id);
      if (_call(id) == null) {
        _putCall(
          ActiveCall(
            id: id,
            accountId: accountId,
            peerUri: target,
            peerName: '',
            incoming: false,
            phase: CallPhase.calling,
            startedAt: DateTime.now(),
          ),
        );
      }
    });
    if (state.calls.isEmpty) await _platform.setInCall(false);
  }

  Future<void> answer(ActiveCall call) async {
    if (!await _microphoneAllowed()) return;
    _stopRinging();
    await _platform.cancelIncomingCall();
    await _platform.setInCall(true);
    _guard(() {
      _core.answer(call.id);
      _markOthersHeld(call.id);
      _putCall(call.copyWith(phase: CallPhase.answering));
    });
  }

  /// The core holds other calls when one starts (call_hold_other_calls).
  void _markOthersHeld(String callId) => state = state.copyWith(
    calls: [
      for (final c in state.calls)
        c.id != callId && c.phase == CallPhase.connected
            ? c.copyWith(onHold: true)
            : c,
    ],
  );

  void hangup(ActiveCall call) => _guard(() => _core.hangup(call.id));

  void toggleMute(ActiveCall call) => _guard(() {
    _core.mute(call.id, !call.muted);
    _putCall(call.copyWith(muted: !call.muted));
  });

  void toggleHold(ActiveCall call) => _guard(() {
    _core.hold(call.id, !call.onHold);
    _putCall(call.copyWith(onHold: !call.onHold));
  });

  /// Key feedback on the keypad before a call.
  void playKeyTone(String key) {
    if (key != '+') _core.playKeyTone(key);
  }

  void sendDtmf(ActiveCall call, String key) =>
      _guard(() => _core.sendDtmf(call.id, key));

  Future<void> toggleSpeaker() async {
    final on = !state.speaker;
    await _platform.setSpeaker(on);
    state = state.copyWith(speaker: on);
  }

  void setSipTrace(bool enable) {
    _core.setSipTrace(enable);
    state = state.copyWith(sipTrace: enable);
  }

  ActiveCall? _call(String id) {
    for (final c in state.calls) {
      if (c.id == id) return c;
    }
    return null;
  }

  void _putCall(ActiveCall call) {
    final calls = [...state.calls];
    final i = calls.indexWhere((c) => c.id == call.id);
    i < 0 ? calls.add(call) : calls[i] = call;
    state = state.copyWith(calls: calls);
  }

  Future<bool> _microphoneAllowed() async {
    if (await _platform.requestMicrophone()) return true;
    _error(_l.errorMicrophone);
    return false;
  }

  // Events

  String? _accountIdFor(int coreId) {
    for (final e in _coreIds.entries) {
      if (e.value == coreId) return e.key;
    }
    return null;
  }

  void _onEvent(SipEvent e) {
    final accountId = _accountIdFor(e.account);
    // Switching an account off unregisters it, and that can still report
    // success or failure; the account just stays off.
    final off =
        accountId != null && !(state.account(accountId)?.enabled ?? false);
    if (off && e.type.contains('REGISTER')) return;
    switch (e.type) {
      case 'REGISTERING':
        // Refreshes also report REGISTERING; keep showing "registered".
        if (accountId != null &&
            state.statusOf(accountId).state != RegState.registered) {
          _setStatus(accountId, const AccountStatus(RegState.registering));
        }
      case 'REGISTER_OK':
        if (accountId != null) {
          _setStatus(accountId, AccountStatus(RegState.registered, e.param));
        }
      case 'REGISTER_FAIL':
        if (accountId != null) {
          if (e.registrationStopped) _authStopped.add(accountId);
          _setStatus(
            accountId,
            AccountStatus(RegState.failed, e.param, e.registrationStopped),
          );
        }
      case 'UNREGISTERING':
        if (accountId != null) {
          final enabled = state.account(accountId)?.enabled ?? false;
          _setStatus(
            accountId,
            AccountStatus(enabled ? RegState.idle : RegState.disabled),
          );
        }
      default:
        _onCallEvent(e, accountId);
    }
  }

  void _onCallEvent(SipEvent e, String? accountId) {
    final id = e.callId;
    if (id == null) return;
    final call =
        _call(id) ??
        ActiveCall(
          id: id,
          accountId: accountId ?? '',
          peerUri: e.peerUri,
          peerName: e.peerName,
          incoming: e.incoming,
          phase: e.incoming ? CallPhase.incoming : CallPhase.calling,
          startedAt: DateTime.now(),
        );

    switch (e.type) {
      case 'CALL_INCOMING':
        _putCall(call);
        // A waiting call while talking shows a banner but doesn't ring.
        if (state.calls.length == 1) {
          _startRinging(call);
          unawaited(_platform.showIncomingCall(call.id, call.peerLabel));
        }
      case 'CALL_OUTGOING':
        _putCall(call);
      case 'CALL_RINGING':
        _putCall(call.copyWith(phase: CallPhase.ringing));
      case 'CALL_PROGRESS':
        _putCall(call.copyWith(phase: CallPhase.earlyMedia));
      case 'CALL_ANSWERED':
        _putCall(call.copyWith(phase: CallPhase.answering));
      case 'CALL_ESTABLISHED':
        _putCall(
          call.copyWith(
            phase: CallPhase.connected,
            connectedAt: DateTime.now(),
          ),
        );
      case 'CALL_MENC':
        _putCall(call.copyWith(encryption: e.param));
      case 'CALL_HOLD':
        _putCall(call.copyWith(remoteHold: true));
      case 'CALL_RESUME':
        _putCall(call.copyWith(remoteHold: false));
      case 'CALL_CLOSED':
        _closeCall(call, e.param);
    }
  }

  void _closeCall(ActiveCall call, String reason) {
    final calls = [
      for (final c in state.calls)
        if (c.id != call.id) c,
    ];
    state = state.copyWith(calls: calls);
    if (!call.incoming && call.connectedAt == null) {
      final message = _callFailure(reason);
      if (message != null) _error(message);
    }

    ref
        .read(callHistoryProvider.notifier)
        .add(
          CallRecord(
            peerUri: call.peerUri,
            peerName: call.peerName,
            accountId: call.accountId,
            incoming: call.incoming,
            startedAt: call.startedAt,
            endedAt: DateTime.now(),
            connectedAt: call.connectedAt,
            reason: reason,
          ),
        );

    if (!calls.any((c) => c.ringingIn)) {
      _stopRinging();
      unawaited(_platform.cancelIncomingCall());
    }
    if (calls.isEmpty) {
      unawaited(_platform.setInCall(false));
      state = state.copyWith(speaker: false);
    }
  }

  /// Why an outgoing call didn't connect, or null if it was just ended
  /// (e.g. hung up before it was answered).
  String? _callFailure(String reason) {
    final code = reason.length >= 3
        ? int.tryParse(reason.substring(0, 3))
        : null;
    if (code == null || code == 487) return null;
    final l = _l;
    return switch (code) {
      486 || 600 => l.callFailedBusy,
      404 || 484 || 604 => l.callFailedNotFound(reason),
      480 => l.callFailedNotReachable(reason),
      // e.g. the line is also set up on a router and the provider takes
      // only one registration
      401 || 403 || 407 => l.callFailedRejected(reason),
      _ => l.callFailed(reason),
    };
  }

  void _guard(void Function() action) {
    try {
      action();
    } on SippierCoreException catch (e) {
      _error(e.toString());
    }
  }

  void _error(String message) => state = state.copyWith(error: message);
}
