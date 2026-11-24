import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/constants/settings_keys.dart';
import '../../core/providers.dart';
import '../../domain/models/invoice_settings.dart';
import '../../l10n/generated/app_localizations.dart';
import '../invoice/invoice_providers.dart';

const shopTypeGrocery = 'GROCERY';
const shopTypeCards = 'CARDS';
const shopTypeBoth = 'BOTH';

/// First-launch screen: choose the app language, the shop type and whether
/// the shop has a receipt printer (which sets the invoice output mode:
/// Print, or Share for shops without one). All three can be changed later.
class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  String _shopType = shopTypeGrocery;
  bool _hasPrinter = true;
  bool _saving = false;

  Future<void> _start() async {
    setState(() => _saving = true);
    final settings = ref.read(settingsRepositoryProvider);
    await settings.setString(SettingsKeys.shopType, _shopType);
    await settings.setString(
      SettingsKeys.outputMode,
      (_hasPrinter ? OutputMode.print : OutputMode.share).db,
    );
    // The invoice settings may already be loaded; make them re-read.
    ref.invalidate(invoiceSettingsProvider);
    await settings.setBool(SettingsKeys.setupDone, true);
    ref.read(setupDoneProvider.notifier).complete();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = ref.watch(appLocaleProvider);
    final theme = Theme.of(context);

    final shopTypes = <(String, String, IconData)>[
      (shopTypeGrocery, l10n.shopTypeGrocery, Icons.storefront),
      (shopTypeCards, l10n.shopTypeCards, Icons.sim_card),
      (shopTypeBoth, l10n.shopTypeBoth, Icons.all_inclusive),
    ];

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 24),
            // Brand rule: the logo appears on cream/white surfaces only.
            Image.asset('assets/branding/souqi_logo.png', height: 160),
            const SizedBox(height: 16),
            Text(
              l10n.setupWelcome,
              style: theme.textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.setupIntro,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            Text(l10n.setupLanguage, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'ar', label: Text(l10n.languageArabic)),
                ButtonSegment(value: 'en', label: Text(l10n.languageEnglish)),
              ],
              selected: {locale.languageCode},
              onSelectionChanged: (selection) {
                ref.read(appLocaleProvider.notifier).set(Locale(selection.first));
              },
            ),
            const SizedBox(height: 24),
            Text(l10n.setupShopType, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final (value, label, icon) in shopTypes)
              Card(
                child: ListTile(
                  leading: Icon(icon),
                  title: Text(label),
                  trailing: _shopType == value
                      ? Icon(Icons.check_circle,
                          color: theme.colorScheme.primary)
                      : null,
                  selected: _shopType == value,
                  onTap: () => setState(() => _shopType = value),
                ),
              ),
            const SizedBox(height: 24),
            Text(l10n.setupPrinterQuestion, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final (value, label, icon) in [
              (true, l10n.setupPrinterYes, Icons.print),
              (false, l10n.setupPrinterNo, Icons.share),
            ])
              Card(
                child: ListTile(
                  key: ValueKey('setup-printer-$value'),
                  leading: Icon(icon),
                  title: Text(label),
                  trailing: _hasPrinter == value
                      ? Icon(Icons.check_circle,
                          color: theme.colorScheme.primary)
                      : null,
                  selected: _hasPrinter == value,
                  onTap: () => setState(() => _hasPrinter = value),
                ),
              ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: _saving ? null : _start,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(l10n.setupStart),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
