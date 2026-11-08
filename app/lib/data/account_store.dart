import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sippier_core/sippier_core.dart';


/// A saved account. The password is kept in the system keychain/keystore,
/// never in this object or in accounts.json.
class AccountEntry {
  const AccountEntry({
    required this.id,
    required this.settings,
    this.enabled = true,
    this.ringtone,
  });

  factory AccountEntry.fromJson(Map<String, dynamic> json) => AccountEntry(
    id: json['id'] as String,
    settings: AccountSettings.fromJson(
      json['settings'] as Map<String, dynamic>,
    ),
    enabled: json['enabled'] as bool? ?? true,
    ringtone: json['ringtone'] as String?,
  );

  final String id;
  final AccountSettings settings;

  /// Registered with the provider. Disabled accounts can't make calls.
  final bool enabled;

  /// Built-in ringtone for incoming calls on desktop; null uses the one in
  /// the audio settings.
  final String? ringtone;

  String get label =>
      settings.displayName.isNotEmpty ? settings.displayName : settings.user;

  /// [ringtone] returns the new value, so it can also clear it.
  AccountEntry copyWith({
    AccountSettings? settings,
    bool? enabled,
    String? Function()? ringtone,
  }) => AccountEntry(
    id: id,
    settings: settings ?? this.settings,
    enabled: enabled ?? this.enabled,
    ringtone: ringtone != null ? ringtone() : this.ringtone,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'settings': settings.toJson(),
    'enabled': enabled,
    if (ringtone != null) 'ringtone': ringtone,
  };
}

/// Accounts in `<app support>/accounts.json`, passwords in secure storage.
class AccountStore {
  AccountStore(String dir) : _file = File('$dir/accounts.json');

  final File _file;

  // The legacy macOS keychain needs no keychain-access-groups entitlement,
  // so the app runs without a provisioning profile. The items' service is
  // Sippier's own, not the plugin's default that every Flutter app shares,
  // so the keychain and its prompts name Sippier. (Up to 0.1.0-beta.2 it
  // was the default, flutter_secure_storage_service.)
  static const _secure = FlutterSecureStorage(
    mOptions: MacOsOptions(
      accountName: 'Sippier',
      usesDataProtectionKeychain: false,
    ),
  );

  static String newId() {
    final r = Random.secure();
    return List.generate(
      8,
      (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  List<AccountEntry> load() {
    if (!_file.existsSync()) return [];
    final json = jsonDecode(_file.readAsStringSync()) as Map<String, dynamic>;
    return [
      for (final a in json['accounts'] as List)
        AccountEntry.fromJson(a as Map<String, dynamic>),
    ];
  }

  Future<void> save(List<AccountEntry> accounts) async {
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'version': 1,
        'accounts': [for (final a in accounts) a.toJson()],
      }),
    );
    await tmp.rename(_file.path);
  }

  Future<String> password(String id) async =>
      await _secure.read(key: 'password.$id') ?? '';

  Future<void> setPassword(String id, String password) =>
      _secure.write(key: 'password.$id', value: password);

  Future<void> deletePassword(String id) => _secure.delete(key: 'password.$id');
}
