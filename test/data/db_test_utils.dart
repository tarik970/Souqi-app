import 'dart:typed_data';

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

Future<int> insertInvoice(DatabaseExecutor db, {required int invoiceNo}) {
  return db.insert('invoices', {
    'invoice_no': invoiceNo,
    'created_at': DateTime.now().millisecondsSinceEpoch,
    'currency_code': 'SYP',
    'base_currency_code': 'SYP',
    'rate_num': 1,
    'rate_den': 1,
    'subtotal_minor': 1000,
    'total_minor': 1000,
    'total_base_minor': 1000,
  });
}

Future<int> insertInvoiceItem(DatabaseExecutor db,
    {required int invoiceId, int? productId}) {
  return db.insert('invoice_items', {
    'invoice_id': invoiceId,
    'product_id': productId,
    'product_name': 'Sugar',
    'kind': 'GOODS',
    'qty_thousandths': 1000,
    'orig_unit_price_minor': 1000,
    'orig_currency_code': 'SYP',
    'orig_rate_num': 1,
    'orig_rate_den': 1,
    'unit_price_minor': 1000,
    'line_total_minor': 1000,
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
