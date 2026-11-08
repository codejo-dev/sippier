import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/account_store.dart';
import '../l10n/app_localizations.dart';
import '../providers.dart';
import 'common.dart';
import 'keypad.dart';

class DialerPage extends ConsumerStatefulWidget {
  const DialerPage({super.key, required this.onAddAccount});

  final VoidCallback onAddAccount;

  @override
  ConsumerState<DialerPage> createState() => _DialerPageState();
}

class _DialerPageState extends ConsumerState<DialerPage> {
  final _number = TextEditingController();
  final _focus = FocusNode();
  String? _accountId;

  @override
  void dispose() {
    _number.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _append(String key) {
    final sel = _number.selection;
    final text = _number.text;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    _number.value = TextEditingValue(
      text: text.replaceRange(start, end, key),
      selection: TextSelection.collapsed(offset: start + key.length),
    );
  }

  void _backspace() {
    final text = _number.text;
    if (text.isNotEmpty) _number.text = text.substring(0, text.length - 1);
  }

  void _call(AccountEntry account) {
    if (_number.text.trim().isEmpty) return;
    ref.read(phoneProvider.notifier).dial(account.id, _number.text);
    _number.clear();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final phone = ref.watch(phoneProvider);
    final accounts = [
      for (final a in phone.accounts)
        if (a.enabled) a,
    ];

    if (accounts.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.dialpad, size: 48),
            const SizedBox(height: 16),
            Text(l.dialerNoAccount),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: widget.onAddAccount,
              icon: const Icon(Icons.add),
              label: Text(l.addAccount),
            ),
          ],
        ),
      );
    }

    final account = accounts.firstWhere(
      (a) => a.id == _accountId,
      orElse: () => accounts.first,
    );

    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (accounts.length > 1)
                DropdownButton<String>(
                  value: account.id,
                  onChanged: (id) => setState(() => _accountId = id),
                  items: [
                    for (final a in accounts)
                      DropdownMenuItem(
                        value: a.id,
                        child: Row(
                          children: [
                            StatusDot(phone.statusOf(a.id).state),
                            const SizedBox(width: 8),
                            Text(a.label),
                          ],
                        ),
                      ),
                  ],
                )
              else
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    StatusDot(phone.statusOf(account.id).state),
                    const SizedBox(width: 8),
                    Text(account.label),
                  ],
                ),
              const SizedBox(height: 8),
              // Same width on both sides of the field keeps the number
              // centred over the keypad.
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(width: 48),
                  SizedBox(
                    width: 260,
                    child: TextField(
                      controller: _number,
                      focusNode: _focus,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium,
                      keyboardType: TextInputType.phone,
                      // The keypad is the input on phones
                      readOnly: MediaQuery.sizeOf(context).shortestSide < 600,
                      showCursor: true,
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: l.dialerNumberHint,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'[0-9+*#a-zA-Z@.:_-]'),
                        ),
                      ],
                      onSubmitted: (_) => _call(account),
                    ),
                  ),
                  SizedBox(
                    width: 48,
                    child: ListenableBuilder(
                      listenable: _number,
                      builder: (context, _) => _number.text.isEmpty
                          ? const SizedBox.shrink()
                          : IconButton(
                              onPressed: _backspace,
                              onLongPress: _number.clear,
                              icon: const Icon(Icons.backspace_outlined),
                              tooltip: l.dialerDelete,
                            ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Keypad(
                onKey: (key) {
                  ref.read(phoneProvider.notifier).playKeyTone(key);
                  _append(key);
                },
              ),
              const SizedBox(height: 16),
              SizedBox.square(
                dimension: 72,
                child: IconButton.filled(
                  onPressed: () => _call(account),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.call, size: 32),
                  tooltip: l.dialerCall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
