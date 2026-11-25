import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/providers.dart';
import '../../domain/models/customer.dart';
import '../../l10n/generated/app_localizations.dart';
import 'customer_widgets.dart';
import 'customers_providers.dart';

/// The quick search box: one field for a customer's name, phone or card /
/// account number. The same field on the home screen and in the sale
/// screen's customer picker.
///
/// Stateless about its text: the screen owns the controller for its whole
/// life (see the dialog rules in the project notes).
class QuickSearchField extends StatelessWidget {
  const QuickSearchField({
    super.key,
    required this.controller,
    required this.onChanged,
    this.focusNode,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) => TextField(
        key: const ValueKey('quick-search-field'),
        controller: controller,
        focusNode: focusNode,
        autofocus: autofocus,
        textInputAction: TextInputAction.search,
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: l10n.quickSearchHint,
          prefixIcon: const Icon(Icons.person_search),
          suffixIcon: value.text.isEmpty
              ? null
              : IconButton(
                  key: const ValueKey('quick-search-clear'),
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          isDense: true,
        ),
      ),
    );
  }
}

/// The results of the quick search for [query]: one row per matching
/// account (or per customer without accounts), best match first.
///
/// While the next keystroke is being searched the previous results stay on
/// screen — every keystroke is a different query, and a spinner between
/// letters would make the list flicker.
class QuickSearchResults extends ConsumerStatefulWidget {
  const QuickSearchResults({
    super.key,
    required this.query,
    required this.onTap,
    this.actionsFor,
    this.leading = const [],
    this.padding = EdgeInsets.zero,
  });

  final String query;
  final ValueChanged<CustomerHit> onTap;

  /// The buttons under a row ("Renew"); none when null.
  final List<Widget> Function(CustomerHit hit)? actionsFor;

  /// Rows shown above the results whatever they are — the picker's
  /// "New customer …" rows.
  final List<Widget> leading;
  final EdgeInsets padding;

  @override
  ConsumerState<QuickSearchResults> createState() =>
      _QuickSearchResultsState();
}

class _QuickSearchResultsState extends ConsumerState<QuickSearchResults> {
  List<CustomerHit>? _last;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = ref.watch(appLocaleProvider).languageCode;
    final theme = Theme.of(context);
    final query = widget.query.trim();
    final found = ref.watch(quickSearchProvider(query));
    final soonDays = ref.watch(dueSoonDaysProvider).value ?? 3;
    final now = ref.watch(clockProvider)();

    if (found.hasValue) _last = found.value;
    final error = found.error;
    final hits = _last;
    final leading = widget.leading;

    if (error != null && !found.hasValue) {
      return Center(child: Text('$error'));
    }
    // Nothing yet (the very first search is still running): no spinner, the
    // answer is a few milliseconds away.
    if (hits == null) {
      return ListView(padding: widget.padding, children: leading);
    }

    return ListView.separated(
      padding: widget.padding,
      itemCount: leading.length + (hits.isEmpty ? 1 : hits.length),
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        if (index < leading.length) return leading[index];
        if (hits.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              l10n.quickSearchEmpty(query),
              key: const ValueKey('quick-search-empty'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          );
        }
        final hit = hits[index - leading.length];
        return CustomerHitTile(
          key: ValueKey(
            'quick-hit-${hit.customer.id}-${hit.account?.id ?? 0}',
          ),
          hit: hit,
          now: now,
          soonDays: soonDays,
          locale: locale,
          onTap: () => widget.onTap(hit),
          actions: widget.actionsFor?.call(hit) ?? const [],
        );
      },
    );
  }
}
