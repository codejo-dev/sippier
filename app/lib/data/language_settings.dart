import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../providers.dart';

/// The app's language, in `<app support>/language.json`: a language code
/// from lib/l10n ("en", "de"), or null to follow the system's display
/// language (the default).
class LanguageController extends Notifier<String?> {
  File get _file => File('${ref.read(appDirProvider)}/language.json');

  @override
  String? build() {
    if (!_file.existsSync()) return null;
    try {
      final json = jsonDecode(_file.readAsStringSync()) as Map<String, dynamic>;
      final language = json['language'] as String?;
      // one this build doesn't have follows the system
      return AppLocalizations.supportedLocales.any(
            (l) => l.languageCode == language,
          )
          ? language
          : null;
    } catch (_) {
      return null;
    }
  }

  void set(String? language) {
    state = language;
    final tmp = File('${_file.path}.tmp');
    tmp.writeAsStringSync(jsonEncode({'language': language}));
    tmp.renameSync(_file.path);
    // Android: the notifications follow it too
    unawaited(ref.read(platformProvider).setLanguage(language));
  }
}
