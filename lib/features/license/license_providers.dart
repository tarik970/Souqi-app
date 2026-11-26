import 'package:flutter/widgets.dart' show BuildContext;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/features.dart';
import '../../core/licensing/license_service.dart';
import '../../core/licensing/license_status.dart';
import '../../core/providers.dart';
import '../vouchers/code_scan_screen.dart';

/// THE LICENSE AS THE SCREENS SEE IT: licensed, trial or unlicensed, and
/// what that allows. It follows `LicenseService` — every check the service
/// makes (an app start, a sale, a print, coming back from the background)
/// lands here, so a trial that just ended shows at once.
///
/// Without a license service in scope ([licenseServiceProvider] is null: a
/// widget test of one screen) it is [LicenseStatus.unrestricted].
class LicenseController extends Notifier<LicenseStatus> {
  @override
  LicenseStatus build() {
    final service = ref.watch(licenseServiceProvider);
    if (service == null) return LicenseStatus.unrestricted;
    void listener(LicenseStatus status) => state = status;
    service.onChanged = listener;
    ref.onDispose(() {
      if (service.onChanged == listener) service.onChanged = null;
    });
    return service.status;
  }

  /// Checks again, now (the app came back from the background, possibly on
  /// another day).
  Future<LicenseStatus> refresh() async {
    final service = ref.read(licenseServiceProvider);
    if (service == null) return state;
    try {
      return await service.refresh();
    } on Object {
      return state;
    }
  }

  /// Takes an activation code. On success the license's features are in
  /// force at once ([FeatureGate]); the caller then starts the app's state
  /// over (`appRestartProvider`) so every screen is built with them.
  Future<ActivationResult> activate(String code) async {
    final service = ref.read(licenseServiceProvider);
    if (service == null) {
      return const ActivationResult.failed(ActivationError.notConfigured);
    }
    final result = await service.activate(code);
    if (result.ok) FeatureGate.apply(service.status.featureMask);
    return result;
  }
}

final licenseProvider =
    NotifierProvider<LicenseController, LicenseStatus>(LicenseController.new);

/// The request code of this phone ("K7QM-29XD-HF4P-8WZN"), or null when the
/// phone could not be identified — or there is no licensing in this scope.
final requestCodeProvider = Provider<String?>(
  (ref) => ref.watch(licenseServiceProvider)?.requestCode,
);

/// An unlicensed app opens on the activation screen. "Browse my data" there
/// sets this, and the home screen shows — read-only as far as selling goes —
/// for the rest of this run.
class BrowsingUnlicensedNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void allow() => state = true;
}

final browsingUnlicensedProvider =
    NotifierProvider<BrowsingUnlicensedNotifier, bool>(
  BrowsingUnlicensedNotifier.new,
);

/// Reads one QR code with the camera (the scanner the card codes use);
/// null when the user backs out. Tests replace it.
final licenseScannerProvider =
    Provider<Future<String?> Function(BuildContext context)>(
  (ref) => scanOneBarcode,
);
