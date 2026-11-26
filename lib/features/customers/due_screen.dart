import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/widgets/load_error_view.dart';
import '../../core/money/money_format.dart';
import '../../core/providers.dart';
import '../../core/utils/due_dates.dart';
import '../../data/repositories/customer_repository.dart';
import '../../domain/models/customer.dart';
import '../../l10n/generated/app_localizations.dart';
import 'contact_actions.dart';
import 'customer_detail_screen.dart';
import 'customer_widgets.dart';
import 'customers_providers.dart';
import 'renewal.dart';

/// The buttons of one due row: one-tap Renew, and the WhatsApp reminder when
/// the customer has a phone number.
List<Widget> dueRowActions(BuildContext context, CustomerHit hit) {
  final l10n = AppLocalizations.of(context);
  return [
    if (hit.customer.hasPhone)
      OutlinedButton.icon(
        key: ValueKey('due-remind-${hit.account?.id}'),
        onPressed: () => sendRenewalReminder(context, hit),
        style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
        icon: const Icon(Icons.chat_outlined, size: 18),
        label: Text(l10n.sendReminder),
      ),
    RenewButton(
      key: ValueKey('due-renew-${hit.account?.id}'),
      onPressed: () => startRenewal(context, hit),
    ),
  ];
}

/// A section title of the due list ("Overdue (4)").
class DueSectionHeader extends StatelessWidget {
  const DueSectionHeader({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(text, style: theme.textTheme.titleSmall),
    );
  }
}

/// The due list as a flat list of widgets: a header per bucket that has
/// rows, then its rows, in due-date order. Shared by the "Due for renewal"
/// screen and by the home screen of a cards shop.
List<Widget> buildDueRows(
  BuildContext context, {
  required DueOverview overview,
  required String locale,
  required ValueChanged<CustomerHit> onTap,
}) {
  final l10n = AppLocalizations.of(context);
  String count(int value) => formatMinor(value, decimals: 0, locale: locale);

  String title(DueBucket bucket) => switch (bucket) {
        DueBucket.overdue => l10n.dueSectionOverdue(count(overview.counts.overdue)),
        DueBucket.today => l10n.dueSectionToday(count(overview.counts.today)),
        _ => l10n.dueSectionSoon(
            overview.soonDays,
            count(overview.counts.soon),
          ),
      };

  final rows = <Widget>[];
  DueBucket? current;
  for (final hit in overview.hits) {
    final bucket = hit.account
            ?.dueStatus(now: overview.now, soonDays: overview.soonDays)
            ?.bucket ??
        DueBucket.soon;
    if (bucket != current) {
      current = bucket;
      rows.add(DueSectionHeader(
        key: ValueKey('due-section-${bucket.name}'),
        text: title(bucket),
      ));
    } else {
      rows.add(const Divider(height: 1));
    }
    rows.add(CustomerHitTile(
      key: ValueKey('due-row-${hit.account?.id}'),
      hit: hit,
      now: overview.now,
      soonDays: overview.soonDays,
      locale: locale,
      onTap: () => onTap(hit),
      actions: dueRowActions(context, hit),
    ));
  }
  return rows;
}

/// "Due for renewal": overdue, due today and due in the next N days, the
/// longest overdue first. Each row has the phone number, a one-tap Renew
/// and a WhatsApp reminder.
class DueScreen extends ConsumerStatefulWidget {
  const DueScreen({super.key});

  @override
  ConsumerState<DueScreen> createState() => _DueScreenState();
}

class _DueScreenState extends ConsumerState<DueScreen> {
  int _limit = CustomerRepository.duePageSize;
  DueOverview? _last;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = ref.watch(appLocaleProvider).languageCode;
    final theme = Theme.of(context);
    // "Show more" is a new query: the rows already shown stay until it
    // answers.
    final loaded = ref.watch(dueOverviewProvider(_limit));
    if (loaded.hasValue) _last = loaded.value;
    final overview = _last;

    Widget body;
    if (overview == null) {
      body = loaded.hasError
          ? LoadErrorView(loaded.error!, loaded.stackTrace)
          : const SizedBox.shrink();
    } else if (overview.hits.isEmpty) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.event_available,
                  size: 56, color: theme.colorScheme.outline),
              const SizedBox(height: 12),
              Text(
                l10n.dueEmpty,
                key: const ValueKey('due-empty'),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
            ],
          ),
        ),
      );
    } else {
      body = ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          ...buildDueRows(
            context,
            overview: overview,
            locale: locale,
            onTap: (hit) => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    CustomerDetailScreen(customerId: hit.customer.id!),
              ),
            ),
          ),
          if (overview.hasMore)
            Padding(
              padding: const EdgeInsets.all(16),
              child: OutlinedButton(
                key: const ValueKey('due-more'),
                onPressed: () => setState(
                  () => _limit += CustomerRepository.duePageSize,
                ),
                child: Text(l10n.showMore),
              ),
            ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.navDue)),
      body: body,
    );
  }
}
