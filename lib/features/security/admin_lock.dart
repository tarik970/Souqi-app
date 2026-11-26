import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/constants/settings_keys.dart';
import '../../core/providers.dart';
import '../../domain/models/voucher.dart';
import '../../l10n/generated/app_localizations.dart';
import 'audit_providers.dart';
import 'pin_dialogs.dart';
import 'pin_session.dart';

/// "PIN TO OPEN SETTINGS, ARCHIVE AND STATISTICS" (off by default) — the
/// three places where a shop's set-up, its history and its figures are.
///
/// ONE SESSION for the three, with the rules of everything the PIN opens
/// ([PinSessionNotifier], the same class behind the debts): it locks again
/// after the "lock again after" time without a touch, and at once when the
/// app goes to the background — two minutes later when the app itself sent
/// the seller away (a share sheet, a file picker: `PinBackgroundGuard`).
///
/// The pieces:
/// - [requireAdminAccess]: asked by the three tiles of the home screen
///   before they open.
/// - [AdminLockGate]: around each of the three screens. It is what keeps
///   the session honest once a screen is open — see there.
/// - [AdminRequirePinTile]: the switch, in Settings → Security.
final adminRequirePinProvider = FutureProvider<bool>(
  (ref) => ref
      .watch(settingsRepositoryProvider)
      .getBool(SettingsKeys.adminRequirePin),
);

/// Settings, the archive and the statistics, unlocked with the PIN.
class AdminUnlockNotifier extends PinSessionNotifier {}

final adminUnlockedProvider =
    NotifierProvider<AdminUnlockNotifier, bool>(AdminUnlockNotifier.new);

/// The gate in front of Settings, the Archive and the Statistics: with the
/// setting on, asks for the PIN unless the session is still unlocked.
/// Returns whether the caller may go on. With the setting off it asks
/// nothing.
Future<bool> requireAdminAccess(BuildContext context) async {
  final container = ProviderScope.containerOf(context, listen: false);
  if (!await container.read(adminRequirePinProvider.future)) return true;
  if (container.read(adminUnlockedProvider)) {
    // Opening one of the three is using the session.
    container.read(adminUnlockedProvider.notifier).touch();
    return true;
  }
  // The idle time is read before the timer needs it.
  await container.read(pinAutoLockMinutesProvider.future);
  if (!context.mounted) return false;
  final l10n = AppLocalizations.of(context);
  if (!await requirePin(context, reason: l10n.pinReasonAdminAccess)) {
    return false;
  }
  container.read(adminUnlockedProvider.notifier).unlock();
  return true;
}

/// Around a whole screen — Settings, the Archive, the Statistics. With the
/// setting off it is [child] and nothing else.
///
/// With it on:
/// - [child] is shown only while the session is unlocked; otherwise a lock
///   and an "Unlock" button are, under the screen's own title. Until the
///   PIN has been entered nothing of [child] is built — and so nothing is
///   read.
/// - EVERY TOUCH ANYWHERE IN THE APP COUNTS AS USING THE SESSION WHILE THIS
///   SCREEN IS OPEN, whatever is on top of it: Settings is a tree of pages
///   (invoice settings, currencies, backup…) and an archive is mostly its
///   invoices, and an owner who spends ten minutes inside one of them is
///   not idle. Once they are back on the home screen this gate is gone, the
///   touches of a sale no longer count, and the session runs out.
/// - WHEN THE SESSION LOCKS, whatever was opened from this screen closes
///   (the rule of `PinGuardedRoute`): an invoice of the archive or a page
///   of the settings must not stay readable on top of a locked door. This
///   screen itself is hidden, not thrown away — its search, its scroll
///   position are there again after the PIN.
class AdminLockGate extends ConsumerStatefulWidget {
  const AdminLockGate({super.key, required this.title, required this.child});

  /// The title of the screen, shown over the lock.
  final String title;
  final Widget child;

  @override
  ConsumerState<AdminLockGate> createState() => _AdminLockGateState();
}

class _AdminLockGateState extends ConsumerState<AdminLockGate> {
  /// The session was open at least once while this gate was on screen:
  /// [AdminLockGate.child] exists and is kept.
  bool _built = false;

  @override
  void initState() {
    super.initState();
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
  }

  @override
  void dispose() {
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    super.dispose();
  }

  void _onPointer(PointerEvent event) {
    if (event is! PointerDownEvent || !mounted) return;
    // Does nothing while the session is locked (or the setting is off).
    ref.read(adminUnlockedProvider.notifier).touch();
  }

  /// The session just locked: close what was opened from this screen.
  void _closeWhatIsOnTop() {
    FocusManager.instance.primaryFocus?.unfocus();
    if (ref.read(adminRequirePinProvider).value != true) return;
    final route = ModalRoute.of(context);
    if (route == null || !route.isActive || route.isCurrent) return;
    Navigator.of(context).popUntil((candidate) => candidate == route);
  }

  @override
  Widget build(BuildContext context) {
    final required = ref.watch(adminRequirePinProvider).value;
    final unlocked = ref.watch(adminUnlockedProvider);
    ref.listen(adminUnlockedProvider, (previous, next) {
      if (previous == true && !next && mounted) _closeWhatIsOnTop();
    });
    // Until the setting is read, nothing of the screen is shown.
    if (required == null) {
      return Scaffold(appBar: AppBar(title: Text(widget.title)));
    }
    final open = !required || unlocked;
    if (open) _built = true;

    // ONE shape of tree whatever the state, so [child] keeps its place —
    // and its state — when the door closes and opens again.
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_built)
          Offstage(
            offstage: !open,
            child: TickerMode(enabled: open, child: widget.child),
          )
        else
          const SizedBox.shrink(),
        if (!open) _LockedScreen(title: widget.title),
      ],
    );
  }
}

class _LockedScreen extends StatelessWidget {
  const _LockedScreen({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lock_outline,
                size: 40,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(height: 12),
              Text(
                l10n.adminLockedMessage,
                key: const ValueKey('admin-locked'),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton.tonal(
                key: const ValueKey('admin-unlock'),
                onPressed: () => requireAdminAccess(context),
                child: Text(l10n.unlock),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Settings → Security → "PIN to open settings, archive and statistics"
/// (off by default).
///
/// Switching it ON makes sure a PIN exists first; switching it OFF asks for
/// the PIN — taking a lock off is exactly what the lock is for. Both are
/// written to the audit log.
class AdminRequirePinTile extends ConsumerWidget {
  const AdminRequirePinTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final on = ref.watch(adminRequirePinProvider).value ?? false;
    return SwitchListTile(
      key: const ValueKey('setting-admin-require-pin'),
      secondary: const Icon(Icons.admin_panel_settings_outlined),
      title: Text(l10n.adminRequirePinTitle),
      subtitle: Text(l10n.adminRequirePinSubtitle),
      value: on,
      onChanged: (value) async {
        final container = ProviderScope.containerOf(context, listen: false);
        final allowed = value
            ? await ensurePinIsSet(context, reason: l10n.adminRequirePinTitle)
            : await requirePin(context, reason: l10n.pinReasonAdminAccess);
        if (!allowed) return;
        await container
            .read(settingsRepositoryProvider)
            .setBool(SettingsKeys.adminRequirePin, value);
        await container
            .read(auditRepositoryProvider)
            .log(value ? AuditAction.adminLockOn : AuditAction.adminLockOff);
        // Whoever just set the lock (or entered the PIN to remove it) is
        // the one holding the key — and is standing inside Settings.
        container.read(adminUnlockedProvider.notifier).unlock();
        container
          ..invalidate(adminRequirePinProvider)
          ..invalidate(auditLogProvider);
      },
    );
  }
}
