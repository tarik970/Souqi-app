import '../../core/utils/bidi.dart';
import '../../l10n/generated/app_localizations.dart';

/// "1 USD = 13,000 SYP" as one piece that keeps its order in Arabic.
///
/// The sentence is numbers and Latin codes in both languages; left alone in
/// a right-to-left line the bidi algorithm moves its leading "1" to the far
/// end ("USD = 13,000 SYP 1").
String rateLine(
  AppLocalizations l10n,
  String code,
  String value,
  String base,
) =>
    isolateForRtl(l10n.localeName, l10n.rateDisplay(code, value, base));
