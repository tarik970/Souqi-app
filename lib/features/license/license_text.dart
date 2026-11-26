import 'package:intl/intl.dart' show DateFormat;

import '../../config/features.dart';
import '../../core/licensing/license_service.dart';
import '../../core/licensing/license_status.dart';
import '../../l10n/generated/app_localizations.dart';

/// What each licensable feature is called on the activation screen.
String featureLabel(AppLocalizations l10n, Feature feature) =>
    switch (feature) {
      Feature.debt => l10n.licenseFeatureDebt,
      Feature.customers => l10n.licenseFeatureCustomers,
      Feature.accounts => l10n.licenseFeatureAccounts,
      Feature.vouchers => l10n.licenseFeatureVouchers,
      Feature.barcode => l10n.licenseFeatureBarcode,
      Feature.discount => l10n.licenseFeatureDiscount,
      Feature.multiCurrency => l10n.licenseFeatureMultiCurrency,
      Feature.dailyReport => l10n.licenseFeatureDailyReport,
      Feature.backup => l10n.licenseFeatureBackup,
    };

String licenseDate(DateTime moment, String locale) =>
    DateFormat.yMMMd(locale).format(moment.toLocal());

/// The one sentence that says why the app is not licensed.
String unlicensedReasonText(
  AppLocalizations l10n,
  LicenseStatus status,
  String locale,
) {
  final expires = status.license?.expiresAt;
  return switch (status.reason) {
    UnlicensedReason.trialDaysOver => l10n.licenseReasonTrialDays,
    UnlicensedReason.trialInvoicesOver => l10n.licenseReasonTrialInvoices,
    UnlicensedReason.expired => expires == null
        ? l10n.licenseErrorExpired
        : l10n.licenseReasonExpired(licenseDate(expires, locale)),
    UnlicensedReason.wrongDevice => l10n.licenseReasonWrongDevice,
    UnlicensedReason.modifiedApp => l10n.licenseReasonModified,
    UnlicensedReason.unsealedBuild => l10n.licenseReasonUnsealed,
    null => '',
  };
}

/// Why an activation code was not accepted.
String activationErrorText(AppLocalizations l10n, ActivationError error) =>
    switch (error) {
      ActivationError.notConfigured => l10n.licenseErrorNotConfigured,
      ActivationError.malformed => l10n.licenseErrorMalformed,
      ActivationError.pinResetCode => l10n.licenseErrorPinReset,
      ActivationError.newerFormat => l10n.licenseErrorNewer,
      ActivationError.badSignature => l10n.licenseErrorSignature,
      ActivationError.wrongDevice => l10n.licenseErrorWrongDevice,
      ActivationError.expired => l10n.licenseErrorExpired,
      ActivationError.olderThanCurrent => l10n.licenseErrorOlder,
      ActivationError.modifiedApp => l10n.licenseReasonModified,
      ActivationError.unsealedBuild => l10n.licenseReasonUnsealed,
      ActivationError.deviceUnknown => l10n.licenseRequestUnavailable,
    };

/// What a refused action says.
String licenseNeededText(AppLocalizations l10n, LicensedAction action) =>
    switch (action) {
      LicensedAction.sell => l10n.licenseNeededSell,
      LicensedAction.print => l10n.licenseNeededPrint,
      LicensedAction.recordDebt => l10n.licenseNeededDebt,
    };
