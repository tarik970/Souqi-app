import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';

import '../../core/providers.dart';
import '../../core/utils/bidi.dart';
import '../../core/utils/due_dates.dart';
import '../../core/utils/normalize.dart';
import '../../core/widgets/numeric_input.dart';
import '../../domain/models/customer.dart';
import '../../domain/models/product.dart';
import '../../l10n/generated/app_localizations.dart';
import 'customers_providers.dart';

/// "This number is already registered": lists who has it and asks whether
/// to save anyway. A warning, never a block — two people can share a line,
/// and a card can change hands.
Future<bool> confirmDuplicateAccount(
  BuildContext context, {
  required String accountNumber,
  required List<AccountDuplicate> duplicates,
}) async {
  final l10n = AppLocalizations.of(context);
  // The list comma of the app's language.
  final names = duplicates
      .map((d) => d.customerName)
      .toSet()
      .join(l10n.localeName == 'ar' ? '، ' : ', ');
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: const ValueKey('account-duplicate-dialog'),
      // Scrolls: with the keyboard still up on a small phone the message
      // and the buttons do not both fit.
      scrollable: true,
      title: Text(l10n.accountDuplicateTitle),
      content: Text(
        l10n.accountDuplicateMessage(ltrIsolate(accountNumber.trim()), names),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const ValueKey('account-duplicate-save'),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.saveAnyway),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// The provider field: free text, with the providers typed before offered
/// as one-tap chips under it, narrowed by what has been typed so far.
///
/// Chips in the page rather than a floating list: nothing to fall off a
/// small screen or to hide under the keyboard.
class ProviderField extends ConsumerWidget {
  const ProviderField({super.key, required this.controller});

  /// Owned by the form that shows this field.
  final TextEditingController controller;

  static const int _maxSuggestions = 6;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final known = ref.watch(providerSuggestionsProvider).value ?? const [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          key: const ValueKey('account-provider-field'),
          controller: controller,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(labelText: l10n.accountProviderLabel),
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) {
            final typed = normalizeName(value.text);
            final matches = [
              for (final provider in known)
                if (normalizeName(provider) != typed &&
                    normalizeName(provider).contains(typed))
                  provider,
            ].take(_maxSuggestions).toList();
            if (matches.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(
                spacing: 8,
                children: [
                  for (final provider in matches)
                    ActionChip(
                      key: ValueKey('provider-suggestion-$provider'),
                      label: Text(provider),
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        controller.value = TextEditingValue(
                          text: provider,
                          selection:
                              TextSelection.collapsed(offset: provider.length),
                        );
                      },
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

/// Add or edit one card / account of a customer.
class AccountFormScreen extends ConsumerStatefulWidget {
  const AccountFormScreen({super.key, required this.customerId, this.account});

  final int customerId;

  /// Null when adding.
  final CustomerAccount? account;

  @override
  ConsumerState<AccountFormScreen> createState() => _AccountFormScreenState();
}

class _AccountFormScreenState extends ConsumerState<AccountFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _number;
  late final TextEditingController _label;
  late final TextEditingController _provider;
  late final TextEditingController _days;
  late final TextEditingController _notes;

  int? _packageId;
  DateTime? _lastRenewal;
  DateTime? _nextDue;
  late bool _active;
  bool _saving = false;

  CustomerAccount? get _initial => widget.account;

  @override
  void initState() {
    super.initState();
    final a = _initial;
    _number = TextEditingController(text: a?.accountNumber ?? '');
    _label = TextEditingController(text: a?.label ?? '');
    _provider = TextEditingController(text: a?.provider ?? '');
    _days = TextEditingController(text: a?.renewalDays?.toString() ?? '');
    _notes = TextEditingController(text: a?.notes ?? '');
    _packageId = a?.defaultProductId;
    _lastRenewal = a?.lastRenewalAt?.toLocal();
    _nextDue = a?.nextDueAt?.toLocal();
    _active = a?.isActive ?? true;
  }

  @override
  void dispose() {
    _number.dispose();
    _label.dispose();
    _provider.dispose();
    _days.dispose();
    _notes.dispose();
    super.dispose();
  }

  /// The renewal period as typed: null when empty, -1 when not a positive
  /// whole number.
  int? get _renewalDays {
    final text = normalizeDigits(_days.text.trim());
    if (text.isEmpty) return null;
    final days = int.tryParse(text);
    return days == null || days <= 0 ? -1 : days;
  }

  /// Next due = last renewal + period, whenever both are known. Called when
  /// either of them changes; a due date picked by hand stays until then.
  void _recomputeDue() {
    final days = _renewalDays;
    final last = _lastRenewal;
    if (last == null || days == null || days <= 0) return;
    _nextDue = nextDueAfter(last, days);
  }

  Future<void> _pickDate({
    required DateTime? current,
    required ValueChanged<DateTime> onPicked,
  }) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 10),
    );
    if (picked == null || !mounted) return;
    setState(() => onPicked(picked));
  }

  bool _inSave = false;

  /// One save at a time. The claim is made BEFORE the first await: the
  /// form's own "saving" flag is only set after the duplicate check has
  /// read the database, and a second tap in that gap would save twice.
  Future<void> _save() async {
    if (_inSave) return;
    _inSave = true;
    try {
      await _saveOnce();
    } finally {
      _inSave = false;
    }
  }

  Future<void> _saveOnce() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    final navigator = Navigator.of(context);
    // The lists are refreshed through the container: the save must show up
    // even if this page was closed while it ran.
    final container = ProviderScope.containerOf(context, listen: false);
    final repository = ref.read(customerRepositoryProvider);
    final number = _number.text.trim();
    final provider = _provider.text.trim();

    final duplicates = await repository.findDuplicateAccounts(
      number,
      provider: provider,
      excludeId: _initial?.id,
    );
    if (!mounted) return;
    if (duplicates.isNotEmpty) {
      final proceed = await confirmDuplicateAccount(
        context,
        accountNumber: number,
        duplicates: duplicates,
      );
      if (!proceed || !mounted) return;
    }

    setState(() => _saving = true);
    final days = _renewalDays;
    final account = CustomerAccount(
      id: _initial?.id,
      customerId: widget.customerId,
      accountNumber: number,
      label: _label.text,
      provider: provider,
      defaultProductId: _packageId,
      renewalDays: days == null || days <= 0 ? null : days,
      lastRenewalAt: _lastRenewal,
      nextDueAt: _nextDue,
      notes: _notes.text,
      isActive: _active,
    );
    if (_initial == null) {
      await repository.insertAccount(account);
    } else {
      await repository.updateAccount(account);
    }
    refreshCustomerData(container);
    if (navigator.mounted) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = ref.watch(appLocaleProvider).languageCode;
    final packages = ref.watch(servicePackagesProvider).value ?? const [];
    final dates = DateFormat.yMd(locale);

    // The account's own package stays selectable even after the product was
    // deactivated: it is shown as it is until the shop picks another.
    final packageIds = {for (final p in packages) p.id};
    final orphan = _packageId != null && !packageIds.contains(_packageId);

    return Scaffold(
      appBar: AppBar(
        title: Text(_initial == null ? l10n.addAccount : l10n.editAccount),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              key: const ValueKey('account-number-field'),
              controller: _number,
              // Text, not a number: leading zeros and letters are kept.
              keyboardType: TextInputType.visiblePassword,
              autocorrect: false,
              textDirection: TextDirection.ltr,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(labelText: l10n.accountNumberLabel),
              validator: (v) => normalizeCode(v ?? '').isEmpty
                  ? l10n.fieldRequired
                  : null,
            ),
            const SizedBox(height: 12),
            ProviderField(controller: _provider),
            const SizedBox(height: 12),
            TextFormField(
              controller: _label,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(labelText: l10n.accountLabelLabel),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int?>(
              key: const ValueKey('account-package-field'),
              initialValue: _packageId,
              isExpanded: true,
              decoration: InputDecoration(labelText: l10n.accountPackageLabel),
              items: [
                DropdownMenuItem<int?>(child: Text(l10n.accountNoPackage)),
                if (orphan)
                  DropdownMenuItem<int?>(
                    value: _packageId,
                    child: Text(l10n.inactiveBadge),
                  ),
                for (final Product package in packages)
                  DropdownMenuItem<int?>(
                    value: package.id,
                    child: Text(
                      package.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) => setState(() => _packageId = value),
            ),
            const SizedBox(height: 12),
            SelectAllOnFocus(
              controller: _days,
              child: TextFormField(
                key: const ValueKey('account-days-field'),
                controller: _days,
                keyboardType: TextInputType.number,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  labelText: l10n.accountRenewalDaysLabel,
                  helperText: l10n.accountRenewalDaysHint,
                  helperMaxLines: 2,
                ),
                validator: (_) =>
                    _renewalDays == -1 ? l10n.invalidNumber : null,
                onChanged: (_) => setState(_recomputeDue),
              ),
            ),
            const SizedBox(height: 12),
            _DateRow(
              key: const ValueKey('account-last-renewal'),
              label: l10n.accountLastRenewalLabel,
              value: _lastRenewal == null ? null : dates.format(_lastRenewal!),
              emptyText: l10n.accountNotSet,
              clearTooltip: l10n.clearDate,
              onTap: () => _pickDate(
                current: _lastRenewal,
                onPicked: (day) {
                  _lastRenewal = day;
                  _recomputeDue();
                },
              ),
              onClear: () => setState(() => _lastRenewal = null),
            ),
            const SizedBox(height: 12),
            _DateRow(
              key: const ValueKey('account-next-due'),
              label: l10n.accountNextDueLabel,
              value: _nextDue == null ? null : dates.format(_nextDue!),
              emptyText: l10n.accountNotSet,
              helper: l10n.accountNextDueHint,
              clearTooltip: l10n.clearDate,
              onTap: () => _pickDate(
                current: _nextDue,
                onPicked: (day) => _nextDue = day,
              ),
              onClear: () => setState(() => _nextDue = null),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notes,
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(labelText: l10n.notesLabel),
            ),
            if (_initial != null)
              SwitchListTile(
                key: const ValueKey('account-active-switch'),
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.activeLabel),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
            const SizedBox(height: 24),
            FilledButton(
              key: const ValueKey('account-save'),
              onPressed: _saving ? null : _save,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(l10n.save),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A date shown like a form field: tap to pick, the small button clears it.
class _DateRow extends StatelessWidget {
  const _DateRow({
    super.key,
    required this.label,
    required this.value,
    required this.emptyText,
    required this.clearTooltip,
    required this.onTap,
    required this.onClear,
    this.helper,
  });

  final String label;
  final String? value;
  final String emptyText;
  final String clearTooltip;
  final String? helper;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          helperMaxLines: 2,
          suffixIcon: value == null
              ? const Icon(Icons.calendar_today, size: 20)
              : IconButton(
                  tooltip: clearTooltip,
                  icon: const Icon(Icons.close),
                  onPressed: onClear,
                ),
        ),
        child: Text(
          value ?? emptyText,
          style: value == null
              ? theme.textTheme.bodyLarge
                  ?.copyWith(color: theme.colorScheme.outline)
              : theme.textTheme.bodyLarge,
        ),
      ),
    );
  }
}
