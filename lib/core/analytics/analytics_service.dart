import 'package:calcwise_core/calcwise_core.dart';

/// Firebase Analytics wrapper for TaxUK.
/// Common events inherited from CalcwiseAnalytics.
/// TaxUK-specific events: VAT calc, income tax calc, Scottish toggle.
class AnalyticsService extends CalcwiseAnalytics {
  AnalyticsService._() : super(appName: 'TaxUK');
  static final AnalyticsService instance = AnalyticsService._();

  // ── VAT Calculator ────────────────────────────────────────────────────────

  Future<void> logVatCalculated({
    required double amount,
    required double rate,
    required bool isFromGross,
  }) =>
      log('vat_calculated', {
        'amount': amount.round(),
        'rate_pct': (rate * 100).round(),
        'from_gross': '$isFromGross',
      });

  // ── Income Tax Calculator ─────────────────────────────────────────────────

  Future<void> logIncomeTaxCalculated({
    required double grossIncome,
    required bool isScotland,
  }) =>
      log('income_tax_calculated', {
        'gross_income': grossIncome.round(),
        'is_scotland': '$isScotland',
      });

  Future<void> logScotlandToggled(bool isScotland) =>
      log('scotland_toggled', {'enabled': '$isScotland'});

  // ── Universal events ──────────────────────────────────────────────────────

  Future<void> logSave() => log('calculation_saved');
  Future<void> logTabSwitch(int i) => log('tab_switched', {'tab_index': i});
  Future<void> logShareResult() => log('share_result');
  Future<void> logResultSaved() => log('result_saved');
  Future<void> logResultShared() => log('result_shared');
  Future<void> logFeatureGated(String feature) =>
      log('feature_gated', {'feature': feature});
  Future<void> logScreenView(String screenName) =>
      log('screen_view', {'screen_name': screenName});
  Future<void> logOnboardingComplete() => log('onboarding_complete');
  Future<void> logOnboardingSkipped() => log('onboarding_skipped');
  Future<void> logFirstCalculate() => log('first_calculate');
  Future<void> logDarkModeToggled(bool enabled) =>
      log('dark_mode_toggled', {'enabled': '$enabled'});
  Future<void> logShareTapped() => log('share_tapped');
  Future<void> logExportStarted() => log('export_started');
  Future<void> logUpgradeButtonTapped(String source) =>
      log('upgrade_tapped', {'source': source});
  Future<void> logPaywallSoftShown() => log('paywall_soft_shown');
  Future<void> logPaywallHardShown() => log('paywall_hard_shown');
  Future<void> logPaywallBuyTapped() => log('paywall_buy_tapped');
  Future<void> logPurchaseSuccess() => log('iap_purchase_success');
  Future<void> logPurchaseError(String r) =>
      log('iap_purchase_error', {'reason': r});
  Future<void> logRewardedVideoWatched() => log('rewarded_video_watched');
  Future<void> logPaywallViewed(String trigger) =>
      log('paywall_viewed', {'trigger': trigger});
  Future<void> logPaywallConverted(String source) =>
      log('paywall_converted', {'source': source});
  Future<void> logCalculationCompleted({Map<String, Object>? params}) =>
      log('calculation_completed', params);
}

final analyticsService = AnalyticsService.instance;
