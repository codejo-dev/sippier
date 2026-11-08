import 'package:flutter/material.dart';

/// Phone keypad. Long-pressing 0 gives "+".
class Keypad extends StatelessWidget {
  const Keypad({super.key, required this.onKey, this.buttonSize = 72});

  final void Function(String key) onKey;
  final double buttonSize;

  static const _keys = [
    ('1', ''),
    ('2', 'ABC'),
    ('3', 'DEF'),
    ('4', 'GHI'),
    ('5', 'JKL'),
    ('6', 'MNO'),
    ('7', 'PQRS'),
    ('8', 'TUV'),
    ('9', 'WXYZ'),
    ('*', ''),
    ('0', '+'),
    ('#', ''),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var row = 0; row < 4; row++)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (key, letters) in _keys.skip(row * 3).take(3))
                Padding(
                  padding: const EdgeInsets.all(6),
                  child: _KeyButton(
                    label: key,
                    letters: letters,
                    size: buttonSize,
                    onTap: () => onKey(key),
                    onLongPress: key == '0' ? () => onKey('+') : null,
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class _KeyButton extends StatelessWidget {
  const _KeyButton({
    required this.label,
    required this.letters,
    required this.size,
    required this.onTap,
    this.onLongPress,
  });

  final String label;
  final String letters;
  final double size;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return SizedBox.square(
      dimension: size,
      child: Material(
        color: scheme.surfaceContainerHighest,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Small keys only have room for the digit
              Text(
                label,
                style: size < 56 ? text.titleLarge : text.headlineSmall,
              ),
              if (letters.isNotEmpty && size >= 56)
                Text(
                  letters,
                  style: text.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
