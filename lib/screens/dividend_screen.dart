import 'package:calcwise_core/calcwise_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../core/uk_tax_engine.dart';
import '../core/analytics/analytics_service.dart';
import '../core/freemium/freemium_service.dart';
import '../core/services/pdf_export_service.dart';
import '../core/theme/app_theme.dart';
import '../main.dart' show adService, analyticsService, paywallSession, smartHistoryService;
import '../widgets/paywall_soft.dart';
import '../widgets/save_scenario_button.dart';
import 'history_screen.dart';

class DividendScreen extends StatefulWidget {
  /// Optional pre-filled gross salary from the income tax tab.
  final double? initialGrossIncome;

  const DividendScreen({super.key, this.initialGrossIncome});

  @override
  State<DividendScreen> createState() => _DividendScreenState();
}

class _DividendScreenState extends State<DividendScreen> with CalcwiseAutoCalcMixin {
  late final TextEditingController _salaryCtrl;
  final _dividendCtrl = TextEditingController(text: '5000');
  final _fmtGbp = NumberFormat.currency(locale: 'en_GB', symbol: '£');
  final _fmtPct = NumberFormat.percentPattern('en_GB');

  DividendResult? _result;

  @override
  void initState() {
    super.initState();
    analyticsService.logScreenView('dividend');
    final initial = widget.initialGrossIncome;
    _salaryCtrl = TextEditingController(
      text: initial != null ? initial.round().toString() : '35000',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _calculate();
    });
  }

  @override
  void dispose() {
    _salaryCtrl.dispose();
    _dividendCtrl.dispose();
    smartHistoryService.cancelPendingSave('taxuk', 'dividend');
    super.dispose();
  }

  void _calculate() {
    analyticsService.maybeLogFirstCalculate();
    final salary =
        double.tryParse(_salaryCtrl.text.replaceAll(',', '.').trim()) ?? 0;
    final dividend =
        double.tryParse(_dividendCtrl.text.replaceAll(',', '.').trim()) ?? 0;
    if (salary < 0 || dividend < 0) return;

    final result = calculateDividend(
      grossIncome: salary,
      grossDividend: dividend,
    );
    setState(() => _result = result);

    analyticsService.logCalculationCompleted(
      params: {
        'calc_type': 'dividend',
        'gross_income': salary.round(),
        'gross_dividend': dividend.round(),
      },
    );
    adService.onAction();
    _scheduleAutoSave();
  }

  double _roundTo(double v, double step) => (v / step).round() * step;

  void _scheduleAutoSave() {
    final r = _result;
    if (r == null) return;
    final salary = double.tryParse(_salaryCtrl.text.replaceAll(',', '.').trim()) ?? 0;
    if (r.grossDividend <= 0 && salary <= 0) return;
    final inputHash = ResultHasher.hashMixed({
      'dividend_income': _roundTo(r.grossDividend, 500),
      'gross_income': _roundTo(salary, 1000),
    });
    smartHistoryService.scheduleAutoSave(
      appKey: 'taxuk',
      screenId: 'dividend',
      inputHash: inputHash,
      l1: {
        'dividend_income': r.grossDividend,
        'gross_income': salary,
        'dividend_tax': r.taxDue,
        'effective_rate': r.effectiveRate,
      },
      l2: {
        'inputs': {
          'dividendIncome': r.grossDividend,
          'grossIncome': salary,
        },
        'results': {
          'allowanceUsed': r.allowance,
          'taxableDiv': r.taxableDividend,
          'dividendTax': r.taxDue,
        },
      },
      onSaved: () { if (mounted) HistoryScreen.refreshNotifier.value++; },
    );
  }

  Future<void> _saveScenario(String? label) async {
    final r = _result;
    if (r == null) return;
    final salary = double.tryParse(_salaryCtrl.text.replaceAll(',', '.').trim()) ?? 0;
    final inputHash = ResultHasher.hashMixed({
      'dividend_income': _roundTo(r.grossDividend, 500),
      'gross_income': _roundTo(salary, 1000),
    });
    await smartHistoryService.saveScenario(
      appKey: 'taxuk',
      screenId: 'dividend',
      inputHash: inputHash,
      l1: {
        'dividend_income': r.grossDividend,
        'gross_income': salary,
        'dividend_tax': r.taxDue,
        'effective_rate': r.effectiveRate,
      },
      l2: {
        'inputs': {
          'dividendIncome': r.grossDividend,
          'grossIncome': salary,
        },
        'results': {
          'allowanceUsed': r.allowance,
          'taxableDiv': r.taxableDividend,
          'dividendTax': r.taxDue,
        },
      },
      label: label,
    );
    HistoryScreen.refreshNotifier.value++;
    try { analyticsService.logSave(); } catch (_) {}
    analyticsService.logResultSaved();
    adService.onSave();
    paywallSession.recordAction().ignore();
  }


  void _reset() {
    _salaryCtrl.text = '35000';
    _dividendCtrl.text = '5000';
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
    final salary =
        double.tryParse(_salaryCtrl.text.replaceAll(',', '.').trim()) ?? 0;
    await TaxUkPdfExportService.exportDividend(
      context: context,
      grossIncome: salary,
      grossDividend: r.grossDividend,
      allowance: r.allowance,
      taxableDividend: r.taxableDividend,
      taxDue: r.taxDue,
      effectiveRate: r.effectiveRate,
      band: r.band,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ct = CalcwiseTheme.of(context);
    final r = _result;

    return Material(
      type: MaterialType.transparency,
      child: Column(
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
              // ── Inputs ─────────────────────────────────────────────────────
              TextField(
                controller: _salaryCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: false,
                ),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Employment / Salary Income',
                  prefixText: '£',
                  hintText: '35000',
                  filled: true,
                ),
                onChanged: (_) => scheduleCalc(_calculate),
                onSubmitted: (_) => _calculate(),
              ),
              const SizedBox(height: AppSpacing.md),

              TextField(
                controller: _dividendCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: false,
                ),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Dividend Income',
                  prefixText: '£',
                  hintText: '5000',
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
                  'Dividend allowance: £500. Scottish taxpayers use the same dividend rates.',
                  style: TextStyle(
                    fontSize: AppTextSize.sm,
                    color: ct.textSecondary,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              // ── Action buttons ─────────────────────────────────────────────
              Row(children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _calculate,
                    child: const Text('Calculate'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                OutlinedButton(
                  onPressed: _reset,
                  child: const Text('Reset'),
                ),
              ]),

              // ── Results ────────────────────────────────────────────────────
              if (r != null) ...[
                const SizedBox(height: AppSpacing.xl),
                CalcwisePageEntrance(
                  child: Column(children: [
                    CalcwiseStaggerItem(
                      index: 0,
                      child: CalcwiseHeroCard(
                        label: 'DIVIDEND TAX DUE',
                        value: _fmtGbp.format(r.taxDue),
                        secondary: '2025/26 rates · ${r.band} Rate taxpayer',
                        rawValue: r.taxDue,
                        valueFormatter: (v) => AmountFormatter.ui(v, 'GBP'),
                        rawStats: [
                          (label: 'Taxable Dividend', value: r.taxableDividend, formatter: (v) => AmountFormatter.ui(v, 'GBP')),
                          (label: 'Allowance Used', value: r.allowance, formatter: (v) => AmountFormatter.ui(v, 'GBP')),
                          (label: 'Effective Rate', value: r.effectiveRate, formatter: (v) => '${v.toStringAsFixed(1)}%'),
                        ],
                        stats: [
                          (
                            label: 'Taxable Dividend',
                            value: _fmtGbp.format(r.taxableDividend),
                          ),
                          (
                            label: 'Allowance Used',
                            value: _fmtGbp.format(r.allowance),
                          ),
                          (
                            label: 'Effective Rate',
                            value: _fmtPct.format(r.effectiveRate),
                          ),
                        ],
                      ),
                    ),
                    CalcwiseStaggerItem(
                      index: 1,
                      child: _DividendInsightCard(result: r, ct: ct),
                    ),
                    CalcwiseStaggerItem(
                      index: 2,
                      child: _DividendSummaryCard(
                        result: r,
                        fmtGbp: _fmtGbp,
                        fmtPct: _fmtPct,
                        ct: ct,
                      ),
                    ),
                    CalcwiseStaggerItem(
                      index: 3,
                      child: _DividendRatesCard(result: r, ct: ct),
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
                          top: AppSpacing.md,
                          bottom: AppSpacing.sm,
                        ),
                        child: OutlinedButton.icon(
                          onPressed: _exportPdf,
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

class _DividendInsightCard extends StatelessWidget {
  final DividendResult result;
  final CalcwiseTheme ct;

  const _DividendInsightCard({required this.result, required this.ct});

  String get _rateStr {
    switch (result.band) {
      case 'Basic':
        return '8.75%';
      case 'Higher':
        return '33.75%';
      default:
        return '39.35%';
    }
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
              result.taxableDividend > 0
                  ? 'Your dividends fall in the $_rateStr ${result.band} Rate band. '
                      'Only dividends above the £500 allowance are taxed.'
                  : 'Your dividends are fully covered by the £500 allowance — no tax to pay.',
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

class _DividendSummaryCard extends StatelessWidget {
  final DividendResult result;
  final NumberFormat fmtGbp;
  final NumberFormat fmtPct;
  final CalcwiseTheme ct;

  const _DividendSummaryCard({
    required this.result,
    required this.fmtGbp,
    required this.fmtPct,
    required this.ct,
  });

  @override
  Widget build(BuildContext context) => SectionCard(
        title: 'Summary',
        children: [
          _Row('Gross Dividend', fmtGbp.format(result.grossDividend), ct),
          _Row(
              'Dividend Allowance', '- ${fmtGbp.format(result.allowance)}', ct),
          _Divider(ct),
          _Row('Taxable Dividend', fmtGbp.format(result.taxableDividend), ct,
              bold: true),
          _Row('Tax Band', result.band, ct),
          _Row(
            'Dividend Tax Due',
            fmtGbp.format(result.taxDue),
            ct,
            highlight: true,
          ),
          _Row(
            'Effective Rate',
            fmtPct.format(result.effectiveRate),
            ct,
          ),
        ],
      );
}

class _DividendRatesCard extends StatelessWidget {
  final DividendResult result;
  final CalcwiseTheme ct;

  const _DividendRatesCard({required this.result, required this.ct});

  @override
  Widget build(BuildContext context) => SectionCard(
        title: '2025/26 Dividend Tax Rates',
        children: [
          for (final entry in const [
            ('Basic Rate (up to £50,270)', '8.75%', 'Basic'),
            ('Higher Rate (£50,270–£125,140)', '33.75%', 'Higher'),
            ('Additional Rate (above £125,140)', '39.35%', 'Additional'),
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
            'Dividend allowance: £500 (2025/26). '
            'Dividends are not subject to Scottish income tax — same rates apply throughout the UK.',
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
