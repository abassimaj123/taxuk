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
import '../main.dart' show adService, analyticsService, smartHistoryService;
import '../widgets/paywall_soft.dart';
import '../widgets/save_scenario_button.dart';

class RentalIncomeScreen extends StatefulWidget {
  const RentalIncomeScreen({super.key});

  @override
  State<RentalIncomeScreen> createState() => _RentalIncomeScreenState();
}

class _RentalIncomeScreenState extends State<RentalIncomeScreen>
    with CalcwiseAutoCalcMixin {
  final _grossRentalCtrl = TextEditingController(text: '12000');
  final _managementCtrl = TextEditingController(text: '0');
  final _repairsCtrl = TextEditingController(text: '0');
  final _insuranceCtrl = TextEditingController(text: '0');
  final _councilTaxCtrl = TextEditingController(text: '0');
  final _utilitiesCtrl = TextEditingController(text: '0');
  final _otherExpensesCtrl = TextEditingController(text: '0');
  final _mortgageInterestCtrl = TextEditingController(text: '0');
  final _otherIncomeCtrl = TextEditingController(text: '35000');

  final _fmtGbp = NumberFormat.currency(locale: 'en_GB', symbol: '£');
  final _fmtPct = NumberFormat('##0.00', 'en_GB');

  RentalIncomeResult? _result;
  bool _isScotland = false;

  @override
  void initState() {
    super.initState();
    analyticsService.logScreenView('rental_income');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _calculate();
    });
  }

  @override
  void dispose() {
    _grossRentalCtrl.dispose();
    _managementCtrl.dispose();
    _repairsCtrl.dispose();
    _insuranceCtrl.dispose();
    _councilTaxCtrl.dispose();
    _utilitiesCtrl.dispose();
    _otherExpensesCtrl.dispose();
    _mortgageInterestCtrl.dispose();
    _otherIncomeCtrl.dispose();
    smartHistoryService.cancelPendingSave('taxuk', 'rental_income');
    super.dispose();
  }

  double _parse(TextEditingController ctrl) =>
      double.tryParse(ctrl.text.replaceAll(',', '.').trim()) ?? 0;

  void _calculate() {
    final grossRental = _parse(_grossRentalCtrl);
    final management = _parse(_managementCtrl);
    final repairs = _parse(_repairsCtrl);
    final insurance = _parse(_insuranceCtrl);
    final councilTax = _parse(_councilTaxCtrl);
    final utilities = _parse(_utilitiesCtrl);
    final otherExpenses = _parse(_otherExpensesCtrl);
    final mortgageInterest = _parse(_mortgageInterestCtrl);
    final otherIncome = _parse(_otherIncomeCtrl);

    final result = calculateRentalIncomeTax(
      grossRental: grossRental,
      managementFees: management,
      repairs: repairs,
      insurance: insurance,
      councilTax: councilTax,
      utilities: utilities,
      otherExpenses: otherExpenses,
      mortgageInterest: mortgageInterest,
      otherIncome: otherIncome,
      isScotland: _isScotland,
    );
    setState(() => _result = result);

    analyticsService.logCalculationCompleted(
      params: {
        'calc_type': 'rental_income',
        'gross_rental': grossRental.round(),
        'other_income': otherIncome.round(),
        'mortgage_interest': mortgageInterest.round(),
      },
    );
    adService.onAction();
    _scheduleAutoSave();
  }

  double _roundTo(double v, double step) => (v / step).round() * step;

  void _scheduleAutoSave() {
    final r = _result;
    if (r == null) return;
    if (r.grossRental <= 0) return;
    final otherIncome = _parse(_otherIncomeCtrl);
    final inputHash = ResultHasher.hashMixed({
      'rental_income': _roundTo(r.grossRental, 500),
      'other_income': _roundTo(otherIncome, 1000),
    });
    smartHistoryService.scheduleAutoSave(
      appKey: 'taxuk',
      screenId: 'rental_income',
      inputHash: inputHash,
      l1: {
        'title': 'Rental — £${r.grossRental.toStringAsFixed(0)} income',
        'subtitle': 'Tax: £${r.taxAfterCredit.toStringAsFixed(0)} · Profit: £${r.netProfit.toStringAsFixed(0)}',
      },
      l2: {
        'inputs': {
          'rentalIncome': r.grossRental,
          'otherIncome': otherIncome,
          'expenses': r.allowableExpenses,
          'propertyAllowance': _parse(_mortgageInterestCtrl),
        },
        'results': {
          'taxableProfit': r.taxableProfit,
          'tax': r.taxAfterCredit,
        },
      },
    );
  }

  Future<void> _saveScenario(String? label) async {
    final r = _result;
    if (r == null) return;
    final otherIncome = _parse(_otherIncomeCtrl);
    final inputHash = ResultHasher.hashMixed({
      'rental_income': _roundTo(r.grossRental, 500),
      'other_income': _roundTo(otherIncome, 1000),
    });
    await smartHistoryService.saveScenario(
      appKey: 'taxuk',
      screenId: 'rental_income',
      inputHash: inputHash,
      l1: {
        'title': 'Rental — £${r.grossRental.toStringAsFixed(0)} income',
        'subtitle': 'Tax: £${r.taxAfterCredit.toStringAsFixed(0)} · Profit: £${r.netProfit.toStringAsFixed(0)}',
      },
      l2: {
        'inputs': {
          'rentalIncome': r.grossRental,
          'otherIncome': otherIncome,
          'expenses': r.allowableExpenses,
          'propertyAllowance': _parse(_mortgageInterestCtrl),
        },
        'results': {
          'taxableProfit': r.taxableProfit,
          'tax': r.taxAfterCredit,
        },
      },
      label: label,
    );
    analyticsService.logResultSaved();
    adService.onSave();
  }


  void _reset() {
    _grossRentalCtrl.text = '12000';
    _managementCtrl.text = '0';
    _repairsCtrl.text = '0';
    _insuranceCtrl.text = '0';
    _councilTaxCtrl.text = '0';
    _utilitiesCtrl.text = '0';
    _otherExpensesCtrl.text = '0';
    _mortgageInterestCtrl.text = '0';
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
    final otherIncome =
        double.tryParse(_otherIncomeCtrl.text.replaceAll(',', '.').trim()) ?? 0;
    final mortgageInterest =
        double.tryParse(
          _mortgageInterestCtrl.text.replaceAll(',', '.').trim(),
        ) ??
        0;
    await TaxUkPdfExportService.exportRentalIncome(
      context: context,
      grossRental: r.grossRental,
      allowableExpenses: r.allowableExpenses,
      taxableProfit: r.taxableProfit,
      taxAfterCredit: r.taxAfterCredit,
      netProfit: r.netProfit,
      effectiveYield: r.effectiveYield,
      mortgageInterestCredit: mortgageInterest > 0
          ? r.mortgageInterestCredit
          : 0,
      otherIncome: otherIncome,
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
              _buildField(
                controller: _grossRentalCtrl,
                label: AppStringsEN.grossRental,
                hint: '12000',
              ),
              const SizedBox(height: AppSpacing.md),
              _buildField(
                controller: _otherIncomeCtrl,
                label: AppStringsEN.otherIncome,
                hint: '35000',
              ),
              const SizedBox(height: AppSpacing.md),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Scottish taxpayer'),
                subtitle: const Text('Uses Scottish income tax rates (42% Higher Rate from £43,662)'),
                value: _isScotland,
                onChanged: (v) {
                  setState(() => _isScotland = v);
                  _calculate();
                },
              ),
              const SizedBox(height: AppSpacing.md),

              // Expenses section header
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Text(
                  AppStringsEN.allowableExpenses,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: ct.textSecondary,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              _buildField(
                controller: _managementCtrl,
                label: AppStringsEN.managementFees,
                hint: '0',
              ),
              const SizedBox(height: AppSpacing.sm),
              _buildField(
                controller: _repairsCtrl,
                label: AppStringsEN.repairs,
                hint: '0',
              ),
              const SizedBox(height: AppSpacing.sm),
              _buildField(
                controller: _insuranceCtrl,
                label: AppStringsEN.insurance,
                hint: '0',
              ),
              const SizedBox(height: AppSpacing.sm),
              _buildField(
                controller: _councilTaxCtrl,
                label: AppStringsEN.councilTax,
                hint: '0',
              ),
              const SizedBox(height: AppSpacing.sm),
              _buildField(
                controller: _utilitiesCtrl,
                label: AppStringsEN.utilities,
                hint: '0',
              ),
              const SizedBox(height: AppSpacing.sm),
              _buildField(
                controller: _otherExpensesCtrl,
                label: 'Other Expenses',
                hint: '0',
              ),
              const SizedBox(height: AppSpacing.md),

              // Mortgage interest — separate section
              _buildField(
                controller: _mortgageInterestCtrl,
                label: 'Mortgage Interest Paid (annual)',
                hint: '0',
              ),
              const SizedBox(height: AppSpacing.xs),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(
                  'Mortgage interest is not deductible from profit. A 20% tax credit applies instead (2025/26 rules).',
                  style: TextStyle(fontSize: 12, color: ct.textSecondary),
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
                        label: 'TAX DUE',
                        value: _fmtGbp.format(r.taxAfterCredit),
                        secondary:
                            '2025/26 rates · Rental Income',
                        stats: [
                          (
                            label: 'Taxable Profit',
                            value: _fmtGbp.format(r.taxableProfit),
                          ),
                          (
                            label: 'Net Profit',
                            value: _fmtGbp.format(r.netProfit),
                          ),
                          (
                            label: 'Effective Yield',
                            value: '${_fmtPct.format(r.effectiveYield)}%',
                          ),
                        ],
                      ),
                    ),
                    CalcwiseStaggerItem(
                      index: 1,
                      child: _RentalInsightCard(result: r, ct: ct),
                    ),
                    CalcwiseStaggerItem(
                      index: 2,
                      child: _RentalSummaryCard(
                        result: r,
                        fmtGbp: _fmtGbp,
                        fmtPct: _fmtPct,
                        ct: ct,
                      ),
                    ),
                    CalcwiseStaggerItem(
                      index: 3,
                      child: _RentalRulesCard(ct: ct),
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

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
  }) =>
      TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: false),
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          labelText: label,
          prefixText: '£',
          hintText: hint,
          filled: true,
        ),
        onChanged: (_) => scheduleCalc(_calculate),
        onSubmitted: (_) => _calculate(),
      );
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _RentalInsightCard extends StatelessWidget {
  final RentalIncomeResult result;
  final CalcwiseTheme ct;

  const _RentalInsightCard({required this.result, required this.ct});

  @override
  Widget build(BuildContext context) {
    final hasProfit = result.taxableProfit > 0;
    final hasCredit = result.mortgageInterestCredit > 0;
    String message;
    if (!hasProfit) {
      message =
          'Your allowable expenses exceed your rental income — no taxable profit this year.';
    } else if (hasCredit) {
      message =
          'A mortgage interest tax credit of £${result.mortgageInterestCredit.toStringAsFixed(0)} '
          'reduces your tax bill. Note: mortgage interest is not deducted from profit.';
    } else {
      message =
          'Your taxable rental profit of £${result.taxableProfit.toStringAsFixed(0)} '
          'is added to your other income and taxed at your marginal rate.';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lightbulb_outline_rounded,
              color: AppTheme.primary, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                  fontSize: 13, color: ct.textPrimary, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

class _RentalSummaryCard extends StatelessWidget {
  final RentalIncomeResult result;
  final NumberFormat fmtGbp;
  final NumberFormat fmtPct;
  final CalcwiseTheme ct;

  const _RentalSummaryCard({
    required this.result,
    required this.fmtGbp,
    required this.fmtPct,
    required this.ct,
  });

  @override
  Widget build(BuildContext context) => SectionCard(
        title: 'Summary',
        children: [
          _Row(AppStringsEN.grossRental, fmtGbp.format(result.grossRental), ct),
          _Row(AppStringsEN.allowableExpenses,
              '− ${fmtGbp.format(result.allowableExpenses)}', ct),
          _Divider(ct),
          _Row(AppStringsEN.taxableProfit,
              fmtGbp.format(result.taxableProfit), ct,
              bold: true),
          _Row('Tax Before Credit',
              fmtGbp.format(result.taxBeforeCredit), ct),
          _Row('Mortgage Interest Credit (20%)',
              '− ${fmtGbp.format(result.mortgageInterestCredit)}', ct),
          _Divider(ct),
          _Row('Tax Due', fmtGbp.format(result.taxAfterCredit), ct,
              highlight: true),
          _Row(AppStringsEN.netProfit, fmtGbp.format(result.netProfit), ct,
              bold: true),
          _Row(AppStringsEN.effectiveYield,
              '${fmtPct.format(result.effectiveYield)}%', ct),
        ],
      );
}

class _RentalRulesCard extends StatelessWidget {
  final CalcwiseTheme ct;
  const _RentalRulesCard({required this.ct});

  @override
  Widget build(BuildContext context) => SectionCard(
        title: '2025/26 Rental Income Rules',
        children: [
          for (final entry in const [
            (
              'Allowable expenses are deducted from gross rental income to give taxable profit.',
              Icons.check_circle_outline_rounded,
            ),
            (
              'Mortgage interest is NOT deductible — a 20% basic rate tax credit applies instead.',
              Icons.info_outline_rounded,
            ),
            (
              'Taxable profit is added to other income and taxed at your marginal rate.',
              Icons.account_balance_outlined,
            ),
            (
              'If total income exceeds £100,000, Personal Allowance is tapered (£1 per £2 above).',
              Icons.warning_amber_rounded,
            ),
          ])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(entry.$2, size: 16, color: ct.textSecondary),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      entry.$1,
                      style: TextStyle(
                          fontSize: 13, color: ct.textSecondary, height: 1.45),
                    ),
                  ),
                ],
              ),
            ),
          Divider(color: ct.cardBorder, height: AppSpacing.xl, thickness: 1),
          Text(
            'Source: HMRC PIM2054 — Section 24 Finance Act 2015. '
            'For informational purposes only.',
            style: TextStyle(
                fontSize: 11, color: ct.textSecondary, height: 1.5),
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
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  color: highlight ? AppTheme.accent : ct.textSecondary,
                  fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
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
