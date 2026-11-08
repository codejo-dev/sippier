import 'dart:convert';

import 'package:sippier_core/sippier_core.dart';

import 'account_store.dart';

/// Accounts in a file, to move them to another device or keep a copy. The
/// passwords are in it unencrypted:
///
///     {"sippier": "accounts", "version": 1, "accounts": [
///       {"settings": {"user": ..., "domain": ...}, "enabled": true,
///        "ringtone": "marimba", "password": "..."}]}
const accountExportFileName = 'sippier-accounts.json';

const _version = 1;

String encodeAccountExport(List<(AccountEntry, String)> accounts) =>
    const JsonEncoder.withIndent('  ').convert({
      'sippier': 'accounts',
      'version': _version,
      'accounts': [
        for (final (account, password) in accounts)
          {
            'settings': account.settings.toJson(),
            'enabled': account.enabled,
            if (account.ringtone != null) 'ringtone': account.ringtone,
            'password': password,
          },
      ],
    });

/// From a newer Sippier, with a format this one doesn't know.
class NewerAccountExport implements Exception {}

/// The accounts in an export, each with a new id and its password. Throws
/// a [FormatException] if [text] isn't one.
List<(AccountEntry, String)> decodeAccountExport(String text) {
  try {
    final json = jsonDecode(text) as Map<String, dynamic>;
    if (json['sippier'] != 'accounts') {
      throw const FormatException('not a Sippier accounts export');
    }
    if ((json['version'] as int) > _version) throw NewerAccountExport();
    return [
      for (final a in (json['accounts'] as List).cast<Map<String, dynamic>>())
        (
          AccountEntry(
            id: AccountStore.newId(),
            settings: AccountSettings.fromJson(
              a['settings'] as Map<String, dynamic>,
            ),
            enabled: a['enabled'] as bool? ?? true,
            ringtone: a['ringtone'] as String?,
          ),
          a['password'] as String? ?? '',
        ),
    ];
  } on TypeError {
    // A field of the wrong type, or missing
    throw const FormatException('not a Sippier accounts export');
  }
}

/// [imported] as they're saved: one with the same address as an account
/// already there replaces it, keeping its id. A ringtone picked from a file
/// that isn't on this device ([customRingtones]) falls back to the default.
List<(AccountEntry, String)> accountsToImport(
  List<(AccountEntry, String)> imported,
  List<AccountEntry> existing,
  Set<String> customRingtones,
) {
  final ids = {for (final a in existing) a.settings.aor: a.id};
  return [
    for (final (account, password) in imported)
      (
        AccountEntry(
          id: ids.putIfAbsent(account.settings.aor, () => account.id),
          settings: account.settings,
          enabled: account.enabled,
          ringtone:
              account.ringtone == null ||
                  !account.ringtone!.startsWith('file:') ||
                  customRingtones.contains(account.ringtone)
              ? account.ringtone
              : null,
        ),
        password,
      ),
  ];
}
