import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
  ];

  /// Tab with the dialling keypad
  ///
  /// In en, this message translates to:
  /// **'Keypad'**
  String get navKeypad;

  /// Tab with the call history
  ///
  /// In en, this message translates to:
  /// **'Recents'**
  String get navRecents;

  /// Tab with the SIP accounts
  ///
  /// In en, this message translates to:
  /// **'Accounts'**
  String get navAccounts;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// Rail destination and page with the version, author, website and licences
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get navAbout;

  /// Android. Restricted, Optimized, Unrestricted and App battery usage are Android's own setting names.
  ///
  /// In en, this message translates to:
  /// **'Battery usage is set to Restricted, so Sippier can\'t receive calls in the background. Set it to Optimized or Unrestricted under App battery usage.'**
  String get bannerBatteryRestricted;

  /// Android. The battery saver is Sippier's own mode that wakes the phone for registration refreshes.
  ///
  /// In en, this message translates to:
  /// **'The battery saver needs battery usage set to Unrestricted. Otherwise Android delays its wake-ups, registrations run out and calls are missed.'**
  String get bannerBatterySaverNeedsUnrestricted;

  /// No description provided for @bannerLockScreen.
  ///
  /// In en, this message translates to:
  /// **'Allow Sippier to show incoming calls on the lock screen.'**
  String get bannerLockScreen;

  /// No description provided for @buttonChange.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get buttonChange;

  /// No description provided for @buttonKeepAwakeInstead.
  ///
  /// In en, this message translates to:
  /// **'Keep awake instead'**
  String get buttonKeepAwakeInstead;

  /// No description provided for @buttonAllow.
  ///
  /// In en, this message translates to:
  /// **'Allow'**
  String get buttonAllow;

  /// No description provided for @buttonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get buttonCancel;

  /// No description provided for @buttonSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get buttonSave;

  /// No description provided for @headerGeneral.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get headerGeneral;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// Follows the system's display language, named in brackets
  ///
  /// In en, this message translates to:
  /// **'System default ({language})'**
  String languageSystem(String language);

  /// This language's own name, as the language list shows it
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageName;

  /// macOS and Windows: start Sippier when the user logs in
  ///
  /// In en, this message translates to:
  /// **'Open at login'**
  String get launchAtLogin;

  /// No description provided for @launchAtLoginMenuBar.
  ///
  /// In en, this message translates to:
  /// **'Starts in the menu bar, ready for calls'**
  String get launchAtLoginMenuBar;

  /// No description provided for @launchAtLoginTray.
  ///
  /// In en, this message translates to:
  /// **'Starts in the notification area, ready for calls'**
  String get launchAtLoginTray;

  /// No description provided for @headerAudio.
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get headerAudio;

  /// No description provided for @ringtone.
  ///
  /// In en, this message translates to:
  /// **'Ringtone'**
  String get ringtone;

  /// No description provided for @ringtoneAndroidHint.
  ///
  /// In en, this message translates to:
  /// **'Set in Android\'s notification settings'**
  String get ringtoneAndroidHint;

  /// No description provided for @headerBackgroundCalls.
  ///
  /// In en, this message translates to:
  /// **'Calls in the background'**
  String get headerBackgroundCalls;

  /// No description provided for @keepPhoneAwake.
  ///
  /// In en, this message translates to:
  /// **'Keep the phone awake'**
  String get keepPhoneAwake;

  /// No description provided for @keepPhoneAwakeOn.
  ///
  /// In en, this message translates to:
  /// **'Most reliable for incoming calls, but the phone never sleeps while Sippier runs.'**
  String get keepPhoneAwakeOn;

  /// No description provided for @keepPhoneAwakeOff.
  ///
  /// In en, this message translates to:
  /// **'Battery saver: Sippier wakes the phone shortly before each registration refresh. Needs battery usage set to Unrestricted. Calls can still be missed with some providers and networks.'**
  String get keepPhoneAwakeOff;

  /// intervals is a list of batterySaverWakeUp items, joined by commas
  ///
  /// In en, this message translates to:
  /// **'Battery saver wakes it every {intervals}.'**
  String batterySaverWakeUps(String intervals);

  /// No description provided for @batterySaverWakeUp.
  ///
  /// In en, this message translates to:
  /// **'{interval} for {account}'**
  String batterySaverWakeUp(String interval, String account);

  /// No description provided for @durationSeconds.
  ///
  /// In en, this message translates to:
  /// **'{seconds} s'**
  String durationSeconds(int seconds);

  /// minutes may have a half, e.g. 7½
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String durationMinutes(String minutes);

  /// No description provided for @headerDiagnostics.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics'**
  String get headerDiagnostics;

  /// No description provided for @sipTrace.
  ///
  /// In en, this message translates to:
  /// **'SIP trace'**
  String get sipTrace;

  /// No description provided for @sipTraceHint.
  ///
  /// In en, this message translates to:
  /// **'Writes every SIP message to the log file. Contains your number and auth hashes, never passwords.'**
  String get sipTraceHint;

  /// No description provided for @log.
  ///
  /// In en, this message translates to:
  /// **'Log'**
  String get log;

  /// No description provided for @logPathCopied.
  ///
  /// In en, this message translates to:
  /// **'Log file path copied'**
  String get logPathCopied;

  /// No description provided for @copyLogPath.
  ///
  /// In en, this message translates to:
  /// **'Copy log file path'**
  String get copyLogPath;

  /// No description provided for @licences.
  ///
  /// In en, this message translates to:
  /// **'Open-source licences'**
  String get licences;

  /// No description provided for @licenceCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 licence} other{{count} licences}}'**
  String licenceCount(int count);

  /// No description provided for @aboutSippier.
  ///
  /// In en, this message translates to:
  /// **'About Sippier'**
  String get aboutSippier;

  /// No description provided for @aboutSippierHint.
  ///
  /// In en, this message translates to:
  /// **'Version, author, website and licences'**
  String get aboutSippierHint;

  /// No description provided for @aboutVersion.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String aboutVersion(String version);

  /// No description provided for @aboutTagline.
  ///
  /// In en, this message translates to:
  /// **'A simple, open-source SIP phone.'**
  String get aboutTagline;

  /// No description provided for @aboutAuthor.
  ///
  /// In en, this message translates to:
  /// **'Author'**
  String get aboutAuthor;

  /// No description provided for @aboutWebsite.
  ///
  /// In en, this message translates to:
  /// **'Website'**
  String get aboutWebsite;

  /// No description provided for @aboutLicence.
  ///
  /// In en, this message translates to:
  /// **'Licence'**
  String get aboutLicence;

  /// No description provided for @addAccount.
  ///
  /// In en, this message translates to:
  /// **'Add account'**
  String get addAccount;

  /// No description provided for @editAccount.
  ///
  /// In en, this message translates to:
  /// **'Edit account'**
  String get editAccount;

  /// No description provided for @removeAccount.
  ///
  /// In en, this message translates to:
  /// **'Remove account'**
  String get removeAccount;

  /// No description provided for @accountsEmpty.
  ///
  /// In en, this message translates to:
  /// **'Sippier works with any SIP provider. Add the account details from your provider.'**
  String get accountsEmpty;

  /// No description provided for @removeAccountQuestion.
  ///
  /// In en, this message translates to:
  /// **'Remove {account}?'**
  String removeAccountQuestion(String account);

  /// No description provided for @removeAccountExplanation.
  ///
  /// In en, this message translates to:
  /// **'The account and its saved password are deleted from this device.'**
  String get removeAccountExplanation;

  /// No description provided for @buttonRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get buttonRemove;

  /// Account switched off
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get regOff;

  /// No description provided for @regIdle.
  ///
  /// In en, this message translates to:
  /// **'Not registered'**
  String get regIdle;

  /// No description provided for @regRegistering.
  ///
  /// In en, this message translates to:
  /// **'Registering…'**
  String get regRegistering;

  /// No description provided for @regRegistered.
  ///
  /// In en, this message translates to:
  /// **'Registered'**
  String get regRegistered;

  /// No description provided for @regFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed: {reason}'**
  String regFailed(String reason);

  /// No description provided for @recentsClear.
  ///
  /// In en, this message translates to:
  /// **'Clear history'**
  String get recentsClear;

  /// No description provided for @recentsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No calls yet.'**
  String get recentsEmpty;

  /// No description provided for @callBack.
  ///
  /// In en, this message translates to:
  /// **'Call back'**
  String get callBack;

  /// No description provided for @recentsClearQuestion.
  ///
  /// In en, this message translates to:
  /// **'Clear call history?'**
  String get recentsClearQuestion;

  /// No description provided for @buttonClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get buttonClear;

  /// No description provided for @callMissed.
  ///
  /// In en, this message translates to:
  /// **'Missed'**
  String get callMissed;

  /// No description provided for @callIncoming.
  ///
  /// In en, this message translates to:
  /// **'Incoming'**
  String get callIncoming;

  /// No description provided for @callOutgoing.
  ///
  /// In en, this message translates to:
  /// **'Outgoing'**
  String get callOutgoing;

  /// No description provided for @dialerNoAccount.
  ///
  /// In en, this message translates to:
  /// **'Add a SIP account to make calls.'**
  String get dialerNoAccount;

  /// No description provided for @dialerNumberHint.
  ///
  /// In en, this message translates to:
  /// **'Number'**
  String get dialerNumberHint;

  /// Deletes the last digit of the number
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get dialerDelete;

  /// No description provided for @dialerCall.
  ///
  /// In en, this message translates to:
  /// **'Call'**
  String get dialerCall;

  /// The account a call goes through
  ///
  /// In en, this message translates to:
  /// **'via {account}'**
  String callVia(String account);

  /// No description provided for @callHideKeypad.
  ///
  /// In en, this message translates to:
  /// **'Hide keypad'**
  String get callHideKeypad;

  /// No description provided for @callMute.
  ///
  /// In en, this message translates to:
  /// **'Mute'**
  String get callMute;

  /// No description provided for @callKeypad.
  ///
  /// In en, this message translates to:
  /// **'Keypad'**
  String get callKeypad;

  /// No description provided for @callSpeaker.
  ///
  /// In en, this message translates to:
  /// **'Speaker'**
  String get callSpeaker;

  /// No description provided for @callHold.
  ///
  /// In en, this message translates to:
  /// **'Hold'**
  String get callHold;

  /// No description provided for @callResume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get callResume;

  /// No description provided for @callEnd.
  ///
  /// In en, this message translates to:
  /// **'End'**
  String get callEnd;

  /// No description provided for @callDecline.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get callDecline;

  /// No description provided for @callAnswer.
  ///
  /// In en, this message translates to:
  /// **'Answer'**
  String get callAnswer;

  /// No description provided for @callAnswerAndHold.
  ///
  /// In en, this message translates to:
  /// **'Answer and hold the current call'**
  String get callAnswerAndHold;

  /// No description provided for @callActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get callActive;

  /// No description provided for @callOnHold.
  ///
  /// In en, this message translates to:
  /// **'On hold'**
  String get callOnHold;

  /// No description provided for @callHeldByOtherSide.
  ///
  /// In en, this message translates to:
  /// **'Held by the other side'**
  String get callHeldByOtherSide;

  /// No description provided for @callIncomingCall.
  ///
  /// In en, this message translates to:
  /// **'Incoming call'**
  String get callIncomingCall;

  /// No description provided for @callCalling.
  ///
  /// In en, this message translates to:
  /// **'Calling…'**
  String get callCalling;

  /// The other side's phone is ringing
  ///
  /// In en, this message translates to:
  /// **'Ringing…'**
  String get callRinging;

  /// No description provided for @callConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get callConnecting;

  /// No description provided for @audioSystemDefault.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get audioSystemDefault;

  /// No description provided for @audioSystemDefaultDevice.
  ///
  /// In en, this message translates to:
  /// **'System default ({device})'**
  String audioSystemDefaultDevice(String device);

  /// No description provided for @audioNotConnected.
  ///
  /// In en, this message translates to:
  /// **'{device} (not connected)'**
  String audioNotConnected(String device);

  /// No description provided for @audioMicrophone.
  ///
  /// In en, this message translates to:
  /// **'Microphone'**
  String get audioMicrophone;

  /// No description provided for @audioSpeaker.
  ///
  /// In en, this message translates to:
  /// **'Speaker'**
  String get audioSpeaker;

  /// The device the ringtone plays on
  ///
  /// In en, this message translates to:
  /// **'Ringing on'**
  String get audioRingingOn;

  /// No description provided for @ringtoneAccountsOwn.
  ///
  /// In en, this message translates to:
  /// **'Accounts can have their own'**
  String get ringtoneAccountsOwn;

  /// No description provided for @ringtoneDefault.
  ///
  /// In en, this message translates to:
  /// **'Default ({tone})'**
  String ringtoneDefault(String tone);

  /// No description provided for @ringtoneChooseFile.
  ///
  /// In en, this message translates to:
  /// **'Choose a file…'**
  String get ringtoneChooseFile;

  /// No description provided for @ringtoneFileTypeSounds.
  ///
  /// In en, this message translates to:
  /// **'Sounds'**
  String get ringtoneFileTypeSounds;

  /// No description provided for @ringtoneFileTypeWav.
  ///
  /// In en, this message translates to:
  /// **'WAV sounds'**
  String get ringtoneFileTypeWav;

  /// No description provided for @ringtonePlay.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get ringtonePlay;

  /// No description provided for @ringtoneStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get ringtoneStop;

  /// No description provided for @ringtoneBubbles.
  ///
  /// In en, this message translates to:
  /// **'Bubbles'**
  String get ringtoneBubbles;

  /// No description provided for @ringtoneMarimba.
  ///
  /// In en, this message translates to:
  /// **'Marimba'**
  String get ringtoneMarimba;

  /// No description provided for @ringtoneGlass.
  ///
  /// In en, this message translates to:
  /// **'Glass'**
  String get ringtoneGlass;

  /// No description provided for @ringtoneClassic.
  ///
  /// In en, this message translates to:
  /// **'Classic'**
  String get ringtoneClassic;

  /// No description provided for @providerSaid.
  ///
  /// In en, this message translates to:
  /// **'Provider said: {detail}'**
  String providerSaid(String detail);

  /// No description provided for @fieldRequired.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get fieldRequired;

  /// No description provided for @fieldHostPort.
  ///
  /// In en, this message translates to:
  /// **'Host or host:port, without \"sip:\"'**
  String get fieldHostPort;

  /// No description provided for @fieldName.
  ///
  /// In en, this message translates to:
  /// **'Name (optional)'**
  String get fieldName;

  /// No description provided for @fieldNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Office line'**
  String get fieldNameHint;

  /// No description provided for @fieldUser.
  ///
  /// In en, this message translates to:
  /// **'Username or number'**
  String get fieldUser;

  /// No description provided for @fieldPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get fieldPassword;

  /// No description provided for @fieldPasswordKeep.
  ///
  /// In en, this message translates to:
  /// **'Leave empty to keep the saved password'**
  String get fieldPasswordKeep;

  /// No description provided for @fieldDomain.
  ///
  /// In en, this message translates to:
  /// **'Domain'**
  String get fieldDomain;

  /// No description provided for @fieldAuthUser.
  ///
  /// In en, this message translates to:
  /// **'Auth username (if different)'**
  String get fieldAuthUser;

  /// No description provided for @fieldOutboundProxy.
  ///
  /// In en, this message translates to:
  /// **'Outbound proxy (optional)'**
  String get fieldOutboundProxy;

  /// No description provided for @fieldAdvanced.
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get fieldAdvanced;

  /// No description provided for @fieldMediaEncryption.
  ///
  /// In en, this message translates to:
  /// **'Media encryption'**
  String get fieldMediaEncryption;

  /// No description provided for @encryptionOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get encryptionOff;

  /// No description provided for @encryptionIfOffered.
  ///
  /// In en, this message translates to:
  /// **'SRTP if offered'**
  String get encryptionIfOffered;

  /// No description provided for @encryptionRequired.
  ///
  /// In en, this message translates to:
  /// **'SRTP required'**
  String get encryptionRequired;

  /// No description provided for @fieldRegInterval.
  ///
  /// In en, this message translates to:
  /// **'Registration interval (seconds)'**
  String get fieldRegInterval;

  /// No description provided for @fieldRegIntervalMin.
  ///
  /// In en, this message translates to:
  /// **'At least 60'**
  String get fieldRegIntervalMin;

  /// No description provided for @fieldCodecs.
  ///
  /// In en, this message translates to:
  /// **'Codecs in order of preference'**
  String get fieldCodecs;

  /// No description provided for @fieldCodecsHint.
  ///
  /// In en, this message translates to:
  /// **'baresip names, e.g. G722/16000/1,PCMA,PCMU'**
  String get fieldCodecsHint;

  /// No description provided for @fieldStun.
  ///
  /// In en, this message translates to:
  /// **'STUN server (optional)'**
  String get fieldStun;

  /// No description provided for @checkUserDomain.
  ///
  /// In en, this message translates to:
  /// **'Only the part before @; the part after it goes under Domain'**
  String get checkUserDomain;

  /// No description provided for @checkWithoutSip.
  ///
  /// In en, this message translates to:
  /// **'Without \"sip:\"'**
  String get checkWithoutSip;

  /// No description provided for @checkNoSpaces.
  ///
  /// In en, this message translates to:
  /// **'No spaces'**
  String get checkNoSpaces;

  /// No description provided for @problemNotRetried.
  ///
  /// In en, this message translates to:
  /// **'{summary} (not retried)'**
  String problemNotRetried(String summary);

  /// No description provided for @problemNotRetriedAdvice.
  ///
  /// In en, this message translates to:
  /// **'{advice} Sippier won\'t retry on its own, so a wrong password can\'t lock you out. Save the account to try again.'**
  String problemNotRetriedAdvice(String advice);

  /// No description provided for @problemLoginRejected.
  ///
  /// In en, this message translates to:
  /// **'Login rejected'**
  String get problemLoginRejected;

  /// No description provided for @problemLoginRejectedAdvice.
  ///
  /// In en, this message translates to:
  /// **'Check the username, auth username and password against your provider\'s details. Some providers block the connection for a few minutes after repeated failures, so check before trying again.'**
  String get problemLoginRejectedAdvice;

  /// No description provided for @problemUnknownUser.
  ///
  /// In en, this message translates to:
  /// **'Unknown username'**
  String get problemUnknownUser;

  /// No description provided for @problemUnknownUserAdvice.
  ///
  /// In en, this message translates to:
  /// **'The provider doesn\'t know this username at this domain. Check both.'**
  String get problemUnknownUserAdvice;

  /// No description provided for @problemIntervalTooShort.
  ///
  /// In en, this message translates to:
  /// **'Registration interval too short'**
  String get problemIntervalTooShort;

  /// No description provided for @problemIntervalTooShortAdvice.
  ///
  /// In en, this message translates to:
  /// **'Raise the registration interval under Advanced.'**
  String get problemIntervalTooShortAdvice;

  /// No description provided for @problemNoAnswer.
  ///
  /// In en, this message translates to:
  /// **'Provider doesn\'t answer'**
  String get problemNoAnswer;

  /// No description provided for @problemNoAnswerAdvice.
  ///
  /// In en, this message translates to:
  /// **'Check the domain and outbound proxy. If they\'re right, the provider may be down; Sippier keeps trying.'**
  String get problemNoAnswerAdvice;

  /// No description provided for @problemNoNetwork.
  ///
  /// In en, this message translates to:
  /// **'No network'**
  String get problemNoNetwork;

  /// No description provided for @problemNoNetworkAdvice.
  ///
  /// In en, this message translates to:
  /// **'Sippier registers again when the network is back.'**
  String get problemNoNetworkAdvice;

  /// No description provided for @problemServerNotFound.
  ///
  /// In en, this message translates to:
  /// **'Server not found'**
  String get problemServerNotFound;

  /// No description provided for @problemServerNotFoundAdvice.
  ///
  /// In en, this message translates to:
  /// **'Check the domain and outbound proxy.'**
  String get problemServerNotFoundAdvice;

  /// No description provided for @problemFailed.
  ///
  /// In en, this message translates to:
  /// **'Registration failed'**
  String get problemFailed;

  /// No description provided for @problemFailedAdvice.
  ///
  /// In en, this message translates to:
  /// **'The provider\'s answer is below.'**
  String get problemFailedAdvice;

  /// No description provided for @errorCoreStart.
  ///
  /// In en, this message translates to:
  /// **'SIP core failed to start: {error}'**
  String errorCoreStart(String error);

  /// No description provided for @errorEndCallsFirst.
  ///
  /// In en, this message translates to:
  /// **'End the calls on {account} before editing it.'**
  String errorEndCallsFirst(String account);

  /// No description provided for @errorMicrophone.
  ///
  /// In en, this message translates to:
  /// **'Sippier needs microphone access for calls.'**
  String get errorMicrophone;

  /// No description provided for @callFailedBusy.
  ///
  /// In en, this message translates to:
  /// **'Busy'**
  String get callFailedBusy;

  /// No description provided for @callFailedNotFound.
  ///
  /// In en, this message translates to:
  /// **'Number not found ({reason})'**
  String callFailedNotFound(String reason);

  /// No description provided for @callFailedNotReachable.
  ///
  /// In en, this message translates to:
  /// **'Not reachable right now ({reason})'**
  String callFailedNotReachable(String reason);

  /// No description provided for @callFailedRejected.
  ///
  /// In en, this message translates to:
  /// **'The provider rejected the call ({reason}). If this line is also set up on another device, e.g. your router, the provider may only accept one of them.'**
  String callFailedRejected(String reason);

  /// No description provided for @callFailed.
  ///
  /// In en, this message translates to:
  /// **'Call failed: {reason}'**
  String callFailed(String reason);

  /// Status in the macOS menu bar and the Windows tray
  ///
  /// In en, this message translates to:
  /// **'In a call'**
  String get statusInCall;

  /// No description provided for @statusNoAccounts.
  ///
  /// In en, this message translates to:
  /// **'No accounts'**
  String get statusNoAccounts;

  /// No description provided for @statusRegisteredOne.
  ///
  /// In en, this message translates to:
  /// **'Registered: {account}'**
  String statusRegisteredOne(String account);

  /// count is 2 or more
  ///
  /// In en, this message translates to:
  /// **'{count} accounts registered'**
  String statusRegisteredAll(int count);

  /// No description provided for @statusRegisteredSome.
  ///
  /// In en, this message translates to:
  /// **'{registered} of {total, plural, =1{1 account} other{{total} accounts}} registered'**
  String statusRegisteredSome(int registered, int total);

  /// Menu item of the macOS menu bar and Windows tray icon
  ///
  /// In en, this message translates to:
  /// **'Open Sippier'**
  String get trayOpen;

  /// No description provided for @trayQuit.
  ///
  /// In en, this message translates to:
  /// **'Quit Sippier'**
  String get trayQuit;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['de', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
