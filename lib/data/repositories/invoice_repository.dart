import 'package:sqflite/sqflite.dart';

import '../../domain/models/invoice.dart';
import '../../domain/models/product.dart';
import 'counter_repository.dart';
import 'product_repository.dart';

/// Reads and writes invoices.
///
/// Takes a [Database] (not a [DatabaseExecutor]) because saving an invoice
/// must run in one transaction: drawing the sequential invoice number, the
/// invoice row, all item rows and the products created or re-priced by the
/// sale either all land or none do.
class InvoiceRepository {
  InvoiceRepository(this._db);

  final Database _db;

  static const _counters = CounterRepository();

  /// Saves [draft] and returns it with its database id and invoice number.
  ///
  /// The number comes from the persisted counter inside the same transaction,
  /// so numbers are sequential, never reused and never shared by two saves.
  ///
  /// The same transaction also carries out each item's catalog instructions
  /// ("type-to-sell"): an item typed into the sale becomes a product — or is
  /// linked to the product that already has that name — and a price the
  /// seller changed becomes the product's saved price. Because it is one
  /// transaction, a sale that is never saved leaves the catalog untouched,
  /// and a save that fails leaves no half-created products behind.
  Future<Invoice> save(Invoice draft) async {
    if (draft.items.isEmpty) {
      throw ArgumentError.value(draft, 'draft', 'an invoice needs items');
    }
    return _db.transaction((txn) async {
      final products = ProductRepository(txn);
      final invoiceNo = await _counters.next(txn, CounterRepository.invoiceNo);
      final id = await txn.insert('invoices', draft.toRow(invoiceNo: invoiceNo));
      final saved = <InvoiceItem>[];
      for (var i = 0; i < draft.items.length; i++) {
        final item = draft.items[i];
        var productId = item.productId;
        if (productId == null && item.saveAsProduct) {
          productId = await _productForTypedItem(txn, products, item);
        } else if (productId != null && item.updateProductPrice) {
          await products.updatePriceFromSale(
            productId,
            priceMinor: item.origUnitPriceMinor,
            currencyCode: item.origCurrencyCode,
          );
        }
        final itemId = await txn.insert('invoice_items', {
          ...item.toRow(invoiceId: id, sortOrder: i),
          'product_id': productId,
        });
        saved.add(item.saved(id: itemId, productId: productId));
      }
      return draft.copyWith(id: id, invoiceNo: invoiceNo, items: saved);
    });
  }

  /// The product a typed item belongs to: the existing product with the same
  /// normalized name (the duplicate guard — "السكر" is "سكر"), otherwise a new
  /// one made from the line. No code is assigned; it can be added later from
  /// the Products screen.
  Future<int> _productForTypedItem(
    Transaction txn,
    ProductRepository products,
    InvoiceItem item,
  ) async {
    final existing = await products.findByName(item.productName);
    if (existing != null) {
      // Selling it again with "save" on means the shop wants it back.
      if (!existing.isActive) await products.setActive(existing.id!, true);
      if (item.updateProductPrice) {
        await products.updatePriceFromSale(
          existing.id!,
          priceMinor: item.origUnitPriceMinor,
          currencyCode: item.origCurrencyCode,
        );
      }
      return existing.id!;
    }

    // The unit may have been deleted while the item sat in the cart; a
    // dangling id would fail the foreign key and take the whole sale with it.
    var unitId = item.kind == ProductKind.goods ? item.unitId : null;
    if (unitId != null) {
      final rows = await txn.query(
        'units',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [unitId],
        limit: 1,
      );
      if (rows.isEmpty) unitId = null;
    }
    return products.insert(Product(
      name: item.productName,
      kind: item.kind,
      unitId: unitId,
      priceMinor: item.origUnitPriceMinor,
      currencyCode: item.origCurrencyCode,
    ));
  }

  Future<Invoice?> getById(int id) async {
    final rows =
        await _db.query('invoices', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return Invoice.fromMap(rows.first, items: await _itemsOf(id));
  }

  Future<Invoice?> getByNumber(int invoiceNo) async {
    final rows = await _db.query(
      'invoices',
      where: 'invoice_no = ?',
      whereArgs: [invoiceNo],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Invoice.fromMap(
      rows.first,
      items: await _itemsOf(rows.first['id'] as int),
    );
  }

  /// The number the next saved invoice will get (for a preview on the sale
  /// screen). Does not consume it.
  Future<int> peekNextInvoiceNo() async {
    final rows = await _db.query(
      'counters',
      columns: ['value'],
      where: 'name = ?',
      whereArgs: [CounterRepository.invoiceNo],
      limit: 1,
    );
    return rows.isEmpty ? 1 : (rows.first['value'] as int) + 1;
  }

  Future<List<InvoiceItem>> _itemsOf(int invoiceId) async {
    final rows = await _db.query(
      'invoice_items',
      where: 'invoice_id = ?',
      whereArgs: [invoiceId],
      orderBy: 'sort_order ASC, id ASC',
    );
    return rows.map(InvoiceItem.fromMap).toList();
  }
}
