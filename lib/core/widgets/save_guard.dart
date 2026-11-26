import 'package:material_ui/material_ui.dart';

import '../../l10n/generated/app_localizations.dart';
import '../logging/error_log.dart';

/// Runs a write the user asked for and returns its result — or, when it
/// THROWS (the storage is full, the database or the Keystore did not
/// answer), says so in a snack bar, writes the error to the error log and
/// returns null.
///
/// The form that called it then frees its Save button again. Without this a
/// failed write left the button disabled for good and nothing on screen: the
/// seller could not tell whether the payment had been recorded.
///
/// [what] names the action in the error log ("payment", "ledger entry").
Future<T?> runSave<T extends Object>(
  BuildContext context,
  Future<T> Function() write, {
  required String what,
}) async {
  // Taken before the await: the page may be gone when the write ends.
  final messenger = ScaffoldMessenger.maybeOf(context);
  final l10n = AppLocalizations.of(context);
  try {
    return await write();
  } on Object catch (error, stack) {
    reportError(error, stack, context: what);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.saveFailedGeneric)));
    return null;
  }
}
