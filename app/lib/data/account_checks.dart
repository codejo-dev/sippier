// Mistakes in account fields that hold for every provider, caught in the
// form instead of as a failed registration (some providers block the
// connection after a few).

import '../l10n/app_localizations.dart';

/// Error for the username, or null.
String? checkUser(AppLocalizations l, String user) {
  final v = user.trim();
  if (v.contains('@') && !v.toLowerCase().startsWith('sip:')) {
    return l.checkUserDomain;
  }
  return _common(l, v);
}

/// Error for the auth username, or null. An @ is fine here: some providers
/// use an email-like auth name.
String? checkAuthUser(AppLocalizations l, String authUser) =>
    _common(l, authUser.trim());

String? _common(AppLocalizations l, String v) {
  if (v.toLowerCase().startsWith('sip:')) return l.checkWithoutSip;
  if (RegExp(r'\s').hasMatch(v)) return l.checkNoSpaces;
  return null;
}
