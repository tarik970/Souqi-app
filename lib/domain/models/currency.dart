import '../../core/money/exchange.dart';

class Currency {
  const Currency({
    required this.code,
    required this.nameAr,
    required this.nameEn,
    this.symbol = '',
    required this.decimalPlaces,
    required this.rate,
    this.rateUpdatedAt,
    this.isActive = true,
    this.sortOrder = 0,
  });

  final String code;
  final String nameAr;
  final String nameEn;
  final String symbol;
  final int decimalPlaces;

  /// Exact rate to the base currency: rate base units per 1 unit of this.
  final RateFraction rate;

  /// Null means the rate was never entered by the user and must be set
  /// before this currency is used in a sale.
  final DateTime? rateUpdatedAt;
  final bool isActive;
  final int sortOrder;

  String nameFor(String languageCode) =>
      languageCode == 'ar' ? nameAr : nameEn;

  static Currency fromMap(Map<String, Object?> map) {
    final updatedAt = map['rate_updated_at'] as int?;
    return Currency(
      code: map['code'] as String,
      nameAr: map['name_ar'] as String,
      nameEn: map['name_en'] as String,
      symbol: map['symbol'] as String,
      decimalPlaces: map['decimal_places'] as int,
      rate: RateFraction(map['rate_num'] as int, map['rate_den'] as int),
      rateUpdatedAt: updatedAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(updatedAt, isUtc: true),
      isActive: map['is_active'] == 1,
      sortOrder: map['sort_order'] as int,
    );
  }

  Map<String, Object?> toMap() => {
        'code': code,
        'name_ar': nameAr,
        'name_en': nameEn,
        'symbol': symbol,
        'decimal_places': decimalPlaces,
        'rate_num': rate.numerator,
        'rate_den': rate.denominator,
        'rate_updated_at': rateUpdatedAt?.millisecondsSinceEpoch,
        'is_active': isActive ? 1 : 0,
        'sort_order': sortOrder,
      };
}
