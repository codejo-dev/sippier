import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'sip/phone.dart';
import 'sip/sippier_core.dart';

/// Path to libsippier_core, passed with --dart-define (see run_macos.sh).
const _corePath = String.fromEnvironment('SIPPIER_CORE_LIB');

void main() {
  runApp(const SpikeApp());
}

class SpikeApp extends StatelessWidget {
  const SpikeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sippier spike',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      darkTheme: ThemeData(
          colorSchemeSeed: Colors.teal,
          brightness: Brightness.dark,
          useMaterial3: true),
      home: _corePath.isEmpty
          ? const Scaffold(
              body: Center(
                  child: Text('Start with run_macos.sh '
                      '(SIPPIER_CORE_LIB is not set).')))
          : const PhoneScreen(),
    );
  }
}

class PhoneScreen extends StatefulWidget {
  const PhoneScreen({super.key});

  @override
  State<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends State<PhoneScreen> {
  late final Phone _phone = Phone(SippierCore(_corePath));
  late final AppLifecycleListener _lifecycle;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _phone.addListener(_onChange);
    _phone.start();
    _lifecycle = AppLifecycleListener(onExitRequested: () async {
      _phone.shutdown();
      return AppExitResponse.exit;
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_phone.calls.values.any((c) => c.connectedAt != null)) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _lifecycle.dispose();
    _phone.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sippier spike'),
        bottom: _phone.error == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(28),
                child: Container(
                  width: double.infinity,
                  color: Theme.of(context).colorScheme.errorContainer,
                  padding: const EdgeInsets.all(6),
                  child: Text(_phone.error!),
                ),
              ),
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: 340, child: _AccountsPane(phone: _phone)),
          const VerticalDivider(width: 1),
          SizedBox(width: 400, child: _CallsPane(phone: _phone)),
          const VerticalDivider(width: 1),
          Expanded(child: _LogPane(phone: _phone)),
        ],
      ),
    );
  }
}

class _AccountsPane extends StatelessWidget {
  const _AccountsPane({required this.phone});

  final Phone phone;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(children: [
          Text('Accounts', style: Theme.of(context).textTheme.titleMedium),
          const Spacer(),
          FilledButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Add'),
            onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => _AccountDialog(phone: phone)),
          ),
        ]),
        const SizedBox(height: 8),
        for (final a in phone.accounts)
          Card(
            child: ListTile(
              leading: Icon(switch (a.state) {
                RegState.registered => Icons.check_circle,
                RegState.registering => Icons.sync,
                RegState.failed => Icons.error,
                RegState.idle => Icons.circle_outlined,
              }, color: switch (a.state) {
                RegState.registered => Colors.green,
                RegState.failed => Colors.red,
                _ => null,
              }),
              title: Text(a.config.aor),
              subtitle: Text('${a.state.name} ${a.detail}'.trim()),
              onTap: () => _edit(context, a),
              trailing: PopupMenuButton<String>(
                onSelected: (v) => switch (v) {
                  'edit' => _edit(context, a),
                  'register' => phone.setRegistered(a, true),
                  'unregister' => phone.setRegistered(a, false),
                  _ => phone.removeAccount(a),
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'register', child: Text('Register')),
                  PopupMenuItem(
                      value: 'unregister', child: Text('Unregister')),
                  PopupMenuItem(value: 'remove', child: Text('Remove')),
                ],
              ),
            ),
          ),
      ],
    );
  }

  void _edit(BuildContext context, Account account) {
    showDialog<void>(
        context: context,
        builder: (_) => _AccountDialog(phone: phone, existing: account));
  }
}

class _AccountDialog extends StatefulWidget {
  const _AccountDialog({required this.phone, this.existing});

  final Phone phone;

  /// The account being edited, or null when adding one.
  final Account? existing;

  @override
  State<_AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<_AccountDialog> {
  Preset _preset = Preset.other;
  final _display = TextEditingController();
  final _user = TextEditingController();
  final _authUser = TextEditingController();
  final _password = TextEditingController();
  final _domain = TextEditingController();
  final _proxy = TextEditingController();
  final _regInterval = TextEditingController();
  final _codecs = TextEditingController();
  String _transport = 'udp';
  String _srtp = 'off';

  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final c = widget.existing?.config;
    if (c == null) {
      _applyPreset(Preset.other);
      return;
    }
    _preset = c.preset;
    _display.text = c.displayName;
    _user.text = c.user;
    _authUser.text = c.authUser;
    _domain.text = c.domain;
    _proxy.text = c.outboundProxy;
    _transport = c.transport;
    _regInterval.text = '${c.regInterval}';
    _codecs.text = c.codecs;
    _srtp = c.srtp;
  }

  void _applyPreset(Preset p) {
    setState(() {
      _preset = p;
      _domain.text = p.domain;
      _transport = p.transport;
      _regInterval.text = '${p.regInterval}';
      _codecs.text = p.codecs;
    });
  }

  void _submit() {
    final config = AccountConfig(
      preset: _preset,
      displayName: _display.text.trim(),
      user: _user.text.trim(),
      authUser: _authUser.text.trim(),
      domain: _domain.text.trim(),
      outboundProxy: _proxy.text.trim(),
      transport: _transport,
      regInterval: int.tryParse(_regInterval.text) ?? _preset.regInterval,
      codecs: _codecs.text.replaceAll(' ', ''),
      srtp: _srtp,
    );
    final existing = widget.existing;
    if (existing == null) {
      widget.phone.addAccount(config, _password.text);
    } else {
      widget.phone.updateAccount(existing, config, _password.text);
    }
    _password.clear();
    Navigator.of(context).pop();
  }

  Widget _field(TextEditingController c, String label,
      {String? hint, bool obscure = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: c,
        obscureText: obscure,
        decoration: InputDecoration(
            labelText: label, hintText: hint, isDense: true),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_editing ? 'Edit SIP account' : 'Add SIP account'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<Preset>(
              initialValue: _preset,
              decoration: const InputDecoration(labelText: 'Provider preset'),
              items: [
                for (final p in Preset.values)
                  DropdownMenuItem(value: p, child: Text(p.label)),
              ],
              onChanged: (p) => _applyPreset(p!),
            ),
            if (_preset.hint.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_preset.hint,
                    style: Theme.of(context).textTheme.bodySmall),
              ),
            const SizedBox(height: 8),
            _field(_display, 'Display name'),
            _field(_user, 'SIP username / number'),
            _field(_authUser, 'Auth username (if different)'),
            _field(_password, 'Password',
                hint: _editing ? 'leave empty to keep the current one' : null,
                obscure: true),
            _field(_domain, 'Domain / registrar',
                hint: 'from your provider portal'),
            _field(_proxy, 'Outbound proxy (optional)', hint: 'host[:port]'),
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _transport,
                  decoration: const InputDecoration(labelText: 'Transport'),
                  items: const [
                    DropdownMenuItem(value: 'udp', child: Text('UDP')),
                    DropdownMenuItem(value: 'tcp', child: Text('TCP')),
                    DropdownMenuItem(value: 'tls', child: Text('TLS')),
                  ],
                  onChanged: (v) => setState(() => _transport = v!),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _srtp,
                  decoration: const InputDecoration(labelText: 'SRTP'),
                  items: const [
                    DropdownMenuItem(value: 'off', child: Text('Off')),
                    DropdownMenuItem(value: 'srtp', child: Text('Optional')),
                    DropdownMenuItem(
                        value: 'srtp-mand', child: Text('Mandatory')),
                  ],
                  onChanged: (v) => setState(() => _srtp = v!),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            _field(_regInterval, 'Registration interval (s)'),
            _field(_codecs, 'Codecs (in order)'),
          ]),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: _submit,
            child: Text(_editing ? 'Save & register' : 'Add & register')),
      ],
    );
  }
}

class _CallsPane extends StatefulWidget {
  const _CallsPane({required this.phone});

  final Phone phone;

  @override
  State<_CallsPane> createState() => _CallsPaneState();
}

class _CallsPaneState extends State<_CallsPane> {
  final _number = TextEditingController();
  Account? _account;

  @override
  Widget build(BuildContext context) {
    final phone = widget.phone;
    final accounts = phone.accounts;
    if (_account != null && !accounts.contains(_account)) _account = null;
    _account ??= accounts.isEmpty ? null : accounts.first;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text('Call', style: Theme.of(context).textTheme.titleMedium),
        DropdownButton<Account>(
          isExpanded: true,
          value: _account,
          hint: const Text('Add an account first'),
          items: [
            for (final a in accounts)
              DropdownMenuItem(value: a, child: Text(a.config.aor)),
          ],
          onChanged: (a) => setState(() => _account = a),
        ),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _number,
              decoration: const InputDecoration(
                  labelText: 'Number or SIP URI', isDense: true),
              onSubmitted: (_) => _dial(),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
              onPressed: _account == null ? null : _dial,
              icon: const Icon(Icons.call),
              label: const Text('Call')),
        ]),
        const SizedBox(height: 16),
        for (final call in phone.calls.values) _CallCard(phone: phone, call: call),
        if (phone.endedCalls.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Recently ended', style: Theme.of(context).textTheme.titleSmall),
          for (final c in phone.endedCalls)
            ListTile(
              dense: true,
              leading: Icon(c.incoming ? Icons.call_received : Icons.call_made),
              title: Text(c.peer),
              subtitle: Text(c.endReason.isEmpty ? 'Ended' : c.endReason),
            ),
        ],
      ],
    );
  }

  void _dial() {
    if (_account == null || _number.text.trim().isEmpty) return;
    widget.phone.dial(_account!, _number.text);
  }
}

class _CallCard extends StatefulWidget {
  const _CallCard({required this.phone, required this.call});

  final Phone phone;
  final Call call;

  @override
  State<_CallCard> createState() => _CallCardState();
}

class _CallCardState extends State<_CallCard> {
  bool _showKeypad = false;

  String _duration(DateTime? since) {
    if (since == null) return '';
    final d = DateTime.now().difference(since);
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return ' · $m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final call = widget.call;
    final phone = widget.phone;
    final ringingIn = call.incoming && call.state == 'Incoming';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(call.peer, style: Theme.of(context).textTheme.titleSmall),
          Text('${call.incoming ? 'Incoming' : 'Outgoing'} · ${call.state}'
              '${_duration(call.connectedAt)}'
              '${call.remoteHold ? ' · held by peer' : ''}'),
          if (call.encryption.isNotEmpty) Text('Encryption: ${call.encryption}'),
          if (call.quality.isNotEmpty) Text(call.quality),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (ringingIn)
              FilledButton.icon(
                  onPressed: () => phone.answer(call),
                  icon: const Icon(Icons.call),
                  label: const Text('Answer')),
            FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                    backgroundColor:
                        Theme.of(context).colorScheme.errorContainer),
                onPressed: () => phone.hangup(call),
                icon: const Icon(Icons.call_end),
                label: Text(ringingIn ? 'Reject' : 'Hang up')),
            if (!ringingIn) ...[
              OutlinedButton(
                  onPressed: () => phone.toggleMute(call),
                  child: Text(call.muted ? 'Unmute' : 'Mute')),
              OutlinedButton(
                  onPressed: () => phone.toggleHold(call),
                  child: Text(call.onHold ? 'Resume' : 'Hold')),
              OutlinedButton(
                  onPressed: () => setState(() => _showKeypad = !_showKeypad),
                  child: const Text('Keypad')),
            ],
          ]),
          if (_showKeypad)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(spacing: 6, runSpacing: 6, children: [
                for (final k in '123456789*0#'.split(''))
                  SizedBox(
                    width: 48,
                    child: OutlinedButton(
                        onPressed: () => phone.dtmf(call, k), child: Text(k)),
                  ),
              ]),
            ),
        ]),
      ),
    );
  }
}

class _LogPane extends StatefulWidget {
  const _LogPane({required this.phone});

  final Phone phone;

  @override
  State<_LogPane> createState() => _LogPaneState();
}

class _LogPaneState extends State<_LogPane> {
  bool _sipTrace = false;

  @override
  Widget build(BuildContext context) {
    final logs = widget.phone.logs;
    final logFile = '${widget.phone.configDir}/sippier.log';

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Row(children: [
          Text('Log', style: Theme.of(context).textTheme.titleMedium),
          const Spacer(),
          const Text('SIP trace to file'),
          Switch(
              value: _sipTrace,
              onChanged: (v) {
                widget.phone.setSipTrace(v);
                setState(() => _sipTrace = v);
              }),
          IconButton(
              tooltip: 'Copy log file path',
              icon: const Icon(Icons.copy),
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: logFile))),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: SelectableText(logFile,
            style: Theme.of(context).textTheme.bodySmall),
      ),
      const Divider(),
      Expanded(
        child: ListView.builder(
          reverse: true,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: logs.length,
          itemBuilder: (_, i) => Text(logs[logs.length - 1 - i],
              style: const TextStyle(fontFamily: 'Menlo', fontSize: 11)),
        ),
      ),
    ]);
  }
}
