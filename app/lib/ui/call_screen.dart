import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../phone/phone_state.dart';
import '../providers.dart';
import 'common.dart';
import 'keypad.dart';

/// Shown while there are calls. The main call is the newest active one;
/// held and waiting calls appear as banners.
class CallScreen extends ConsumerStatefulWidget {
  const CallScreen({super.key});

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> {
  Timer? _ticker;
  bool _showKeypad = false;
  String _dtmf = '';

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final phone = ref.watch(phoneProvider);
    final notifier = ref.read(phoneProvider.notifier);
    final calls = phone.calls;
    final main = calls.reversed.firstWhere(
      (c) => !c.ringingIn && !c.onHold,
      orElse: () =>
          calls.firstWhere((c) => !c.ringingIn, orElse: () => calls.first),
    );
    final waiting = [
      for (final c in calls)
        if (c != main && c.ringingIn) c,
    ];
    final others = [
      for (final c in calls)
        if (c != main && !c.ringingIn) c,
    ];
    final text = Theme.of(context).textTheme;
    final account = phone.account(main.accountId);

    // Fills the screen when there's room (the spacers spread the content)
    // and scrolls when there isn't, e.g. with the keypad in a small window.
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final height = constraints.maxHeight;
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            for (final c in waiting) _WaitingBanner(call: c),
                            for (final c in others) _OtherCallBanner(call: c),
                            const Spacer(),
                            if (!_showKeypad) ...[
                              CircleAvatar(
                                radius: 44,
                                child: main.peerName.isEmpty
                                    ? const Icon(Icons.person, size: 44)
                                    : Text(
                                        main.peerName.characters.first,
                                        style: text.headlineLarge,
                                      ),
                              ),
                              const SizedBox(height: 16),
                            ],
                            Text(
                              main.peerLabel,
                              style: text.headlineMedium,
                              textAlign: TextAlign.center,
                            ),
                            if (main.peerName.isNotEmpty)
                              Text(main.peerNumber, style: text.bodyLarge),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (main.encryption.isNotEmpty) ...[
                                  const Icon(Icons.lock, size: 16),
                                  const SizedBox(width: 4),
                                ],
                                Text(
                                  _statusText(l, main),
                                  style: text.titleMedium,
                                ),
                              ],
                            ),
                            if (account != null)
                              Text(
                                l.callVia(account.label),
                                style: text.bodySmall,
                              ),
                            const Spacer(),
                            if (main.ringingIn)
                              const SizedBox.shrink()
                            else if (_showKeypad) ...[
                              Text(_dtmf, style: text.headlineSmall),
                              const SizedBox(height: 8),
                              Keypad(
                                buttonSize: height < 520
                                    ? 44
                                    : height < 700
                                    ? 56
                                    : 64,
                                onKey: (k) {
                                  setState(() => _dtmf += k);
                                  notifier.sendDtmf(main, k);
                                },
                              ),
                              TextButton(
                                onPressed: () =>
                                    setState(() => _showKeypad = false),
                                child: Text(l.callHideKeypad),
                              ),
                            ] else
                              Wrap(
                                spacing: 24,
                                runSpacing: 16,
                                alignment: WrapAlignment.center,
                                children: [
                                  CallControl(
                                    icon: main.muted
                                        ? Icons.mic_off
                                        : Icons.mic,
                                    label: l.callMute,
                                    active: main.muted,
                                    onPressed: () => notifier.toggleMute(main),
                                  ),
                                  CallControl(
                                    icon: Icons.dialpad,
                                    label: l.callKeypad,
                                    onPressed: () =>
                                        setState(() => _showKeypad = true),
                                  ),
                                  if (Platform.isAndroid || Platform.isIOS)
                                    CallControl(
                                      icon: Icons.volume_up,
                                      label: l.callSpeaker,
                                      active: phone.speaker,
                                      onPressed: notifier.toggleSpeaker,
                                    ),
                                  CallControl(
                                    icon: Icons.pause,
                                    label: main.onHold
                                        ? l.callResume
                                        : l.callHold,
                                    active: main.onHold,
                                    onPressed: main.phase == CallPhase.connected
                                        ? () => notifier.toggleHold(main)
                                        : null,
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
      // Always reachable, also when the content above scrolls
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: main.ringingIn
              ? _IncomingControls(call: main)
              : Center(
                  heightFactor: 1,
                  child: CallControl(
                    icon: Icons.call_end,
                    label: l.callEnd,
                    color: Colors.red,
                    onPressed: () => notifier.hangup(main),
                  ),
                ),
        ),
      ),
    );
  }

  String _statusText(AppLocalizations l, ActiveCall call) {
    if (call.onHold) return l.callOnHold;
    if (call.remoteHold) return l.callHeldByOtherSide;
    return switch (call.phase) {
      CallPhase.incoming => l.callIncomingCall,
      CallPhase.calling => l.callCalling,
      CallPhase.ringing => l.callRinging,
      CallPhase.earlyMedia => l.callConnecting,
      CallPhase.answering => l.callConnecting,
      CallPhase.connected => formatDuration(
        DateTime.now().difference(call.connectedAt ?? DateTime.now()),
      ),
    };
  }
}

class _IncomingControls extends ConsumerWidget {
  const _IncomingControls({required this.call});

  final ActiveCall call;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final notifier = ref.read(phoneProvider.notifier);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        CallControl(
          icon: Icons.call_end,
          label: l.callDecline,
          color: Colors.red,
          onPressed: () => notifier.hangup(call),
        ),
        CallControl(
          icon: Icons.call,
          label: l.callAnswer,
          color: Colors.green,
          onPressed: () => notifier.answer(call),
        ),
      ],
    );
  }
}

/// A second incoming call while talking. Answering holds the current one.
class _WaitingBanner extends ConsumerWidget {
  const _WaitingBanner({required this.call});

  final ActiveCall call;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final notifier = ref.read(phoneProvider.notifier);
    return Card(
      child: ListTile(
        leading: const Icon(Icons.ring_volume),
        title: Text(call.peerLabel),
        subtitle: Text(l.callIncomingCall),
        trailing: Wrap(
          spacing: 8,
          children: [
            IconButton.filled(
              onPressed: () => notifier.hangup(call),
              style: IconButton.styleFrom(backgroundColor: Colors.red),
              icon: const Icon(Icons.call_end, color: Colors.white),
              tooltip: l.callDecline,
            ),
            IconButton.filled(
              onPressed: () => notifier.answer(call),
              style: IconButton.styleFrom(backgroundColor: Colors.green),
              icon: const Icon(Icons.call, color: Colors.white),
              tooltip: l.callAnswerAndHold,
            ),
          ],
        ),
      ),
    );
  }
}

class _OtherCallBanner extends ConsumerWidget {
  const _OtherCallBanner({required this.call});

  final ActiveCall call;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final notifier = ref.read(phoneProvider.notifier);
    return Card(
      child: ListTile(
        leading: const Icon(Icons.pause_circle_outline),
        title: Text(call.peerLabel),
        subtitle: Text(call.onHold ? l.callOnHold : l.callActive),
        trailing: IconButton(
          onPressed: () => notifier.hangup(call),
          icon: const Icon(Icons.call_end),
          tooltip: l.callEnd,
        ),
        onTap: call.phase == CallPhase.connected
            ? () => notifier.toggleHold(call)
            : null,
      ),
    );
  }
}
