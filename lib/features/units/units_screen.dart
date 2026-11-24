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

  Future<void> _showForm(
      BuildContext context, WidgetRef ref, Unit? unit) async {
    final l10n = AppLocalizations.of(context);
    final controller =
        TextEditingController(text: unit?.nameFor('en') ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(unit == null ? l10n.addUnit : l10n.editUnit),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: l10n.unitName),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(controller.text.trim()),
            child: Text(l10n.save),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final repo = ref.read(unitRepositoryProvider);
    if (unit == null) {
      await repo.insertCustom(name);
    } else {
      await repo.updateCustom(unit.id!, name);
    }
    ref.invalidate(unitsProvider);
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, Unit unit) async {
    final l10n = AppLocalizations.of(context);
    final locale = ref.read(appLocaleProvider).languageCode;
    final messenger = ScaffoldMessenger.of(context);
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
      await ref.read(unitRepositoryProvider).deleteCustom(unit.id!);
      ref.invalidate(unitsProvider);
    } on UnitInUseException catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.unitInUse(e.productCount))),
      );
    }
  }
}
