import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../phone/phone_state.dart';
import '../providers.dart';
import 'about_page.dart';
import 'audio_settings_section.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key, this.showAbout = false});

  /// A way to the About page, on phones; the rail has its own.
  final bool showAbout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final phone = ref.watch(phoneProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l.navSettings)),
      body: ListView(
        children: [
          _Header(l.headerGeneral),
          const _LanguageField(),
          const _LaunchAtLoginSwitch(),
          _Header(l.headerAudio),
          if (Platform.isAndroid)
            ListTile(
              title: Text(l.ringtone),
              subtitle: Text(l.ringtoneAndroidHint),
              trailing: const Icon(Icons.open_in_new),
              onTap: ref.read(platformProvider).openRingtoneSettings,
            )
          else
            const AudioSettingsSection(),
          if (Platform.isAndroid) ...[
            _Header(l.headerBackgroundCalls),
            SwitchListTile(
              title: Text(l.keepPhoneAwake),
              subtitle: Text(_stayAwakeText(l, ref, phone)),
              isThreeLine: true,
              value: ref.watch(stayAwakeProvider),
              onChanged: ref.read(stayAwakeProvider.notifier).set,
            ),
          ],
          _Header(l.headerDiagnostics),
          SwitchListTile(
            title: Text(l.sipTrace),
            subtitle: Text(l.sipTraceHint),
            value: phone.sipTrace,
            onChanged: ref.read(phoneProvider.notifier).setSipTrace,
          ),
          ListTile(
            title: Text(l.log),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => const LogPage())),
          ),
          if (showAbout) ...[
            _Header(l.navAbout),
            ListTile(
              title: Text(l.aboutSippier),
              subtitle: Text(l.aboutSippierHint),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const AboutPage()),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// macOS 13+ and Windows: starting at login, in the menu bar or tray. The
/// system keeps the setting, and the user can change it there too, so it's
/// read again whenever Sippier comes back to the front.
class _LaunchAtLoginSwitch extends ConsumerStatefulWidget {
  const _LaunchAtLoginSwitch();

  @override
  ConsumerState<_LaunchAtLoginSwitch> createState() =>
      _LaunchAtLoginSwitchState();
}

class _LaunchAtLoginSwitchState extends ConsumerState<_LaunchAtLoginSwitch> {
  /// Null where it's not up to the app (Android, macOS 12).
  bool? _on;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _read);
    _read();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _read() async {
    final on = await ref.read(platformProvider).launchAtLogin();
    if (mounted && on != _on) setState(() => _on = on);
  }

  Future<void> _set(bool on) async {
    setState(() => _on = on);
    final now = await ref.read(platformProvider).setLaunchAtLogin(on);
    if (mounted) setState(() => _on = now);
  }

  @override
  Widget build(BuildContext context) {
    final on = _on;
    if (on == null) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    return SwitchListTile(
      title: Text(l.launchAtLogin),
      subtitle: Text(
        Platform.isMacOS ? l.launchAtLoginMenuBar : l.launchAtLoginTray,
      ),
      value: on,
      onChanged: _set,
    );
  }
}

/// What each choice costs, with the battery saver's wake-ups per account:
/// half of the registration time the provider granted.
String _stayAwakeText(AppLocalizations l, WidgetRef ref, PhoneState phone) {
  final stayAwake = ref.watch(stayAwakeProvider);
  final notifier = ref.read(phoneProvider.notifier);
  final wakeUps = [
    for (final a in phone.accounts)
      if (a.enabled)
        if (notifier.grantedExpires(a.id) case final s?)
          l.batterySaverWakeUp(_minutes(l, s ~/ 2), a.label),
  ];
  final text = stayAwake ? l.keepPhoneAwakeOn : l.keepPhoneAwakeOff;
  return wakeUps.isEmpty
      ? text
      : '$text\n${l.batterySaverWakeUps(wakeUps.join(', '))}';
}

/// 450 -> "7½ min", 45 -> "45 s"
String _minutes(AppLocalizations l, int seconds) {
  if (seconds < 60) return l.durationSeconds(seconds);
  final halves = (seconds / 30).round();
  return l.durationMinutes('${halves ~/ 2}${halves.isOdd ? '½' : ''}');
}

/// The app's language: the system's, or one of lib/l10n's, each in its own
/// name.
class _LanguageField extends ConsumerWidget {
  const _LanguageField();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final language = ref.watch(languageProvider);
    final system = lookupAppLocalizations(appLocale(null)).languageName;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: DropdownButtonFormField<String?>(
        key: ValueKey(language),
        initialValue: language,
        isExpanded: true,
        decoration: InputDecoration(labelText: l.language),
        items: [
          DropdownMenuItem(value: null, child: Text(l.languageSystem(system))),
          for (final locale in AppLocalizations.supportedLocales)
            DropdownMenuItem(
              value: locale.languageCode,
              child: Text(lookupAppLocalizations(locale).languageName),
            ),
        ],
        onChanged: ref.read(languageProvider.notifier).set,
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}

class LogPage extends ConsumerWidget {
  const LogPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final lines = ref.watch(logProvider);
    final path = '${ref.read(appDirProvider)}/sippier.log';
    return Scaffold(
      appBar: AppBar(
        title: Text(l.log),
        actions: [
          IconButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: path));
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(l.logPathCopied)));
            },
            icon: const Icon(Icons.copy),
            tooltip: l.copyLogPath,
          ),
        ],
      ),
      body: ListView.builder(
        reverse: true,
        padding: const EdgeInsets.all(8),
        itemCount: lines.length,
        itemBuilder: (context, i) => SelectableText(
          lines[lines.length - 1 - i],
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
      ),
    );
  }
}
