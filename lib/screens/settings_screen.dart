import 'package:calcwise_core/calcwise_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/freemium/freemium_service.dart';
import '../core/freemium/iap_service.dart';
import '../core/theme/app_theme.dart';
import '../l10n/strings_en.dart';
import '../main.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ct = CalcwiseTheme.of(context);
    return Scaffold(
      backgroundColor: ct.surface,
      appBar: AppBar(
        backgroundColor: ct.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: ct.textSecondary,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppRadius.mdPlus),
              border:
                  Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
            ),
            child: const Icon(Icons.settings_rounded,
                color: AppTheme.primary, size: 18),
          ),
          const SizedBox(width: AppSpacing.smPlus),
          Text(
            AppStringsEN.settings,
            style: TextStyle(
              color: ct.textPrimary,
              fontSize: AppTextSize.bodyXl,
              fontWeight: FontWeight.w700,
            ),
          ),
        ]),
      ),
      body: ListView(
        children: [
          // ── Premium ─────────────────────────────────────────────────────
          _SectionHeader(AppStringsEN.premium),
          ValueListenableBuilder<bool>(
            valueListenable: freemiumService.isPremiumNotifier,
            builder: (context, isPremium, _) {
              if (isPremium) {
                return ListTile(
                  leading: const Icon(Icons.verified_rounded,
                      color: AppTheme.accent),
                  title: Text(AppStringsEN.premiumActive,
                      style: TextStyle(color: ct.textPrimary)),
                  subtitle: Text(AppStringsEN.premiumDesc,
                      style: TextStyle(color: ct.textSecondary)),
                );
              }
              return Column(mainAxisSize: MainAxisSize.min, children: [
                ListTile(
                  leading:
                      const Icon(Icons.star_outline, color: AppTheme.primary),
                  title: Text(AppStringsEN.getPremium,
                      style: TextStyle(color: ct.textPrimary)),
                  subtitle: Text(AppStringsEN.premiumDesc,
                      style: TextStyle(color: ct.textSecondary)),
                  trailing: Icon(Icons.chevron_right_rounded,
                      color: ct.textSecondary),
                  onTap: () => IAPService.instance.buy(),
                ),
                ListTile(
                  leading: const Icon(Icons.restore, color: AppTheme.primary),
                  title: Text(AppStringsEN.restorePurchase,
                      style: TextStyle(color: ct.textPrimary)),
                  onTap: () => IAPService.instance.restore(),
                ),
                if (kDebugMode)
                  ListTile(
                    leading: const Icon(Icons.bug_report,
                        color: AppTheme.warningOrange),
                    title: Text('Force Premium (DEV)',
                        style: TextStyle(color: ct.textPrimary)),
                    onTap: () => freemiumService.debugUnlockPremium(),
                  ),
              ]);
            },
          ),

          const Divider(),

          // ── Appearance ──────────────────────────────────────────────────
          _SectionHeader('Appearance'),
          ValueListenableBuilder<ThemeMode>(
            valueListenable: themeModeService.notifier,
            builder: (context, mode, _) => ListTile(
              leading: const Icon(Icons.brightness_6_rounded,
                  color: AppTheme.primary),
              title: Text('Theme', style: TextStyle(color: ct.textPrimary)),
              subtitle: Text(
                mode == ThemeMode.dark
                    ? 'Dark'
                    : mode == ThemeMode.light
                        ? 'Light'
                        : 'System default',
                style: TextStyle(color: ct.textSecondary),
              ),
              trailing: DropdownButton<ThemeMode>(
                value: mode,
                underline: const SizedBox.shrink(),
                dropdownColor: ct.surfaceHigh,
                items: [
                  DropdownMenuItem(
                    value: ThemeMode.system,
                    child:
                        Text('Auto', style: TextStyle(color: ct.textPrimary)),
                  ),
                  DropdownMenuItem(
                    value: ThemeMode.light,
                    child:
                        Text('Light', style: TextStyle(color: ct.textPrimary)),
                  ),
                  DropdownMenuItem(
                    value: ThemeMode.dark,
                    child:
                        Text('Dark', style: TextStyle(color: ct.textPrimary)),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) themeModeService.set(v);
                },
              ),
            ),
          ),

          const Divider(),

          // ── Legal ────────────────────────────────────────────────────────
          _SectionHeader('Legal'),
          ListTile(
            leading:
                const Icon(Icons.info_outline_rounded, color: AppTheme.primary),
            title: Text('About', style: TextStyle(color: ct.textPrimary)),
            subtitle: Text(
              AppStringsEN.disclaimer,
              style: TextStyle(fontSize: 12, color: ct.textSecondary),
            ),
          ),
          ListTile(
            leading:
                const Icon(Icons.privacy_tip_outlined, color: AppTheme.primary),
            title: Text(AppStringsEN.privacyPolicy,
                style: TextStyle(color: ct.textPrimary)),
            trailing: Icon(Icons.open_in_new_rounded,
                color: ct.textSecondary, size: 16),
            onTap: () => _launch('https://calqwise.com/privacy'),
          ),
          ListTile(
            leading:
                const Icon(Icons.mail_outline_rounded, color: AppTheme.primary),
            title: Text(AppStringsEN.contactSupport,
                style: TextStyle(color: ct.textPrimary)),
            trailing: Icon(Icons.open_in_new_rounded,
                color: ct.textSecondary, size: 16),
            onTap: () =>
                _launch('mailto:support@calqwise.com?subject=TaxUK%20Support'),
          ),
          const SizedBox(height: AppSpacing.xxxl),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    final ct = CalcwiseTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.xs),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.0,
          color: ct.textSecondary,
        ),
      ),
    );
  }
}
