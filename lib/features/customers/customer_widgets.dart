import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';

import '../../config/features.dart';
import '../../core/utils/bidi.dart';
import '../../core/utils/due_dates.dart';
import '../../domain/models/customer.dart';
import '../../l10n/generated/app_localizations.dart';

/// The due status in WORDS: "Overdue by 3 days", "Due today", "Due in 2
/// days", "OK". Null status (no due date) reads "No due date".
String dueStatusText(AppLocalizations l10n, DueStatus? status) {
  if (status == null) return l10n.dueNoDate;
  return switch (status.bucket) {
    DueBucket.overdue => l10n.dueOverdueBy(status.days),
    DueBucket.today => l10n.dueToday,
    DueBucket.soon => l10n.dueInDays(status.days),
    DueBucket.later => l10n.dueOk,
  };
}

/// The due status as an icon and words. Colour is only the third signal:
/// the words alone say everything, for a grey-scale screen or a
/// colour-blind seller.
class DueStatusLabel extends StatelessWidget {
  const DueStatusLabel({super.key, required this.status, this.dueDate});

  final DueStatus? status;

  /// Shown after the words ("OK · 12/25/2026") when given.
  final String? dueDate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (icon, color) = switch (status?.bucket) {
      DueBucket.overdue => (Icons.error_outline, scheme.error),
      DueBucket.today => (Icons.notifications_active_outlined, scheme.primary),
      DueBucket.soon => (Icons.schedule, scheme.primary),
      DueBucket.later => (Icons.check_circle_outline, scheme.outline),
      null => (Icons.remove_circle_outline, scheme.outline),
    };
    final words = dueStatusText(l10n, status);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            dueDate == null ? words : '$words · $dueDate',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

/// One row of the quick search, the due list and a customer's account list:
/// the customer's name, phone, the account (provider · number), its default
/// package, the last renewal date and the due status in words — with the
/// row's buttons underneath.
///
/// The buttons sit in a [Wrap] under the text rather than beside it, so on a
/// small phone at a large system font they move to a second line instead of
/// squeezing the text or overflowing.
class CustomerHitTile extends StatelessWidget {
  const CustomerHitTile({
    super.key,
    required this.hit,
    required this.now,
    required this.soonDays,
    required this.locale,
    this.onTap,
    this.actions = const [],
    this.showCustomer = true,
  });

  final CustomerHit hit;

  /// The moment the due status is judged at.
  final DateTime now;
  final int soonDays;

  /// The app language, for dates.
  final String locale;
  final VoidCallback? onTap;
  final List<Widget> actions;

  /// False on the customer's own page, where the name is the page title.
  final bool showCustomer;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final outline = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final customer = hit.customer;
    final account = accountsEnabled ? hit.account : null;
    final dates = DateFormat.yMd(locale);

    final accountLine = account == null
        ? null
        : [
            if (account.provider != null) account.provider!,
            ltrIsolate(account.accountNumber),
            if (account.label != null) account.label!,
          ].join(' · ');
    final details = account == null
        ? null
        : [
            if (hit.packageName != null) l10n.packageLabel(hit.packageName!),
            if (account.lastRenewalAt != null)
              l10n.lastRenewalLabel(
                dates.format(account.lastRenewalAt!.toLocal()),
              ),
          ].join(' · ');

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showCustomer)
              Text(
                customer.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            if (showCustomer && customer.hasPhone)
              Text(
                ltrIsolate(customer.phone!),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: outline,
              ),
            if (accountLine != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  accountLine,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: showCustomer
                      ? theme.textTheme.bodyMedium
                      : theme.textTheme.titleSmall,
                ),
              ),
            if (details != null && details.isNotEmpty)
              Text(
                details,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: outline,
              ),
            if (account != null) ...[
              const SizedBox(height: 4),
              if (!account.isActive)
                Text(l10n.inactiveBadge, style: outline)
              else
                DueStatusLabel(
                  status: account.dueStatus(now: now, soonDays: soonDays),
                  dueDate: account.nextDueAt == null
                      ? null
                      : dates.format(account.nextDueAt!.toLocal()),
                ),
            ],
            if (actions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    alignment: WrapAlignment.end,
                    children: actions,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A compact "Renew" button for a row.
class RenewButton extends StatelessWidget {
  const RenewButton({super.key, required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => FilledButton.tonalIcon(
        onPressed: onPressed,
        style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
        icon: const Icon(Icons.autorenew, size: 18),
        label: Text(AppLocalizations.of(context).renew),
      );
}
