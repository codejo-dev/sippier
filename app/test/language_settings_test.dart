import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sippier/providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the picked language is saved and used for the strings', () async {
    final dir = await Directory.systemTemp.createTemp('sippier_language');
    addTearDown(() => dir.delete(recursive: true));
    ProviderContainer start() {
      final c = ProviderContainer(
        overrides: [appDirProvider.overrideWithValue(dir.path)],
      );
      addTearDown(c.dispose);
      return c;
    }

    final app = start();
    expect(app.read(languageProvider), isNull);
    // the test binding's system language is English
    expect(app.read(l10nProvider).navSettings, 'Settings');

    app.read(languageProvider.notifier).set('de');
    expect(app.read(l10nProvider).navSettings, 'Einstellungen');

    // after a restart
    final restarted = start();
    expect(restarted.read(languageProvider), 'de');
    restarted.read(languageProvider.notifier).set(null);
    expect(restarted.read(l10nProvider).navSettings, 'Settings');
  });

  test('a language this build lacks follows the system', () async {
    final dir = await Directory.systemTemp.createTemp('sippier_language');
    addTearDown(() => dir.delete(recursive: true));
    File('${dir.path}/language.json').writeAsStringSync('{"language":"xx"}');
    final c = ProviderContainer(
      overrides: [appDirProvider.overrideWithValue(dir.path)],
    );
    addTearDown(c.dispose);
    expect(c.read(languageProvider), isNull);
  });
}
