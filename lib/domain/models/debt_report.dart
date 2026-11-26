/// What the daily debt report says: the figures and the rows of its four
/// sheets, read from the ledger once. No Flutter and no database here; the
/// Excel and PDF builders only lay this out.
library;

import 'debt.dart';

class DebtReportSummary {
  const DebtReportSummary({
    required this.totalOutstandingBaseMinor,
    required this.totalCreditBaseMinor,
    required this.debtorsCount,
    required this.overdueCount,
    required this.aging,
    required this.collectedTodayBaseMinor,
    required this.newDebtTodayBaseMinor,
  });

  /// What customers owe (credit balances are not netted off).
  final int totalOutstandingBaseMinor;

  /// What the shop owes customers, as a positive number.
  final int totalCreditBaseMinor;

  /// Customers who owe something.
  final int debtorsCount;

  /// Customers with a debt past its due day.
  final int overdueCount;

  /// Unpaid amounts by age (FIFO), 0–30 / 31–60 / 61–90 / 90+ days.
  final AgingSummary aging;

  /// Payments dated today that were not reversed.
  final int collectedTodayBaseMinor;

  /// Debt made today (sales on credit, manual debts, debit adjustments) that
  /// was not reversed. Opening balances are old debt, not new.
  final int newDebtTodayBaseMinor;
}

/// One row of the "Debtors" sheet: a customer who owes.
class DebtReportDebtor {
  const DebtReportDebtor({
    required this.name,
    this.phone,
    required this.balanceBaseMinor,
    this.creditLimitBaseMinor,
    this.oldestUnpaidAt,
    this.lastPaymentAt,
    required this.overdue,
  });

  final String name;
  final String? phone;
  final int balanceBaseMinor;
  final int? creditLimitBaseMinor;
  final DateTime? oldestUnpaidAt;
  final DateTime? lastPaymentAt;
  final bool overdue;
}

/// One row of "Today's movements": a ledger entry dated or written today.
class DebtReportMovement {
  const DebtReportMovement({
    required this.entry,
    required this.customerName,
    this.customerPhone,
  });

  final DebtEntry entry;
  final String customerName;
  final String? customerPhone;
}

/// One row of "All balances": every customer with an account in the ledger,
/// owing, settled (zero) or in credit.
class DebtReportBalance {
  const DebtReportBalance({
    required this.name,
    this.phone,
    required this.balanceBaseMinor,
    this.creditLimitBaseMinor,
    this.lastPaymentAt,
    required this.isActive,
  });

  final String name;
  final String? phone;

  /// Positive = the customer owes; negative = the shop owes the customer.
  final int balanceBaseMinor;
  final int? creditLimitBaseMinor;
  final DateTime? lastPaymentAt;
  final bool isActive;
}

/// The money every figure is in.
class ReportCurrency {
  const ReportCurrency({
    required this.code,
    required this.symbol,
    required this.decimals,
  });

  final String code;
  final String symbol;
  final int decimals;

  /// What follows an amount: the symbol, or the code when there is none.
  String get label => symbol.isEmpty ? code : symbol;
}

class DebtReportData {
  const DebtReportData({
    required this.generatedAt,
    required this.shopName,
    required this.language,
    required this.currency,
    required this.summary,
    required this.debtors,
    required this.movements,
    required this.balances,
  });

  /// Local time.
  final DateTime generatedAt;
  final String shopName;

  /// 'ar' or 'en' — the INVOICE language: the report is a document, like
  /// the invoice, and may be handed to someone else.
  final String language;
  final ReportCurrency currency;
  final DebtReportSummary summary;

  /// Biggest balance first.
  final List<DebtReportDebtor> debtors;

  /// In the order they were written.
  final List<DebtReportMovement> movements;

  /// By name.
  final List<DebtReportBalance> balances;

  bool get rightToLeft => language == 'ar';
}
