import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/licensing/license_status.dart';
import '../../core/money/money_format.dart';
import '../../core/providers.dart';
import '../../l10n/generated/app_localizations.dart';
import 'license_providers.dart';
import 'license_screen.dart';
import 'license_text.dart';

void openLicenseScreen(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const LicenseScreen()),
  );
}

/// WHERE AN UNLICENSED APP OPENS: on the activation screen, with the request
/// code — instead of [child], the home screen. "Browse my data" on that
/// screen lets [child] through for the rest of the run; selling, printing
/// and new debt entries stay blocked wherever they are tried.
///
/// It also looks at the license again whenever the app comes back from the
/// background: a license can run out overnight.
class LicenseGate extends ConsumerStatefulWidget {
  const LicenseGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<LicenseGate> createState() => _LicenseGateState();
}

class _LicenseGateState extends ConsumerState<LicenseGate>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    ref.read(licenseProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(licenseProvider);
    final browsing = ref.watch(browsingUnlicensedProvider);
    if (status.isUnlicensed && !browsing) {
      return const LicenseScreen(gate: true);
    }
    return widget.child;
  }
}

/// A license that ends is said on the home screen this many days ahead: a
/// shop must not find out at the first sale of the morning.
const int licenseExpiryNoticeDays = 14;

/// The line on top of the home screen while the app is not licensed: how
/// much of the trial is left, or that selling is locked — and the way to
/// the activation screen. With a license in place there is nothing, except
/// in its last [licenseExpiryNoticeDays] days (and while the phone's date
/// is wrong).
class LicenseBanner extends ConsumerWidget {
  const LicenseBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(licenseProvider);
    final now = ref.watch(licenseServiceProvider)?.now ?? DateTime.now();
    final expires = status.license?.expiresAt;
    // Whole days left of a license that ends, counting the one begun.
    final daysLeft = !status.isLicensed || expires == null
        ? null
        : (expires.difference(now.toUtc()).inMinutes / (24 * 60)).ceil();
    final ending = daysLeft != null && daysLeft <= licenseExpiryNoticeDays;
    if (status.isLicensed && !status.clockWentBack && !ending) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(appLocaleProvider).languageCode;
    String number(int value) => formatMinor(value, decimals: 0, locale: locale);

    final locked = status.isUnlicensed;
    final text = status.isLicensed
        ? ending
            ? l10n.licenseBannerEnding(number(daysLeft < 0 ? 0 : daysLeft))
            : l10n.licenseClockWarning
        : locked
            ? l10n.licenseBannerLocked
            : l10n.licenseBannerTrial(
                number(status.trialDaysLeft(now)),
                number(status.trialInvoicesLeft ?? 0),
              );
    final background =
        locked ? scheme.errorContainer : scheme.secondaryContainer;
    final foreground =
        locked ? scheme.onErrorContainer : scheme.onSecondaryContainer;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Material(
        key: const ValueKey('license-banner'),
        color: background,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => openLicenseScreen(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      locked ? Icons.lock_outline : Icons.hourglass_bottom,
                      size: 20,
                      color: foreground,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        text,
                        style: TextStyle(color: foreground),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (!status.isLicensed)
                      Text(
                        l10n.licenseActivate,
                        style: TextStyle(
                          color: foreground,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
                if (status.clockWentBack && (!status.isLicensed || ending))
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      l10n.licenseClockWarning,
                      key: const ValueKey('license-clock-warning'),
                      style: TextStyle(color: foreground, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// What a screen that only WRITES (the sale, a payment, a new debt) shows in
/// place of its form while the license does not allow [action]: why, and
/// the way to the activation screen.
class LicenseLockedBody extends ConsumerWidget {
  const LicenseLockedBody({super.key, required this.action});

  final LicensedAction action;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final status = ref.watch(licenseProvider);
    final locale = ref.watch(appLocaleProvider).languageCode;
    final reason = unlicensedReasonText(l10n, status, locale);
    return Center(
      key: const ValueKey('license-locked'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 56, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(
              licenseNeededText(l10n, action),
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (reason.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(reason, textAlign: TextAlign.center),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              key: const ValueKey('license-locked-activate'),
              onPressed: () => openLicenseScreen(context),
              icon: const Icon(Icons.vpn_key_outlined),
              label: Text(l10n.licenseActivate),
            ),
          ],
        ),
      ),
    );
  }
}

/// A whole screen in that state: its title, and [LicenseLockedBody].
class LicenseLockedScaffold extends StatelessWidget {
  const LicenseLockedScaffold({
    super.key,
    required this.title,
    required this.action,
  });

  final String title;
  final LicensedAction action;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: LicenseLockedBody(action: action),
      );
}

/// Says that [action] needs an activation, and offers the way there. For
/// what was refused at the last moment (a sale saved as the trial ran out).
Future<void> showLicenseNeeded(BuildContext context, LicensedAction action) {
  return showDialog<void>(
    context: context,
    builder: (_) => LicenseNeededDialog(action: action),
  );
}

class LicenseNeededDialog extends ConsumerWidget {
  const LicenseNeededDialog({super.key, required this.action});

  final LicensedAction action;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final status = ref.watch(licenseProvider);
    final locale = ref.watch(appLocaleProvider).languageCode;
    final reason = unlicensedReasonText(l10n, status, locale);
    return AlertDialog(
      key: const ValueKey('license-needed'),
      icon: const Icon(Icons.lock_outline),
      title: Text(l10n.licenseNeededTitle),
      scrollable: true,
      content: Text(
        reason.isEmpty
            ? licenseNeededText(l10n, action)
            : '${licenseNeededText(l10n, action)}\n\n$reason',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const ValueKey('license-needed-activate'),
          onPressed: () {
            final navigator = Navigator.of(context);
            navigator.pop();
            navigator.push(
              MaterialPageRoute<void>(builder: (_) => const LicenseScreen()),
            );
          },
          child: Text(l10n.licenseActivate),
        ),
      ],
    );
  }
}

/// True when the license allows [action]; otherwise says so
/// ([showLicenseNeeded]) and returns false. For a button that would start
/// something the license does not allow.
bool licenseAllows(BuildContext context, LicensedAction action) {
  final container = ProviderScope.containerOf(context, listen: false);
  if (container.read(licenseProvider).allows(action)) return true;
  showLicenseNeeded(context, action);
  return false;
}
