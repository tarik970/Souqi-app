import 'package:material_ui/material_ui.dart';

import '../money/money_format.dart';

/// The on-screen number pad of the quantity sheet and of the return screen:
/// 1–9, the decimal separator, 0 and backspace (a long press clears).
///
/// It only reports keys; the screen that shows it owns the text being typed
/// and the "first key replaces" rule (a value a field opened with is
/// restated, not continued).
class NumberPad extends StatelessWidget {
  const NumberPad({
    super.key,
    required this.locale,
    required this.separatorEnabled,
    required this.onDigit,
    required this.onSeparator,
    required this.onBackspace,
    required this.onClear,
  });

  /// The app language: the digits and the separator are shown in its shapes.
  final String locale;

  /// False while the value being typed takes no decimals (whole cards).
  final bool separatorEnabled;
  final ValueChanged<String> onDigit;
  final VoidCallback onSeparator;
  final VoidCallback onBackspace;
  final VoidCallback onClear;

  /// The height of the whole pad: four rows of keys with their padding.
  static const double height = 4 * (_keyHeight + 8);

  static const double _keyHeight = 54;

  @override
  Widget build(BuildContext context) {
    Widget key(
      Widget child,
      VoidCallback? onTap, {
      VoidCallback? onLongPress,
      String? id,
    }) {
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: SizedBox(
            height: _keyHeight,
            child: OutlinedButton(
              key: id == null ? null : ValueKey('keypad-$id'),
              onPressed: onTap,
              onLongPress: onLongPress,
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.zero,
                textStyle: Theme.of(context).textTheme.titleLarge,
              ),
              child: child,
            ),
          ),
        ),
      );
    }

    Widget digit(String d) => key(
          Text(localizeDigits(d, locale)),
          () => onDigit(d),
          id: d,
        );

    // A NUMBER PAD IS NEVER MIRRORED: 1 2 3 from left to right in Arabic
    // too, as on the phone's dialer and every calculator. Without this the
    // rows follow the app's direction and read 3 2 1.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Column(
        children: [
          Row(children: [digit('1'), digit('2'), digit('3')]),
          Row(children: [digit('4'), digit('5'), digit('6')]),
          Row(children: [digit('7'), digit('8'), digit('9')]),
          Row(children: [
            key(
              Text(decimalSeparator(locale)),
              separatorEnabled ? onSeparator : null,
              id: 'separator',
            ),
            digit('0'),
            key(
              const Icon(Icons.backspace_outlined),
              onBackspace,
              onLongPress: onClear,
              id: 'backspace',
            ),
          ]),
        ],
      ),
    );
  }
}
