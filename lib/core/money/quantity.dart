/// Quantity math. Quantities are stored as INTEGER thousandths
/// (500 = 0.5 kg). Line total = round(price * qty / 1000), half-up.
library;

import 'rounding.dart';

const int quantityScale = 1000;

/// Line total in minor units of the price's OWN currency.
///
/// Only for a line whose price currency is already the invoice currency. When
/// the two differ, use `convertLineTotalMinor` in exchange.dart, which folds
/// the quantity and the rate into one rounding step; converting the unit
/// price first and multiplying here would scale the rounding error by the
/// quantity.
int lineTotalMinor({required int unitPriceMinor, required int qtyThousandths}) {
  if (qtyThousandths < 0) {
    throw ArgumentError.value(qtyThousandths, 'qtyThousandths', 'must be >= 0');
  }
  return divRoundHalfUp(
    BigInt.from(unitPriceMinor) * BigInt.from(qtyThousandths),
    BigInt.from(quantityScale),
  );
}

/// Percent discount amount in minor units. [basisPoints] is the percentage
/// scaled by 100 (1000 = 10.00%). Rounded half-up once.
int percentDiscountMinor({required int subtotalMinor, required int basisPoints}) {
  if (basisPoints < 0 || basisPoints > 10000) {
    throw ArgumentError.value(basisPoints, 'basisPoints', 'must be 0..10000');
  }
  return divRoundHalfUp(
    BigInt.from(subtotalMinor) * BigInt.from(basisPoints),
    BigInt.from(10000),
  );
}
