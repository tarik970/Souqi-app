import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../config/features.dart';
import '../../core/constants/settings_keys.dart';
import '../../core/providers.dart';
import '../../l10n/generated/app_localizations.dart';
import '../backup/backup_screen.dart';
import '../currencies/currencies_screen.dart';
import '../debts/debt_settings.dart';
import '../debts/report/debt_report_settings_screen.dart';
import '../invoice/invoice_settings_screen.dart';
import '../license/license_providers.dart';
import '../license/license_screen.dart';
import '../sale/sale_providers.dart';
import '../security/pin_session.dart';
import '../security/security_settings.dart';
import '../setup/setup_screen.dart';
import '../units/units_screen.dart';
import 'about_screen.dart';
import 'renewal_settings.dart';
import 'retention_tile.dart';

final shopTypeProvider = FutureProvider<String>(
  (ref) => ref.watch(settingsRepositoryProvider).getString(
        SettingsKeys.shopType,
      ),
);

/// Settings → "Activation": what the license of this phone is, and the way
/// to the activation screen (the request code, entering a code).
class LicenseSettingsTile extends ConsumerWidget {
  const LicenseSettingsTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final status = ref.watch(licenseProvider);
    final shop = status.shopName;
    final state = status.isLicensed
        ? l10n.licenseStatusLicensed
        : status.isTrial
            ? l10n.licenseStatusTrial
            : l10n.licenseStatusUnlicensed;
    return ListTile(
      key: const ValueKey('setting-license'),
      leading: Icon(
        status.isLicensed ? Icons.verified_outlined : Icons.vpn_key_outlined,
      ),
      title: Text(l10n.licenseTitle),
      subtitle: Text(shop == null ? state : '$state · $shop'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const LicenseScreen()),
      ),
    );
  }
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = ref.watch(appLocaleProvider);
    final shopType = ref.watch(shopTypeProvider).value ?? shopTypeGrocery;
    final sale = ref.watch(saleSettingsProvider).value ?? const SaleSettings();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.navSettings)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          // "No backup in the last 7 days": first thing on the page.
          const BackupReminderBanner(),
          const LicenseSettingsTile(),
          const Divider(),
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
            // UNDER the title and as wide as the tile, not a trailing
            // widget: "Cards & subscriptions" at a large system font is
            // wider than what a ListTile leaves beside its title, and it
            // overflowed on a phone. Expanded, the choice gets the whole
            // row and is cut with an ellipsis if even that is not enough.
            subtitle: DropdownButton<String>(
              key: const ValueKey('setting-shop-type-dropdown'),
              value: shopType,
              isExpanded: true,
              underline: const SizedBox.shrink(),
              items: [
                for (final (value, label) in [
                  (shopTypeGrocery, l10n.shopTypeGrocery),
                  (shopTypeCards, l10n.shopTypeCards),
                  (shopTypeBoth, l10n.shopTypeBoth),
                ])
                  DropdownMenuItem(
                    value: value,
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) async {
                if (value == null) return;
                final container =
                    ProviderScope.containerOf(context, listen: false);
                await ref
                    .read(settingsRepositoryProvider)
                    .setString(SettingsKeys.shopType, value);
                container.invalidate(shopTypeProvider);
              },
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              l10n.sectionSelling,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
          ),
          SwitchListTile(
            key: const ValueKey('setting-save-new-items'),
            secondary: const Icon(Icons.playlist_add),
            title: Text(l10n.settingSaveNewItems),
            subtitle: Text(l10n.settingSaveNewItemsHint),
            value: sale.saveNewItems,
            onChanged: (on) => ref
                .read(saleSettingsProvider.notifier)
                .change((s) => s.copyWith(saveNewItems: on)),
          ),
          SwitchListTile(
            key: const ValueKey('setting-update-prices'),
            secondary: const Icon(Icons.price_change_outlined),
            title: Text(l10n.settingUpdatePrices),
            subtitle: Text(l10n.settingUpdatePricesHint),
            value: sale.updatePrices,
            onChanged: (on) => ref
                .read(saleSettingsProvider.notifier)
                .change((s) => s.copyWith(updatePrices: on)),
          ),
          SwitchListTile(
            key: const ValueKey('setting-auto-favorites'),
            secondary: const Icon(Icons.auto_awesome_outlined),
            title: Text(l10n.settingAutoFavorites),
            subtitle: Text(l10n.settingAutoFavoritesHint),
            value: sale.autoFavorites,
            onChanged: (on) => ref
                .read(saleSettingsProvider.notifier)
                .change((s) => s.copyWith(autoFavorites: on)),
          ),
          SwitchListTile(
            key: const ValueKey('setting-cash-received'),
            secondary: const Icon(Icons.payments_outlined),
            title: Text(l10n.settingCashReceived),
            subtitle: Text(l10n.settingCashReceivedHint),
            value: sale.cashReceivedField,
            onChanged: (on) => ref
                .read(saleSettingsProvider.notifier)
                .change((s) => s.copyWith(cashReceivedField: on)),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.receipt_long),
            title: Text(l10n.invoiceSettingsTitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const InvoiceSettingsScreen()),
            ),
          ),
          if (featureOn(Feature.multiCurrency))
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              l10n.sectionArchive,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
          ),
          const RetentionTile(),
          const Divider(),
          if (featureOn(Feature.customers) && featureOn(Feature.accounts)) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                l10n.sectionCustomers,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
            ),
            const DueSoonDaysTile(),
            const ReminderTextTile(),
            const Divider(),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              l10n.sectionSecurity,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
          ),
          const RecoveryMissingBanner(),
          const PinSettingsTile(),
          const AuditLogTile(),
          const PinAutoLockTile(),
          const Divider(),
          if (featureOn(Feature.backup)) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                l10n.backupSection,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
            ),
            const BackupSettingsTile(),
            const Divider(),
          ],
          if (featureOn(Feature.debt)) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                l10n.debtSettingsSection,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
            ),
            const DebtDueDaysTile(),
            const DebtRequirePinTile(),
            const DebtReminderTile(),
            const DebtReportTile(),
            const OpeningBalancesTile(),
            const Divider(),
          ],
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
