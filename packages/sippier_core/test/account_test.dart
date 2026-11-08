import 'package:sippier_core/sippier_core.dart';
import 'package:test/test.dart';

void main() {
  test('account line has no password and quotes the outbound proxy', () {
    const s = AccountSettings(
      user: '+4930123',
      domain: 'example.net',
      displayName: 'Desk "1"',
      authUser: 'auth1',
      outboundProxy: 'proxy.example.net',
      transport: 'tcp',
      regInterval: 900,
      codecs: 'G722/16000/1,PCMA',
      mediaEncryption: 'srtp',
    );
    expect(
      s.toAccountLine(),
      '"Desk 1" <sip:+4930123@example.net;transport=tcp>;auth_user=auth1'
      ';outbound="sip:proxy.example.net;transport=tcp";regint=900'
      ';mediaenc=srtp;audio_codecs=G722/16000/1,PCMA'
      ';answermode=manual;dtmfmode=auto;100rel=yes',
    );
  });

  test('settings survive a JSON round trip', () {
    const s = AccountSettings(
      user: 'u',
      domain: 'd',
      stunServer: 'stun.example.net:3478',
    );
    expect(
      AccountSettings.fromJson(s.toJson()).toAccountLine(),
      s.toAccountLine(),
    );
  });
}
