import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/providers.dart';
import '../../data/repositories/unit_repository.dart';
import '../../domain/models/unit.dart';
import '../../l10n/generated/app_localizations.dart';

class UnitsScreen extends ConsumerWidget {
  const UnitsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = ref.watch(appLocaleProvider).languageCode;
    final units = ref.watch(unitsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.unitsTitle)),
      body: units.when(
        data: (items) => ListView.builder(
          itemCount: items.length,
          itemBuilder: (context, index) {
            final unit = items[index];
            return ListTile(
              leading: const Icon(Icons.straighten),
              title: Text(unit.nameFor(locale)),
              subtitle: unit.isPreset ? Text(l10n.presetBadge) : null,
              trailing: unit.isPreset
                  ? null
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit),
                          tooltip: l10n.edit,
                          onPressed: () => _showForm(context, ref, unit),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: l10n.delete,
                          onPressed: () => _delete(context, ref, unit),
                        ),
                      ],
                    ),
            );
          },
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: () => _showForm(context, ref, null),
        icon: const Icon(Icons.add),
        label: Text(l10n.addUnit),
      ),
    );
  }

  // Both actions take the repository and the provider container before their
  // dialog opens, so nothing reads `ref` after an await.
  Future<void> _showForm(
      BuildContext context, WidgetRef ref, Unit? unit) async {
    final container = ProviderScope.containerOf(context, listen: false);
    final repo = ref.read(unitRepositoryProvider);
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _UnitNameDialog(unit: unit),
    );
    if (name == null || name.isEmpty) return;
    if (unit == null) {
      await repo.insertCustom(name);
    } else {
      await repo.updateCustom(unit.id!, name);
    }
    container.invalidate(unitsProvider);
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, Unit unit) async {
    final l10n = AppLocalizations.of(context);
    final locale = ref.read(appLocaleProvider).languageCode;
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    final repo = ref.read(unitRepositoryProvider);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteUnitTitle),
        content: Text(l10n.deleteUnitMessage(unit.nameFor(locale))),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await repo.deleteCustom(unit.id!);
      container.invalidate(unitsProvider);
    } on UnitInUseException catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.unitInUse(e.productCount))),
      );
    }
  }
}

/// Asks for the name of a custom unit. Pops with the trimmed name, or with
/// nothing when cancelled. Owns its text controller: it must outlive the
/// dialog's exit animation, so it is disposed with the dialog, not by the
/// caller.
class _UnitNameDialog extends StatefulWidget {
  const _UnitNameDialog({required this.unit});

  /// Null when adding a unit.
  final Unit? unit;

  @override
  State<_UnitNameDialog> createState() => _UnitNameDialogState();
}

class _UnitNameDialogState extends State<_UnitNameDialog> {
  late final _controller =
      TextEditingController(text: widget.unit?.nameFor('en') ?? '');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.unit == null ? l10n.addUnit : l10n.editUnit),
      content: TextField(
        controller: _controller,
        autofocus: true,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(labelText: l10n.unitName),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l10n.save)),
      ],
    );
  }
}
