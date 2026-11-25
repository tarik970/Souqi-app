/// How a prepaid card code is written for people: grouped in fours on paper,
/// masked on screen. Pure text — unit-tested without widgets.
library;

import 'normalize.dart';

/// The bullet a hidden character is shown as.
const String codeMaskBullet = '•';

/// What is shown when there is nothing of the code to show at all: a code
/// too short to give four characters away, or one that cannot be decrypted
/// on this device.
const String codeFullyMasked = '•••• ••••';

/// The code cut into groups of [size] characters, the last group taking what
/// is left: "1234567890123456" → [1234, 5678, 9012, 3456].
///
/// Spaces and dashes the code was typed with are dropped first, so a card
/// entered as "1234-5678-9012-3456" and one entered without dashes print the
/// same way.
List<String> codeGroups(String code, {int size = 4}) {
  final plain = stripCodeSeparators(code);
  return [
    for (var i = 0; i < plain.length; i += size)
      plain.substring(i, i + size > plain.length ? plain.length : i + size),
  ];
}

/// "1234 5678 9012 3456".
String groupCode(String code) => codeGroups(code).join(' ');

/// The part of a code that may be shown without the PIN: its last four
/// characters — or the last two of a short code, or nothing of a very short
/// one, so that what is shown is never most of the secret.
String codeTail(String code) {
  final plain = stripCodeSeparators(code);
  final shown = plain.length > 8
      ? 4
      : plain.length > 4
          ? 2
          : 0;
  return plain.substring(plain.length - shown);
}

/// The masked form used everywhere on screen: "•••• •••• 3456".
///
/// Always two masked groups, whatever the real length — the mask does not
/// give the length of the code away either.
String maskCode(String code) => maskWithTail(codeTail(code));

/// [maskCode] for a tail that was computed earlier.
String maskWithTail(String tail) =>
    tail.isEmpty ? codeFullyMasked : '$codeFullyMasked $tail';
