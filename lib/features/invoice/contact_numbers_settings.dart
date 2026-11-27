import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/utils/normalize.dart';
import '../../domain/models/invoice_extras.dart';
import '../../domain/models/invoice_settings.dart';
import '../../l10n/generated/app_localizations.dart';
import 'invoice_providers.dart';
import 'settings_parts.dart';

/// Invoice settings → "Contact numbers": up to [InvoiceContact.max] lines of
/// "name: phone" printed under the header or above the footer of every
/// paper.
class ContactNumbersSection extends ConsumerWidget {
  const ContactNumbersSection({super.key});

  void _change(
    WidgetRef ref,
    InvoiceSettings Function(InvoiceSettings s) update,
  ) =>
      ref.read(invoiceSettingsProvider.notifier).change(update);

  Future<void> _edit(BuildContext context, WidgetRef ref, int? index) async {
    final notifier = ref.read(invoiceSettingsProvider.notifier);
    final current = ref.read(invoiceSettingsProvider).requireValue.contacts;
    final contact = await showDialog<InvoiceContact>(
      context: context,
      builder: (_) =>
          ContactEditDialog(initial: index == null ? null : current[index]),
    );
    if (contact == null) return;
    // Applied to the list as it is now, not as it was when the dialog opened.
    await notifier.change((s) {
      final list = [...s.contacts];
      if (index == null) {
        if (list.length >= InvoiceContact.max) return s;
        list.add(contact);
      } else if (index < list.length) {
        list[index] = contact;
      }
      return s.copyWith(contacts: list);
    });
  }

  void _move(WidgetRef ref, int index, int by) => _change(ref, (s) {
        final list = [...s.contacts];
        final to = index + by;
        if (index < 0 || index >= list.length || to < 0 || to >= list.length) {
          return s;
        }
        final item = list.removeAt(index);
        list.insert(to, item);
        return s.copyWith(contacts: list);
      });

  void _delete(WidgetRef ref, int index) => _change(ref, (s) {
        if (index >= s.contacts.length) return s;
        return s.copyWith(contacts: [...s.contacts]..removeAt(index));
      });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final s = ref.watch(invoiceSettingsProvider).requireValue;
    final contacts = s.contacts;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSectionTitle(l10n.contactsSection),
        SwitchListTile(
          key: const ValueKey('contacts-switch'),
          title: Text(l10n.contactsSwitch),
          subtitle: Text(l10n.contactsHint),
          value: s.showContacts,
          onChanged: (value) =>
              _change(ref, (s) => s.copyWith(showContacts: value)),
        ),
        if (s.showContacts) ...[
          if (contacts.isEmpty) SettingsHint(l10n.contactsEmpty),
          for (var i = 0; i < contacts.length; i++)
            ListTile(
              key: ValueKey('contact-$i'),
              leading: const Icon(Icons.phone_outlined),
              title: Text(
                contacts[i].name.isEmpty ? contacts[i].phone : contacts[i].name,
              ),
              subtitle: contacts[i].name.isEmpty
                  ? null
                  : Text(contacts[i].phone, textDirection: TextDirection.ltr),
              onTap: () => _edit(context, ref, i),
              trailing: PopupMenuButton<String>(
                key: ValueKey('contact-menu-$i'),
                onSelected: (action) => switch (action) {
                  'up' => _move(ref, i, -1),
                  'down' => _move(ref, i, 1),
                  'edit' => _edit(context, ref, i),
                  _ => _delete(ref, i),
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    key: ValueKey('contact-edit-$i'),
                    value: 'edit',
                    child: Text(l10n.edit),
                  ),
                  if (i > 0)
                    PopupMenuItem(
                      key: ValueKey('contact-up-$i'),
                      value: 'up',
                      child: Text(l10n.contactMoveUp),
                    ),
                  if (i < contacts.length - 1)
                    PopupMenuItem(
                      key: ValueKey('contact-down-$i'),
                      value: 'down',
                      child: Text(l10n.contactMoveDown),
                    ),
                  PopupMenuItem(
                    key: ValueKey('contact-delete-$i'),
                    value: 'delete',
                    child: Text(l10n.delete),
                  ),
                ],
              ),
            ),
          if (contacts.length < InvoiceContact.max)
            SettingsPadded(
              child: OutlinedButton.icon(
                key: const ValueKey('contact-add'),
                onPressed: () => _edit(context, ref, null),
                icon: const Icon(Icons.add),
                label: Text(l10n.contactsAdd),
              ),
            )
          else
            SettingsHint(l10n.contactsMax),
          SettingsPadded(child: Text(l10n.contactsPositionLabel)),
          RadioGroup<ContactsPosition>(
            groupValue: s.contactsPosition,
            onChanged: (value) {
              if (value != null) {
                _change(ref, (s) => s.copyWith(contactsPosition: value));
              }
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RadioListTile<ContactsPosition>(
                  key: const ValueKey('contacts-position-header'),
                  value: ContactsPosition.header,
                  title: Text(l10n.contactsPositionHeader),
                ),
                RadioListTile<ContactsPosition>(
                  key: const ValueKey('contacts-position-footer'),
                  value: ContactsPosition.footer,
                  title: Text(l10n.contactsPositionFooter),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// A phone number has at least this many digits.
const int minContactPhoneDigits = 3;

/// One contact line, added or edited. Owns its controllers; returns the
/// [InvoiceContact] through `Navigator.pop`. The phone is kept as typed —
/// Arabic-Indic digits too — and normalised only on the paper.
class ContactEditDialog extends StatefulWidget {
  const ContactEditDialog({super.key, this.initial});

  final InvoiceContact? initial;

  @override
  State<ContactEditDialog> createState() => _ContactEditDialogState();
}

class _ContactEditDialogState extends State<ContactEditDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.initial?.name ?? '');
  late final TextEditingController _phone =
      TextEditingController(text: widget.initial?.phone ?? '');
  bool _invalid = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _save() {
    final phone = _phone.text.trim();
    if (normalizePhone(phone).length < minContactPhoneDigits) {
      setState(() => _invalid = true);
      return;
    }
    Navigator.of(context).pop(
      InvoiceContact(name: _name.text.trim(), phone: phone),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      key: const ValueKey('contact-dialog'),
      scrollable: true,
      title: Text(
        widget.initial == null ? l10n.contactAddTitle : l10n.contactEditTitle,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const ValueKey('contact-name-field'),
            controller: _name,
            autofocus: true,
            maxLength: 40,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(labelText: l10n.contactNameLabel),
          ),
          TextField(
            key: const ValueKey('contact-phone-field'),
            controller: _phone,
            keyboardType: TextInputType.phone,
            textDirection: TextDirection.ltr,
            maxLength: 24,
            inputFormatters: [
              // Western, Arabic-Indic and Persian digits; spaces and the
              // signs a phone number is written with.
              FilteringTextInputFormatter.allow(RegExp(r'[0-9٠-٩۰-۹ +\-()]')),
            ],
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: l10n.contactPhoneLabel,
              errorText: _invalid ? l10n.contactPhoneInvalid : null,
            ),
            onChanged: (_) {
              if (_invalid) setState(() => _invalid = false);
            },
            onSubmitted: (_) => _save(),
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const ValueKey('contact-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const ValueKey('contact-save'),
          onPressed: _save,
          child: Text(l10n.save),
        ),
      ],
    );
  }
}
