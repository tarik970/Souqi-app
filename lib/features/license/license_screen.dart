import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../config/features.dart';
import '../../config/support.dart';
import '../../core/licensing/license_codec.dart';
import '../../core/licensing/license_status.dart';
import '../../core/money/money_format.dart';
import '../../core/platform/native_bridge.dart';
import '../../core/providers.dart';
import '../../l10n/generated/app_localizations.dart';
import '../customers/contact_actions.dart';
import '../invoice/invoice_providers.dart';
import 'license_providers.dart';
import 'license_text.dart';

/// THE ACTIVATION SCREEN: what the license of this phone is, the REQUEST
/// CODE the shop sends to the developer (Copy / Send on WhatsApp), and where
/// the ACTIVATION CODE that comes back is entered — pasted (spaces, dashes
/// and line breaks do not matter) or scanned as a QR code.
///
/// Reached from Settings at any time. An app that is NOT licensed opens on
/// it instead of the home screen ([gate]): it then also offers "Browse my
/// data" — the archive, the customers' balances, the backup and the daily
/// report stay open; only selling, printing and new debt entries are not.
///
/// Nothing here talks to a server: a code is checked on the phone, against
/// the developer's public key.
class LicenseScreen extends ConsumerStatefulWidget {
  const LicenseScreen({super.key, this.gate = false});

  /// Shown in place of the home screen of an unlicensed app.
  final bool gate;

  @override
  ConsumerState<LicenseScreen> createState() => _LicenseScreenState();
}

class _LicenseScreenState extends ConsumerState<LicenseScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  /// The shop a code was just accepted for (said until the app starts over).
  String? _activatedFor;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _copy(String requestCode) async {
    final l10n = AppLocalizations.of(context);
    await Clipboard.setData(ClipboardData(text: requestCode));
    _snack(l10n.licenseCopied);
  }

  /// The request code as a message, handed to WhatsApp: straight to the
  /// developer's chat when the app knows the number, otherwise WhatsApp
  /// asks which chat. Without WhatsApp: the share sheet.
  Future<void> _sendOnWhatsApp(String requestCode) async {
    final l10n = AppLocalizations.of(context);
    final bridge = ref.read(nativeBridgeProvider);
    final text = l10n.licenseRequestMessage(requestCode);
    var opened = false;
    try {
      final packages = await bridge.whatsAppPackages();
      if (!mounted) return;
      if (packages.isNotEmpty) {
        final package = packages.length == 1
            ? packages.single
            : await askWhatsAppPackage(context, packages);
        if (package == null) return;
        // Only a real number opens the developer's chat: while the constant
        // is empty or still a placeholder, the shop picks the chat itself.
        final developer = developerWhatsAppNumber;
        if (developer.isNotEmpty) {
          opened = await bridge.openWhatsAppChat(
            package: package,
            internationalPhone: developer,
            text: text,
          );
        }
        if (!opened) opened = await bridge.shareText(text, package: package);
      }
      if (!opened) opened = await bridge.shareText(text);
    } on OutputException {
      opened = false;
    }
    if (!opened) _snack(l10n.licenseShareFailed);
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (!mounted || text.isEmpty) return;
    setState(() {
      _code.text = text;
      _error = null;
    });
  }

  Future<void> _scan() async {
    final scanned = await ref.read(licenseScannerProvider)(context);
    if (!mounted || scanned == null || scanned.trim().isEmpty) return;
    setState(() {
      _code.text = scanned.trim();
      _error = null;
    });
    await _activate();
  }

  Future<void> _activate() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    final text = _code.text.trim();
    if (text.isEmpty) {
      setState(() => _error = l10n.licenseErrorMalformed);
      return;
    }
    // Taken before the first await: an accepted code restarts the app's
    // state, and this screen is gone by then.
    final container = ProviderScope.containerOf(context, listen: false);
    final restart = container.read(appRestartProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    final result =
        await container.read(licenseProvider.notifier).activate(text);
    final license = result.license;
    if (license == null) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = activationErrorText(l10n, result.error!);
      });
      return;
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _activatedFor = license.shopName;
        _code.clear();
      });
    }
    // The shop name on every paper is now the license's.
    container.invalidate(invoiceSettingsProvider);
    // Every screen is built again with what the license turns on and off.
    await restart(
      container.read(databaseProvider),
      AppRestartNotice.activated,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final status = ref.watch(licenseProvider);
    final requestCode = ref.watch(requestCodeProvider);
    final activatedFor = _activatedFor;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.licenseTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _StatusCard(status: status),
          if (status.clockWentBack) ...[
            const SizedBox(height: 12),
            Card(
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  l10n.licenseClockWarning,
                  key: const ValueKey('license-clock-warning'),
                  style: TextStyle(color: theme.colorScheme.onErrorContainer),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.licenseRequestTitle,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  if (requestCode == null)
                    Text(
                      l10n.licenseRequestUnavailable,
                      key: const ValueKey('license-request-unavailable'),
                      style: TextStyle(color: theme.colorScheme.error),
                    )
                  else ...[
                    // Groups wrap between each other, never inside one; the
                    // code is left-to-right in both app languages.
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Wrap(
                        key: const ValueKey('license-request-code'),
                        alignment: WrapAlignment.center,
                        spacing: 12,
                        runSpacing: 4,
                        children: [
                          for (final group in requestCode.split('-'))
                            Text(
                              group,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                letterSpacing: 2,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.licenseRequestHint,
                      style: theme.textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        OutlinedButton.icon(
                          key: const ValueKey('license-copy'),
                          onPressed: () => _copy(requestCode),
                          icon: const Icon(Icons.copy, size: 18),
                          label: Text(l10n.licenseCopy),
                        ),
                        FilledButton.tonalIcon(
                          key: const ValueKey('license-whatsapp'),
                          onPressed: () => _sendOnWhatsApp(requestCode),
                          icon: const Icon(Icons.chat_outlined, size: 18),
                          label: Text(l10n.sendOnWhatsApp),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.licenseEnterTitle,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.licenseEnterHint,
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('license-code-field'),
                    controller: _code,
                    enabled: !_busy,
                    minLines: 3,
                    maxLines: 6,
                    autocorrect: false,
                    enableSuggestions: false,
                    textCapitalization: TextCapitalization.characters,
                    textDirection: TextDirection.ltr,
                    keyboardType: TextInputType.multiline,
                    style: const TextStyle(letterSpacing: 1),
                    onChanged: (_) {
                      if (_error != null) setState(() => _error = null);
                    },
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      errorText: _error,
                      errorMaxLines: 4,
                    ),
                  ),
                  if (activatedFor != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        l10n.licenseActivatedFor(activatedFor),
                        key: const ValueKey('license-activated'),
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      OutlinedButton.icon(
                        key: const ValueKey('license-paste'),
                        onPressed: _busy ? null : _paste,
                        icon: const Icon(Icons.content_paste, size: 18),
                        label: Text(l10n.licensePaste),
                      ),
                      OutlinedButton.icon(
                        key: const ValueKey('license-scan'),
                        onPressed: _busy ? null : _scan,
                        icon: const Icon(Icons.qr_code_scanner, size: 18),
                        label: Text(l10n.licenseScan),
                      ),
                      FilledButton.icon(
                        key: const ValueKey('license-activate'),
                        onPressed: _busy ? null : _activate,
                        icon: _busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.vpn_key_outlined, size: 18),
                        label: Text(l10n.licenseActivate),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (widget.gate) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              key: const ValueKey('license-browse'),
              onPressed: () =>
                  ref.read(browsingUnlicensedProvider.notifier).allow(),
              icon: const Icon(Icons.folder_open_outlined),
              label: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(l10n.licenseBrowse),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// What the license of this phone is, in a card.
class _StatusCard extends ConsumerWidget {
  const _StatusCard({required this.status});

  final LicenseStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = ref.watch(appLocaleProvider).languageCode;
    String number(int value) => formatMinor(value, decimals: 0, locale: locale);
    final now = ref.watch(licenseServiceProvider)?.now ?? DateTime.now();
    final license = status.license;
    final expires = license?.expiresAt;

    final (icon, color, title) = switch (status.mode) {
      LicenseMode.licensed => (
          Icons.verified_outlined,
          theme.colorScheme.primary,
          l10n.licenseStatusLicensed,
        ),
      LicenseMode.trial => (
          Icons.hourglass_bottom,
          theme.colorScheme.secondary,
          l10n.licenseStatusTrial,
        ),
      LicenseMode.unlicensed => (
          Icons.lock_outline,
          theme.colorScheme.error,
          l10n.licenseStatusUnlicensed,
        ),
    };

    return Card(
      key: ValueKey('license-status-${status.mode.name}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleLarge?.copyWith(color: color),
                  ),
                ),
              ],
            ),
            if (status.isTrial) ...[
              const SizedBox(height: 8),
              Text(
                l10n.licenseTrialLeft(
                  number(status.trialDaysLeft(now)),
                  number(status.trialInvoicesLeft ?? 0),
                ),
                key: const ValueKey('license-trial-left'),
              ),
            ],
            if (status.isUnlicensed) ...[
              const SizedBox(height: 8),
              Text(
                unlicensedReasonText(l10n, status, locale),
                key: const ValueKey('license-reason'),
                style: TextStyle(color: theme.colorScheme.error),
              ),
              const SizedBox(height: 8),
              Text(l10n.licenseLockedNote, style: theme.textTheme.bodySmall),
            ],
            if (license != null) ...[
              const SizedBox(height: 8),
              Text(
                l10n.licenseShopLine(license.shopName),
                key: const ValueKey('license-shop'),
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                expires == null
                    ? l10n.licenseLifetime
                    : l10n.licenseExpiresLine(licenseDate(expires, locale)),
                key: const ValueKey('license-validity'),
              ),
              Text(
                l10n.licenseIdLine('${license.licenseId}'),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Text(l10n.licenseFeaturesLabel, style: theme.textTheme.bodySmall),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final feature in Feature.values)
                    if (license.features & licenseFeatureBits[feature.wire]! !=
                            0 &&
                        feature.compiledIn)
                      Chip(
                        key: ValueKey('license-feature-${feature.wire}'),
                        label: Text(featureLabel(l10n, feature)),
                        visualDensity: VisualDensity.compact,
                      ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
