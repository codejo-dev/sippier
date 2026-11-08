import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';

/// Android: keep the phone awake for calls in the background, in
/// `<app support>/background.json`. On (the default) holds a wake lock, the
/// most reliable way, but the CPU never sleeps. Off, alarms wake it shortly
/// before each registration refresh: fine for providers that grant long
/// registrations and keep the network path open. The wake lock is one for
/// the whole app, so this is one setting, not one per account.
class StayAwakeController extends Notifier<bool> {
  File get _file => File('${ref.read(appDirProvider)}/background.json');

  @override
  bool build() {
    if (!_file.existsSync()) return true;
    try {
      final json = jsonDecode(_file.readAsStringSync()) as Map<String, dynamic>;
      return json['stayAwake'] as bool? ?? true;
    } catch (_) {
      return true; // unreadable: the reliable default
    }
  }

  void set(bool stayAwake) {
    state = stayAwake;
    final tmp = File('${_file.path}.tmp');
    tmp.writeAsStringSync(jsonEncode({'stayAwake': stayAwake}));
    tmp.renameSync(_file.path);
  }
}
