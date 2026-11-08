import 'package:flutter_test/flutter_test.dart';
import 'package:sippier/data/account_export.dart';
import 'package:sippier/data/account_store.dart';
import 'package:sippier_core/sippier_core.dart';

const _office = AccountEntry(
  id: 'a1',
  settings: AccountSettings(
    user: '4940555',
    domain: 'sip.example.net',
    displayName: 'Office',
    transport: 'tls',
    regInterval: 900,
  ),
  ringtone: 'marimba',
);
const _home = AccountEntry(
  id: 'a2',
  settings: AccountSettings(user: '4930555', domain: 'sip.example.org'),
  enabled: false,
  ringtone: 'file:My song.m4a',
);

void main() {
  test('an export reads back with every setting and password', () {
    final text = encodeAccountExport([(_office, 'secret'), (_home, '')]);
    final accounts = decodeAccountExport(text);

    expect(accounts, hasLength(2));
    final (office, password) = accounts[0];
    expect(office.settings.toJson(), _office.settings.toJson());
    expect(office.enabled, isTrue);
    expect(office.ringtone, 'marimba');
    expect(password, 'secret');
    expect(office.id, isNot('a1'), reason: 'ids are per device');
    expect(accounts[1].$1.enabled, isFalse);
    expect(accounts[1].$2, '');
  });

  test('anything else is a FormatException', () {
    for (final text in [
      'not json',
      '[]',
      '{"accounts": []}',
      '{"sippier": "accounts", "version": 1, "accounts": [{"settings": {}}]}',
    ]) {
      expect(
        () => decodeAccountExport(text),
        throwsFormatException,
        reason: text,
      );
    }
  });

  test('a newer format is refused', () {
    expect(
      () => decodeAccountExport(
        '{"sippier": "accounts", "version": 2, "accounts": []}',
      ),
      throwsA(isA<NewerAccountExport>()),
    );
  });

  test('an account with the same address replaces the one there', () {
    final imported = decodeAccountExport(
      encodeAccountExport([(_office, 'new'), (_home, 'pw')]),
    );
    final existing = [AccountEntry(id: 'mine', settings: _office.settings)];

    final result = accountsToImport(imported, existing, const {});

    expect(result[0].$1.id, 'mine');
    expect(result[0].$2, 'new');
    expect(result[1].$1.id, imported[1].$1.id);
  });

  test('a ringtone file that isn\'t on this device falls back', () {
    final imported = decodeAccountExport(
      encodeAccountExport([(_office, ''), (_home, '')]),
    );

    final without = accountsToImport(imported, const [], const {});
    expect(without[0].$1.ringtone, 'marimba');
    expect(without[1].$1.ringtone, isNull);

    final withFile = accountsToImport(imported, const [], {'file:My song.m4a'});
    expect(withFile[1].$1.ringtone, 'file:My song.m4a');
  });
}
