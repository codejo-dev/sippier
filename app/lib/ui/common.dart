import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../phone/phone_state.dart';
import '../phone/registration_problem.dart';

Color regStateColor(BuildContext context, RegState state) => switch (state) {
  RegState.registered => Colors.green,
  RegState.registering => Colors.amber,
  RegState.failed => Theme.of(context).colorScheme.error,
  RegState.idle || RegState.disabled => Theme.of(context).disabledColor,
};

/// Coloured dot for an account's registration state.
class StatusDot extends StatelessWidget {
  const StatusDot(this.state, {super.key});

  final RegState state;

  @override
  Widget build(BuildContext context) => Container(
    width: 10,
    height: 10,
    decoration: BoxDecoration(
      color: regStateColor(context, state),
      shape: BoxShape.circle,
    ),
  );
}

/// Rounded vertical bar for an account's registration state, at the start
/// of a list row. Takes the height it's given.
class StatusBar extends StatelessWidget {
  const StatusBar(this.state, {super.key});

  final RegState state;

  @override
  Widget build(BuildContext context) => Container(
    width: 6,
    decoration: BoxDecoration(
      color: regStateColor(context, state),
      borderRadius: BorderRadius.circular(3),
    ),
  );
}

String regStateLabel(AppLocalizations l, AccountStatus s) => switch (s.state) {
  RegState.disabled => l.regOff,
  RegState.idle => l.regIdle,
  RegState.registering => l.regRegistering,
  RegState.registered => l.regRegistered,
  RegState.failed => l.regFailed(
    RegistrationProblem.from(l, s.detail, stopped: s.stopped).summary,
  ),
};

String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

String formatTime(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  final now = DateTime.now();
  final time = '${two(t.hour)}:${two(t.minute)}';
  if (t.year == now.year && t.month == now.month && t.day == now.day) {
    return time;
  }
  return '${two(t.day)}.${two(t.month)}.${t.year == now.year ? '' : t.year} $time';
}

/// Round icon button with a label underneath, as on phone call screens.
class CallControl extends StatelessWidget {
  const CallControl({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.active = false,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool active;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background =
        color ?? (active ? scheme.primary : scheme.surfaceContainerHighest);
    final foreground = color != null
        ? Colors.white
        : active
        ? scheme.onPrimary
        : scheme.onSurface;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox.square(
          dimension: 64,
          child: IconButton.filled(
            onPressed: onPressed,
            style: IconButton.styleFrom(
              backgroundColor: background,
              foregroundColor: foreground,
            ),
            icon: Icon(icon, size: 28),
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: Theme.of(context).textTheme.labelMedium),
      ],
    );
  }
}
