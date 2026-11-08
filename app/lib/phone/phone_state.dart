import '../data/account_store.dart';

enum RegState { disabled, idle, registering, registered, failed }

class AccountStatus {
  const AccountStatus(this.state, [this.detail = '', this.stopped = false]);

  final RegState state;

  /// Provider response, e.g. "200 OK" or "403 Forbidden".
  final String detail;

  /// Failed and not retried (auth failure, see the core's one-strike rule).
  final bool stopped;
}

enum CallPhase { incoming, calling, ringing, earlyMedia, answering, connected }

class ActiveCall {
  const ActiveCall({
    required this.id,
    required this.accountId,
    required this.peerUri,
    required this.peerName,
    required this.incoming,
    required this.phase,
    required this.startedAt,
    this.connectedAt,
    this.muted = false,
    this.onHold = false,
    this.remoteHold = false,
    this.encryption = '',
  });

  final String id;
  final String accountId;
  final String peerUri;
  final String peerName;
  final bool incoming;
  final CallPhase phase;
  final DateTime startedAt;
  final DateTime? connectedAt;
  final bool muted;
  final bool onHold;
  final bool remoteHold;

  /// Media encryption reported by baresip, e.g. "srtp", empty if none.
  final String encryption;

  bool get ringingIn => phase == CallPhase.incoming;

  /// The user part of the peer URI, which is usually the phone number.
  String get peerNumber {
    final m = RegExp(r'^sips?:([^@;>]+)').firstMatch(peerUri);
    return m?.group(1) ?? peerUri;
  }

  String get peerLabel => peerName.isNotEmpty ? peerName : peerNumber;

  ActiveCall copyWith({
    CallPhase? phase,
    DateTime? connectedAt,
    bool? muted,
    bool? onHold,
    bool? remoteHold,
    String? encryption,
  }) => ActiveCall(
    id: id,
    accountId: accountId,
    peerUri: peerUri,
    peerName: peerName,
    incoming: incoming,
    phase: phase ?? this.phase,
    startedAt: startedAt,
    connectedAt: connectedAt ?? this.connectedAt,
    muted: muted ?? this.muted,
    onHold: onHold ?? this.onHold,
    remoteHold: remoteHold ?? this.remoteHold,
    encryption: encryption ?? this.encryption,
  );
}

class PhoneState {
  const PhoneState({
    this.ready = false,
    this.accounts = const [],
    this.status = const {},
    this.calls = const [],
    this.speaker = false,
    this.sipTrace = false,
    this.error,
  });

  /// Core started and saved accounts added.
  final bool ready;
  final List<AccountEntry> accounts;

  /// Registration status by account id.
  final Map<String, AccountStatus> status;

  /// Active calls in order of arrival.
  final List<ActiveCall> calls;
  final bool speaker;
  final bool sipTrace;

  /// Last error for the UI to show once, see PhoneController.clearError.
  final String? error;

  AccountEntry? account(String id) {
    for (final a in accounts) {
      if (a.id == id) return a;
    }
    return null;
  }

  /// Registration status; always [RegState.disabled] for accounts that are
  /// switched off.
  AccountStatus statusOf(String id) => account(id)?.enabled == false
      ? const AccountStatus(RegState.disabled)
      : status[id] ?? const AccountStatus(RegState.idle);

  PhoneState copyWith({
    bool? ready,
    List<AccountEntry>? accounts,
    Map<String, AccountStatus>? status,
    List<ActiveCall>? calls,
    bool? speaker,
    bool? sipTrace,
    String? error,
    bool clearError = false,
  }) => PhoneState(
    ready: ready ?? this.ready,
    accounts: accounts ?? this.accounts,
    status: status ?? this.status,
    calls: calls ?? this.calls,
    speaker: speaker ?? this.speaker,
    sipTrace: sipTrace ?? this.sipTrace,
    error: clearError ? null : error ?? this.error,
  );
}
