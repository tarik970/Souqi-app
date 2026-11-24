/// Human-readable file sizes, for the storage figures in Settings → About.
library;

import '../money/money_format.dart';

enum ByteUnit { bytes, kilobytes, megabytes }

/// A size split into the number to show and the unit it is in, so the words
/// ("KB", "كيلوبايت") stay in the localizations and out of this file.
class ByteSize {
  const ByteSize({required this.value, required this.unit});

  /// Already localized: grouped, with the locale's digits and separator.
  final String value;
  final ByteUnit unit;
}

const int _kilobyte = 1024;
const int _megabyte = 1024 * 1024;

/// Formats [bytes] in the largest unit that leaves a number below 1024,
/// with one decimal place while the number is small enough for it to mean
/// something ("2.4 MB", "640 KB", "812 B").
ByteSize formatByteSize(int bytes, {required String locale}) {
  if (bytes < _kilobyte) {
    return ByteSize(
      value: formatMinor(bytes, decimals: 0, locale: locale),
      unit: ByteUnit.bytes,
    );
  }
  final divisor = bytes < _megabyte ? _kilobyte : _megabyte;
  final unit = bytes < _megabyte ? ByteUnit.kilobytes : ByteUnit.megabytes;
  // Tenths of the unit, rounded: 1,588,000 B → 15 tenths of a MB → "1.5".
  final tenths = (bytes * 10 + divisor ~/ 2) ~/ divisor;
  final decimals = tenths >= 1000 ? 0 : 1;
  return ByteSize(
    value: formatMinor(
      decimals == 0 ? (tenths + 5) ~/ 10 : tenths,
      decimals: decimals,
      locale: locale,
    ),
    unit: unit,
  );
}
