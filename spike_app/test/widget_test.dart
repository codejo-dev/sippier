import 'package:flutter_test/flutter_test.dart';
import 'package:sippier_spike/sip/phone.dart';

void main() {
  test('account line never contains the password and keeps settings', () {
    final config = AccountConfig(
      preset: Preset.other,
      displayName: 'Sven "Test"',
      user: '4930123',
      authUser: 'K123',
      domain: 'sip.example.com',
      outboundProxy: 'proxy.example.com:5061',
      transport: 'tls',
      regInterval: 900,
      codecs: 'G722,PCMA,PCMU',
      srtp: 'srtp-mand',
    );

    expect(config.aor, 'sip:4930123@sip.example.com');
    expect(
      config.toAccountLine(),
      '"Sven Test" <sip:4930123@sip.example.com;transport=tls>'
      ';auth_user=K123'
      ';outbound="sip:proxy.example.com:5061;transport=tls"'
      ';regint=900;mediaenc=srtp-mand;audio_codecs=G722,PCMA,PCMU'
      ';answermode=manual;dtmfmode=rtpevent;100rel=yes',
    );
  });
}
