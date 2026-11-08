import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../providers.dart';
import 'about_page.dart';
import 'accounts_page.dart';
import 'call_screen.dart';
import 'dialer_page.dart';
import 'recents_page.dart';
import 'settings_page.dart';

/// Tabs (keypad, recents, accounts, settings), replaced by the call screen
/// while there are calls. Phones have them in a bottom bar, and About in
/// the settings; wider windows in a rail on the left, with settings and
/// About at its foot.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  static const _accountsTab = 2;
  static const _settingsTab = 3;
  static const _aboutTab = 4;
  int _tab = 0;
  bool _lockScreenAllowed = true;
  bool _backgroundRestricted = false;
  bool _batteryUnrestricted = true;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onExitRequested: () async {
        ref.read(phoneProvider.notifier).shutdown();
        return AppExitResponse.exit;
      },
      // e.g. back from the system setting
      onResume: _checkSystemSettings,
    );
    _checkSystemSettings();
  }

  /// Android settings that stop calls from coming in or showing up.
  Future<void> _checkSystemSettings() async {
    final platform = ref.read(platformProvider);
    final allowed = await platform.canShowCallsOnLockScreen();
    final restricted = await platform.isBackgroundRestricted();
    final unrestricted = await platform.isBatteryUnrestricted();
    if (mounted &&
        (allowed != _lockScreenAllowed ||
            restricted != _backgroundRestricted ||
            unrestricted != _batteryUnrestricted)) {
      setState(() {
        _lockScreenAllowed = allowed;
        _backgroundRestricted = restricted;
        _batteryUnrestricted = unrestricted;
      });
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final hasCalls = ref.watch(phoneProvider.select((s) => s.calls.isNotEmpty));
    // Keep collecting log lines while the log page is closed
    ref.listen(logProvider, (_, _) {});
    ref.listen(phoneProvider.select((s) => s.error), (_, error) {
      if (error == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          duration: Duration(seconds: error.length > 80 ? 8 : 4),
        ),
      );
      ref.read(phoneProvider.notifier).clearError();
    });

    if (hasCalls) return const CallScreen();

    final phone = MediaQuery.sizeOf(context).width < 640;
    final pages = [
      DialerPage(onAddAccount: () => setState(() => _tab = _accountsTab)),
      const RecentsPage(),
      const AccountsPage(),
      SettingsPage(showAbout: phone),
      // Built when it's opened, so its licences load only then
      if (_tab == _aboutTab) const AboutPage() else const SizedBox.shrink(),
    ];
    final destinations = [
      (Icons.dialpad, l.navKeypad),
      (Icons.history, l.navRecents),
      (Icons.account_circle_outlined, l.navAccounts),
      (Icons.settings_outlined, l.navSettings),
      (Icons.info_outline, l.navAbout),
    ];
    Widget body = IndexedStack(index: _tab, children: pages);
    final stayAwake = ref.watch(stayAwakeProvider);
    final banners = [
      if (_backgroundRestricted)
        MaterialBanner(
          leading: const Icon(Icons.battery_alert_outlined),
          content: Text(l.bannerBatteryRestricted),
          actions: [
            TextButton(
              onPressed: () => ref.read(platformProvider).openBatterySettings(),
              child: Text(l.buttonChange),
            ),
          ],
        ),
      // Optimized: the battery saver's wake-ups come late or not at all
      if (!stayAwake && !_batteryUnrestricted && !_backgroundRestricted)
        MaterialBanner(
          leading: const Icon(Icons.battery_alert_outlined),
          content: Text(l.bannerBatterySaverNeedsUnrestricted),
          actions: [
            TextButton(
              onPressed: () => ref.read(stayAwakeProvider.notifier).set(true),
              child: Text(l.buttonKeepAwakeInstead),
            ),
            TextButton(
              onPressed: () =>
                  ref.read(platformProvider).requestUnrestrictedBattery(),
              child: Text(l.buttonAllow),
            ),
          ],
        ),
      if (!_lockScreenAllowed)
        MaterialBanner(
          leading: const Icon(Icons.phone_locked_outlined),
          content: Text(l.bannerLockScreen),
          actions: [
            TextButton(
              onPressed: () =>
                  ref.read(platformProvider).openLockScreenSettings(),
              child: Text(l.buttonAllow),
            ),
          ],
        ),
    ];
    if (banners.isNotEmpty) {
      body = Column(
        children: [
          SafeArea(bottom: false, child: Column(children: banners)),
          Expanded(child: body),
        ],
      );
    }

    if (phone) {
      return Scaffold(
        body: body,
        bottomNavigationBar: NavigationBar(
          // About (open when the window became narrow) is part of settings
          selectedIndex: _tab < _aboutTab ? _tab : _settingsTab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: [
            for (final (icon, label) in destinations.take(_aboutTab))
              NavigationDestination(icon: Icon(icon), label: label),
          ],
        ),
      );
    }
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _tab < _settingsTab ? _tab : null,
            onDestinationSelected: (i) => setState(() => _tab = i),
            labelType: NavigationRailLabelType.all,
            destinations: [
              for (final (icon, label) in destinations.take(_settingsTab))
                NavigationRailDestination(icon: Icon(icon), label: Text(label)),
            ],
            trailing: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final tab in [_settingsTab, _aboutTab])
                    _RailButton(
                      icon: destinations[tab].$1,
                      label: destinations[tab].$2,
                      selected: _tab == tab,
                      onTap: () => setState(() => _tab = tab),
                    ),
                ],
              ),
            ),
            trailingAtBottom: true,
          ),
          const VerticalDivider(width: 1),
          Expanded(child: body),
        ],
      ),
    );
  }
}

/// A destination at the rail's foot (settings, About), drawn like the
/// rail's own: the icon in a pill that fills when selected, the label
/// underneath.
class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.labelMedium;
    // The rail's own destinations' spacing
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Semantics(
        button: true,
        selected: selected,
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: SizedBox(
            width: 80,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 32,
                  decoration: ShapeDecoration(
                    shape: const StadiumBorder(),
                    color: selected ? scheme.secondaryContainer : null,
                  ),
                  child: Icon(
                    icon,
                    color: selected
                        ? scheme.onSecondaryContainer
                        : scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: style?.copyWith(
                    color: selected
                        ? scheme.onSurface
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
