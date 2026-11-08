import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:sippier/data/account_checks.dart';
import 'package:sippier/l10n/app_localizations.dart';
import 'package:sippier/phone/registration_problem.dart';

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final de = lookupAppLocalizations(const Locale('de'));

  group('RegistrationProblem', () {
    test('auth failures are a rejected login', () {
      for (final reason in [
        '401 Unauthorized',
        '403 Forbidden - 6037 Identities do not match',
      ]) {
        expect(RegistrationProblem.from(en, reason).summary, 'Login rejected');
      }
    });

    test('says when Sippier stopped retrying', () {
      final p = RegistrationProblem.from(en, '403 Forbidden', stopped: true);
      expect(p.summary, 'Login rejected (not retried)');
      expect(p.advice, contains('Save the account to try again'));
    });

    test('local network errors', () {
      for (final reason in [
        'Register: No route to host [65]',
        'Register: Cannot assign requested address [99]',
      ]) {
        expect(RegistrationProblem.from(en, reason).summary, 'No network');
      }
    });

    test('anything else keeps a generic summary', () {
      expect(
        RegistrationProblem.from(en, '482 Loop Detected').summary,
        'Registration failed',
      );
    });

    test('in German', () {
      final p = RegistrationProblem.from(de, '403 Forbidden', stopped: true);
      expect(p.summary, 'Anmeldung abgelehnt (kein neuer Versuch)');
      expect(p.advice, startsWith('Vergleiche Benutzername'));
      expect(
        RegistrationProblem.from(de, 'Register: No route to host [65]').summary,
        'Kein Netzwerk',
      );
    });
  });

  group('account checks', () {
    test('username', () {
      expect(checkUser(en, '4930555'), isNull);
      expect(checkUser(en, '+4930555'), isNull);
      expect(checkUser(en, '4930555@sip.example.net'), contains('Domain'));
      expect(checkUser(en, 'sip:4930555'), contains('sip:'));
      expect(checkUser(en, '4930 555'), contains('spaces'));
    });

    test('auth username', () {
      expect(checkAuthUser(en, ''), isNull);
      // email-like auth names exist
      expect(checkAuthUser(en, 'line@provider.example'), isNull);
      expect(checkAuthUser(en, 'sip:auth'), contains('sip:'));
      expect(checkAuthUser(en, 'au th'), contains('spaces'));
    });

    test('in German', () {
      expect(checkUser(de, '4930 555'), 'Keine Leerzeichen');
      expect(checkAuthUser(de, 'sip:auth'), contains('sip:'));
    });
  });

  group('status plurals', () {
    test('one of one, two of three', () {
      expect(en.statusRegisteredSome(0, 1), '0 of 1 account registered');
      expect(en.statusRegisteredSome(2, 3), '2 of 3 accounts registered');
      expect(de.statusRegisteredSome(0, 1), '0 von 1 Konto registriert');
      expect(de.statusRegisteredSome(2, 3), '2 von 3 Konten registriert');
    });
  });
}
