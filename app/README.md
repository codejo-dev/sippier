# Sippier app

The Flutter app (macOS, Android, Windows). See the repository README for
building.

- `lib/phone/`: phone state and controller (Riverpod), fed by `sippier_core` events
- `lib/data/`: saved accounts (passwords in Keychain/Keystore), call history, audio and background settings
- `lib/ui/`: keypad, call screen, recents, accounts, settings
- `lib/l10n/`: English and German strings. Add a string to `app_en.arb` (the template) and `app_de.arb`; `flutter pub get`, `build` or `run` regenerate `app_localizations*.dart`. Widgets use `AppLocalizations.of(context)`, code without a context `ref.read(l10nProvider)`. The app follows the system's display language unless one is picked under Settings > General > Language (`language.json`); a new ARB file shows up there by itself, named by its `languageName`. Android's notification strings are in `android/app/src/main/res/values*/strings.xml`.
- `lib/platform_bridge.dart`: microphone permission, DNS servers, audio mode, ringing and the menu bar or tray (`MainActivity.kt`, `MainFlutterWindow.swift`, `windows/runner/flutter_window.cpp`)
