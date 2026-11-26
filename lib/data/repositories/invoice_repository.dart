import 'package:sqflite/sqflite.dart';

import '../../core/security/code_cipher.dart';
import '../../domain/models/debt.dart';
import '../../domain/models/invoice.dart';
import '../../domain/models/product.dart';
import 'counter_repository.dart';
import 'customer_repository.dart';
import 'debt_repository.dart';
import 'product_repository.dart';
import 'voucher_repository.dart';

/// Reads and writes invoices.
///
/// Takes a [Database] (not a [DatabaseExecutor]) because saving an invoice
/// must run in one transaction: drawing the sequential invoice number, the
/// invoice row, all item rows, the products created or re-priced by the
/// sale and the renewal dates of the attached account either all land or
/// none do.
class InvoiceRepository {
  InvoiceRepository(this._db, {this.codeCipher});

  final Database _db;

  /// Set when prepaid card codes are sold from stock (the
  /// `voucherStockEnabled` flag): saving an invoice then takes the codes of
  /// its card lines in the same transaction. Null = the feature is off and
  /// such a product sells like any other service.
  final CodeCipher? codeCipher;

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
  ///
  /// [payment] is how the sale was paid (the payment sheet of the debt
  /// ledger). The part of the total that was not paid goes onto the
  /// customer's account as a DEBT entry in this same transaction, and the
  /// invoice row keeps what it will print: paid, from credit, the balance
  /// before and after. A sale that may not go on credit — no customer, or a
  /// credit limit nobody overrode — throws here and nothing at all is saved.
  /// Null = the debt ledger is off: the sale is simply paid and the ledger
  /// is not touched.
  Future<Invoice> save(Invoice draft, {SalePayment? payment}) async {
    if (draft.items.isEmpty) {
      throw ArgumentError.value(draft, 'draft', 'an invoice needs items');
    }
    return _db.transaction((txn) async {
      final products = ProductRepository(txn);
      // Before anything is written: the checks that can refuse the sale.
      final ledger = payment == null
          ? null
          : await DebtRepository.planSale(txn, draft: draft, payment: payment);
      if (payment != null) {
        draft = draft.copyWith(
          paidMinor: payment.paidMinor,
          creditUsedMinor: payment.creditUsedMinor,
          prevBalanceBaseMinor: ledger?.prevBalanceBaseMinor,
          newBalanceBaseMinor: ledger?.newBalanceBaseMinor,
        );
      }
      final invoiceNo = await _counters.next(txn, CounterRepository.invoiceNo);
      final id = await txn.insert('invoices', draft.toRow(invoiceNo: invoiceNo));
      if (ledger != null) {
        await DebtRepository.postSale(
          txn,
          plan: ledger,
          draft: draft,
          invoiceId: id,
          invoiceNo: invoiceNo,
        );
      }
      // A renewal moves the account's dates in this same transaction: the
      // invoice and the new due date land together, or neither does.
      if (draft.renewsAccount) {
        await CustomerRepository(txn)
            .recordRenewal(draft.accountId!, draft.createdAt);
      }
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
        // A product sold from code stock: its codes are taken here, so the
        // invoice and the cards it hands out exist together or not at all.
        // Two sales can never be given the same card — transactions run one
        // at a time — and a sale that cannot get all its cards throws and
        // is rolled back whole.
        final cipher = codeCipher;
        if (cipher != null && productId != null) {
          await VoucherRepository.sellForItem(
            txn,
            cipher: cipher,
            invoice: draft,
            invoiceId: id,
            invoiceNo: invoiceNo,
            item: item,
            itemId: itemId,
            productId: productId,
          );
        }
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
    final barcode = item.newProductBarcode;
    final existing = await products.findByName(item.productName);
    if (existing != null) {
      // Selling it again with "save" on means the shop wants it back.
      if (!existing.isActive) await products.setActive(existing.id!, true);
      // Started from its barcode: the product learns it (if it had none).
      if (barcode != null) await products.adoptBarcode(existing.id!, barcode);
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
      // One barcode, one product: never a second product on the same one.
      barcode: barcode != null && !await products.isBarcodeTaken(barcode)
          ? barcode
          : null,
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
