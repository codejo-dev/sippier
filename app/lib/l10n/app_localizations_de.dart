// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get navKeypad => 'Tastenfeld';

  @override
  String get navRecents => 'Anrufliste';

  @override
  String get navAccounts => 'Konten';

  @override
  String get navSettings => 'Einstellungen';

  @override
  String get navAbout => 'Über';

  @override
  String get bannerBatteryRestricted =>
      'Die Akkunutzung ist auf „Eingeschränkt“ gesetzt, daher kann Sippier im Hintergrund keine Anrufe empfangen. Stelle sie unter „App-Akkunutzung“ auf „Optimiert“ oder „Nicht eingeschränkt“.';

  @override
  String get bannerBatterySaverNeedsUnrestricted =>
      'Der Akkusparmodus braucht die Akkunutzung „Nicht eingeschränkt“. Sonst verzögert Android das Aufwecken, Registrierungen laufen ab und Anrufe gehen verloren.';

  @override
  String get bannerLockScreen =>
      'Erlaube Sippier, eingehende Anrufe auf dem Sperrbildschirm anzuzeigen.';

  @override
  String get buttonChange => 'Ändern';

  @override
  String get buttonKeepAwakeInstead => 'Stattdessen wach halten';

  @override
  String get buttonAllow => 'Erlauben';

  @override
  String get buttonCancel => 'Abbrechen';

  @override
  String get buttonSave => 'Speichern';

  @override
  String get buttonExport => 'Exportieren';

  @override
  String get buttonImport => 'Importieren';

  @override
  String get headerGeneral => 'Allgemein';

  @override
  String get language => 'Sprache';

  @override
  String languageSystem(String language) {
    return 'Systemstandard ($language)';
  }

  @override
  String get languageName => 'Deutsch';

  @override
  String get launchAtLogin => 'Beim Anmelden öffnen';

  @override
  String get launchAtLoginMenuBar =>
      'Startet in der Menüleiste, bereit für Anrufe';

  @override
  String get launchAtLoginTray =>
      'Startet im Infobereich der Taskleiste, bereit für Anrufe';

  @override
  String get headerAudio => 'Audio';

  @override
  String get ringtone => 'Klingelton';

  @override
  String get ringtoneAndroidHint =>
      'In den Benachrichtigungseinstellungen von Android festlegen';

  @override
  String get headerBackgroundCalls => 'Anrufe im Hintergrund';

  @override
  String get keepPhoneAwake => 'Telefon wach halten';

  @override
  String get keepPhoneAwakeOn =>
      'Am zuverlässigsten für eingehende Anrufe, aber das Telefon schläft nie, solange Sippier läuft.';

  @override
  String get keepPhoneAwakeOff =>
      'Akkusparmodus: Sippier weckt das Telefon kurz vor jeder Erneuerung der Registrierung. Braucht die Akkunutzung „Nicht eingeschränkt“. Bei manchen Anbietern und Netzen können trotzdem Anrufe verloren gehen.';

  @override
  String batterySaverWakeUps(String intervals) {
    return 'Der Akkusparmodus weckt es alle $intervals.';
  }

  @override
  String batterySaverWakeUp(String interval, String account) {
    return '$interval für $account';
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
  String get headerDiagnostics => 'Diagnose';

  @override
  String get sipTrace => 'SIP-Trace';

  @override
  String get sipTraceHint =>
      'Schreibt jede SIP-Nachricht in die Protokolldatei. Enthält deine Nummer und Auth-Hashes, nie Passwörter.';

  @override
  String get log => 'Protokoll';

  @override
  String get logPathCopied => 'Pfad der Protokolldatei kopiert';

  @override
  String get copyLogPath => 'Pfad der Protokolldatei kopieren';

  @override
  String get licences => 'Open-Source-Lizenzen';

  @override
  String licenceCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Lizenzen',
      one: '1 Lizenz',
    );
    return '$_temp0';
  }

  @override
  String get aboutSippier => 'Über Sippier';

  @override
  String get aboutSippierHint => 'Version, Autor, Website und Lizenzen';

  @override
  String aboutVersion(String version) {
    return 'Version $version';
  }

  @override
  String get aboutTagline => 'Ein einfaches Open-Source-SIP-Telefon.';

  @override
  String get aboutAuthor => 'Autor';

  @override
  String get aboutWebsite => 'Website';

  @override
  String get aboutLicence => 'Lizenz';

  @override
  String get addAccount => 'Konto hinzufügen';

  @override
  String get editAccount => 'Konto bearbeiten';

  @override
  String get removeAccount => 'Konto entfernen';

  @override
  String get accountsEmpty =>
      'Sippier funktioniert mit jedem SIP-Anbieter. Trage die Zugangsdaten deines Anbieters ein.';

  @override
  String get accountsExport => 'Konten exportieren';

  @override
  String get accountsImport => 'Konten importieren';

  @override
  String get accountsFileType => 'Sippier-Konten';

  @override
  String get accountsExportTitle => 'Mit Passwörtern exportieren?';

  @override
  String get accountsExportWarning =>
      'Die Datei enthält die Passwörter deiner Konten unverschlüsselt. Wer sie bekommt, kann deine Leitungen nutzen. Bewahre sie sicher auf und lösche sie, sobald du sie nicht mehr brauchst.';

  @override
  String accountsExported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Konten exportiert',
      one: '1 Konto exportiert',
    );
    return '$_temp0';
  }

  @override
  String get fileWriteFailed => 'Die Datei konnte nicht geschrieben werden.';

  @override
  String accountsImportTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Konten importieren?',
      one: '1 Konto importieren?',
    );
    return '$_temp0';
  }

  @override
  String get accountsImportReplaces =>
      'Ein Konto mit derselben Adresse wie ein vorhandenes ersetzt dieses, samt Passwort.';

  @override
  String accountsImported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Konten importiert',
      one: '1 Konto importiert',
    );
    return '$_temp0';
  }

  @override
  String get accountsImportInvalid => 'Das ist keine Kontendatei von Sippier.';

  @override
  String get accountsImportNewer =>
      'Die Datei stammt von einer neueren Sippier-Version. Aktualisiere Sippier, um sie zu importieren.';

  @override
  String removeAccountQuestion(String account) {
    return '$account entfernen?';
  }

  @override
  String get removeAccountExplanation =>
      'Das Konto und sein gespeichertes Passwort werden von diesem Gerät gelöscht.';

  @override
  String get buttonRemove => 'Entfernen';

  @override
  String get regOff => 'Aus';

  @override
  String get regIdle => 'Nicht registriert';

  @override
  String get regRegistering => 'Wird registriert…';

  @override
  String get regRegistered => 'Registriert';

  @override
  String regFailed(String reason) {
    return 'Fehlgeschlagen: $reason';
  }

  @override
  String get recentsClear => 'Anrufliste löschen';

  @override
  String get recentsEmpty => 'Noch keine Anrufe.';

  @override
  String get callBack => 'Zurückrufen';

  @override
  String get recentsClearQuestion => 'Anrufliste löschen?';

  @override
  String get buttonClear => 'Löschen';

  @override
  String get callMissed => 'Verpasst';

  @override
  String get callIncoming => 'Eingehend';

  @override
  String get callOutgoing => 'Ausgehend';

  @override
  String get dialerNoAccount => 'Füge ein SIP-Konto hinzu, um zu telefonieren.';

  @override
  String get dialerNumberHint => 'Nummer';

  @override
  String get dialerDelete => 'Löschen';

  @override
  String get dialerCall => 'Anrufen';

  @override
  String callVia(String account) {
    return 'über $account';
  }

  @override
  String get callHideKeypad => 'Tastenfeld ausblenden';

  @override
  String get callMute => 'Stumm';

  @override
  String get callKeypad => 'Tastenfeld';

  @override
  String get callSpeaker => 'Lautsprecher';

  @override
  String get callHold => 'Halten';

  @override
  String get callResume => 'Fortsetzen';

  @override
  String get callEnd => 'Beenden';

  @override
  String get callDecline => 'Ablehnen';

  @override
  String get callAnswer => 'Annehmen';

  @override
  String get callAnswerAndHold => 'Annehmen und aktuellen Anruf halten';

  @override
  String get callActive => 'Aktiv';

  @override
  String get callOnHold => 'Gehalten';

  @override
  String get callHeldByOtherSide => 'Von der Gegenseite gehalten';

  @override
  String get callIncomingCall => 'Eingehender Anruf';

  @override
  String get callCalling => 'Wählt…';

  @override
  String get callRinging => 'Klingelt…';

  @override
  String get callConnecting => 'Verbindet…';

  @override
  String get audioSystemDefault => 'Systemstandard';

  @override
  String audioSystemDefaultDevice(String device) {
    return 'Systemstandard ($device)';
  }

  @override
  String audioNotConnected(String device) {
    return '$device (nicht verbunden)';
  }

  @override
  String get audioMicrophone => 'Mikrofon';

  @override
  String get audioSpeaker => 'Lautsprecher';

  @override
  String get audioRingingOn => 'Klingeln auf';

  @override
  String get ringtoneAccountsOwn => 'Konten können einen eigenen haben';

  @override
  String ringtoneDefault(String tone) {
    return 'Standard ($tone)';
  }

  @override
  String get ringtoneChooseFile => 'Datei auswählen…';

  @override
  String get ringtoneFileTypeSounds => 'Töne';

  @override
  String get ringtoneFileTypeWav => 'WAV-Töne';

  @override
  String get ringtonePlay => 'Abspielen';

  @override
  String get ringtoneStop => 'Stopp';

  @override
  String get ringtoneBubbles => 'Blubbern';

  @override
  String get ringtoneMarimba => 'Marimba';

  @override
  String get ringtoneGlass => 'Glas';

  @override
  String get ringtoneClassic => 'Klassisch';

  @override
  String providerSaid(String detail) {
    return 'Antwort des Anbieters: $detail';
  }

  @override
  String get fieldRequired => 'Pflichtfeld';

  @override
  String get fieldHostPort => 'Host oder Host:Port, ohne „sip:“';

  @override
  String get fieldName => 'Name (optional)';

  @override
  String get fieldNameHint => 'z. B. Büroanschluss';

  @override
  String get fieldUser => 'Benutzername oder Rufnummer';

  @override
  String get fieldPassword => 'Passwort';

  @override
  String get fieldPasswordKeep =>
      'Leer lassen, um das gespeicherte Passwort zu behalten';

  @override
  String get fieldDomain => 'Domain';

  @override
  String get fieldAuthUser => 'Auth-Benutzername (falls abweichend)';

  @override
  String get fieldOutboundProxy => 'Outbound-Proxy (optional)';

  @override
  String get fieldAdvanced => 'Erweitert';

  @override
  String get fieldMediaEncryption => 'Medienverschlüsselung';

  @override
  String get encryptionOff => 'Aus';

  @override
  String get encryptionIfOffered => 'SRTP, wenn angeboten';

  @override
  String get encryptionRequired => 'SRTP erforderlich';

  @override
  String get fieldRegInterval => 'Registrierungsintervall (Sekunden)';

  @override
  String get fieldRegIntervalMin => 'Mindestens 60';

  @override
  String get fieldCodecs => 'Codecs nach Priorität';

  @override
  String get fieldCodecsHint => 'baresip-Namen, z. B. G722/16000/1,PCMA,PCMU';

  @override
  String get fieldStun => 'STUN-Server (optional)';

  @override
  String get checkUserDomain =>
      'Nur der Teil vor dem @; der Teil danach gehört unter Domain';

  @override
  String get checkWithoutSip => 'Ohne „sip:“';

  @override
  String get checkNoSpaces => 'Keine Leerzeichen';

  @override
  String problemNotRetried(String summary) {
    return '$summary (kein neuer Versuch)';
  }

  @override
  String problemNotRetriedAdvice(String advice) {
    return '$advice Sippier versucht es nicht von selbst erneut, damit ein falsches Passwort dich nicht aussperren kann. Speichere das Konto, um es noch einmal zu versuchen.';
  }

  @override
  String get problemLoginRejected => 'Anmeldung abgelehnt';

  @override
  String get problemLoginRejectedAdvice =>
      'Vergleiche Benutzername, Auth-Benutzername und Passwort mit den Angaben deines Anbieters. Manche Anbieter sperren die Verbindung nach wiederholten Fehlversuchen für einige Minuten, also prüfe alles, bevor du es erneut versuchst.';

  @override
  String get problemUnknownUser => 'Unbekannter Benutzername';

  @override
  String get problemUnknownUserAdvice =>
      'Der Anbieter kennt diesen Benutzernamen unter dieser Domain nicht. Prüfe beides.';

  @override
  String get problemIntervalTooShort => 'Registrierungsintervall zu kurz';

  @override
  String get problemIntervalTooShortAdvice =>
      'Erhöhe das Registrierungsintervall unter „Erweitert“.';

  @override
  String get problemNoAnswer => 'Anbieter antwortet nicht';

  @override
  String get problemNoAnswerAdvice =>
      'Prüfe Domain und Outbound-Proxy. Stimmen sie, ist der Anbieter vielleicht gestört; Sippier versucht es weiter.';

  @override
  String get problemNoNetwork => 'Kein Netzwerk';

  @override
  String get problemNoNetworkAdvice =>
      'Sippier registriert sich erneut, sobald das Netzwerk wieder da ist.';

  @override
  String get problemServerNotFound => 'Server nicht gefunden';

  @override
  String get problemServerNotFoundAdvice => 'Prüfe Domain und Outbound-Proxy.';

  @override
  String get problemFailed => 'Registrierung fehlgeschlagen';

  @override
  String get problemFailedAdvice => 'Die Antwort des Anbieters steht unten.';

  @override
  String errorCoreStart(String error) {
    return 'Der SIP-Kern konnte nicht starten: $error';
  }

  @override
  String errorEndCallsFirst(String account) {
    return 'Beende die Anrufe über $account, bevor du das Konto bearbeitest.';
  }

  @override
  String get errorMicrophone =>
      'Sippier braucht für Anrufe Zugriff auf das Mikrofon.';

  @override
  String get callFailedBusy => 'Besetzt';

  @override
  String callFailedNotFound(String reason) {
    return 'Nummer nicht gefunden ($reason)';
  }

  @override
  String callFailedNotReachable(String reason) {
    return 'Gerade nicht erreichbar ($reason)';
  }

  @override
  String callFailedRejected(String reason) {
    return 'Der Anbieter hat den Anruf abgelehnt ($reason). Ist dieser Anschluss auch auf einem anderen Gerät eingerichtet, z. B. deinem Router, akzeptiert der Anbieter vielleicht nur eines davon.';
  }

  @override
  String callFailed(String reason) {
    return 'Anruf fehlgeschlagen: $reason';
  }

  @override
  String get statusInCall => 'Im Gespräch';

  @override
  String get statusNoAccounts => 'Keine Konten';

  @override
  String statusRegisteredOne(String account) {
    return 'Registriert: $account';
  }

  @override
  String statusRegisteredAll(int count) {
    return '$count Konten registriert';
  }

  @override
  String statusRegisteredSome(int registered, int total) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: '$total Konten',
      one: '1 Konto',
    );
    return '$registered von $_temp0 registriert';
  }

  @override
  String get trayOpen => 'Sippier öffnen';

  @override
  String get trayQuit => 'Sippier beenden';
}
