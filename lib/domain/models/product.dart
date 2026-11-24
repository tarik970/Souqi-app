enum ProductKind {
  goods('GOODS'),
  service('SERVICE');

  const ProductKind(this.db);

  final String db;

  static ProductKind fromDb(String value) =>
      values.firstWhere((k) => k.db == value);
}

class Product {
  const Product({
    this.id,
    required this.name,
    this.code,
    this.barcode,
    required this.kind,
    this.unitId,
    required this.priceMinor,
    required this.currencyCode,
    this.isFavorite = false,
    this.isActive = true,
    this.requiresAccount = false,
    this.soldFromCodeStock = false,
    this.lowStockThreshold,
  });

  final int? id;
  final String name;
  final String? code;
  final String? barcode;
  final ProductKind kind;
  final int? unitId; // GOODS only
  final int priceMinor;
  final String currencyCode;
  final bool isFavorite;
  final bool isActive;
  final bool requiresAccount; // SERVICE only
  final bool soldFromCodeStock; // SERVICE only
  final int? lowStockThreshold;

  Product copyWith({
    int? id,
    String? name,
    String? Function()? code,
    String? Function()? barcode,
    ProductKind? kind,
    int? Function()? unitId,
    int? priceMinor,
    String? currencyCode,
    bool? isFavorite,
    bool? isActive,
    bool? requiresAccount,
    bool? soldFromCodeStock,
    int? Function()? lowStockThreshold,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      code: code != null ? code() : this.code,
      barcode: barcode != null ? barcode() : this.barcode,
      kind: kind ?? this.kind,
      unitId: unitId != null ? unitId() : this.unitId,
      priceMinor: priceMinor ?? this.priceMinor,
      currencyCode: currencyCode ?? this.currencyCode,
      isFavorite: isFavorite ?? this.isFavorite,
      isActive: isActive ?? this.isActive,
      requiresAccount: requiresAccount ?? this.requiresAccount,
      soldFromCodeStock: soldFromCodeStock ?? this.soldFromCodeStock,
      lowStockThreshold: lowStockThreshold != null
          ? lowStockThreshold()
          : this.lowStockThreshold,
    );
  }

  static Product fromMap(Map<String, Object?> map) {
    return Product(
      id: map['id'] as int,
      name: map['name'] as String,
      code: map['code'] as String?,
      barcode: map['barcode'] as String?,
      kind: ProductKind.fromDb(map['kind'] as String),
      unitId: map['unit_id'] as int?,
      priceMinor: map['price_minor'] as int,
      currencyCode: map['currency_code'] as String,
      isFavorite: map['is_favorite'] == 1,
      isActive: map['is_active'] == 1,
      requiresAccount: map['requires_account'] == 1,
      soldFromCodeStock: map['sold_from_code_stock'] == 1,
      lowStockThreshold: map['low_stock_threshold'] as int?,
    );
  }
}
