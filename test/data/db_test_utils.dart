import 'dart:typed_data';

import 'package:souqi/core/utils/normalize.dart';
import 'package:souqi/data/db/app_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Opens a fresh in-memory database with the full v1 schema and seeds.
Future<AppDatabase> openTestDb() {
  return AppDatabase.open(
    factory: databaseFactoryFfi,
    path: inMemoryDatabasePath,
  );
}

Future<int> insertUnit(DatabaseExecutor db) {
  return db.insert('units', {
    'name_ar': 'كغ',
    'name_en': 'kg',
    'is_preset': 0,
    'is_active': 1,
    'sort_order': 99,
  });
}

Future<int> insertProduct(
  DatabaseExecutor db, {
  String name = 'Sugar',
  String? code,
  String kind = 'GOODS',
  int? unitId,
  String currency = 'SYP',
  int soldFromCodeStock = 0,
}) {
  final now = DateTime.now().millisecondsSinceEpoch;
  return db.insert('products', {
    'name': name,
    'name_norm': name.toLowerCase(),
    'code': code,
    'kind': kind,
    'unit_id': unitId,
    'price_minor': 1000,
    'currency_code': currency,
    'sold_from_code_stock': soldFromCodeStock,
    'created_at': now,
    'updated_at': now,
  });
}

Future<int> insertCustomer(DatabaseExecutor db, {String name = 'Ahmad'}) {
  return db.insert('customers', {
    'name': name,
    'name_norm': name.toLowerCase(),
    'created_at': DateTime.now().millisecondsSinceEpoch,
  });
}

/// An invoice row. Defaults to a 1,000-minor SYP sale; the named arguments
/// cover the cases the archive and statistics tests need (another currency
/// with its own rate snapshot, a discount, customer snapshots).
Future<int> insertInvoice(
  DatabaseExecutor db, {
  required int invoiceNo,
  DateTime? createdAt,
  String currency = 'SYP',
  int rateNum = 1,
  int rateDen = 1,
  int subtotalMinor = 1000,
  int discountMinor = 0,
  int? totalMinor,
  int? totalBaseMinor,
  String? customerName,
  String? customerPhone,
  String? accountNumber,
}) {
  final total = totalMinor ?? (subtotalMinor - discountMinor);
  return db.insert('invoices', {
    'invoice_no': invoiceNo,
    'created_at':
        (createdAt ?? DateTime.now()).toUtc().millisecondsSinceEpoch,
    'currency_code': currency,
    'base_currency_code': 'SYP',
    'rate_num': rateNum,
    'rate_den': rateDen,
    'subtotal_minor': subtotalMinor,
    'discount_type': discountMinor > 0 ? 'AMOUNT' : null,
    'discount_value': discountMinor > 0 ? discountMinor : null,
    'discount_minor': discountMinor,
    'total_minor': total,
    'total_base_minor': totalBaseMinor ?? total,
    'customer_name': customerName,
    'customer_name_norm':
        customerName == null ? null : normalizeName(customerName),
    'customer_phone': customerPhone,
    'customer_phone_norm':
        customerPhone == null ? null : normalizePhone(customerPhone),
    'account_number': accountNumber,
    'account_number_norm':
        accountNumber == null ? null : normalizeCode(accountNumber),
  });
}

Future<int> insertInvoiceItem(
  DatabaseExecutor db, {
  required int invoiceId,
  int? productId,
  String name = 'Sugar',
  int qtyThousandths = 1000,
  int unitPriceMinor = 1000,
  int? lineTotalMinor,
  String currency = 'SYP',
  int rateNum = 1,
  int rateDen = 1,
  int sortOrder = 0,
}) {
  return db.insert('invoice_items', {
    'invoice_id': invoiceId,
    'product_id': productId,
    'sort_order': sortOrder,
    'product_name': name,
    'product_name_norm': normalizeName(name),
    'kind': 'GOODS',
    'qty_thousandths': qtyThousandths,
    'orig_unit_price_minor': unitPriceMinor,
    'orig_currency_code': currency,
    'orig_rate_num': rateNum,
    'orig_rate_den': rateDen,
    'unit_price_minor': unitPriceMinor,
    'line_total_minor': lineTotalMinor ??
        (unitPriceMinor * qtyThousandths) ~/ 1000,
  });
}

Future<int> insertVoucherBatch(DatabaseExecutor db, {required int productId}) {
  return db.insert('voucher_batches', {
    'product_id': productId,
    'created_at': DateTime.now().millisecondsSinceEpoch,
    'code_count': 10,
  });
}

Future<int> insertVoucherCode(
  DatabaseExecutor db, {
  required int productId,
  required int batchId,
  required String codeHash,
}) {
  return db.insert('voucher_codes', {
    'product_id': productId,
    'batch_id': batchId,
    'code_cipher': Uint8List.fromList([1, 2, 3]),
    'code_hash': codeHash,
    'created_at': DateTime.now().millisecondsSinceEpoch,
  });
}
