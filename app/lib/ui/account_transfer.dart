import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/account_export.dart';
import '../data/account_store.dart';
import '../data/audio_settings.dart';
import '../l10n/app_localizations.dart';
import '../providers.dart';

/// Export and import of the accounts (account_export.dart), from the
/// accounts page.

XTypeGroup _fileType(AppLocalizations l) => XTypeGroup(
  label: l.accountsFileType,
  extensions: const ['json'],
  uniformTypeIdentifiers: const ['public.json'],
  // Android: file managers don't all know .json
  mimeTypes: const ['application/json', 'application/octet-stream'],
);

/// Asks first, as the file has the passwords in plain text.
Future<void> exportAccounts(BuildContext context, WidgetRef ref) async {
  final l = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l.accountsExportTitle),
      content: Text(l.accountsExportWarning),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l.buttonCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(l.buttonExport),
        ),
      ],
    ),
  );
  if (ok != true) return;

  final accounts = ref.read(phoneProvider).accounts;
  final store = ref.read(accountStoreProvider);
  final content = encodeAccountExport([
    for (final a in accounts) (a, await store.password(a.id)),
  ]);
  try {
    final saved =
        await ref
            .read(platformProvider)
            .saveFile(accountExportFileName, 'application/json', content) ??
        await _saveWithDialog(l, content);
    if (saved) {
      messenger.showSnackBar(
        SnackBar(content: Text(l.accountsExported(accounts.length))),
      );
    }
  } on Exception {
    messenger.showSnackBar(SnackBar(content: Text(l.fileWriteFailed)));
  }
}

Future<bool> _saveWithDialog(AppLocalizations l, String content) async {
  final location = await getSaveLocation(
    suggestedName: accountExportFileName,
    acceptedTypeGroups: [_fileType(l)],
  );
  if (location == null) return false;
  await File(location.path).writeAsString(content);
  return true;
}

/// Shows what's in the file and asks before saving it.
Future<void> importAccounts(BuildContext context, WidgetRef ref) async {
  final l = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  void say(String text) =>
      messenger.showSnackBar(SnackBar(content: Text(text)));

  final file = await openFile(acceptedTypeGroups: [_fileType(l)]);
  if (file == null) return;
  final List<(AccountEntry, String)> imported;
  try {
    imported = decodeAccountExport(await file.readAsString());
  } on NewerAccountExport {
    return say(l.accountsImportNewer);
  } on FormatException {
    return say(l.accountsImportInvalid);
  }
  if (imported.isEmpty) return say(l.accountsImportInvalid);

  final toImport = accountsToImport(
    imported,
    ref.read(phoneProvider).accounts,
    customRingtones(ref.read(appDirProvider)).toSet(),
  );
  if (!context.mounted) return;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l.accountsImportTitle(toImport.length)),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (a, _) in toImport)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('${a.label}\n${a.settings.aor}'),
              ),
            const SizedBox(height: 8),
            Text(l.accountsImportReplaces),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l.buttonCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(l.buttonImport),
        ),
      ],
    ),
  );
  if (ok != true) return;

  final phone = ref.read(phoneProvider.notifier);
  for (final (account, password) in toImport) {
    await phone.saveAccount(account, password);
  }
  say(l.accountsImported(toImport.length));
}
