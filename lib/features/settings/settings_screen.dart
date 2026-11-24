import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/constants/settings_keys.dart';
import '../../core/providers.dart';
import '../../l10n/generated/app_localizations.dart';
import '../currencies/currencies_screen.dart';
import '../setup/setup_screen.dart';
import '../units/units_screen.dart';
import 'about_screen.dart';

final shopTypeProvider = FutureProvider<String>(
  (ref) => ref.watch(settingsRepositoryProvider).getString(
        SettingsKeys.shopType,
      ),
);

final showPoweredByProvider = FutureProvider<bool>(
  (ref) => ref.watch(settingsRepositoryProvider).getBool(
        SettingsKeys.showPoweredBy,
      ),
);

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = ref.watch(appLocaleProvider);
    final shopType = ref.watch(shopTypeProvider).value ?? shopTypeGrocery;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.navSettings)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          ListTile(
            leading: const Icon(Icons.language),
            title: Text(l10n.setupLanguage),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'ar', label: Text(l10n.languageArabic)),
                ButtonSegment(value: 'en', label: Text(l10n.languageEnglish)),
              ],
              selected: {locale.languageCode},
              onSelectionChanged: (selection) {
                ref
                    .read(appLocaleProvider.notifier)
                    .set(Locale(selection.first));
              },
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.store),
            title: Text(l10n.setupShopType),
            trailing: DropdownButton<String>(
              value: shopType,
              underline: const SizedBox.shrink(),
              items: [
                DropdownMenuItem(
                    value: shopTypeGrocery, child: Text(l10n.shopTypeGrocery)),
                DropdownMenuItem(
                    value: shopTypeCards, child: Text(l10n.shopTypeCards)),
                DropdownMenuItem(
                    value: shopTypeBoth, child: Text(l10n.shopTypeBoth)),
              ],
              onChanged: (value) async {
                if (value == null) return;
                await ref
                    .read(settingsRepositoryProvider)
                    .setString(SettingsKeys.shopType, value);
                ref.invalidate(shopTypeProvider);
              },
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.currency_exchange),
            title: Text(l10n.settingsCurrencies),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CurrenciesScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.straighten),
            title: Text(l10n.unitsTitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const UnitsScreen()),
            ),
          ),
          const Divider(),
          SwitchListTile(
            secondary: const Icon(Icons.receipt),
            title: Text(l10n.showPoweredBy),
            value: ref.watch(showPoweredByProvider).value ?? true,
            onChanged: (value) async {
              await ref
                  .read(settingsRepositoryProvider)
                  .setBool(SettingsKeys.showPoweredBy, value);
              ref.invalidate(showPoweredByProvider);
            },
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(l10n.aboutTitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AboutScreen()),
            ),
          ),
        ],
      ),
    );
  }
}
