// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get navKeypad => 'Keypad';

  @override
  String get navRecents => 'Recents';

  @override
  String get navAccounts => 'Accounts';

  @override
  String get navSettings => 'Settings';

  @override
  String get navAbout => 'About';

  @override
  String get bannerBatteryRestricted =>
      'Battery usage is set to Restricted, so Sippier can\'t receive calls in the background. Set it to Optimized or Unrestricted under App battery usage.';

  @override
  String get bannerBatterySaverNeedsUnrestricted =>
      'The battery saver needs battery usage set to Unrestricted. Otherwise Android delays its wake-ups, registrations run out and calls are missed.';

  @override
  String get bannerLockScreen =>
      'Allow Sippier to show incoming calls on the lock screen.';

  @override
  String get buttonChange => 'Change';

  @override
  String get buttonKeepAwakeInstead => 'Keep awake instead';

  @override
  String get buttonAllow => 'Allow';

  @override
  String get buttonCancel => 'Cancel';

  @override
  String get buttonSave => 'Save';

  @override
  String get headerGeneral => 'General';

  @override
  String get language => 'Language';

  @override
  String languageSystem(String language) {
    return 'System default ($language)';
  }

  @override
  String get languageName => 'English';

  @override
  String get launchAtLogin => 'Open at login';

  @override
  String get launchAtLoginMenuBar => 'Starts in the menu bar, ready for calls';

  @override
  String get launchAtLoginTray =>
      'Starts in the notification area, ready for calls';

  @override
  String get headerAudio => 'Audio';

  @override
  String get ringtone => 'Ringtone';

  @override
  String get ringtoneAndroidHint => 'Set in Android\'s notification settings';

  @override
  String get headerBackgroundCalls => 'Calls in the background';

  @override
  String get keepPhoneAwake => 'Keep the phone awake';

  @override
  String get keepPhoneAwakeOn =>
      'Most reliable for incoming calls, but the phone never sleeps while Sippier runs.';

  @override
  String get keepPhoneAwakeOff =>
      'Battery saver: Sippier wakes the phone shortly before each registration refresh. Needs battery usage set to Unrestricted. Calls can still be missed with some providers and networks.';

  @override
  String batterySaverWakeUps(String intervals) {
    return 'Battery saver wakes it every $intervals.';
  }

  @override
  String batterySaverWakeUp(String interval, String account) {
    return '$interval for $account';
  }

  @override
  String durationSeconds(int seconds) {
    return '$seconds s';
  }

  @override
  String durationMinutes(String minutes) {
    return '$minutes min';
  }

  @override
  String get headerDiagnostics => 'Diagnostics';

  @override
  String get sipTrace => 'SIP trace';

  @override
  String get sipTraceHint =>
      'Writes every SIP message to the log file. Contains your number and auth hashes, never passwords.';

  @override
  String get log => 'Log';

  @override
  String get logPathCopied => 'Log file path copied';

  @override
  String get copyLogPath => 'Copy log file path';

  @override
  String get licences => 'Open-source licences';

  @override
  String licenceCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count licences',
      one: '1 licence',
    );
    return '$_temp0';
  }

  @override
  String get aboutSippier => 'About Sippier';

  @override
  String get aboutSippierHint => 'Version, author, website and licences';

  @override
  String aboutVersion(String version) {
    return 'Version $version';
  }

  @override
  String get aboutTagline => 'A simple, open-source SIP phone.';

  @override
  String get aboutAuthor => 'Author';

  @override
  String get aboutWebsite => 'Website';

  @override
  String get aboutLicence => 'Licence';

  @override
  String get addAccount => 'Add account';

  @override
  String get editAccount => 'Edit account';

  @override
  String get removeAccount => 'Remove account';

  @override
  String get accountsEmpty =>
      'Sippier works with any SIP provider. Add the account details from your provider.';

  @override
  String removeAccountQuestion(String account) {
    return 'Remove $account?';
  }

  @override
  String get removeAccountExplanation =>
      'The account and its saved password are deleted from this device.';

  @override
  String get buttonRemove => 'Remove';

  @override
  String get regOff => 'Off';

  @override
  String get regIdle => 'Not registered';

  @override
  String get regRegistering => 'Registering…';

  @override
  String get regRegistered => 'Registered';

  @override
  String regFailed(String reason) {
    return 'Failed: $reason';
  }

  @override
  String get recentsClear => 'Clear history';

  @override
  String get recentsEmpty => 'No calls yet.';

  @override
  String get callBack => 'Call back';

  @override
  String get recentsClearQuestion => 'Clear call history?';

  @override
  String get buttonClear => 'Clear';

  @override
  String get callMissed => 'Missed';

  @override
  String get callIncoming => 'Incoming';

  @override
  String get callOutgoing => 'Outgoing';

  @override
  String get dialerNoAccount => 'Add a SIP account to make calls.';

  @override
  String get dialerNumberHint => 'Number';

  @override
  String get dialerDelete => 'Delete';

  @override
  String get dialerCall => 'Call';

  @override
  String callVia(String account) {
    return 'via $account';
  }

  @override
  String get callHideKeypad => 'Hide keypad';

  @override
  String get callMute => 'Mute';

  @override
  String get callKeypad => 'Keypad';

  @override
  String get callSpeaker => 'Speaker';

  @override
  String get callHold => 'Hold';

  @override
  String get callResume => 'Resume';

  @override
  String get callEnd => 'End';

  @override
  String get callDecline => 'Decline';

  @override
  String get callAnswer => 'Answer';

  @override
  String get callAnswerAndHold => 'Answer and hold the current call';

  @override
  String get callActive => 'Active';

  @override
  String get callOnHold => 'On hold';

  @override
  String get callHeldByOtherSide => 'Held by the other side';

  @override
  String get callIncomingCall => 'Incoming call';

  @override
  String get callCalling => 'Calling…';

  @override
  String get callRinging => 'Ringing…';

  @override
  String get callConnecting => 'Connecting…';

  @override
  String get audioSystemDefault => 'System default';

  @override
  String audioSystemDefaultDevice(String device) {
    return 'System default ($device)';
  }

  @override
  String audioNotConnected(String device) {
    return '$device (not connected)';
  }

  @override
  String get audioMicrophone => 'Microphone';

  @override
  String get audioSpeaker => 'Speaker';

  @override
  String get audioRingingOn => 'Ringing on';

  @override
  String get ringtoneAccountsOwn => 'Accounts can have their own';

  @override
  String ringtoneDefault(String tone) {
    return 'Default ($tone)';
  }

  @override
  String get ringtoneChooseFile => 'Choose a file…';

  @override
  String get ringtoneFileTypeSounds => 'Sounds';

  @override
  String get ringtoneFileTypeWav => 'WAV sounds';

  @override
  String get ringtonePlay => 'Play';

  @override
  String get ringtoneStop => 'Stop';

  @override
  String get ringtoneBubbles => 'Bubbles';

  @override
  String get ringtoneMarimba => 'Marimba';

  @override
  String get ringtoneGlass => 'Glass';

  @override
  String get ringtoneClassic => 'Classic';

  @override
  String providerSaid(String detail) {
    return 'Provider said: $detail';
  }

  @override
  String get fieldRequired => 'Required';

  @override
  String get fieldHostPort => 'Host or host:port, without \"sip:\"';

  @override
  String get fieldName => 'Name (optional)';

  @override
  String get fieldNameHint => 'e.g. Office line';

  @override
  String get fieldUser => 'Username or number';

  @override
  String get fieldPassword => 'Password';

  @override
  String get fieldPasswordKeep => 'Leave empty to keep the saved password';

  @override
  String get fieldDomain => 'Domain';

  @override
  String get fieldAuthUser => 'Auth username (if different)';

  @override
  String get fieldOutboundProxy => 'Outbound proxy (optional)';

  @override
  String get fieldAdvanced => 'Advanced';

  @override
  String get fieldMediaEncryption => 'Media encryption';

  @override
  String get encryptionOff => 'Off';

  @override
  String get encryptionIfOffered => 'SRTP if offered';

  @override
  String get encryptionRequired => 'SRTP required';

  @override
  String get fieldRegInterval => 'Registration interval (seconds)';

  @override
  String get fieldRegIntervalMin => 'At least 60';

  @override
  String get fieldCodecs => 'Codecs in order of preference';

  @override
  String get fieldCodecsHint => 'baresip names, e.g. G722/16000/1,PCMA,PCMU';

  @override
  String get fieldStun => 'STUN server (optional)';

  @override
  String get checkUserDomain =>
      'Only the part before @; the part after it goes under Domain';

  @override
  String get checkWithoutSip => 'Without \"sip:\"';

  @override
  String get checkNoSpaces => 'No spaces';

  @override
  String problemNotRetried(String summary) {
    return '$summary (not retried)';
  }

  @override
  String problemNotRetriedAdvice(String advice) {
    return '$advice Sippier won\'t retry on its own, so a wrong password can\'t lock you out. Save the account to try again.';
  }

  @override
  String get problemLoginRejected => 'Login rejected';

  @override
  String get problemLoginRejectedAdvice =>
      'Check the username, auth username and password against your provider\'s details. Some providers block the connection for a few minutes after repeated failures, so check before trying again.';

  @override
  String get problemUnknownUser => 'Unknown username';

  @override
  String get problemUnknownUserAdvice =>
      'The provider doesn\'t know this username at this domain. Check both.';

  @override
  String get problemIntervalTooShort => 'Registration interval too short';

  @override
  String get problemIntervalTooShortAdvice =>
      'Raise the registration interval under Advanced.';

  @override
  String get problemNoAnswer => 'Provider doesn\'t answer';

  @override
  String get problemNoAnswerAdvice =>
      'Check the domain and outbound proxy. If they\'re right, the provider may be down; Sippier keeps trying.';

  @override
  String get problemNoNetwork => 'No network';

  @override
  String get problemNoNetworkAdvice =>
      'Sippier registers again when the network is back.';

  @override
  String get problemServerNotFound => 'Server not found';

  @override
  String get problemServerNotFoundAdvice =>
      'Check the domain and outbound proxy.';

  @override
  String get problemFailed => 'Registration failed';

  @override
  String get problemFailedAdvice => 'The provider\'s answer is below.';

  @override
  String errorCoreStart(String error) {
    return 'SIP core failed to start: $error';
  }

  @override
  String errorEndCallsFirst(String account) {
    return 'End the calls on $account before editing it.';
  }

  @override
  String get errorMicrophone => 'Sippier needs microphone access for calls.';

  @override
  String get callFailedBusy => 'Busy';

  @override
  String callFailedNotFound(String reason) {
    return 'Number not found ($reason)';
  }

  @override
  String callFailedNotReachable(String reason) {
    return 'Not reachable right now ($reason)';
  }

  @override
  String callFailedRejected(String reason) {
    return 'The provider rejected the call ($reason). If this line is also set up on another device, e.g. your router, the provider may only accept one of them.';
  }

  @override
  String callFailed(String reason) {
    return 'Call failed: $reason';
  }

  @override
  String get statusInCall => 'In a call';

  @override
  String get statusNoAccounts => 'No accounts';

  @override
  String statusRegisteredOne(String account) {
    return 'Registered: $account';
  }

  @override
  String statusRegisteredAll(int count) {
    return '$count accounts registered';
  }

  @override
  String statusRegisteredSome(int registered, int total) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: '$total accounts',
      one: '1 account',
    );
    return '$registered of $_temp0 registered';
  }

  @override
  String get trayOpen => 'Open Sippier';

  @override
  String get trayQuit => 'Quit Sippier';
}
