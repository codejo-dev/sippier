import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/account_store.dart';
import 'data/audio_settings.dart';
import 'data/background_settings.dart';
import 'data/call_history.dart';
import 'data/language_settings.dart';
import 'l10n/app_localizations.dart';
import 'phone/log_controller.dart';
import 'phone/phone_controller.dart';
import 'phone/phone_state.dart';
import 'platform_bridge.dart';

/// The app support directory, set in main().
final appDirProvider = Provider<String>((ref) => throw UnimplementedError());

/// The language picked in the settings, or null for the system's.
final languageProvider = NotifierProvider<LanguageController, String?>(
  LanguageController.new,
);

/// The language the app shows: the one picked in the settings, else the
/// system's display language as MaterialApp resolves it.
Locale appLocale(String? language) => language != null
    ? Locale(language)
    : basicLocaleListResolution(
        WidgetsBinding.instance.platformDispatcher.locales,
        AppLocalizations.supportedLocales,
      );

/// Strings for code without a BuildContext (the phone controller's errors
/// and the menu bar or tray status), in the app's language, also after it
/// or the system's changes.
final l10nProvider = Provider<AppLocalizations>((ref) {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  final observer = _LocaleObserver(ref.invalidateSelf);
  binding.addObserver(observer);
  ref.onDispose(() => binding.removeObserver(observer));
  return lookupAppLocalizations(appLocale(ref.watch(languageProvider)));
});

class _LocaleObserver with WidgetsBindingObserver {
  _LocaleObserver(this.onChange);

  final VoidCallback onChange;

  @override
  void didChangeLocales(List<Locale>? locales) => onChange();
}

final accountStoreProvider = Provider(
  (ref) => AccountStore(ref.watch(appDirProvider)),
);

final platformProvider = Provider((ref) => PlatformBridge());

final phoneProvider = NotifierProvider<PhoneController, PhoneState>(
  PhoneController.new,
);

final audioSettingsProvider =
    NotifierProvider<AudioSettingsController, AudioSettings>(
      AudioSettingsController.new,
    );

final stayAwakeProvider = NotifierProvider<StayAwakeController, bool>(
  StayAwakeController.new,
);

final callHistoryProvider = NotifierProvider<CallHistory, List<CallRecord>>(
  CallHistory.new,
);

final logProvider = NotifierProvider<LogController, List<String>>(
  LogController.new,
);
