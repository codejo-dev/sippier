import '../l10n/app_localizations.dart';

/// A failed registration in words a user can act on. The provider's own
/// answer stays available for support.
class RegistrationProblem {
  const RegistrationProblem(this.summary, this.advice);

  /// [reason] is the provider's answer ("403 Forbidden - 6037 Identities do
  /// not match") or a local error ("Register: No route to host [65]").
  /// [stopped]: Sippier gave up after an auth failure (no automatic retry,
  /// so a wrong password can't trip a provider's lockout).
  factory RegistrationProblem.from(
    AppLocalizations l,
    String reason, {
    bool stopped = false,
  }) {
    final p = _explain(l, reason);
    return stopped
        ? RegistrationProblem(
            l.problemNotRetried(p.summary),
            l.problemNotRetriedAdvice(p.advice),
          )
        : p;
  }

  /// For the account list, e.g. "Login rejected".
  final String summary;

  /// What to do, for the account form.
  final String advice;
}

RegistrationProblem _explain(AppLocalizations l, String reason) {
  final r = reason.toLowerCase();
  final code = reason.length >= 3 ? int.tryParse(reason.substring(0, 3)) : null;

  if (code == 401 || code == 403 || code == 407) {
    return RegistrationProblem(
      l.problemLoginRejected,
      l.problemLoginRejectedAdvice,
    );
  }
  if (code == 404) {
    return RegistrationProblem(
      l.problemUnknownUser,
      l.problemUnknownUserAdvice,
    );
  }
  if (code == 423) {
    return RegistrationProblem(
      l.problemIntervalTooShort,
      l.problemIntervalTooShortAdvice,
    );
  }
  if (code == 408 ||
      code == 503 ||
      code == 504 ||
      r.contains('timed out') ||
      r.contains('timeout')) {
    return RegistrationProblem(l.problemNoAnswer, l.problemNoAnswerAdvice);
  }
  if (r.contains('no route to host') ||
      r.contains('network is unreachable') ||
      r.contains('network is down') ||
      r.contains('cannot assign requested address')) {
    return RegistrationProblem(l.problemNoNetwork, l.problemNoNetworkAdvice);
  }
  if (code == null &&
      (r.contains('no such') ||
          r.contains('not resolved') ||
          r.contains('not found'))) {
    return RegistrationProblem(
      l.problemServerNotFound,
      l.problemServerNotFoundAdvice,
    );
  }
  return RegistrationProblem(l.problemFailed, l.problemFailedAdvice);
}
