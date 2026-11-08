import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'l10n/app_localizations.dart';
import 'providers.dart';
import 'ui/home_shell.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _registerNativeLicenses();
  final dir = await getApplicationSupportDirectory();
  await dir.create(recursive: true);
  final container = ProviderContainer(
    overrides: [appDirProvider.overrideWithValue(dir.path)],
  );
  // Start the phone and log right away: on Android this engine may run in
  // the background without any UI.
  container
    ..read(phoneProvider)
    ..read(logProvider);
  runApp(
    UncontrolledProviderScope(container: container, child: const SippierApp()),
  );
}

class SippierApp extends ConsumerWidget {
  const SippierApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(languageProvider);
    return MaterialApp(
      title: 'Sippier',
      // English and German (lib/l10n): the one picked in the settings, else
      // the system's
      locale: language == null ? null : Locale(language),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: sippierTheme(Brightness.light),
      darkTheme: sippierTheme(Brightness.dark),
      home: const HomeShell(),
    );
  }
}

/// Licences of the native libraries built into libsippier_core, for the
/// licences page. Dart packages register their own.
void _registerNativeLicenses() {
  final packages = {
    'baresip': 'baresip',
    'libre': 'libre',
    'libg722': 'libg722',
    'opus': 'Opus',
    'openssl': 'OpenSSL',
    // echo cancellation, linked in on desktop only (Android uses the
    // platform's)
    if (defaultTargetPlatform != TargetPlatform.android) ...{
      'webrtc-audio-processing': 'WebRTC audio processing',
      'abseil': 'Abseil',
    },
  };
  LicenseRegistry.addLicense(() async* {
    for (final MapEntry(key: file, value: name) in packages.entries) {
      yield LicenseEntryWithLineBreaks([
        name,
      ], await rootBundle.loadString('assets/licenses/$file.txt'));
    }
  });
}
