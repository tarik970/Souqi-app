/// Keeping numbers readable inside right-to-left text.
library;

/// LEFT-TO-RIGHT ISOLATE and POP DIRECTIONAL ISOLATE. Built from their code
/// points on purpose: literal invisible characters in source are a trap.
final String _lri = String.fromCharCode(0x2066);
final String _pdi = String.fromCharCode(0x2069);

/// Wraps [text] so it keeps its typed order when it sits inside Arabic text.
///
/// A phone or card number written in groups ("0944 123 456", "0011-2233 44")
/// is laid out right to left by the bidi algorithm next to Arabic words and
/// reads backwards. Isolating it pins the order in both directions. The two
/// marks are invisible and take no width.
String ltrIsolate(String text) => text.isEmpty ? text : '$_lri$text$_pdi';

/// [ltrIsolate] where it is needed — in a right-to-left sentence — and the
/// text as it is elsewhere. [localeName] is the language of the sentence
/// the text goes into (`AppLocalizations.localeName`).
String isolateForRtl(String localeName, String text) =>
    localeName.startsWith('ar') ? ltrIsolate(text) : text;
