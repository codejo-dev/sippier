import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../providers.dart';
import 'account_form.dart';
import 'account_transfer.dart';
import 'common.dart';

class AccountsPage extends ConsumerWidget {
  const AccountsPage({super.key});

  static Future<void> openForm(BuildContext context, {String? accountId}) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AccountForm(accountId: accountId),
        ),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final phone = ref.watch(phoneProvider);
    final notifier = ref.read(phoneProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.navAccounts),
        actions: [
          PopupMenuButton<void Function()>(
            onSelected: (action) => action(),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: () => exportAccounts(context, ref),
                enabled: phone.accounts.isNotEmpty,
                child: Text(l.accountsExport),
              ),
              PopupMenuItem(
                value: () => importAccounts(context, ref),
                child: Text(l.accountsImport),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openForm(context),
        icon: const Icon(Icons.add),
        label: Text(l.addAccount),
      ),
      body: phone.accounts.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(l.accountsEmpty, textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    // e.g. on a new device, from an export of the old one
                    TextButton.icon(
                      onPressed: () => importAccounts(context, ref),
                      icon: const Icon(Icons.file_open_outlined),
                      label: Text(l.accountsImport),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              children: [
                for (final a in phone.accounts)
                  InkWell(
                    onTap: () => openForm(context, accountId: a.id),
                    // The status bar spans the row, same margin top and
                    // bottom.
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 10, 0, 10),
                            child: StatusBar(phone.statusOf(a.id).state),
                          ),
                          Expanded(
                            child: ListTile(
                              contentPadding: const EdgeInsets.only(
                                left: 12,
                                right: 16,
                              ),
                              title: Text(a.label),
                              subtitle: Text(
                                '${a.settings.aor}\n'
                                '${regStateLabel(l, phone.statusOf(a.id))}',
                              ),
                              isThreeLine: true,
                              trailing: Switch(
                                value: a.enabled,
                                onChanged: (v) => notifier.setEnabled(a, v),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
