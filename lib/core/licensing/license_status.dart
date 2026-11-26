/// What the license check comes to, and the rules it follows. Pure: the
/// same function decides for the app and for the background engine, and the
/// tests feed it directly.
library;

import 'clock_guard.dart';
import 'license_codec.dart';

/// The trial: seven days or thirty invoices, whichever comes first.
const Duration trialLength = Duration(days: 7);
const int trialInvoiceLimit = 30;

enum LicenseMode {
  /// A valid license of this device.
  licensed,

  /// No license yet, and the trial is still running: everything is on.
  trial,

  /// Selling, printing and new debt entries are blocked. The shop's data
  /// stays readable, and the backup and the daily report keep working.
  unlicensed,
}

/// Why the app is [LicenseMode.unlicensed].
enum UnlicensedReason {
  trialDaysOver,
  trialInvoicesOver,

  /// The license of this device has run out.
  expired,

  /// The activation code stored with this data belongs to another device
  /// (the data was moved to a new phone, or the phone was reset).
  wrongDevice,

  /// The APK was signed by someone else: it is not the developer's build.
  modifiedApp,

  /// A release build made before `expectedSigningCertSha256` was filled in.
  unsealedBuild,
}

/// Whether the running APK is the developer's.
enum BuildIntegrity { ok, modified, unsealed }

/// What needs a license.
enum LicensedAction { sell, print, recordDebt }

class LicenseStatus {
  const LicenseStatus({
    required this.mode,
    this.reason,
    this.license,
    required this.featureMask,
    required this.canSell,
    required this.canPrint,
    this.trialEndsAt,
    this.trialInvoicesLeft,
    this.clockWentBack = false,
    this.storedCodeForOtherDevice = false,
  });

  /// "No licensing here": what a `ProviderScope` without a license service
  /// has (widget tests, previews). The app itself always has a service.
  static const LicenseStatus unrestricted = LicenseStatus(
    mode: LicenseMode.licensed,
    featureMask: allLicenseFeatures,
    canSell: true,
    canPrint: true,
  );

  final LicenseMode mode;

  /// Set exactly when [mode] is [LicenseMode.unlicensed].
  final UnlicensedReason? reason;

  /// The license of THIS device — signed by the developer, for this device —
  /// whether it is still valid ([LicenseMode.licensed]) or has expired.
  final LicensePayload? license;

  /// What `featureOn` goes by: the license's features; everything during the
  /// trial and after it (what was made in the trial stays readable).
  final int featureMask;

  /// A new invoice may be saved; a new debt entry may be recorded.
  final bool canSell;

  /// An invoice, a receipt or a statement may be printed or shared.
  final bool canPrint;

  /// The trial, while it runs: its last moment and the invoices left.
  final DateTime? trialEndsAt;
  final int? trialInvoicesLeft;

  /// The phone's date is more than 48 hours behind what it showed before —
  /// said only while time matters (a trial, a license that expires).
  final bool clockWentBack;

  /// An activation code is stored, signed by the developer, but for another
  /// device.
  final bool storedCodeForOtherDevice;

  bool get isLicensed => mode == LicenseMode.licensed;

  bool get isTrial => mode == LicenseMode.trial;

  bool get isUnlicensed => mode == LicenseMode.unlicensed;

  bool get canRecordDebt => canSell;

  bool allows(LicensedAction action) => switch (action) {
        LicensedAction.sell => canSell,
        LicensedAction.print => canPrint,
        LicensedAction.recordDebt => canRecordDebt,
      };

  /// The name every invoice carries once a license is in place.
  String? get shopName => license?.shopName;

  /// Whole days of trial left at [now], counting the one that has begun.
  int trialDaysLeft(DateTime now) {
    final end = trialEndsAt;
    if (end == null) return 0;
    final left = end.difference(now.toUtc());
    if (left.isNegative) return 0;
    return (left.inMinutes / (24 * 60)).ceil();
  }

  @override
  bool operator ==(Object other) =>
      other is LicenseStatus &&
      other.mode == mode &&
      other.reason == reason &&
      other.license?.licenseId == license?.licenseId &&
      other.license?.issuedAt == license?.issuedAt &&
      other.license?.shopName == license?.shopName &&
      other.featureMask == featureMask &&
      other.canSell == canSell &&
      other.canPrint == canPrint &&
      other.trialEndsAt == trialEndsAt &&
      other.trialInvoicesLeft == trialInvoicesLeft &&
      other.clockWentBack == clockWentBack &&
      other.storedCodeForOtherDevice == storedCodeForOtherDevice;

  @override
  int get hashCode => Object.hash(
        mode,
        reason,
        license?.licenseId,
        featureMask,
        canSell,
        canPrint,
        trialEndsAt,
        trialInvoicesLeft,
        clockWentBack,
        storedCodeForOtherDevice,
      );
}

/// An action that needs a license was refused. Nothing was saved or sent.
class LicenseRequiredException implements Exception {
  const LicenseRequiredException(this.action, this.status);

  final LicensedAction action;
  final LicenseStatus status;

  @override
  String toString() =>
      'LicenseRequiredException(${action.name}, ${status.reason?.name})';
}

/// The checks the data layer asks for before it writes. `LicenseService` is
/// the implementation; a repository built without one (a unit test) checks
/// nothing.
abstract interface class LicenseGuard {
  /// Throws [LicenseRequiredException] unless an invoice may be saved now.
  Future<void> ensureCanSell();

  /// Throws [LicenseRequiredException] unless paper may be put out now.
  Future<void> ensureCanPrint();

  /// Throws [LicenseRequiredException] unless a ledger entry may be made.
  Future<void> ensureCanRecordDebt();

  /// An invoice was saved: the trial has one fewer left.
  Future<void> saleSaved();
}

/// THE RULES.
///
/// - [integrity] not ok: unlicensed, whatever else is true.
/// - [license] (already checked: the developer's signature, this device)
///   valid at the licensing time: licensed, with its features. Expired:
///   unlicensed, still with its features — what the shop has stays readable.
/// - No license: the trial, until seven days after [trialStartedAt] or
///   [invoicesUsed] reaches thirty; then unlicensed, with every feature
///   still visible.
///
/// The LAST invoice of the trial can still be printed: saving it is what
/// ends the trial, and an invoice that cannot be handed over is worth
/// nothing. So with exactly thirty used and days left, printing is allowed
/// and selling is not.
LicenseStatus evaluateLicense({
  required LicensePayload? license,
  required BuildIntegrity integrity,
  required DateTime trialStartedAt,
  required int invoicesUsed,
  required ClockReading clock,
  bool storedCodeForOtherDevice = false,
}) {
  final now = clock.now;
  final features = license?.features ?? allLicenseFeatures;

  if (integrity != BuildIntegrity.ok) {
    return LicenseStatus(
      mode: LicenseMode.unlicensed,
      reason: integrity == BuildIntegrity.unsealed
          ? UnlicensedReason.unsealedBuild
          : UnlicensedReason.modifiedApp,
      license: license,
      featureMask: features,
      canSell: false,
      canPrint: false,
      storedCodeForOtherDevice: storedCodeForOtherDevice,
    );
  }

  if (license != null) {
    final live = license.isLiveAt(now);
    return LicenseStatus(
      mode: live ? LicenseMode.licensed : LicenseMode.unlicensed,
      reason: live ? null : UnlicensedReason.expired,
      license: license,
      featureMask: features,
      canSell: live,
      canPrint: live,
      // A lifetime license does not care what day it is.
      clockWentBack: clock.wentBack && license.expiresAt != null,
    );
  }

  final trialEnd = trialStartedAt.toUtc().add(trialLength);
  final daysOver = !now.isBefore(trialEnd);
  final used = invoicesUsed < 0 ? 0 : invoicesUsed;
  final invoicesOver = used >= trialInvoiceLimit;
  if (!daysOver && !invoicesOver) {
    return LicenseStatus(
      mode: LicenseMode.trial,
      featureMask: allLicenseFeatures,
      canSell: true,
      canPrint: true,
      trialEndsAt: trialEnd,
      trialInvoicesLeft: trialInvoiceLimit - used,
      clockWentBack: clock.wentBack,
      storedCodeForOtherDevice: storedCodeForOtherDevice,
    );
  }
  return LicenseStatus(
    mode: LicenseMode.unlicensed,
    reason: storedCodeForOtherDevice
        ? UnlicensedReason.wrongDevice
        : daysOver
            ? UnlicensedReason.trialDaysOver
            : UnlicensedReason.trialInvoicesOver,
    featureMask: allLicenseFeatures,
    canSell: false,
    canPrint: !daysOver && used <= trialInvoiceLimit,
    clockWentBack: clock.wentBack,
    storedCodeForOtherDevice: storedCodeForOtherDevice,
  );
}
