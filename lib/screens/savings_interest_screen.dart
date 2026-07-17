import 'package:calcwise_core/calcwise_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../core/uk_tax_engine.dart';
import '../core/analytics/analytics_service.dart';
import '../core/freemium/freemium_service.dart';
import '../core/services/pdf_export_service.dart';
import '../core/theme/app_theme.dart';
import '../l10n/strings_en.dart';
import '../main.dart' show adService, analyticsService, paywallSession, smartHistoryService;
import '../widgets/paywall_hard.dart';
import '../widgets/paywall_soft.dart';
import '../widgets/save_scenario_button.dart';
import 'history_screen.dart';

class SavingsInterestScreen extends StatefulWidget {
  const SavingsInterestScreen({super.key});

  @override
  State<SavingsInterestScreen> createState() => _SavingsInterestScreenState();
}

class _SavingsInterestScreenState extends State<SavingsInterestScreen>
    with CalcwiseAutoCalcMixin {
  final _grossInterestCtrl = TextEditingController(text: '2000');
  final _otherIncomeCtrl = TextEditingController(text: '35000');
  final _fmtGbp = NumberFormat.currency(locale: 'en_GB', symbol: '£');

  SavingsInterestResult? _result;
  bool _isScotland = false;

  @override
  void initState() {
    super.initState();
    analyticsService.logScreenView('savings_interest');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _calculate();
    });
  }

  @override
  void dispose() {
    _grossInterestCtrl.dispose();
    _otherIncomeCtrl.dispose();
    smartHistoryService.cancelPendingSave('taxuk', 'savings_interest');
    super.dispose();
  }

  void _calculate() {
    analyticsService.maybeLogFirstCalculate();
    final grossInterest =
        double.tryParse(_grossInterestCtrl.text.replaceAll(',', '.').trim()) ??
            0;
    final otherIncome =
        double.tryParse(_otherIncomeCtrl.text.replaceAll(',', '.').trim()) ?? 0;
    if (grossInterest < 0 || otherIncome < 0) return;

    final result = calculateSavingsInterestTax(
      grossInterest: grossInterest,
      otherIncome: otherIncome,
      isScotland: _isScotland,
    );
    setState(() => _result = result);

    analyticsService.logCalculationCompleted(
      params: {
        'calc_type': 'savings_interest',
        'gross_interest': grossInterest.round(),
        'other_income': otherIncome.round(),
      },
    );
    adService.onAction();
    _scheduleAutoSave();
  }

  double _roundTo(double v, double step) => (v / step).round() * step;

  void _scheduleAutoSave() {
    final r = _result;
    if (r == null) return;
    if (r.grossInterest <= 0) return;
    final otherIncome = double.tryParse(_otherIncomeCtrl.text.replaceAll(',', '.').trim()) ?? 0;
    final inputHash = ResultHasher.hashMixed({
      'interest': _roundTo(r.grossInterest, 100),
      'other_income': _roundTo(otherIncome, 1000),
    });
    smartHistoryService.scheduleAutoSave(
      appKey: 'taxuk',
      screenId: 'savings_interest',
      inputHash: inputHash,
      l1: {
        'interest': r.grossInterest,
        'other_income': otherIncome,
        'psa_used': r.personalSavingsAllowance,
        'tax_on_savings': r.taxDue,
        'net_interest': r.grossInterest - r.taxDue,
      },
      l2: {
        'inputs': {
          'type': 'savings_interest',
          'interest': r.grossInterest,
          'otherIncome': otherIncome,
        },
        'results': {
          'psa': r.personalSavingsAllowance,
          'taxableSavings': r.taxableInterest,
          'tax': r.taxDue,
          'netInterest': r.grossInterest - r.taxDue,
        },
      },
      onSaved: () { if (mounted) HistoryScreen.refreshNotifier.value++; },
    );
  }

  Future<void> _saveScenario(String? label) async {
    final r = _result;
    if (r == null) return;
    final otherIncome = double.tryParse(_otherIncomeCtrl.text.replaceAll(',', '.').trim()) ?? 0;
    final inputHash = ResultHasher.hashMixed({
      'interest': _roundTo(r.grossInterest, 100),
      'other_income': _roundTo(otherIncome, 1000),
    });
    await smartHistoryService.saveScenario(
      appKey: 'taxuk',
      screenId: 'savings_interest',
      inputHash: inputHash,
      l1: {
        'interest': r.grossInterest,
        'other_income': otherIncome,
        'psa_used': r.personalSavingsAllowance,
        'tax_on_savings': r.taxDue,
        'net_interest': r.grossInterest - r.taxDue,
      },
      l2: {
        'inputs': {
          'type': 'savings_interest',
          'interest': r.grossInterest,
          'otherIncome': otherIncome,
        },
        'results': {
          'psa': r.personalSavingsAllowance,
          'taxableSavings': r.taxableInterest,
          'tax': r.taxDue,
          'netInterest': r.grossInterest - r.taxDue,
        },
      },
      label: label,
    );
    HistoryScreen.refreshNotifier.value++;
    try { analyticsService.logSave(); } catch (_) {}
    analyticsService.logResultSaved();
    adService.onSave();
    final trigger = await paywallSession.recordAction();
    if (!mounted) return;
    if (trigger == PaywallTrigger.soft) PaywallSoft.show(context);
    if (trigger == PaywallTrigger.hard) PaywallHard.show(context);
  }


  void _reset() {
    _grossInterestCtrl.text = '2000';
    _otherIncomeCtrl.text = '35000';
    setState(() => _result = null);
  }

  Future<void> _exportPdf() async {
    final r = _result;
    if (r == null) return;
    if (!freemiumService.hasFullAccess) {
      if (!mounted) return;
      await PaywallSoft.show(
        context,
        featureTitle: 'Export PDF',
        featureSubtitle: 'Upgrade to export and share your results as PDF.',
      );
      return;
    }
    if (!mounted) return;
    await TaxUkPdfExportService.exportSavingsInterest(
      context: context,
      grossInterest: r.grossInterest,
      otherIncome:
          double.tryParse(
            _otherIncomeCtrl.text.replaceAll(',', '.').trim(),
          ) ??
          0,
      personalSavingsAllowance: r.personalSavingsAllowance,
      taxableInterest: r.taxableInterest,
      taxDue: r.taxDue,
      band: r.band,
      effectiveRate: r.effectiveRate,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ct = CalcwiseTheme.of(context);
    final r = _result;

    return Scaffold(
      appBar: AppBar(title: const Text('Savings Interest')),
      body: Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.xxxl,
            ),
            children: [
              // ── Inputs ──────────────────────────────────────────────────────
              TextField(
                controller: _otherIncomeCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: false,
                ),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: AppStringsEN.otherIncome,
                  prefixText: '£',
                  hintText: '35000',
                  filled: true,
                ),
                onChanged: (_) => scheduleCalc(_calculate),
                onSubmitted: (_) => _calculate(),
              ),
              const SizedBox(height: AppSpacing.md),

              TextField(
                controller: _grossInterestCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: false,
                ),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: AppStringsEN.grossInterest,
                  prefixText: '£',
                  hintText: '2000',
                  filled: true,
                ),
                onChanged: (_) => scheduleCalc(_calculate),
                onSubmitted: (_) => _calculate(),
              ),
              const SizedBox(height: AppSpacing.xs),

              // Note
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(
                  'Personal Savings Allowance: £1,000 (Basic), £500 (Higher), £0 (Additional rate). '
                  'Starter rate relief applies if non-savings income is under £17,570.',
                  style: TextStyle(
                    fontSize: AppTextSize.sm,
                    color: ct.textSecondary,
                  ),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Scottish taxpayer'),
                subtitle: const Text('Uses Scottish income tax bands (Higher Rate: 42% from £43,662)'),
                value: _isScotland,
                onChanged: (v) {
                  setState(() => _isScotland = v);
                  _calculate();
                },
              ),
              const SizedBox(height: AppSpacing.lg),

              // ── Action buttons ───────────────────────────────────────────────
              Row(children: [
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      HapticFeedback.mediumImpact();
                      _calculate();
                    },
                    child: const Text('Calculate'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                OutlinedButton(
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    _reset();
                  },
                  child: const Text('Reset'),
                ),
              ]),

              // ── Results ─────────────────────────────────────────────────────
              if (r != null) ...[
                const SizedBox(height: AppSpacing.xl),
                CalcwisePageEntrance(
                  child: Column(children: [
                    CalcwiseStaggerItem(
                      index: 0,
                      child: CalcwiseHeroCard(
                        label: 'TAX DUE ON SAVINGS',
                        value: _fmtGbp.format(r.taxDue),
                        secondary:
                            '2026/27 rates · ${r.band} taxpayer',
                        rawValue: r.taxDue,
                        valueFormatter: (v) => AmountFormatter.ui(v, 'GBP'),
                        stats: [
                          (
                            label: 'Taxable Interest',
                            value: _fmtGbp.format(r.taxableInterest),
                          ),
                          (
                            label: 'PSA Used',
                            value: _fmtGbp.format(r.personalSavingsAllowance),
                          ),
                          (
                            label: 'Effective Rate',
                            value:
                                '${r.effectiveRate.toStringAsFixed(1)}%',
                          ),
                        ],
                      ),
                    ),
                    CalcwiseStaggerItem(
                      index: 1,
                      child: _SavingsInsightCard(result: r, ct: ct),
                    ),
                    CalcwiseStaggerItem(
                      index: 2,
                      child: _SavingsSummaryCard(
                        result: r,
                        fmtGbp: _fmtGbp,
                        ct: ct,
                      ),
                    ),
                    CalcwiseStaggerItem(
                      index: 3,
                      child: _SavingsRatesCard(result: r, ct: ct),
                    ),
                    CalcwiseStaggerItem(
                      index: 4,
                      child: Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.sm),
                        child: SaveScenarioButton(onSave: _saveScenario),
                      ),
                    ),
                    CalcwiseStaggerItem(
                      index: 5,
                      child: Padding(
                        padding: const EdgeInsets.only(
                          top: AppSpacing.xs,
                          bottom: AppSpacing.sm,
                        ),
                        child: OutlinedButton.icon(
                          onPressed: () {
                            HapticFeedback.mediumImpact();
                            _exportPdf();
                          },
                          icon: const Icon(
                            Icons.picture_as_pdf_outlined,
                            size: 18,
                          ),
                          label: const Text('Export PDF'),
                        ),
                      ),
                    ),
                  ]),
                ),
              ],
            ],
          ),
        ),
        const CalcwiseAdFooter(),
      ],
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _SavingsInsightCard extends StatelessWidget {
  final SavingsInterestResult result;
  final CalcwiseTheme ct;

  const _SavingsInsightCard({required this.result, required this.ct});

  String get _insightText {
    if (result.taxDue <= 0) {
      return 'Your interest is fully covered by the Personal Savings Allowance '
          '${result.starterRateRelief > 0 ? 'and the 0% starter rate band ' : ''}'
          '— no tax to pay.';
    }
    // Savings balance needed at 4.5% to produce this interest
    final balanceAt45 = result.grossInterest / 0.045;
    final balanceFmt =
        NumberFormat.currency(locale: 'en_GB', symbol: '£').format(balanceAt45);
    return 'If you have ~$balanceFmt in savings at 4.5%, '
        'you owe tax on your interest. Consider an ISA for tax-free savings.';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: AppTheme.primary.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lightbulb_outline_rounded,
              color: AppTheme.primary, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              _insightText,
              style: TextStyle(
                fontSize: AppTextSize.md,
                color: ct.textPrimary,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SavingsSummaryCard extends StatelessWidget {
  final SavingsInterestResult result;
  final NumberFormat fmtGbp;
  final CalcwiseTheme ct;

  const _SavingsSummaryCard({
    required this.result,
    required this.fmtGbp,
    required this.ct,
  });

  @override
  Widget build(BuildContext context) => SectionCard(
        title: 'Summary',
        children: [
          _Row(AppStringsEN.grossInterest, fmtGbp.format(result.grossInterest),
              ct),
          _Row(
            AppStringsEN.personalSavingsAllowance,
            '- ${fmtGbp.format(result.personalSavingsAllowance)}',
            ct,
          ),
          if (result.starterRateRelief > 0)
            _Row(
              AppStringsEN.starterRateRelief,
              '- ${fmtGbp.format(result.starterRateRelief)}',
              ct,
            ),
          _Divider(ct),
          _Row(
            AppStringsEN.taxableInterest,
            fmtGbp.format(result.taxableInterest),
            ct,
            bold: true,
          ),
          _Row(AppStringsEN.taxRateBand, result.band, ct),
          _Row(
            'Tax Due on Savings',
            fmtGbp.format(result.taxDue),
            ct,
            highlight: true,
          ),
          _Row(
            AppStringsEN.effectiveRatePct,
            '${result.effectiveRate.toStringAsFixed(2)}%',
            ct,
          ),
        ],
      );
}

class _SavingsRatesCard extends StatelessWidget {
  final SavingsInterestResult result;
  final CalcwiseTheme ct;

  const _SavingsRatesCard({required this.result, required this.ct});

  @override
  Widget build(BuildContext context) => SectionCard(
        title: '2026/27 Personal Savings Allowance',
        children: [
          for (final entry in const [
            ('Basic Rate (up to £50,270)', '£1,000 PSA', 'Basic Rate'),
            ('Higher Rate (£50,270–£125,140)', '£500 PSA', 'Higher Rate'),
            ('Additional Rate (above £125,140)', '£0 PSA', 'Additional Rate'),
          ]) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      entry.$1,
                      style: TextStyle(
                        fontSize: AppTextSize.md,
                        color: entry.$3 == result.band
                            ? ct.textPrimary
                            : ct.textSecondary,
                        fontWeight: entry.$3 == result.band
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.smPlus,
                        vertical: AppSpacing.xxs),
                    decoration: BoxDecoration(
                      color: entry.$3 == result.band
                          ? AppTheme.primary.withValues(alpha: 0.15)
                          : ct.cardBorder.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Text(
                      entry.$2,
                      style: TextStyle(
                        fontSize: AppTextSize.md,
                        fontWeight: FontWeight.w700,
                        color: entry.$3 == result.band
                            ? AppTheme.primary
                            : ct.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          Divider(color: ct.cardBorder, height: AppSpacing.xl, thickness: 1),
          Text(
            'Tax above the PSA is charged at your marginal rate (20%, 40%, or 45%). '
            'If non-savings income is under £17,570, you may also benefit from the '
            '0% savings starter rate on up to £5,000 of interest.',
            style:
                TextStyle(fontSize: AppTextSize.xs, color: ct.textSecondary, height: 1.5),
          ),
        ],
      );
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final CalcwiseTheme ct;
  final bool highlight;
  final bool bold;

  const _Row(
    this.label,
    this.value,
    this.ct, {
    this.highlight = false,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: AppTextSize.body,
                  color: highlight ? AppTheme.accent : ct.textSecondary,
                  fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: AppTextSize.body,
                color: highlight ? AppTheme.accent : ct.textPrimary,
                fontWeight:
                    bold || highlight ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ],
        ),
      );
}

class _Divider extends StatelessWidget {
  final CalcwiseTheme ct;
  const _Divider(this.ct);

  @override
  Widget build(BuildContext context) => Divider(
        color: ct.cardBorder,
        height: AppSpacing.xl,
        thickness: 1,
      );
}

class _SaveButton extends StatelessWidget {
  final VoidCallback onSave;
  const _SaveButton({required this.onSave});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: AppSpacing.sm),
        child: OutlinedButton.icon(
          onPressed: onSave,
          icon: const Icon(Icons.bookmark_outline_rounded, size: 18),
          label: const Text('Save to History'),
        ),
      );
}
