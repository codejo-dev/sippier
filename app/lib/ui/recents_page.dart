import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/call_history.dart';
import '../l10n/app_localizations.dart';
import '../providers.dart';
import 'common.dart';

class RecentsPage extends ConsumerWidget {
  const RecentsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final records = ref.watch(callHistoryProvider);
    final phone = ref.watch(phoneProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.navRecents),
        actions: [
          if (records.isNotEmpty)
            IconButton(
              onPressed: () => _confirmClear(context, ref),
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: l.recentsClear,
            ),
        ],
      ),
      body: records.isEmpty
          ? Center(child: Text(l.recentsEmpty))
          : ListView.builder(
              itemCount: records.length,
              itemBuilder: (context, i) {
                final r = records[i];
                final account = phone.account(r.accountId);
                final canCall = account != null && account.enabled;
                return ListTile(
                  leading: _DirectionIcon(r),
                  title: Text(_label(r)),
                  subtitle: Text(
                    [
                      formatTime(r.startedAt),
                      if (r.connectedAt != null) formatDuration(r.duration),
                      if (account != null) account.label,
                    ].join('  ·  '),
                  ),
                  trailing: IconButton(
                    onPressed: canCall
                        ? () => ref
                              .read(phoneProvider.notifier)
                              .dial(account.id, _number(r))
                        : null,
                    icon: const Icon(Icons.call),
                    tooltip: l.callBack,
                  ),
                );
              },
            ),
    );
  }

  static String _number(CallRecord r) {
    final m = RegExp(r'^sips?:([^@;>]+)').firstMatch(r.peerUri);
    return m?.group(1) ?? r.peerUri;
  }

  static String _label(CallRecord r) =>
      r.peerName.isNotEmpty ? r.peerName : _number(r);

  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.recentsClearQuestion),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.buttonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.buttonClear),
          ),
        ],
      ),
    );
    if (ok == true) ref.read(callHistoryProvider.notifier).clear();
  }
}

class _DirectionIcon extends StatelessWidget {
  const _DirectionIcon(this.record);

  final CallRecord record;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (record.missed) {
      return Icon(
        Icons.call_missed,
        color: Theme.of(context).colorScheme.error,
        semanticLabel: l.callMissed,
      );
    }
    return record.incoming
        ? Icon(Icons.call_received, semanticLabel: l.callIncoming)
        : Icon(Icons.call_made, semanticLabel: l.callOutgoing);
  }
}
