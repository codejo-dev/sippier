/// SIP account settings, turned into a baresip account line.
class AccountSettings {
  const AccountSettings({
    required this.user,
    required this.domain,
    this.displayName = '',
    this.authUser = '',
    this.outboundProxy = '',
    this.transport = 'udp',
    this.regInterval = 600,
    this.codecs = '',
    this.mediaEncryption = '',
    this.stunServer = '',
  });

  factory AccountSettings.fromJson(Map<String, dynamic> json) =>
      AccountSettings(
        user: json['user'] as String,
        domain: json['domain'] as String,
        displayName: json['displayName'] as String? ?? '',
        authUser: json['authUser'] as String? ?? '',
        outboundProxy: json['outboundProxy'] as String? ?? '',
        transport: json['transport'] as String? ?? 'udp',
        regInterval: json['regInterval'] as int? ?? 600,
        codecs: json['codecs'] as String? ?? '',
        mediaEncryption: json['mediaEncryption'] as String? ?? '',
        stunServer: json['stunServer'] as String? ?? '',
      );

  final String user;
  final String domain;
  final String displayName;

  /// Username for digest auth if it differs from [user].
  final String authUser;

  /// host[:port], without "sip:".
  final String outboundProxy;

  /// udp, tcp or tls.
  final String transport;

  /// Seconds between registrations.
  final int regInterval;

  /// Comma separated, baresip names (G.722 is "G722/16000/1"). Empty uses
  /// baresip's default order.
  final String codecs;

  /// '' (off), 'srtp' (optional) or 'srtp-mand'.
  final String mediaEncryption;

  /// host[:port], without "stun:".
  final String stunServer;

  String get aor => 'sip:$user@$domain';

  Map<String, dynamic> toJson() => {
    'user': user,
    'domain': domain,
    'displayName': displayName,
    'authUser': authUser,
    'outboundProxy': outboundProxy,
    'transport': transport,
    'regInterval': regInterval,
    'codecs': codecs,
    'mediaEncryption': mediaEncryption,
    'stunServer': stunServer,
  };

  /// baresip account line, without the password.
  String toAccountLine() {
    final tp = transport == 'udp' ? '' : ';transport=$transport';
    final name = displayName.replaceAll('"', '');
    final b = StringBuffer('"$name" <sip:$user@$domain$tp>');
    if (authUser.isNotEmpty) b.write(';auth_user=$authUser');
    if (outboundProxy.isNotEmpty) b.write(';outbound="sip:$outboundProxy$tp"');
    b.write(';regint=$regInterval');
    if (mediaEncryption.isNotEmpty) b.write(';mediaenc=$mediaEncryption');
    if (codecs.isNotEmpty) b.write(';audio_codecs=$codecs');
    if (stunServer.isNotEmpty) {
      b.write(';medianat=stun;stunserver="stun:$stunServer"');
    }
    // auto: RFC 4733 events when the other side offers telephone-event,
    // SIP INFO otherwise (rtpevent drops the keys silently then)
    b.write(';answermode=manual;dtmfmode=auto;100rel=yes');
    return b.toString();
  }
}
