import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sippier_core/sippier_core.dart';

import '../data/account_checks.dart';
import '../data/account_store.dart';
import '../data/audio_settings.dart';
import '../l10n/app_localizations.dart';
import '../phone/phone_state.dart';
import '../phone/registration_problem.dart';
import '../providers.dart';
import 'audio_settings_section.dart';

/// Add or edit an account. The password is typed here and goes straight to
/// secure storage and the core; it's never shown again.
class AccountForm extends ConsumerStatefulWidget {
  const AccountForm({super.key, this.accountId});

  /// null to add a new account.
  final String? accountId;

  @override
  ConsumerState<AccountForm> createState() => _AccountFormState();
}

class _AccountFormState extends ConsumerState<AccountForm> {
  final _form = GlobalKey<FormState>();
  final _displayName = TextEditingController();
  final _user = TextEditingController();
  final _password = TextEditingController();
  final _domain = TextEditingController();
  final _authUser = TextEditingController();
  final _outboundProxy = TextEditingController();
  final _regInterval = TextEditingController();
  final _codecs = TextEditingController();
  final _stunServer = TextEditingController();
  String _transport = 'udp';
  String _mediaEncryption = '';

  /// Null uses the default ringtone from the audio settings.
  String? _ringtone;

  bool _obscure = true;
  AccountEntry? _existing;

  @override
  void initState() {
    super.initState();
    final id = widget.accountId;
    _existing = id == null ? null : ref.read(phoneProvider).account(id);
    final e = _existing;
    if (e == null) {
      // providers that want a longer interval say so (423 Min-Expires) and
      // libre follows; codecs the provider lacks are skipped in the offer
      _regInterval.text = '600';
      _codecs.text = 'opus/48000/2,G722/16000/1,PCMA,PCMU';
      return;
    }
    final s = e.settings;
    _displayName.text = s.displayName;
    _user.text = s.user;
    _domain.text = s.domain;
    _authUser.text = s.authUser;
    _outboundProxy.text = s.outboundProxy;
    _regInterval.text = '${s.regInterval}';
    _codecs.text = s.codecs;
    _stunServer.text = s.stunServer;
    _transport = s.transport;
    _mediaEncryption = s.mediaEncryption;
    _ringtone = e.ringtone;
  }

  @override
  void dispose() {
    for (final c in [
      _displayName,
      _user,
      _password,
      _domain,
      _authUser,
      _outboundProxy,
      _regInterval,
      _codecs,
      _stunServer,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Why the saved account didn't register, with what to do.
  Widget? _problemBanner() {
    final e = _existing;
    if (e == null) return null;
    final status = ref.watch(phoneProvider).statusOf(e.id);
    if (status.state != RegState.failed) return null;
    final l = AppLocalizations.of(context);
    final problem = RegistrationProblem.from(
      l,
      status.detail,
      stopped: status.stopped,
    );
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.errorContainer,
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              problem.summary,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              problem.advice,
              style: TextStyle(color: theme.colorScheme.onErrorContainer),
            ),
            const SizedBox(height: 4),
            Text(
              l.providerSaid(status.detail),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Desktop only: Android rings with its notification channel's sound.
  Widget _ringtoneField() => RingtoneField(
    value: _ringtone,
    defaultTone:
        ref.watch(audioSettingsProvider).ringtone ??
        defaultRingtone(SippierCore.instance.ringtones()),
    onChanged: (t) => setState(() => _ringtone = t),
  );

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final settings = AccountSettings(
      displayName: _displayName.text.trim(),
      user: _user.text.trim(),
      domain: _domain.text.trim(),
      authUser: _authUser.text.trim(),
      outboundProxy: _outboundProxy.text.trim(),
      transport: _transport,
      regInterval: int.parse(_regInterval.text.trim()),
      codecs: _codecs.text.replaceAll(' ', ''),
      mediaEncryption: _mediaEncryption,
      stunServer: _stunServer.text.trim(),
    );
    final entry =
        _existing?.copyWith(settings: settings, ringtone: () => _ringtone) ??
        AccountEntry(
          id: AccountStore.newId(),
          settings: settings,
          ringtone: _ringtone,
        );
    await ref.read(phoneProvider.notifier).saveAccount(entry, _password.text);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _remove() async {
    final e = _existing!;
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.removeAccountQuestion(e.label)),
        content: Text(l.removeAccountExplanation),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.buttonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.buttonRemove),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(phoneProvider.notifier).removeAccount(e);
    if (mounted) Navigator.pop(context);
  }

  String? _required(String? v) => v == null || v.trim().isEmpty
      ? AppLocalizations.of(context).fieldRequired
      : null;

  String? _hostPort(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    return RegExp(r'^[\w.\-\[\]:]+$').hasMatch(v.trim())
        ? null
        : AppLocalizations.of(context).fieldHostPort;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final editing = _existing != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? l.editAccount : l.addAccount),
        actions: [
          if (editing)
            IconButton(
              onPressed: _remove,
              icon: const Icon(Icons.delete_outline),
              tooltip: l.removeAccount,
            ),
          TextButton(onPressed: _save, child: Text(l.buttonSave)),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ?_problemBanner(),
            TextFormField(
              controller: _displayName,
              decoration: InputDecoration(
                labelText: l.fieldName,
                hintText: l.fieldNameHint,
              ),
            ),
            TextFormField(
              controller: _user,
              decoration: InputDecoration(
                labelText: l.fieldUser,
                errorMaxLines: 2,
              ),
              validator: (v) => _required(v) ?? checkUser(l, v!),
              // a saved account may already hold a wrong value
              autovalidateMode: _existing != null
                  ? AutovalidateMode.always
                  : AutovalidateMode.onUserInteraction,
              autocorrect: false,
            ),
            TextFormField(
              controller: _password,
              obscureText: _obscure,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: l.fieldPassword,
                helperText: editing ? l.fieldPasswordKeep : null,
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(
                    _obscure ? Icons.visibility : Icons.visibility_off,
                  ),
                ),
              ),
              validator: editing ? null : _required,
            ),
            TextFormField(
              controller: _domain,
              decoration: InputDecoration(
                labelText: l.fieldDomain,
                hintText: 'sip.example.net',
              ),
              validator: (v) => _required(v) ?? _hostPort(v),
              autocorrect: false,
            ),
            TextFormField(
              controller: _authUser,
              decoration: InputDecoration(
                labelText: l.fieldAuthUser,
                errorMaxLines: 2,
              ),
              validator: (v) => checkAuthUser(l, v ?? ''),
              // a saved account may already hold a wrong value
              autovalidateMode: _existing != null
                  ? AutovalidateMode.always
                  : AutovalidateMode.onUserInteraction,
              autocorrect: false,
            ),
            TextFormField(
              controller: _outboundProxy,
              decoration: InputDecoration(
                labelText: l.fieldOutboundProxy,
                hintText: 'proxy.example.net',
              ),
              validator: _hostPort,
              autocorrect: false,
            ),
            if (!Platform.isAndroid) _ringtoneField(),
            const SizedBox(height: 8),
            ExpansionTile(
              title: Text(l.fieldAdvanced),
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 16),
              children: [
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'udp', label: Text('UDP')),
                    ButtonSegment(value: 'tcp', label: Text('TCP')),
                    ButtonSegment(value: 'tls', label: Text('TLS')),
                  ],
                  selected: {_transport},
                  onSelectionChanged: (s) =>
                      setState(() => _transport = s.first),
                ),
                DropdownButtonFormField<String>(
                  initialValue: _mediaEncryption,
                  decoration: InputDecoration(
                    labelText: l.fieldMediaEncryption,
                  ),
                  items: [
                    DropdownMenuItem(value: '', child: Text(l.encryptionOff)),
                    DropdownMenuItem(
                      value: 'srtp',
                      child: Text(l.encryptionIfOffered),
                    ),
                    DropdownMenuItem(
                      value: 'srtp-mand',
                      child: Text(l.encryptionRequired),
                    ),
                  ],
                  onChanged: (v) => setState(() => _mediaEncryption = v!),
                ),
                TextFormField(
                  controller: _regInterval,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: l.fieldRegInterval),
                  validator: (v) {
                    final n = int.tryParse(v?.trim() ?? '');
                    return n == null || n < 60 ? l.fieldRegIntervalMin : null;
                  },
                ),
                TextFormField(
                  controller: _codecs,
                  decoration: InputDecoration(
                    labelText: l.fieldCodecs,
                    helperText: l.fieldCodecsHint,
                  ),
                  autocorrect: false,
                ),
                TextFormField(
                  controller: _stunServer,
                  decoration: InputDecoration(
                    labelText: l.fieldStun,
                    hintText: 'stun.example.net:3478',
                  ),
                  validator: _hostPort,
                  autocorrect: false,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
