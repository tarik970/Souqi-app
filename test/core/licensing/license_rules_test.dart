import 'package:flutter_test/flutter_test.dart';
import 'package:souqi/config/features.dart';
import 'package:souqi/core/licensing/clock_guard.dart';
import 'package:souqi/core/licensing/license_codec.dart';
import 'package:souqi/core/licensing/license_status.dart';

/// The rules of licensing as pure functions: the clock that cannot be turned
/// back, and what a license, a trial and a clock add up to.
void main() {
  final t0 = DateTime.utc(2026, 11, 26, 10);

  group('the clock guard', () {
    test('follows a clock that goes forward', () {
      var reading = observeClock(const ClockState(), t0);
      expect(reading.now, t0);
      expect(reading.wentBack, isFalse);
      reading = observeClock(reading.state, t0.add(const Duration(days: 3)));
      expect(reading.now, t0.add(const Duration(days: 3)));
      expect(reading.wentBack, isFalse);
      expect(
        reading.state.latestMs,
        t0.add(const Duration(days: 3)).millisecondsSinceEpoch,
      );
    });

    test('a step back within 48 hours is taken as it is, without a warning',
        () {
      final seen = observeClock(const ClockState(), t0).state;
      final corrected = t0.subtract(const Duration(hours: 47));
      final reading = observeClock(seen, corrected);
      expect(reading.wentBack, isFalse);
      expect(reading.now, corrected);
      // The mark is kept.
      expect(reading.state.latestMs, t0.millisecondsSinceEpoch);
    });

    test('more than 48 hours back is detected, and time is where it was', () {
      final seen = observeClock(const ClockState(), t0).state;
      final reading =
          observeClock(seen, t0.subtract(const Duration(days: 30)));
      expect(reading.wentBack, isTrue);
      expect(reading.now, t0, reason: 'as if time had not gone back');
    });

    test('with the date set back a year, licensing time still passes', () {
      var state = observeClock(const ClockState(), t0).state;
      var wall = t0.subtract(const Duration(days: 365));
      var reading = observeClock(state, wall);
      state = reading.state;
      // Ten days of daily use with the wrong date.
      for (var day = 0; day < 10; day++) {
        wall = wall.add(const Duration(days: 1));
        reading = observeClock(state, wall);
        state = reading.state;
      }
      expect(reading.wentBack, isTrue);
      expect(reading.now, t0.add(const Duration(days: 10)),
          reason: 'a year back did not buy a year: ten days passed');
    });

    test('turning the clock back again and again never stops time', () {
      var state = observeClock(const ClockState(), t0).state;
      late ClockReading reading;
      // Every day: one day of use, then the date is put back where it was.
      final frozen = t0.subtract(const Duration(days: 100));
      for (var day = 0; day < 20; day++) {
        reading = observeClock(state, frozen);
        state = reading.state;
        reading = observeClock(state, frozen.add(const Duration(days: 1)));
        state = reading.state;
      }
      expect(reading.now, t0.add(const Duration(days: 20)));
    });

    test('one look never adds more than 48 hours while the clock is behind',
        () {
      var state = observeClock(const ClockState(), t0).state;
      // The date is set to 2010 by mistake…
      state = observeClock(state, DateTime.utc(2010)).state;
      // …and then to 2020, still wrong: ten "years" between two looks.
      final reading = observeClock(state, DateTime.utc(2020));
      expect(reading.wentBack, isTrue);
      expect(reading.now, t0.add(clockRollbackTolerance));
    });

    test('setting the right date again ends the warning', () {
      var state = observeClock(const ClockState(), t0).state;
      state = observeClock(state, DateTime.utc(2010)).state;
      final reading = observeClock(state, t0.add(const Duration(hours: 5)));
      expect(reading.wentBack, isFalse);
      expect(reading.now, t0.add(const Duration(hours: 5)));
    });

    test('a newer license restarts the guard from when it was issued', () {
      // The phone once showed 2062.
      var state = observeClock(const ClockState(), DateTime.utc(2062)).state;
      expect(observeClock(state, t0).wentBack, isTrue);
      state = restartClock(t0, t0.subtract(const Duration(hours: 1)));
      final reading = observeClock(state, t0);
      expect(reading.wentBack, isFalse);
      expect(reading.now, t0);
      // A phone whose date is BEHIND the developer's: the license's own
      // date is the earliest it can be.
      final behind = restartClock(DateTime.utc(2020), t0);
      expect(observeClock(behind, DateTime.utc(2020)).now, t0);
      expect(observeClock(behind, DateTime.utc(2020)).wentBack, isTrue);
    });
  });

  group('the rules', () {
    ClockReading at(DateTime now, {bool wentBack = false}) => ClockReading(
          state: ClockState(
            latestMs: now.millisecondsSinceEpoch,
            lastNowMs: now.millisecondsSinceEpoch,
          ),
          now: now,
          wentBack: wentBack,
        );

    LicensePayload license({DateTime? expiresAt, int? features}) =>
        LicensePayload(
          deviceHash: List<int>.filled(deviceHashLength, 1),
          licenseId: 5,
          features: features ?? allLicenseFeatures,
          issuedAt: t0,
          expiresAt: expiresAt,
          shopName: 'Shop',
        );

    LicenseStatus trial({required Duration after, required int invoices}) =>
        evaluateLicense(
          license: null,
          integrity: BuildIntegrity.ok,
          trialStartedAt: t0,
          invoicesUsed: invoices,
          clock: at(t0.add(after)),
        );

    test('the trial: seven days, everything on', () {
      final status = trial(after: const Duration(days: 6, hours: 23), invoices: 0);
      expect(status.mode, LicenseMode.trial);
      expect(status.canSell, isTrue);
      expect(status.canPrint, isTrue);
      expect(status.featureMask, allLicenseFeatures);
      expect(status.trialInvoicesLeft, trialInvoiceLimit);
      expect(status.trialEndsAt, t0.add(trialLength));
      expect(status.trialDaysLeft(t0.add(const Duration(days: 6, hours: 23))), 1);
      expect(status.trialDaysLeft(t0), 7);
    });

    test('the trial ends after seven days', () {
      final status = trial(after: const Duration(days: 7), invoices: 3);
      expect(status.mode, LicenseMode.unlicensed);
      expect(status.reason, UnlicensedReason.trialDaysOver);
      expect(status.canSell, isFalse);
      expect(status.canPrint, isFalse);
      // What the shop made stays readable: no feature is hidden.
      expect(status.featureMask, allLicenseFeatures);
    });

    test('the trial ends after thirty invoices — whichever comes first', () {
      final almost = trial(after: const Duration(days: 1), invoices: 29);
      expect(almost.mode, LicenseMode.trial);
      expect(almost.trialInvoicesLeft, 1);

      final used = trial(after: const Duration(days: 1), invoices: 30);
      expect(used.mode, LicenseMode.unlicensed);
      expect(used.reason, UnlicensedReason.trialInvoicesOver);
      expect(used.canSell, isFalse);
      // The thirtieth invoice itself can still be handed over.
      expect(used.canPrint, isTrue);

      // Not once the days are over as well.
      final late = trial(after: const Duration(days: 8), invoices: 30);
      expect(late.reason, UnlicensedReason.trialDaysOver);
      expect(late.canPrint, isFalse);
    });

    test('a valid license: licensed, with ITS features', () {
      final mask = FeatureGate.maskOf([Feature.customers, Feature.barcode]);
      final status = evaluateLicense(
        license: license(features: mask),
        integrity: BuildIntegrity.ok,
        // A trial long over does not matter to a licensed phone.
        trialStartedAt: t0.subtract(const Duration(days: 400)),
        invoicesUsed: 9000,
        clock: at(t0.add(const Duration(days: 300))),
      );
      expect(status.mode, LicenseMode.licensed);
      expect(status.canSell, isTrue);
      expect(status.canPrint, isTrue);
      expect(status.featureMask, mask);
      expect(status.shopName, 'Shop');
    });

    test('an expired license: unlicensed, and no trial to fall back on', () {
      final expires = t0.add(const Duration(days: 30));
      LicenseStatus on(DateTime now) => evaluateLicense(
            license: license(expiresAt: expires),
            integrity: BuildIntegrity.ok,
            // Even with a trial that would still be running.
            trialStartedAt: now,
            invoicesUsed: 0,
            clock: at(now),
          );
      expect(on(expires.subtract(const Duration(seconds: 1))).isLicensed, isTrue);
      final after = on(expires);
      expect(after.mode, LicenseMode.unlicensed);
      expect(after.reason, UnlicensedReason.expired);
      expect(after.canSell, isFalse);
      expect(after.canPrint, isFalse);
      expect(after.license, isNotNull, reason: 'the shop name stays');
    });

    test('a clock that went back is said while time matters, not for a '
        'lifetime license', () {
      LicenseStatus status(LicensePayload? l) => evaluateLicense(
            license: l,
            integrity: BuildIntegrity.ok,
            trialStartedAt: t0,
            invoicesUsed: 0,
            clock: at(t0.add(const Duration(days: 1)), wentBack: true),
          );
      expect(status(null).clockWentBack, isTrue);
      expect(
        status(license(expiresAt: t0.add(const Duration(days: 90))))
            .clockWentBack,
        isTrue,
      );
      expect(status(license()).clockWentBack, isFalse);
    });

    test('a modified or unsealed build never sells, licensed or not', () {
      for (final (integrity, reason) in [
        (BuildIntegrity.modified, UnlicensedReason.modifiedApp),
        (BuildIntegrity.unsealed, UnlicensedReason.unsealedBuild),
      ]) {
        final status = evaluateLicense(
          license: license(),
          integrity: integrity,
          trialStartedAt: t0,
          invoicesUsed: 0,
          clock: at(t0),
        );
        expect(status.mode, LicenseMode.unlicensed);
        expect(status.reason, reason);
        expect(status.canSell, isFalse);
        expect(status.canPrint, isFalse);
      }
    });

    test('a stored code of another device: the trial if it still runs, '
        'otherwise "wrong device"', () {
      LicenseStatus status(Duration after) => evaluateLicense(
            license: null,
            integrity: BuildIntegrity.ok,
            trialStartedAt: t0,
            invoicesUsed: 0,
            clock: at(t0.add(after)),
            storedCodeForOtherDevice: true,
          );
      expect(status(const Duration(days: 1)).mode, LicenseMode.trial);
      final over = status(const Duration(days: 9));
      expect(over.mode, LicenseMode.unlicensed);
      expect(over.reason, UnlicensedReason.wrongDevice);
    });
  });

  group('featureOn', () {
    tearDown(FeatureGate.reset);

    test('everything is on until a license says otherwise', () {
      for (final feature in Feature.values) {
        expect(featureOn(feature), isTrue, reason: feature.name);
      }
    });

    test('a feature is on only with its bit', () {
      FeatureGate.apply(FeatureGate.maskOf([Feature.customers, Feature.backup]));
      expect(featureOn(Feature.customers), isTrue);
      expect(featureOn(Feature.backup), isTrue);
      for (final off in [
        Feature.debt,
        Feature.accounts,
        Feature.vouchers,
        Feature.barcode,
        Feature.discount,
        Feature.multiCurrency,
        Feature.dailyReport,
      ]) {
        expect(featureOn(off), isFalse, reason: off.name);
      }
    });

    test('a feature is off without what it requires', () {
      // The ledger's bit without customers: no ledger.
      FeatureGate.apply(FeatureGate.maskOf([Feature.debt, Feature.dailyReport]));
      expect(featureOn(Feature.debt), isFalse);
      expect(featureOn(Feature.dailyReport), isFalse);
      // The daily report without the ledger: no report.
      FeatureGate.apply(
        FeatureGate.maskOf([Feature.customers, Feature.dailyReport]),
      );
      expect(featureOn(Feature.dailyReport), isFalse);
      FeatureGate.applyWithout([Feature.customers]);
      expect(featureOn(Feature.accounts), isFalse);
      expect(featureOn(Feature.debt), isFalse);
      expect(featureOn(Feature.vouchers), isTrue);
    });

    test('the compile-time flags are the upper limit', () {
      // In this build every flag is on; the rule is that none of them can
      // be exceeded.
      for (final feature in Feature.values) {
        expect(featureOn(feature), feature.compiledIn);
      }
    });
  });
}
