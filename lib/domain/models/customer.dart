/// Customers and their cards / accounts (internet cards, ADSL lines,
/// subscriptions…). Shared by the renewal flow and, later, the debt ledger.
library;

import '../../core/utils/due_dates.dart';
import 'invoice.dart';
import 'product.dart';

DateTime? _dateOrNull(Object? epochMs) => epochMs == null
    ? null
    : DateTime.fromMillisecondsSinceEpoch(epochMs as int, isUtc: true);

String? _blankToNull(String? text) {
  final trimmed = text?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}

class Customer {
  const Customer({
    this.id,
    required this.name,
    this.phone,
    this.notes,
    this.isActive = true,
    this.createdAt,
    this.creditLimitBaseMinor,
    this.defaultDueDays,
  });

  final int? id;
  final String name;

  /// Exactly as typed ("0944 123 456"); the digits-only search form lives in
  /// the `phone_norm` column.
  final String? phone;
  final String? notes;

  /// Customers are never deleted, only deactivated.
  final bool isActive;
  final DateTime? createdAt;

  /// The most this customer may owe, in base-currency minor units. Null = no
  /// limit. A sale that would go over it warns and needs an override.
  final int? creditLimitBaseMinor;

  /// Days this customer is given to pay a new debt. Null = the shop's
  /// default (a setting, 30 unless changed).
  final int? defaultDueDays;

  bool get hasPhone => (phone ?? '').trim().isNotEmpty;

  Customer copyWith({
    int? id,
    String? name,
    String? Function()? phone,
    String? Function()? notes,
    bool? isActive,
    int? Function()? creditLimitBaseMinor,
    int? Function()? defaultDueDays,
  }) =>
      Customer(
        id: id ?? this.id,
        name: name ?? this.name,
        phone: phone != null ? phone() : this.phone,
        notes: notes != null ? notes() : this.notes,
        isActive: isActive ?? this.isActive,
        createdAt: createdAt,
        creditLimitBaseMinor: creditLimitBaseMinor != null
            ? creditLimitBaseMinor()
            : this.creditLimitBaseMinor,
        defaultDueDays:
            defaultDueDays != null ? defaultDueDays() : this.defaultDueDays,
      );

  /// [prefix] is for joined queries that alias the columns ("c_name").
  static Customer fromMap(Map<String, Object?> map, {String prefix = ''}) =>
      Customer(
        id: map['${prefix}id'] as int?,
        name: map['${prefix}name'] as String,
        phone: _blankToNull(map['${prefix}phone'] as String?),
        notes: _blankToNull(map['${prefix}notes'] as String?),
        isActive: map['${prefix}is_active'] != 0,
        createdAt: _dateOrNull(map['${prefix}created_at']),
        creditLimitBaseMinor: map['${prefix}credit_limit_base_minor'] as int?,
        defaultDueDays: map['${prefix}default_due_days'] as int?,
      );
}

/// One card / account of a customer.
class CustomerAccount {
  const CustomerAccount({
    this.id,
    required this.customerId,
    required this.accountNumber,
    this.label,
    this.provider,
    this.defaultProductId,
    this.renewalDays,
    this.lastRenewalAt,
    this.nextDueAt,
    this.notes,
    this.isActive = true,
    this.createdAt,
  });

  final int? id;
  final int customerId;

  /// Text, exactly as typed: leading zeros and letters are part of it.
  final String accountNumber;

  /// What kind of account it is ("internet card", "ADSL line").
  final String? label;
  final String? provider;

  /// The SERVICE/CARD product a renewal starts with.
  final int? defaultProductId;

  /// Days one renewal lasts. Null = no schedule: the account never shows up
  /// on the due list by itself.
  final int? renewalDays;
  final DateTime? lastRenewalAt;

  /// The DAY the account is next due, as the local midnight that starts it
  /// (see `due_dates.dart`).
  final DateTime? nextDueAt;
  final String? notes;
  final bool isActive;
  final DateTime? createdAt;

  /// Its place on the due list as seen at [now]; null without a due date.
  DueStatus? dueStatus({required DateTime now, required int soonDays}) =>
      dueStatusOf(nextDueAt, now: now, soonDays: soonDays);

  CustomerAccount copyWith({
    int? id,
    int? customerId,
    String? accountNumber,
    String? Function()? label,
    String? Function()? provider,
    int? Function()? defaultProductId,
    int? Function()? renewalDays,
    DateTime? Function()? lastRenewalAt,
    DateTime? Function()? nextDueAt,
    String? Function()? notes,
    bool? isActive,
  }) =>
      CustomerAccount(
        id: id ?? this.id,
        customerId: customerId ?? this.customerId,
        accountNumber: accountNumber ?? this.accountNumber,
        label: label != null ? label() : this.label,
        provider: provider != null ? provider() : this.provider,
        defaultProductId: defaultProductId != null
            ? defaultProductId()
            : this.defaultProductId,
        renewalDays: renewalDays != null ? renewalDays() : this.renewalDays,
        lastRenewalAt:
            lastRenewalAt != null ? lastRenewalAt() : this.lastRenewalAt,
        nextDueAt: nextDueAt != null ? nextDueAt() : this.nextDueAt,
        notes: notes != null ? notes() : this.notes,
        isActive: isActive ?? this.isActive,
        createdAt: createdAt,
      );

  /// [prefix] is for joined queries that alias the columns ("a_id").
  static CustomerAccount fromMap(
    Map<String, Object?> map, {
    String prefix = '',
  }) =>
      CustomerAccount(
        id: map['${prefix}id'] as int?,
        customerId: map['${prefix}customer_id'] as int,
        accountNumber: map['${prefix}account_number'] as String,
        label: _blankToNull(map['${prefix}label'] as String?),
        provider: _blankToNull(map['${prefix}provider'] as String?),
        defaultProductId: map['${prefix}default_product_id'] as int?,
        renewalDays: map['${prefix}renewal_days'] as int?,
        lastRenewalAt: _dateOrNull(map['${prefix}last_renewal_at']),
        nextDueAt: _dateOrNull(map['${prefix}next_due_at']),
        notes: _blankToNull(map['${prefix}notes'] as String?),
        isActive: map['${prefix}is_active'] != 0,
        createdAt: _dateOrNull(map['${prefix}created_at']),
      );
}

/// One row of the quick search and of the due list: a customer, and one of
/// their accounts when the row is about an account.
///
/// A customer with three cards is three rows; a customer with none is one row
/// with [account] null.
class CustomerHit {
  const CustomerHit({
    required this.customer,
    this.account,
    this.packageName,
    this.packageActive = true,
  });

  final Customer customer;
  final CustomerAccount? account;

  /// Name of the account's default package, when it has one.
  final String? packageName;

  /// False when that product has been deactivated since.
  final bool packageActive;

  /// What attaching this row to a sale records.
  SaleCustomer get forSale => SaleCustomer(
        customerId: customer.id!,
        name: customer.name,
        phone: customer.phone,
        accountId: account?.id,
        accountNumber: account?.accountNumber,
        accountProvider: account?.provider,
        defaultProductId: account?.defaultProductId,
      );
}

/// The customer (and account) attached to the sale in progress. The invoice
/// stores these as SNAPSHOTS next to the nullable links to the live records.
class SaleCustomer {
  const SaleCustomer({
    required this.customerId,
    required this.name,
    this.phone,
    this.accountId,
    this.accountNumber,
    this.accountProvider,
    this.defaultProductId,
  });

  final int customerId;
  final String name;
  final String? phone;
  final int? accountId;
  final String? accountNumber;
  final String? accountProvider;

  /// The account's default package when it was attached — what "the package
  /// was changed" is measured against after the sale.
  final int? defaultProductId;

  bool get hasAccount => accountId != null;
}

/// What a customer has bought, in the BASE currency, from the invoices that
/// are still in the archive.
class CustomerTotals {
  const CustomerTotals({
    required this.invoiceCount,
    required this.totalBaseMinor,
    this.lastPurchaseAt,
  });

  final int invoiceCount;
  final int totalBaseMinor;
  final DateTime? lastPurchaseAt;
}

/// One line of a customer's purchase / renewal history.
class CustomerInvoice {
  const CustomerInvoice({
    required this.id,
    required this.invoiceNo,
    required this.createdAt,
    required this.currencyCode,
    required this.totalMinor,
    required this.itemCount,
    this.firstItemName,
    this.accountNumber,
    this.isVoided = false,
  });

  final int id;
  final int invoiceNo;
  final DateTime createdAt;
  final String currencyCode;
  final int totalMinor;
  final int itemCount;

  /// The invoice was voided: listed, marked, and left out of the totals.
  final bool isVoided;

  /// The first item sold — for a renewal, the package.
  final String? firstItemName;

  /// The account snapshot, when the sale was linked to one.
  final String? accountNumber;

  static CustomerInvoice fromRow(Map<String, Object?> row) => CustomerInvoice(
        id: row['id'] as int,
        invoiceNo: row['invoice_no'] as int,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          row['created_at'] as int,
          isUtc: true,
        ),
        currencyCode: row['currency_code'] as String,
        totalMinor: row['total_minor'] as int,
        itemCount: (row['item_count'] as int?) ?? 0,
        firstItemName: row['first_item'] as String?,
        accountNumber: _blankToNull(row['account_number'] as String?),
        isVoided: row['voided_at'] != null,
      );
}

/// Another account that already carries the number being saved.
class AccountDuplicate {
  const AccountDuplicate({required this.account, required this.customerName});

  final CustomerAccount account;
  final String customerName;
}

/// "Make this the default package for this account": offered after a
/// renewal that sold a different package from the account's default one.
class DefaultPackageOffer {
  const DefaultPackageOffer({
    required this.accountId,
    required this.productId,
    required this.productName,
  });

  final int accountId;
  final int productId;
  final String productName;
}

/// The offer to make after [saved] was sold to [customer], or null.
///
/// Only when the sale really was a renewal of the attached account and sold
/// exactly ONE saved SERVICE/CARD product that is not already the account's
/// default: with two different packages on the invoice there is no telling
/// which one the seller means.
DefaultPackageOffer? defaultPackageOfferFor(
  Invoice saved,
  SaleCustomer? customer,
) {
  final accountId = customer?.accountId;
  if (accountId == null || !saved.renewsAccount) return null;
  final packages = <int, String>{
    for (final item in saved.items)
      if (item.kind == ProductKind.service && item.productId != null)
        item.productId!: item.productName,
  };
  if (packages.length != 1) return null;
  final productId = packages.keys.single;
  if (productId == customer!.defaultProductId) return null;
  return DefaultPackageOffer(
    accountId: accountId,
    productId: productId,
    productName: packages.values.single,
  );
}
