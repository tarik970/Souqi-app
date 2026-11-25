/// Prepaid card codes ("vouchers"): batches, stock counts and the views of a
/// code the screens are allowed to hold.
///
/// Nothing in this file carries a code in the clear except [InvoiceCode.code]
/// — the one value built for the printer — and it never has a `toString` that
/// would put it into a log.
library;

import 'product.dart';

enum VoucherStatus {
  available('AVAILABLE'),
  sold('SOLD'),
  voided('VOID');

  const VoucherStatus(this.db);

  final String db;

  static VoucherStatus fromDb(String value) =>
      values.firstWhere((s) => s.db == value);
}

/// An expiry is a DAY: the card can be sold up to and including it. It is
/// stored as the local midnight that ENDS that day (the start of the next),
/// so "still sellable" is simply `now < expiry_at`.
DateTime expiryFromDate(DateTime lastValidDay) =>
    DateTime(lastValidDay.year, lastValidDay.month, lastValidDay.day + 1);

/// The last day a card with this stored expiry can be sold on.
DateTime expiryLastDay(DateTime expiryAt) {
  final local = expiryAt.toLocal();
  return DateTime(local.year, local.month, local.day - 1);
}

/// The stock of one "sold from code stock" product.
class ProductStock {
  const ProductStock({
    required this.product,
    required this.available,
    required this.expired,
    required this.sold,
    required this.voided,
  });

  final Product product;

  /// Can be sold right now: AVAILABLE and not past expiry.
  final int available;

  /// Still marked AVAILABLE but past expiry — never sold automatically.
  final int expired;
  final int sold;
  final int voided;

  bool get isOut => available == 0;

  /// At or under the product's threshold. A product without a threshold is
  /// only ever "out", never "low".
  bool get isLow {
    final threshold = product.lowStockThreshold;
    return threshold != null && available <= threshold;
  }

  /// Shown in the warnings at the top of the stock screen and counted by the
  /// home screen badge.
  bool get needsAttention => product.isActive && (isOut || isLow);
}

/// One loaded batch with what is left of it.
class VoucherBatch {
  const VoucherBatch({
    required this.id,
    required this.productId,
    required this.createdAt,
    required this.codeCount,
    this.costPerCardMinor,
    this.costCurrencyCode,
    this.expiryAt,
    this.note,
    this.available = 0,
    this.expired = 0,
    this.sold = 0,
    this.voided = 0,
  });

  final int id;
  final int productId;
  final DateTime createdAt;

  /// How many codes the batch was loaded with.
  final int codeCount;
  final int? costPerCardMinor;
  final String? costCurrencyCode;
  final DateTime? expiryAt;
  final String? note;

  final int available;
  final int expired;
  final int sold;
  final int voided;

  /// Nothing of it was ever sold or voided after a sale: it can be deleted.
  bool get isUnsold => sold == 0;
}

/// A code as a screen may show it: masked, with its status and — once sold —
/// the snapshots of the sale. The secret itself is not in here.
class VoucherCodeView {
  const VoucherCodeView({
    required this.id,
    required this.productId,
    required this.productName,
    required this.batchId,
    required this.masked,
    required this.unreadable,
    this.serial,
    this.expiryAt,
    required this.status,
    this.statusChangedAt,
    this.statusNote,
    this.soldAt,
    this.invoiceId,
    this.soldInvoiceNo,
    this.soldCustomerName,
    this.soldAccountNumber,
  });

  final int id;
  final int productId;
  final String productName;
  final int batchId;

  /// "•••• •••• 3456".
  final String masked;

  /// The stored bytes cannot be decrypted on this device.
  final bool unreadable;
  final String? serial;
  final DateTime? expiryAt;
  final VoucherStatus status;
  final DateTime? statusChangedAt;

  /// The reason given when it was voided or returned to stock.
  final String? statusNote;
  final DateTime? soldAt;

  /// The live invoice, while it still exists in the archive.
  final int? invoiceId;

  /// The invoice number, kept after the invoice itself is deleted.
  final int? soldInvoiceNo;
  final String? soldCustomerName;
  final String? soldAccountNumber;

  bool isExpired(DateTime now) =>
      status == VoucherStatus.available &&
      expiryAt != null &&
      !now.isBefore(expiryAt!);
}

/// A sold code on its way to the paper (or, masked, to the screen).
class InvoiceCode {
  const InvoiceCode({
    required this.id,
    this.invoiceItemId,
    required this.productName,
    required this.code,
    required this.masked,
    this.unreadable = false,
    this.serial,
    this.expiryAt,
  });

  final int id;
  final int? invoiceItemId;
  final String productName;

  /// The code itself. Null when this value was built for the screen, or when
  /// the stored bytes cannot be decrypted on this device.
  final String? code;
  final String masked;

  /// The stored bytes cannot be decrypted on this device: the paper says so
  /// instead of printing nothing where the customer expects a code.
  final bool unreadable;
  final String? serial;
  final DateTime? expiryAt;

  /// The same card with the secret dropped — what the on-screen preview gets.
  InvoiceCode get hidden => InvoiceCode(
        id: id,
        invoiceItemId: invoiceItemId,
        productName: productName,
        code: null,
        masked: masked,
        unreadable: unreadable,
        serial: serial,
        expiryAt: expiryAt,
      );
}

/// What loading a batch did, for the "120 added, 3 duplicates skipped,
/// 1 empty line" report.
class ImportReport {
  const ImportReport({
    required this.added,
    this.duplicatesInBatch = 0,
    this.duplicatesExisting = 0,
    this.emptyLines = 0,
    this.invalidLines = 0,
    this.batchId,
  });

  final int added;

  /// The same code twice in the text being loaded.
  final int duplicatesInBatch;

  /// Codes this product already has, in any status.
  final int duplicatesExisting;
  final int emptyLines;
  final int invalidLines;

  /// Null when nothing was added (and so no batch was created).
  final int? batchId;

  int get duplicates => duplicatesInBatch + duplicatesExisting;
}

/// Not enough sellable codes for a line of the sale. Thrown inside the
/// invoice transaction, which is then rolled back: nothing is sold.
class InsufficientCodeStockException implements Exception {
  const InsufficientCodeStockException({
    required this.productName,
    required this.requested,
    required this.available,
  });

  final String productName;
  final int requested;
  final int available;

  @override
  String toString() => 'InsufficientCodeStockException: "$productName" '
      'needs $requested, has $available';
}

/// A card product was put on the invoice with a quantity that is not a whole
/// number of cards.
class CodeQuantityException implements Exception {
  const CodeQuantityException(this.productName);

  final String productName;

  @override
  String toString() =>
      'CodeQuantityException: "$productName" is sold in whole cards';
}

/// One row of the "was this card sold, and to whom?" answer.
typedef CodeLookupResult = VoucherCodeView;

/// One sensitive action, as the audit log screen lists it.
class AuditEntry {
  const AuditEntry({
    required this.id,
    required this.createdAt,
    required this.action,
    this.productId,
    this.productName,
    this.details = const {},
  });

  final int id;
  final DateTime createdAt;

  /// One of [AuditAction]'s `db` values; kept as text so a row written by a
  /// newer version of the app still lists.
  final String action;
  final int? productId;
  final String? productName;

  /// Small facts about the action (a count, an invoice number, the reason).
  /// Never a code.
  final Map<String, Object?> details;
}

/// The actions the audit log records.
enum AuditAction {
  codeImport('CODE_IMPORT'),
  codeReveal('CODE_REVEAL'),
  codeLookup('CODE_LOOKUP'),
  codeVoid('CODE_VOID'),
  codeRestore('CODE_RESTORE'),
  codeExport('CODE_EXPORT'),
  codeExpiryChange('CODE_EXPIRY_CHANGE'),
  batchDelete('BATCH_DELETE'),
  invoiceReprint('INVOICE_REPRINT'),
  pinSet('PIN_SET'),
  pinChange('PIN_CHANGE'),
  pinRemove('PIN_REMOVE'),

  /// A recovery code made for the current PIN (which did not have one).
  recoveryCodeCreate('RECOVERY_CODE_CREATE'),

  /// A forgotten PIN replaced with the recovery code.
  pinRecover('PIN_RECOVER'),

  /// A forgotten PIN replaced with a developer-signed reset code (phase 5b).
  pinResetSigned('PIN_RESET_SIGNED');

  const AuditAction(this.db);

  final String db;

  static AuditAction? fromDb(String value) {
    for (final action in values) {
      if (action.db == value) return action;
    }
    return null;
  }
}
