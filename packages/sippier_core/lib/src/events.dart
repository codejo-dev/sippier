/// Events from the native core, decoded from its JSON messages.
sealed class CoreEvent {
  const CoreEvent();

  factory CoreEvent.fromJson(Map<String, dynamic> json) =>
      json['kind'] == 'log' ? LogEvent.fromJson(json) : SipEvent.fromJson(json);
}

/// A baresip log line.
final class LogEvent extends CoreEvent {
  const LogEvent(this.level, this.text);

  LogEvent.fromJson(Map<String, dynamic> json)
    : level = json['level'] as int? ?? 1,
      text = (json['text'] as String? ?? '').trimRight();

  /// 0 debug, 1 info, 2 warning, 3 error.
  final int level;
  final String text;
}

/// A baresip event (registration or call), see baresip's bevent.c.
final class SipEvent extends CoreEvent {
  SipEvent.fromJson(this.raw)
    : type = raw['type'] as String? ?? '',
      account = raw['account'] as int? ?? -1,
      param = raw['param'] as String? ?? '';

  /// e.g. REGISTER_OK, CALL_INCOMING, CALL_CLOSED.
  final String type;

  /// Account id from [SippierCore.addAccount], or -1.
  final int account;

  /// Event detail, e.g. "200 OK" or a hang-up reason.
  final String param;

  final Map<String, dynamic> raw;

  String? get callId => raw['id'] as String?;
  bool get incoming => raw['direction'] == 'incoming';
  String get peerUri => raw['peeruri'] as String? ?? '';
  String get peerName => raw['peerdisplayname'] as String? ?? '';

  /// Set on REGISTER_FAIL after an auth failure: the core stopped
  /// retrying so the provider doesn't block our IP.
  bool get registrationStopped => raw['registration_stopped'] == true;

  @override
  String toString() => 'SipEvent($type, account $account, $param)';
}
