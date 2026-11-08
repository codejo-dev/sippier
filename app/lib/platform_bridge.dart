import 'package:flutter/services.dart';

/// Native helpers in MainActivity.kt, MainFlutterWindow.swift and
/// flutter_window.cpp (Windows). Methods a platform doesn't implement do
/// nothing.
class PlatformBridge {
  PlatformBridge() {
    _channel.setMethodCallHandler(_onCall);
  }

  static const _channel = MethodChannel('sippier/platform');

  /// Android: the default network's DNS servers changed.
  void Function(List<String> servers)? onDnsServersChanged;

  /// Android: the default network or its addresses changed.
  void Function()? onNetworkChanged;

  /// Android: notification buttons.
  void Function(String callId)? onAnswer;
  void Function(String callId)? onHangup;
  void Function()? onQuit;

  /// Android battery saver alarm: keep registrations alive; returns the
  /// milliseconds until the next alarm.
  int Function()? onKeepAlive;

  /// Asks for microphone access where the app must (Android). Elsewhere
  /// the system asks when audio starts, so this returns true.
  Future<bool> requestMicrophone() async =>
      await _invoke<bool>('requestMicrophone') ?? true;

  /// Android only; elsewhere libre reads the system's servers itself.
  Future<List<String>> dnsServers() async =>
      (await _invoke<List<Object?>>('dnsServers'))?.cast<String>() ?? const [];

  /// Android: switches to communication audio mode (earpiece, echo
  /// cancellation) for the duration of the calls.
  Future<void> setInCall(bool inCall) => _invoke('setInCall', inCall);

  Future<void> setSpeaker(bool on) => _invoke('setSpeaker', on);

  Future<void> startRinging() => _invoke('startRinging');

  Future<void> stopRinging() => _invoke('stopRinging');

  /// Android 14+: whether incoming calls may open full screen over the lock
  /// screen. Always true elsewhere.
  Future<bool> canShowCallsOnLockScreen() async =>
      await _invoke<bool>('canShowCallsOnLockScreen') ?? true;

  Future<void> openLockScreenSettings() => _invoke('openLockScreenSettings');

  /// Android: battery usage is set to "Restricted", so the system stops
  /// Sippier in the background and no calls come in. False elsewhere.
  Future<bool> isBackgroundRestricted() async =>
      await _invoke<bool>('isBackgroundRestricted') ?? false;

  /// Android: battery usage is "Unrestricted". The battery saver needs it:
  /// under "Optimized" Android delays and caps its wake-ups, so
  /// registrations run out. True elsewhere.
  Future<bool> isBatteryUnrestricted() async =>
      await _invoke<bool>('isBatteryUnrestricted') ?? true;

  /// Android: the system dialog that sets battery usage to "Unrestricted".
  Future<void> requestUnrestrictedBattery() =>
      _invoke('requestUnrestrictedBattery');

  /// Android: the app's info page, where "App battery usage" is.
  Future<void> openBatterySettings() => _invoke('openBatterySettings');

  /// Android: the incoming-call notification channel's settings, where the
  /// user picks its sound.
  Future<void> openRingtoneSettings() => _invoke('openRingtoneSettings');

  /// macOS menu bar, Windows tray: text and icon. While [background] (any
  /// account enabled) or [inCall], Android keeps a foreground service
  /// running and macOS keeps App Nap off. Android holds a wake lock while
  /// [stayAwake] or [inCall], and otherwise wakes for registration
  /// refreshes by alarm. [openLabel] and [quitLabel] are the menu bar's
  /// and tray's menu items, in the app's language.
  Future<void> updateStatus({
    required String text,
    required bool registered,
    required bool background,
    required bool inCall,
    required bool stayAwake,
    required String openLabel,
    required String quitLabel,
  }) => _invoke('updateStatus', {
    'text': text,
    'registered': registered,
    'background': background,
    'inCall': inCall,
    'stayAwake': stayAwake,
    'openLabel': openLabel,
    'quitLabel': quitLabel,
  });

  /// Android: incoming call notification, shown over the lock screen.
  Future<void> showIncomingCall(String callId, String caller) =>
      _invoke('showIncomingCall', {'callId': callId, 'caller': caller});

  Future<void> cancelIncomingCall() => _invoke('cancelIncomingCall');

  /// Android: ends the process after the core has shut down.
  Future<void> quit() => _invoke('quit');

  /// Opens a web page in the default browser.
  Future<void> openUrl(String url) => _invoke('openUrl', url);

  /// Android: saves [content] where the user picks, in the system's file
  /// screen. False if they cancel; null elsewhere, where file_selector's
  /// save dialog does it.
  Future<bool?> saveFile(String name, String mimeType, String content) =>
      _invoke<bool>('saveFile', {
        'name': name,
        'mimeType': mimeType,
        'content': content,
      });

  /// macOS 13+ and Windows: whether Sippier starts when the user logs in,
  /// as the system has it (the user can change it there too). Null where
  /// that's not up to the app.
  Future<bool?> launchAtLogin() => _invoke<bool>('launchAtLogin');

  /// Returns whether Sippier now starts at login. macOS may want the user to
  /// allow it in System Settings first, and opens them.
  Future<bool?> setLaunchAtLogin(bool on) =>
      _invoke<bool>('setLaunchAtLogin', on);

  /// Android 13+: the language picked in the settings ("de"), or null for
  /// the system's, as the app's language, so the notifications follow it.
  /// Desktop runners get their strings with [updateStatus].
  Future<void> setLanguage(String? language) =>
      _invoke('setLanguage', language);

  Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      return null;
    }
  }

  Future<Object?> _onCall(MethodCall call) async {
    switch (call.method) {
      case 'keepAlive':
        return onKeepAlive?.call() ?? 60000;
      case 'dnsServersChanged':
        onDnsServersChanged?.call((call.arguments as List).cast<String>());
      case 'networkChanged':
        onNetworkChanged?.call();
      case 'answer':
        onAnswer?.call(call.arguments as String);
      case 'hangup':
        onHangup?.call(call.arguments as String);
      case 'quit':
        onQuit?.call();
    }
    return null;
  }
}
