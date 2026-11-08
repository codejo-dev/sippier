// Renders every screen with sample data at phone and desktop sizes, in
// English and German, and fails on layout errors (e.g. overflows). With
// SCREENSHOTS=1 it also writes PNGs to build/screenshots/<language>/.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sippier/data/account_store.dart';
import 'package:sippier/data/call_history.dart';
import 'package:sippier/l10n/app_localizations.dart';
import 'package:sippier/phone/phone_controller.dart';
import 'package:sippier/phone/phone_state.dart';
import 'package:sippier/providers.dart';
import 'package:sippier/ui/about_page.dart';
import 'package:sippier/ui/account_form.dart';
import 'package:sippier/ui/home_shell.dart';
import 'package:sippier/ui/theme.dart';
import 'package:sippier_core/sippier_core.dart';

const _office = AccountEntry(
  id: 'a1',
  settings: AccountSettings(
    user: '4930555',
    domain: 'sip.example.net',
    displayName: 'Office',
  ),
);
const _home = AccountEntry(
  id: 'a2',
  settings: AccountSettings(user: '4940555', domain: 'sip.plusnet.de'),
  enabled: false,
);
const _line = AccountEntry(
  id: 'a3',
  settings: AccountSettings(
    user: '+49711555',
    domain: 'fixed.vodafone.de',
    displayName: 'Landline',
    authUser: 'IMPL_49711555',
    outboundProxy: 'egf13.fixed.vodafone.de',
  ),
);

ActiveCall _call(
  String id,
  CallPhase phase, {
  bool incoming = false,
  String name = '',
}) => ActiveCall(
  id: id,
  accountId: 'a1',
  peerUri: 'sip:+4989123456@sip.example.net',
  peerName: name,
  incoming: incoming,
  phase: phase,
  startedAt: DateTime(2026, 11, 2, 10),
  connectedAt: phase == CallPhase.connected ? DateTime.now() : null,
  encryption: phase == CallPhase.connected ? 'srtp' : '',
);

class _FakePhone extends PhoneController {
  _FakePhone(this.initial);

  final PhoneState initial;

  @override
  PhoneState build() => initial;
}

class _FakeHistory extends CallHistory {
  @override
  List<CallRecord> build() => [
    CallRecord(
      peerUri: 'sip:+4989123456@sip.example.net',
      peerName: 'Anna Example',
      accountId: 'a1',
      incoming: true,
      startedAt: DateTime.now().subtract(const Duration(hours: 1)),
      endedAt: DateTime.now(),
      connectedAt: DateTime.now().subtract(const Duration(minutes: 3)),
    ),
    CallRecord(
      peerUri: 'sip:0301234567@sip.example.net',
      peerName: '',
      accountId: 'a1',
      incoming: true,
      startedAt: DateTime(2026, 10, 30, 18, 5),
      endedAt: DateTime(2026, 10, 30, 18, 6),
    ),
    CallRecord(
      peerUri: 'sip:+4940999@sip.plusnet.de',
      peerName: '',
      accountId: 'a2',
      incoming: false,
      startedAt: DateTime(2025, 12, 24, 9, 30),
      endedAt: DateTime(2025, 12, 24, 9, 45),
      connectedAt: DateTime(2025, 12, 24, 9, 31),
    ),
  ];
}

const _accounts = PhoneState(
  ready: true,
  accounts: [_office, _home, _line],
  status: {
    'a1': AccountStatus(RegState.registered, '200 OK'),
    'a2': AccountStatus(RegState.disabled),
    'a3': AccountStatus(
      RegState.failed,
      '403 Forbidden - 6037 Identities do not match',
      true,
    ),
  },
);

final _sizes = {
  'phone': const Size(390, 844),
  'desktop': const Size(1000, 700),
};

Future<void> _loadFonts() async {
  final dir =
      '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      final bytes = File('$dir/$f').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }

  await load('Roboto', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf']);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

Future<void> _screen(
  WidgetTester tester,
  String name,
  Size size,
  PhoneState state,
  Widget home, {
  required Locale locale,
  int tab = 0,
  Finder? tap,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final key = GlobalKey();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDirProvider.overrideWithValue(Directory.systemTemp.path),
        phoneProvider.overrideWith(() => _FakePhone(state)),
        callHistoryProvider.overrideWith(_FakeHistory.new),
      ],
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: sippierTheme(Brightness.light, fontFamily: 'Roboto'),
          home: home,
        ),
      ),
    ),
  );
  await tester.pump();
  if (tab > 0) {
    final l = lookupAppLocalizations(locale);
    final labels = [
      l.navKeypad,
      l.navRecents,
      l.navAccounts,
      l.navSettings,
      l.navAbout,
    ];
    await tester.tap(find.text(labels[tab]).last);
    // the rail's selection moves with an animation, which starts with the
    // first frame
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }
  if (tap != null) {
    await tester.tap(tap);
    await tester.pump();
  }
  expect(tester.takeException(), isNull, reason: name);

  if (Platform.environment['SCREENSHOTS'] == '1') {
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/screenshots/${locale.languageCode}/$name.png');
      await file.create(recursive: true);
      await file.writeAsBytes(png!.buffer.asUint8List());
    });
  }
}

void main() {
  setUpAll(_loadFonts);
  for (final locale in const [Locale('en'), Locale('de')]) {
    group(locale.languageCode, () => _screens(locale));
  }
}

void _screens(Locale locale) {
  Future<void> screen(
    WidgetTester tester,
    String name,
    Size size,
    PhoneState state,
    Widget home, {
    int tab = 0,
    Finder? tap,
  }) => _screen(
    tester,
    name,
    size,
    state,
    home,
    locale: locale,
    tab: tab,
    tap: tap,
  );

  for (final MapEntry(key: sizeName, value: size) in _sizes.entries) {
    testWidgets(
      'no accounts ($sizeName)',
      (t) => screen(
        t,
        'empty-$sizeName',
        size,
        const PhoneState(ready: true),
        const HomeShell(),
      ),
    );
    testWidgets(
      'dialer ($sizeName)',
      (t) => screen(t, 'dialer-$sizeName', size, _accounts, const HomeShell()),
    );
    testWidgets(
      'recents ($sizeName)',
      (t) => screen(
        t,
        'recents-$sizeName',
        size,
        _accounts,
        const HomeShell(),
        tab: 1,
      ),
    );
    testWidgets(
      'accounts ($sizeName)',
      (t) => screen(
        t,
        'accounts-$sizeName',
        size,
        _accounts,
        const HomeShell(),
        tab: 2,
      ),
    );
    testWidgets(
      'settings ($sizeName)',
      (t) => screen(
        t,
        'settings-$sizeName',
        size,
        _accounts,
        const HomeShell(),
        tab: 3,
      ),
    );
    // The rail's foot on desktop; on phones it opens from the settings
    testWidgets(
      'about ($sizeName)',
      (t) => sizeName == 'phone'
          ? screen(t, 'about-$sizeName', size, _accounts, const AboutPage())
          : screen(
              t,
              'about-$sizeName',
              size,
              _accounts,
              const HomeShell(),
              tab: 4,
            ),
    );
    testWidgets(
      'account form ($sizeName)',
      (t) => screen(
        t,
        'account-form-$sizeName',
        size,
        _accounts,
        const AccountForm(accountId: 'a1'),
      ),
    );
    testWidgets(
      'account form, registration failed ($sizeName)',
      (t) => screen(
        t,
        'account-form-failed-$sizeName',
        size,
        _accounts,
        const AccountForm(accountId: 'a3'),
      ),
    );
    testWidgets(
      'incoming call ($sizeName)',
      (t) => screen(
        t,
        'call-incoming-$sizeName',
        size,
        _accounts.copyWith(
          calls: [
            _call(
              'c1',
              CallPhase.incoming,
              incoming: true,
              name: 'Anna Example',
            ),
          ],
        ),
        const HomeShell(),
      ),
    );
    testWidgets(
      'call with waiting call ($sizeName)',
      (t) => screen(
        t,
        'call-waiting-$sizeName',
        size,
        _accounts.copyWith(
          calls: [
            _call('c1', CallPhase.connected),
            _call(
              'c2',
              CallPhase.incoming,
              incoming: true,
              name: 'Anna Example',
            ),
          ],
        ),
        const HomeShell(),
      ),
    );
  }

  // The in-call keypad on a short phone and in a small desktop window
  for (final MapEntry(key: name, value: size) in {
    'phone-short': const Size(360, 640),
    'small-window': const Size(700, 460),
  }.entries) {
    testWidgets(
      'call keypad ($name)',
      (t) => screen(
        t,
        'call-keypad-$name',
        size,
        _accounts.copyWith(calls: [_call('c1', CallPhase.connected)]),
        const HomeShell(),
        tap: find.byIcon(Icons.dialpad),
      ),
    );
  }
}
