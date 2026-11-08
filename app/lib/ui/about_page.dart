import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../providers.dart';

const _website = 'https://github.com/codejo-dev/sippier';
const _author = 'https://codejo.com';
const _licence = '$_website/blob/main/LICENSE';

// Set by the flutter tool from --build-name and --build-number (the release
// workflow passes the tag's version), else from pubspec.yaml.
const _version = String.fromEnvironment('FLUTTER_BUILD_NAME');
const _build = String.fromEnvironment('FLUTTER_BUILD_NUMBER');

/// The app's version, author and website, and the licences of everything
/// built into it: the Dart packages' and the native libraries' (registered
/// in main.dart).
class AboutPage extends ConsumerWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = TextStyle(color: theme.colorScheme.onSurfaceVariant);
    void open(String url) => ref.read(platformProvider).openUrl(url);
    return Scaffold(
      appBar: AppBar(title: Text(l.navAbout)),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Sippier', style: theme.textTheme.headlineMedium),
                if (_version.isNotEmpty)
                  Text(
                    l.aboutVersion(
                      _build.isEmpty ? _version : '$_version ($_build)',
                    ),
                    style: muted,
                  ),
                const SizedBox(height: 12),
                Text(l.aboutTagline),
              ],
            ),
          ),
          ListTile(
            title: Text(l.aboutAuthor),
            subtitle: const Text('codejo'),
            trailing: const Icon(Icons.open_in_new),
            onTap: () => open(_author),
          ),
          ListTile(
            title: Text(l.aboutWebsite),
            subtitle: const Text('github.com/codejo-dev/sippier'),
            trailing: const Icon(Icons.open_in_new),
            onTap: () => open(_website),
          ),
          ListTile(
            title: Text(l.aboutLicence),
            subtitle: const Text(
              'Apache License 2.0\nCopyright 2026 The Sippier Authors',
            ),
            isThreeLine: true,
            trailing: const Icon(Icons.open_in_new),
            onTap: () => open(_licence),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Text(
              l.licences,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          const _Licences(),
        ],
      ),
    );
  }
}

/// Licences by package, in alphabetical order. Loaded once, the first time
/// the page opens.
final Future<SplayTreeMap<String, List<LicenseEntry>>> _licencesByPackage =
    () async {
      final packages = SplayTreeMap<String, List<LicenseEntry>>(
        (a, b) => a.toLowerCase().compareTo(b.toLowerCase()),
      );
      await for (final entry in LicenseRegistry.licenses) {
        for (final package in entry.packages) {
          (packages[package] ??= []).add(entry);
        }
      }
      return packages;
    }();

class _Licences extends StatelessWidget {
  const _Licences();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return FutureBuilder(
      future: _licencesByPackage,
      builder: (context, snapshot) {
        final packages = snapshot.data;
        if (packages == null) {
          return snapshot.hasError
              ? const SizedBox.shrink()
              : const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                );
        }
        return Column(
          children: [
            for (final MapEntry(key: package, value: entries)
                in packages.entries)
              ListTile(
                title: Text(package),
                subtitle: Text(l.licenceCount(entries.length)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => _LicencePage(package, entries),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// One package's licence texts.
class _LicencePage extends StatelessWidget {
  const _LicencePage(this.package, this.entries);

  final String package;
  final List<LicenseEntry> entries;

  @override
  Widget build(BuildContext context) {
    final bold = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold);
    return Scaffold(
      appBar: AppBar(title: Text(package)),
      body: SelectionArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            for (final (i, entry) in entries.indexed) ...[
              if (i > 0) const Divider(height: 32),
              for (final paragraph in entry.paragraphs)
                if (paragraph.indent == LicenseParagraph.centeredIndent)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      paragraph.text,
                      style: bold,
                      textAlign: TextAlign.center,
                    ),
                  )
                else
                  Padding(
                    padding: EdgeInsetsDirectional.only(
                      top: 8,
                      start: 16.0 * paragraph.indent,
                    ),
                    child: Text(paragraph.text),
                  ),
            ],
          ],
        ),
      ),
    );
  }
}
