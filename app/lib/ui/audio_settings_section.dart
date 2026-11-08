import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sippier_core/sippier_core.dart';

import '../data/audio_settings.dart';
import '../l10n/app_localizations.dart';
import '../providers.dart';

/// Desktop: microphone, speaker and ringing device, and the default
/// ringtone. Android routes audio itself.
class AudioSettingsSection extends ConsumerStatefulWidget {
  const AudioSettingsSection({super.key});

  @override
  ConsumerState<AudioSettingsSection> createState() =>
      _AudioSettingsSectionState();
}

class _AudioSettingsSectionState extends ConsumerState<AudioSettingsSection> {
  final _core = SippierCore.instance;
  AudioDevices _devices = const AudioDevices();
  List<String> _ringtones = const [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  /// Devices come and go (headsets, AirPods), so refresh when a list opens.
  void _reload() {
    try {
      setState(() {
        _devices = _core.audioDevices();
        _ringtones = _core.ringtones();
      });
    } on SippierCoreException {
      // core not running: keep what we have
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final settings = ref.watch(audioSettingsProvider);
    final notifier = ref.read(audioSettingsProvider.notifier);

    Widget device(
      String label,
      AudioRole role,
      List<AudioDevice> devices,
      String? selected,
      String? defaultId,
    ) {
      final defaultName = devices
          .where((d) => d.id == defaultId)
          .firstOrNull
          ?.name;
      final missing = selected != null && !devices.any((d) => d.id == selected);
      return _Row(
        child: DropdownButtonFormField<String?>(
          key: ValueKey('$role/$selected/${devices.length}'),
          initialValue: selected,
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          onTap: _reload,
          items: [
            DropdownMenuItem(
              value: null,
              child: Text(
                defaultName == null
                    ? l.audioSystemDefault
                    : l.audioSystemDefaultDevice(defaultName),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            for (final d in devices)
              DropdownMenuItem(
                value: d.id,
                child: Text(d.name, overflow: TextOverflow.ellipsis),
              ),
            if (missing)
              DropdownMenuItem(
                value: selected,
                child: Text(
                  l.audioNotConnected(settings.names[selected] ?? selected),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (id) => notifier.setDevice(
            role,
            id == null
                ? null
                : devices.firstWhere(
                    (d) => d.id == id,
                    orElse: () => AudioDevice(id, settings.names[id] ?? id),
                  ),
          ),
        ),
      );
    }

    return Column(
      children: [
        device(
          l.audioMicrophone,
          AudioRole.input,
          _devices.inputs,
          settings.input,
          _devices.defaultInput,
        ),
        device(
          l.audioSpeaker,
          AudioRole.output,
          _devices.outputs,
          settings.output,
          _devices.defaultOutput,
        ),
        device(
          l.audioRingingOn,
          AudioRole.ringer,
          _devices.outputs,
          settings.ringer,
          _devices.defaultOutput,
        ),
        _Row(
          child: RingtoneField(
            value: settings.ringtone ?? defaultRingtone(_ringtones),
            helperText: l.ringtoneAccountsOwn,
            onChanged: (t) {
              if (t != null) notifier.setRingtone(t);
            },
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 12), child: child);
}

/// Ringtone choice: the built-in ones, sounds picked before and "Choose a
/// file…", with a preview button. With [defaultTone], a "Default (…)"
/// entry stands for null.
class RingtoneField extends ConsumerStatefulWidget {
  const RingtoneField({
    super.key,
    required this.value,
    required this.onChanged,
    this.defaultTone,
    this.helperText,
  });

  final String? value;
  final ValueChanged<String?> onChanged;
  final String? defaultTone;
  final String? helperText;

  @override
  ConsumerState<RingtoneField> createState() => _RingtoneFieldState();
}

class _RingtoneFieldState extends ConsumerState<RingtoneField> {
  static const _pick = '\u0000pick';

  /// Bumped to show the old choice again when picking a file is cancelled.
  int _reset = 0;

  Future<void> _pickFile() async {
    final l = AppLocalizations.of(context);
    final file = await openFile(
      acceptedTypeGroups: [
        // CoreAudio reads these on macOS; elsewhere the core reads WAV
        Platform.isMacOS
            ? XTypeGroup(
                label: l.ringtoneFileTypeSounds,
                extensions: const ['m4a', 'mp3', 'wav', 'aiff', 'aif', 'caf'],
                uniformTypeIdentifiers: const ['public.audio'],
              )
            : XTypeGroup(
                label: l.ringtoneFileTypeWav,
                extensions: const ['wav'],
              ),
      ],
    );
    if (file == null) {
      setState(() => _reset++);
      return;
    }
    widget.onChanged(await importRingtone(ref.read(appDirProvider), file.path));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final appDir = ref.read(appDirProvider);
    final builtIn = SippierCore.instance.ringtones();
    final custom = customRingtones(appDir);
    final known =
        widget.value != null &&
        (builtIn.contains(widget.value) || custom.contains(widget.value));
    final preview =
        (known ? widget.value : null) ??
        widget.defaultTone ??
        defaultRingtone(builtIn);
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String?>(
            key: ValueKey('${widget.value}/$_reset/${custom.length}'),
            initialValue: known ? widget.value : null,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: l.ringtone,
              helperText: widget.helperText,
            ),
            items: [
              if (widget.defaultTone != null)
                DropdownMenuItem(
                  value: null,
                  child: Text(
                    l.ringtoneDefault(ringtoneLabel(l, widget.defaultTone!)),
                  ),
                ),
              for (final t in [...builtIn, ...custom])
                DropdownMenuItem(
                  value: t,
                  child: Text(
                    ringtoneLabel(l, t),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              DropdownMenuItem(value: _pick, child: Text(l.ringtoneChooseFile)),
            ],
            onChanged: (t) => t == _pick ? _pickFile() : widget.onChanged(t),
          ),
        ),
        RingtonePreviewButton(coreRingtone(preview, appDir)),
      ],
    );
  }
}

/// Plays a ringtone for a few seconds on the ringing device.
class RingtonePreviewButton extends StatefulWidget {
  const RingtonePreviewButton(this.tone, {super.key});

  final String tone;

  @override
  State<RingtonePreviewButton> createState() => _RingtonePreviewButtonState();
}

class _RingtonePreviewButtonState extends State<RingtonePreviewButton> {
  Timer? _stop;

  bool get _playing => _stop != null;

  void _start() {
    try {
      SippierCore.instance.ringStart(widget.tone);
    } on SippierCoreException {
      return;
    }
    _stop?.cancel();
    setState(() => _stop = Timer(const Duration(seconds: 4), _end));
  }

  void _end() {
    _stop?.cancel();
    SippierCore.instance.ringStop();
    if (mounted) setState(() => _stop = null);
  }

  @override
  void didUpdateWidget(RingtonePreviewButton old) {
    super.didUpdateWidget(old);
    if (_playing && old.tone != widget.tone) _start();
  }

  @override
  void dispose() {
    if (_playing) {
      _stop?.cancel();
      SippierCore.instance.ringStop();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return IconButton(
      onPressed: _playing ? _end : _start,
      icon: Icon(_playing ? Icons.stop : Icons.play_arrow),
      tooltip: _playing ? l.ringtoneStop : l.ringtonePlay,
    );
  }
}
