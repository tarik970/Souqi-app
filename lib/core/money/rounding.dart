/// Integer division with half-up rounding (half away from zero for negative
/// values). This is the single rounding step used by all money math.
library;

/// Returns `numerator / denominator` rounded half-up.
/// [denominator] must be positive.
int divRoundHalfUp(BigInt numerator, BigInt denominator) {
  if (denominator <= BigInt.zero) {
    throw ArgumentError.value(denominator, 'denominator', 'must be > 0');
  }
  final two = BigInt.two;
  final BigInt q;
  if (numerator >= BigInt.zero) {
    q = (two * numerator + denominator) ~/ (two * denominator);
  } else {
    q = -((two * (-numerator) + denominator) ~/ (two * denominator));
  }
  if (!q.isValidInt) {
    throw ArgumentError('result does not fit in a 64-bit integer: $q');
  }
  return q.toInt();
}
