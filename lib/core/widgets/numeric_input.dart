/// Numeric entry that behaves the way a cashier expects: the first keystroke
/// after a field gains focus REPLACES what is there, later keystrokes append.
library;

import 'package:material_ui/material_ui.dart';

/// Wraps a numeric text field so that whenever it gains focus its whole value
/// is selected, and the first keystroke therefore replaces it instead of
/// appending to it.
///
/// A field that opens showing 1 and is typed 5 into must become 5, not 15 —
/// a seller changing a quantity, a price or a received amount is restating
/// the number, not continuing it. Later keystrokes append as usual, so 1 then
/// 2 still gives 12.
///
/// The controller stays with the form around it: this widget only moves the
/// selection, never the text, and owns nothing it has to dispose.
///
/// It is a wrapper rather than a [TextField] subclass so that it goes around
/// a plain [TextField], a [TextFormField] with its validator, or a shared
/// field widget, without any of them changing shape.
class SelectAllOnFocus extends StatefulWidget {
  const SelectAllOnFocus({
    super.key,
    required this.controller,
    required this.child,
  });

  /// The controller of the field inside [child].
  final TextEditingController controller;

  final Widget child;

  @override
  State<SelectAllOnFocus> createState() => _SelectAllOnFocusState();
}

class _SelectAllOnFocusState extends State<SelectAllOnFocus> {
  /// Watches the focus of the field below without ever taking focus itself:
  /// a [Focus] node reports true as soon as a descendant is focused.
  final _watcher = FocusNode(
    skipTraversal: true,
    canRequestFocus: false,
    debugLabel: 'SelectAllOnFocus',
  );

  @override
  void dispose() {
    _watcher.dispose();
    super.dispose();
  }

  void _selectAll() {
    final text = widget.controller.text;
    if (text.isEmpty) return;
    final whole = TextSelection(baseOffset: 0, extentOffset: text.length);
    if (widget.controller.selection == whole) return;
    widget.controller.selection = whole;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _watcher,
      onFocusChange: (hasFocus) {
        if (!hasFocus) return;
        _selectAll();
        // A tap both focuses the field and drops the caret where the finger
        // landed, and the caret can be placed after the focus change: select
        // again once the frame is done — still before any keystroke.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _watcher.hasFocus) _selectAll();
        });
      },
      child: widget.child,
    );
  }
}
