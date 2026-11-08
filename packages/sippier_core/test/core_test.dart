@TestOn('mac-os || windows')
library;

import 'dart:io';

import 'package:sippier_core/sippier_core.dart';
import 'package:test/test.dart';

void main() {
  test('core starts, logs and shuts down', () async {
    final dir = await Directory.systemTemp.createTemp('sippier_core_test');
    final core = SippierCore.instance;
    final logs = <String>[];
    final sub = core.events
        .where((e) => e is LogEvent)
        .listen((e) => logs.add((e as LogEvent).text));

    core.init(dir.path);
    core.setDnsServers(['192.0.2.1', '[2001:db8::1]:5353']);

    // device list from CoreAudio or the MMDevice API; choosing devices and
    // the default again
    final devices = core.audioDevices();
    expect(devices.outputs, isNotEmpty);
    expect(devices.defaultOutput, isNotNull);
    core.setAudioDevices(output: devices.outputs.first.id);
    core.setAudioDevices();
    expect(core.ringtones(), ['bubbles', 'marimba', 'glass', 'classic']);

    await Future<void>.delayed(const Duration(milliseconds: 200));
    core.shutdown();
    await sub.cancel();

    expect(File('${dir.path}/sippier.log').existsSync(), isTrue);
    expect(logs, isNotEmpty);
    // echo cancellation (aec.c) is linked in and registered
    expect(
      logs.any((l) => l.startsWith('aec: echo cancellation')),
      isTrue,
      reason: 'echo cancellation missing',
    );
    // sleep and wake handling, and following the default devices
    expect(logs.where((l) => l.contains("can't watch system sleep")), isEmpty);
    expect(logs.where((l) => l.contains("can't watch the default")), isEmpty);
    if (Platform.isWindows) {
      // the system's roots, exported for OpenSSL
      final ca = File('${dir.path}/cacerts.pem');
      expect(ca.existsSync(), isTrue);
      expect(ca.readAsStringSync(), contains('-----BEGIN CERTIFICATE-----'));
      expect(logs.where((l) => l.contains('no CA bundle')), isEmpty);
    }
    await dir.delete(recursive: true);
  });
}
