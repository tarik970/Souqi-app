import 'package:sqflite/sqflite.dart';

import '../../domain/models/invoice.dart';
import 'counter_repository.dart';

/// Reads and writes invoices.
///
/// Takes a [Database] (not a [DatabaseExecutor]) because saving an invoice
/// must run in one transaction: drawing the sequential invoice number, the
/// invoice row and all item rows either all land or none do.
class InvoiceRepository {
  InvoiceRepository(this._db);

  final Database _db;

  static const _counters = CounterRepository();

  /// Saves [draft] and returns it with its database id and invoice number.
  ///
  /// The number comes from the persisted counter inside the same transaction,
  /// so numbers are sequential, never reused and never shared by two saves.
  Future<Invoice> save(Invoice draft) async {
    if (draft.items.isEmpty) {
      throw ArgumentError.value(draft, 'draft', 'an invoice needs items');
    }
    return _db.transaction((txn) async {
      final invoiceNo = await _counters.next(txn, CounterRepository.invoiceNo);
      final id = await txn.insert('invoices', draft.toRow(invoiceNo: invoiceNo));
      final saved = <InvoiceItem>[];
      for (var i = 0; i < draft.items.length; i++) {
        final item = draft.items[i];
        final itemId = await txn.insert(
          'invoice_items',
          item.toRow(invoiceId: id, sortOrder: i),
        );
        saved.add(InvoiceItem(
          id: itemId,
          productId: item.productId,
          productName: item.productName,
          productCode: item.productCode,
          kind: item.kind,
          unitName: item.unitName,
          qtyThousandths: item.qtyThousandths,
          origUnitPriceMinor: item.origUnitPriceMinor,
          origCurrencyCode: item.origCurrencyCode,
          origRate: item.origRate,
          unitPriceMinor: item.unitPriceMinor,
          lineTotalMinor: item.lineTotalMinor,
        ));
      }
      return draft.copyWith(id: id, invoiceNo: invoiceNo, items: saved);
    });
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
