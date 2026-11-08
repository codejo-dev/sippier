import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sippier_core/sippier_core.dart';

import '../l10n/app_localizations.dart';
import '../providers.dart';

/// Audio devices and the default ringtone, in `<app support>/audio.json`.
/// Device ids come from [SippierCore.audioDevices]; null follows the
/// system default.
class AudioSettings {
  const AudioSettings({
    this.input,
    this.output,
    this.ringer,
    this.ringtone,
    this.names = const {},
  });

  factory AudioSettings.fromJson(Map<String, dynamic> json) => AudioSettings(
    input: json['input'] as String?,
    output: json['output'] as String?,
    ringer: json['ringer'] as String?,
    ringtone: json['ringtone'] as String?,
    names: (json['names'] as Map<String, dynamic>? ?? const {})
        .cast<String, String>(),
  );

  final String? input;
  final String? output;
  final String? ringer;

  /// For accounts without a ringtone of their own; null is the platform's
  /// default ([defaultRingtone]).
  final String? ringtone;

  /// Last seen name per device id, to show a chosen device that isn't
  /// connected.
  final Map<String, String> names;

  Map<String, dynamic> toJson() => {
    'input': input,
    'output': output,
    'ringer': ringer,
    'ringtone': ringtone,
    'names': names,
  };
}

enum AudioRole { input, output, ringer }

/// The default, which the core lists first.
String defaultRingtone(List<String> tones) =>
    tones.isEmpty ? 'bubbles' : tones.first;

/// Sound files the user picked are copied into `<app support>/ringtones/`,
/// so the macOS sandbox still lets the core read them later. Their
/// ringtone value is `file:<file name>`.
const _filePrefix = 'file:';

Directory _ringtoneDir(String appDir) => Directory('$appDir/ringtones');

/// The picked sounds, as ringtone values, by name.
List<String> customRingtones(String appDir) {
  final dir = _ringtoneDir(appDir);
  if (!dir.existsSync()) return const [];
  final names = [
    for (final f in dir.listSync().whereType<File>()) f.uri.pathSegments.last,
  ]..sort();
  return [for (final n in names) '$_filePrefix$n'];
}

/// What the core plays: a picked sound with its full path.
String coreRingtone(String tone, String appDir) => tone.startsWith(_filePrefix)
    ? '$_filePrefix${_ringtoneDir(appDir).path}/${tone.substring(5)}'
    : tone;

/// Copies a picked sound file into the ringtone folder and returns its
/// ringtone value. A file of the same name gets a number added.
Future<String> importRingtone(String appDir, String path) async {
  final dir = await _ringtoneDir(appDir).create(recursive: true);
  final file = File(path).uri.pathSegments.last;
  final dot = file.lastIndexOf('.');
  final stem = dot > 0 ? file.substring(0, dot) : file;
  final ext = dot > 0 ? file.substring(dot) : '';
  var name = file;
  for (var i = 2; File('${dir.path}/$name').existsSync(); i++) {
    name = '$stem ($i)$ext';
  }
  await File(path).copy('${dir.path}/$name');
  return '$_filePrefix$name';
}

/// "bubbles" -> "Bubbles" (translated), "file:My song.m4a" -> "My song"
String ringtoneLabel(AppLocalizations l, String tone) {
  if (tone.startsWith(_filePrefix)) {
    final name = tone.substring(_filePrefix.length);
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }
  return switch (tone) {
    'bubbles' => l.ringtoneBubbles,
    'marimba' => l.ringtoneMarimba,
    'glass' => l.ringtoneGlass,
    'classic' => l.ringtoneClassic,
    // one the core added since
    _ => tone.isEmpty ? tone : tone[0].toUpperCase() + tone.substring(1),
  };
}

class AudioSettingsController extends Notifier<AudioSettings> {
  File get _file => File('${ref.read(appDirProvider)}/audio.json');

  @override
  AudioSettings build() {
    if (!_file.existsSync()) return const AudioSettings();
    try {
      return AudioSettings.fromJson(
        jsonDecode(_file.readAsStringSync()) as Map<String, dynamic>,
      );
    } catch (_) {
      return const AudioSettings(); // unreadable: start over
    }
  }

  /// [device] null follows the system default.
  void setDevice(AudioRole role, AudioDevice? device) {
    final s = state;
    _save(
      AudioSettings(
        input: role == AudioRole.input ? device?.id : s.input,
        output: role == AudioRole.output ? device?.id : s.output,
        ringer: role == AudioRole.ringer ? device?.id : s.ringer,
        ringtone: s.ringtone,
        names: {...s.names, if (device != null) device.id: device.name},
      ),
    );
  }

  void setRingtone(String tone) {
    final s = state;
    _save(
      AudioSettings(
        input: s.input,
        output: s.output,
        ringer: s.ringer,
        ringtone: tone,
        names: s.names,
      ),
    );
  }

  void _save(AudioSettings s) {
    state = s;
    final tmp = File('${_file.path}.tmp');
    tmp.writeAsStringSync(jsonEncode(s.toJson()));
    tmp.renameSync(_file.path);
  }
}
