import 'package:flutter/widgets.dart';

/// Runs [action] when this widget first appears and every time the app
/// comes back to the front.
///
/// For what must follow the calendar: a screen left on "Today" overnight —
/// a shop phone is never switched off — would still show, and delete,
/// yesterday.
class OnOpenAndResume extends StatefulWidget {
  const OnOpenAndResume({super.key, required this.action, required this.child});

  final VoidCallback action;
  final Widget child;

  @override
  State<OnOpenAndResume> createState() => _OnOpenAndResumeState();
}

class _OnOpenAndResumeState extends State<OnOpenAndResume>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // After the first frame: [action] may change a provider, which is not
    // allowed while the tree is being built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.action();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) widget.action();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
