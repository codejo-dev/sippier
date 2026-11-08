import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'sippier_core.dart';

/// Default account settings per provider.
///
/// Codecs need baresip's full name when the sample rate isn't 8000
/// (G.722 is registered as G722/16000/1).
enum Preset {
  other('Other SIP provider', domain: '', transport: 'udp', regInterval: 600,
      codecs: 'opus/48000/2,G722/16000/1,PCMA,PCMU'),
  fonial('fonial', domain: 'sip.plusnet.de', transport: 'udp',
      regInterval: 600, codecs: 'G722/16000/1,PCMA,PCMU',
      hint: 'Credentials from the fonial portal. plusnet publishes UDP only.'),
  // fixed.vodafone.de has no DNS records; the egfNN proxy resolves via
  // NAPTR/SRV to UDP SBCs.
  vodafoneDsl('Vodafone DE (DSL)', domain: 'fixed.vodafone.de',
      transport: 'udp', regInterval: 900, codecs: 'G722/16000/1,PCMA,PCMU',
      hint: 'Username: your number as +49…  ·  Auth username: IMPI_49…  ·  '
          'Outbound proxy: egfNN.fixed.vodafone.de from your data sheet.');

  const Preset(this.label,
      {required this.domain,
      required this.transport,
      required this.regInterval,
      required this.codecs,
      this.hint = ''});

  final String label;
  final String domain;
  final String transport;
  final int regInterval;
  final String codecs;
  final String hint;
}

class AccountConfig {
  AccountConfig({
    required this.preset,
    required this.displayName,
    required this.user,
    required this.authUser,
    required this.domain,
    required this.outboundProxy,
    required this.transport,
    required this.regInterval,
    required this.codecs,
    required this.srtp,
  });

  final Preset preset;
  final String displayName;
  final String user;
  final String authUser;
  final String domain;
  final String outboundProxy;
  final String transport;
  final int regInterval;
  final String codecs;

  /// 'off', 'srtp' (optional) or 'srtp-mand'.
  final String srtp;

  /// How baresip reports this account in events ("accountaor").
  String get aor => 'sip:$user@$domain';

  /// baresip account line, without the password.
  String toAccountLine() {
    final tp = transport == 'udp' ? '' : ';transport=$transport';
    final name = displayName.replaceAll('"', '');
    final b = StringBuffer('"$name" <sip:$user@$domain$tp>');
    if (authUser.isNotEmpty) b.write(';auth_user=$authUser');
    if (outboundProxy.isNotEmpty) b.write(';outbound="sip:$outboundProxy$tp"');
    b.write(';regint=$regInterval');
    if (srtp != 'off') b.write(';mediaenc=$srtp');
    if (codecs.isNotEmpty) b.write(';audio_codecs=$codecs');
    b.write(';answermode=manual;dtmfmode=rtpevent;100rel=yes');
    return b.toString();
  }
}

enum RegState { idle, registering, registered, failed }

class Account {
  Account(this.id, this.config);

  final int id;
  AccountConfig config;
  RegState state = RegState.idle;
  String detail = '';
}

class Call {
  Call({
    required this.id,
    required this.accountAor,
    required this.peer,
    required this.incoming,
  });

  final String id;
  final String accountAor;
  final String peer;
  final bool incoming;
  String state = '';
  DateTime? connectedAt;
  bool muted = false;
  bool onHold = false;
  bool remoteHold = false;
  String encryption = '';
  String quality = '';
  String endReason = '';
}

/// App-side phone state, fed by events from sippier_core.
class Phone extends ChangeNotifier {
  Phone(this.core);

  static const _maxLogLines = 500;

  final SippierCore core;
  final accounts = <Account>[];
  final calls = <String, Call>{};
  final endedCalls = <Call>[];
  final logs = <String>[];
  String configDir = '';
  String? error;
  StreamSubscription<Map<String, dynamic>>? _sub;

  Future<void> start() async {
    configDir = (await getApplicationSupportDirectory()).path;
    _sub = core.events.listen(_onEvent);
    try {
      core.init(configDir);
    } on SippierCoreException catch (e) {
      error = e.toString();
    }
    notifyListeners();
  }

  void shutdown() {
    _sub?.cancel();
    core.shutdown();
  }

  void addAccount(AccountConfig config, String password) {
    _guard(() {
      final id = core.addAccount(config.toAccountLine(), password);
      accounts.add(Account(id, config));
      core.register(id);
    });
  }

  bool hasCalls(Account account) =>
      calls.values.any((c) => c.accountAor == account.config.aor);

  /// Applies new settings and registers again. An empty password keeps the
  /// current one.
  void updateAccount(Account account, AccountConfig config, String password) {
    if (hasCalls(account)) {
      error = 'End the calls on ${account.config.aor} before editing it.';
      notifyListeners();
      return;
    }
    _guard(() {
      try {
        core.updateAccount(account.id, config.toAccountLine(), password);
      } on SippierCoreException {
        accounts.remove(account);
        rethrow;
      }
      account
        ..config = config
        ..state = RegState.idle
        ..detail = '';
      core.register(account.id);
    });
  }

  void setRegistered(Account account, bool enable) {
    _guard(() {
      core.register(account.id, enable: enable);
      if (!enable) account.state = RegState.idle;
    });
  }

  void removeAccount(Account account) {
    _guard(() {
      core.removeAccount(account.id);
      accounts.remove(account);
    });
  }

  void dial(Account account, String number) {
    _guard(() {
      final id = core.call(account.id, number.trim());
      calls.putIfAbsent(
          id,
          () => Call(
              id: id, accountAor: account.config.aor, peer: number,
              incoming: false)..state = 'Calling');
    });
  }

  void answer(Call call) => _guard(() => core.answer(call.id));

  void hangup(Call call) => _guard(() => core.hangup(call.id));

  void toggleMute(Call call) => _guard(() {
        core.mute(call.id, !call.muted);
        call.muted = !call.muted;
      });

  void toggleHold(Call call) => _guard(() {
        core.hold(call.id, !call.onHold);
        call.onHold = !call.onHold;
      });

  void dtmf(Call call, String key) => _guard(() => core.sendDtmf(call.id, key));

  void setSipTrace(bool enable) => core.setSipTrace(enable);

  void _guard(void Function() action) {
    try {
      error = null;
      action();
    } on SippierCoreException catch (e) {
      error = e.toString();
    }
    notifyListeners();
  }

  Account? _accountFor(Map<String, dynamic> e) {
    final aor = (e['accountaor'] as String? ?? '').toLowerCase();
    for (final a in accounts) {
      if (a.config.aor.toLowerCase() == aor) return a;
    }
    return null;
  }

  void _onEvent(Map<String, dynamic> e) {
    if (e['kind'] == 'log') {
      logs.add((e['text'] as String).trimRight());
      if (logs.length > _maxLogLines) logs.removeRange(0, 100);
      notifyListeners();
      return;
    }

    final type = e['type'] as String? ?? '';
    final param = e['param'] as String? ?? '';
    final account = _accountFor(e);

    switch (type) {
      case 'REGISTERING':
        account?.state = RegState.registering;
      case 'REGISTER_OK':
        account
          ?..state = RegState.registered
          ..detail = param;
      case 'REGISTER_FAIL':
        account
          ?..state = RegState.failed
          ..detail = e['registration_stopped'] == true
              ? '$param (stopped, no retry)'
              : param;
      case 'UNREGISTERING':
        account?.state = RegState.idle;
      default:
        _onCallEvent(type, param, e);
    }
    notifyListeners();
  }

  void _onCallEvent(String type, String param, Map<String, dynamic> e) {
    final id = e['id'] as String?;
    if (id == null) return;

    final call = calls.putIfAbsent(
        id,
        () => Call(
            id: id,
            accountAor: e['accountaor'] as String? ?? '',
            peer: _peerLabel(e),
            incoming: e['direction'] == 'incoming'));

    switch (type) {
      case 'CALL_INCOMING':
        call.state = 'Incoming';
      case 'CALL_OUTGOING':
        call.state = 'Calling';
      case 'CALL_RINGING':
        call.state = 'Ringing';
      case 'CALL_PROGRESS':
        call.state = 'Early media';
      case 'CALL_ANSWERED':
        call.state = 'Answered';
      case 'CALL_ESTABLISHED':
        call
          ..state = 'Connected'
          ..connectedAt = DateTime.now();
      case 'CALL_MENC':
        call.encryption = param;
      case 'CALL_HOLD':
        call.remoteHold = true;
      case 'CALL_RESUME':
        call.remoteHold = false;
      case 'CALL_RTCP':
        call.quality = _rtcpSummary(e);
      case 'AUDIO_ERROR':
        call.endReason = 'Audio error: $param';
      case 'CALL_CLOSED':
        calls.remove(id);
        call
          ..state = 'Ended'
          ..endReason = param;
        endedCalls.insert(0, call);
        if (endedCalls.length > 5) endedCalls.removeLast();
    }
  }

  static String _peerLabel(Map<String, dynamic> e) {
    final name = e['peerdisplayname'] as String? ?? '';
    final uri = e['peeruri'] as String? ?? '';
    return name.isEmpty ? uri : '$name <$uri>';
  }

  static String _rtcpSummary(Map<String, dynamic> e) {
    final stats = e['rtcp_stats'];
    if (stats is! Map) return '';
    final rx = stats['rx'];
    final rtt = stats['rtt'];
    if (rx is! Map) return '';
    return 'rx lost ${rx['lost']}, jitter ${rx['jit']} µs, rtt $rtt µs';
  }
}
