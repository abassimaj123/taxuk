import 'dart:math';
import 'package:calcwise_core/calcwise_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../core/uk_tax_engine.dart';
import '../core/analytics/analytics_service.dart';
import '../core/db/database_service.dart';
import '../core/freemium/freemium_service.dart';
import '../core/theme/app_theme.dart';
import '../l10n/strings_en.dart';
import '../main.dart';
import '../widgets/paywall_soft.dart';
import 'salary_comparison_screen.dart';

class IncomeTaxScreen extends StatefulWidget {
  const IncomeTaxScreen({super.key});

  @override
  State<IncomeTaxScreen> createState() => _IncomeTaxScreenState();
}

class _IncomeTaxScreenState extends State<IncomeTaxScreen> with CalcwiseAutoCalcMixin {
  // ── Controllers ─────────────────────────────────────────────────────────────
  final _grossCtrl = TextEditingController(text: '35000');
  final _pensionCtrl = TextEditingController(text: '0');
  final _targetNetCtrl = TextEditingController(text: '25000');
  final _fmtGbp = NumberFormat.currency(locale: 'en_GB', symbol: '£');
  final _fmtPct = NumberFormat.percentPattern('en_GB');

  // ── State ────────────────────────────────────────────────────────────────────
  IncomeTaxRegion _region = IncomeTaxRegion.england;
  bool get _isScotland => _region.usesScottishRates;
  bool _isSelfEmployed = false;
  bool _hasMarriageAllowance = false;
  bool _isReverse = false; // forward (gross→net) vs reverse (net→gross)
  IncomeTaxResult? _result;
  double? _reverseGross; // result in reverse mode

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _calculate();
    });
  }

  @override
  void dispose() {
    _grossCtrl.dispose();
    _pensionCtrl.dispose();
    _targetNetCtrl.dispose();
    super.dispose();
  }

  // ── Calculation ──────────────────────────────────────────────────────────────

  void _calculate() {
    if (_isReverse) {
      _calculateReverse();
    } else {
      _calculateForward();
    }
  }

  void _calculateForward() {
    final gross =
        double.tryParse(_grossCtrl.text.replaceAll(',', '.').trim()) ?? 0;
    final pensionPct =
        double.tryParse(_pensionCtrl.text.replaceAll(',', '.').trim()) ?? 0;
    if (gross < 0) return;

    final pension = gross * (pensionPct.clamp(0, 100) / 100);
    final effectiveGross = grossAfterPension(gross, pension);
    final pa = UKTaxEngine.effectivePersonalAllowance(effectiveGross);
    final tax = UKTaxEngine.incomeTax(effectiveGross, isScotland: _isScotland);
    final ni = _isSelfEmployed
        ? calculateSelfEmployedNI(effectiveGross)
        : UKTaxEngine.nationalInsurance(effectiveGross);
    final niBreakdown = _isSelfEmployed
        ? calculateSelfEmployedNIBreakdown(effectiveGross)
        : (class2: 0.0, class4: 0.0);
    final maCredit = _hasMarriageAllowance ? marriageAllowanceCredit : 0.0;
    final taxAfterMA = max(0.0, tax - maCredit);
    final net = effectiveGross - taxAfterMA - ni;
    final effRate = effectiveGross > 0 ? taxAfterMA / effectiveGross : 0.0;
    final margRate =
        UKTaxEngine.marginalTaxRate(effectiveGross, isScotland: _isScotland);
    final bands = UKTaxEngine.taxBandBreakdown(
      effectiveGross,
      isScotland: _isScotland,
    );

    setState(() {
      _reverseGross = null;
      _result = IncomeTaxResult(
        grossIncome: gross,
        personalAllowance: pa,
        incomeTax: taxAfterMA,
        nationalInsurance: ni,
        netIncome: net,
        effectiveTaxRate: effRate,
        marginalTaxRate: margRate,
        bandBreakdown: bands,
        isScotland: _isScotland,
        pensionContribution: pension,
        isSelfEmployed: _isSelfEmployed,
        hasMarriageAllowance: _hasMarriageAllowance,
        marriageAllowanceCreditApplied: maCredit,
        class2NI: niBreakdown.class2,
        class4NI: niBreakdown.class4,
      );
    });

    analyticsService.logIncomeTaxCalculated(
      grossIncome: gross,
      isScotland: _isScotland,
    );
    adService.onAction();
  }

  void _calculateReverse() {
    final targetNet =
        double.tryParse(_targetNetCtrl.text.replaceAll(',', '.').trim()) ?? 0;
    final pensionPct =
        double.tryParse(_pensionCtrl.text.replaceAll(',', '.').trim()) ?? 0;
    if (targetNet <= 0) return;

    // We solve for gross such that pension is a % of gross — iterative approach
    // Since pension = gross * pct, pension reduces gross by a fixed %, so we
    // can compute requiredEffective first, then gross = effective / (1 - pct/100)
    final pctFraction = pensionPct.clamp(0, 99) / 100;
    final requiredEffective = reverseCalculateGross(
      targetNet: targetNet,
      isScotland: _isScotland,
      pensionContrib: 0, // we compute pension from effective gross
      selfEmployed: _isSelfEmployed,
    );
    // gross = effectiveGross / (1 - pensionPct/100)
    final gross = pctFraction < 1 ? requiredEffective / (1 - pctFraction) : requiredEffective;

    setState(() {
      _reverseGross = gross;
      _result = null;
    });

    adService.onAction();
  }

  // ── Save ─────────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    final r = _result;
    if (r == null) return;
    final count = await DatabaseService.instance.count();
    if (!freemiumService.hasFullAccess &&
        count >= MonetizationConfig.freeHistoryLimit) {
      if (!mounted) return;
      await PaywallSoft.show(
        context,
        featureTitle: AppStringsEN.historyLimit,
        featureSubtitle: 'Upgrade to save unlimited calculations.',
      );
      return;
    }
    await DatabaseService.instance.insert(
      inputs: {
        'type': 'income_tax',
        'gross': r.grossIncome,
        'is_scotland': r.isScotland,
        'is_self_employed': r.isSelfEmployed,
        'pension': r.pensionContribution,
      },
      results: {
        'net': r.netIncome,
        'income_tax': r.incomeTax,
        'ni': r.nationalInsurance,
        'effective_rate': r.effectiveTaxRate,
        'marginal_rate': r.marginalTaxRate,
      },
    );
    analyticsService.logResultSaved();
    adService.onSave();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Saved to history')));
  }

  void _reset() {
    _grossCtrl.text = '35000';
    _pensionCtrl.text = '0';
    _targetNetCtrl.text = '25000';
    setState(() {
      _region = IncomeTaxRegion.england;
      _isSelfEmployed = false;
      _hasMarriageAllowance = false;
      _isReverse = false;
      _result = null;
      _reverseGross = null;
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final ct = CalcwiseTheme.of(context);
    final r = _result;

    return Column(
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
              // ── Mode toggle (Forward / Reverse) ─────────────────────────
              _ModeToggle(
                isReverse: _isReverse,
                ct: ct,
                onChanged: (v) => setState(() {
                  _isReverse = v;
                  _result = null;
                  _reverseGross = null;
                }),
              ),
              const SizedBox(height: AppSpacing.lg),

              // ── Main input ───────────────────────────────────────────────
              if (!_isReverse)
                TextField(
                  controller: _grossCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: false,
                  ),
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Gross Annual Salary',
                    prefixText: '£',
                    hintText: '35000',
                    filled: true,
                  ),
                  onChanged: (_) => scheduleCalc(_calculate),
                  onSubmitted: (_) => _calculate(),
                )
              else
                TextField(
                  controller: _targetNetCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: false,
                  ),
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Target Take-Home (net)',
                    prefixText: '£',
                    hintText: '25000',
                    helperText: 'We\'ll calculate the gross salary you need',
                    filled: true,
                  ),
                  onChanged: (_) => scheduleCalc(_calculate),
                  onSubmitted: (_) => _calculate(),
                ),
              const SizedBox(height: AppSpacing.md),

              // ── Pension input ────────────────────────────────────────────
              TextField(
                controller: _pensionCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Pension Contribution (salary sacrifice)',
                  suffixText: '%',
                  hintText: '0',
                  helperText: 'Reduces taxable income and NI',
                  filled: true,
                ),
                onChanged: (_) => scheduleCalc(_calculate),
              ),
              const SizedBox(height: AppSpacing.lg),

              // ── Region selector ──────────────────────────────────────────
              _SectionLabel('Tax Region', ct),
              const SizedBox(height: AppSpacing.sm),
              _RegionSelector(
                region: _region,
                ct: ct,
                onChanged: (r) {
                  setState(() => _region = r);
                  analyticsService.logRegionSelected(r.label);
                  analyticsService.logScotlandToggled(r.usesScottishRates);
                  if (_result != null || _reverseGross != null) {
                    _calculate();
                  }
                },
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                _region.ratesNote,
                style: TextStyle(fontSize: 12, color: ct.textSecondary),
              ),
              const SizedBox(height: AppSpacing.lg),

              // ── Toggles ──────────────────────────────────────────────────
              Container(
                decoration: BoxDecoration(
                  color: ct.surface,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: ct.cardBorder),
                ),
                child: Column(
                  children: [
                    SwitchListTile(
                      title: Text(
                        'Self-Employed (Class 2 + 4 NI)',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: ct.textPrimary,
                        ),
                      ),
                      subtitle: Text(
                        _isSelfEmployed
                            ? 'NI: £3.45/wk (Class 2) + 6%/2% on profits (Class 4)'
                            : 'PAYE: Class 1 NI (8% / 2%)',
                        style: TextStyle(
                          fontSize: 12,
                          color: ct.textSecondary,
                        ),
                      ),
                      value: _isSelfEmployed,
                      activeColor: AppTheme.primary,
                      onChanged: (v) {
                        setState(() => _isSelfEmployed = v);
                        if (_result != null || _reverseGross != null) {
                          _calculate();
                        }
                      },
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.xs,
                      ),
                    ),
                    Divider(
                        height: 1,
                        thickness: 1,
                        color: ct.cardBorder,
                        indent: AppSpacing.md),
                    SwitchListTile(
                      title: Text(
                        'Marriage Allowance (recipient)',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: ct.textPrimary,
                        ),
                      ),
                      subtitle: Text(
                        _hasMarriageAllowance
                            ? '+£252/year tax credit from partner\'s unused allowance'
                            : 'Partner transfers 10% of Personal Allowance to you',
                        style: TextStyle(
                          fontSize: 12,
                          color: ct.textSecondary,
                        ),
                      ),
                      value: _hasMarriageAllowance,
                      activeColor: AppTheme.primary,
                      onChanged: (v) {
                        setState(() => _hasMarriageAllowance = v);
                        if (_result != null) _calculate();
                      },
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.xs,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              // ── Action buttons ───────────────────────────────────────────
              Row(children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _calculate,
                    child: Text(_isReverse
                        ? 'Find Required Gross'
                        : 'Calculate'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                OutlinedButton(
                  onPressed: _reset,
                  child: const Text('Reset'),
                ),
              ]),

              // ── Reverse result ───────────────────────────────────────────
              if (_isReverse && _reverseGross != null) ...[
                const SizedBox(height: AppSpacing.xl),
                CalcwisePageEntrance(
                  child: Column(children: [
                    CalcwiseStaggerItem(
                      index: 0,
                      child: CalcwiseHeroCard(
                        label: 'REQUIRED GROSS SALARY',
                        value: _fmtGbp.format(_reverseGross),
                        secondary:
                            '${_region.label} · ${_isSelfEmployed ? 'Self-employed' : 'PAYE'}',
                        stats: [
                          (
                            label: 'Target Net',
                            value: _fmtGbp.format(
                              double.tryParse(_targetNetCtrl.text) ?? 0,
                            ),
                          ),
                          if (_reverseGross! > 0)
                            (
                              label: 'Est. Monthly',
                              value: _fmtGbp.format(_reverseGross! / 12),
                            ),
                        ],
                      ),
                    ),
                    CalcwiseStaggerItem(
                      index: 1,
                      child: _ReverseInsightCard(
                        gross: _reverseGross!,
                        targetNet:
                            double.tryParse(_targetNetCtrl.text) ?? 0,
                        fmtGbp: _fmtGbp,
                        ct: ct,
                      ),
                    ),
                  ]),
                ),
              ],

              // ── Forward results ──────────────────────────────────────────
              if (!_isReverse && r != null) ...[
                const SizedBox(height: AppSpacing.xl),
                CalcwisePageEntrance(
                  child: Column(children: [
                    CalcwiseStaggerItem(
                      index: 0,
                      child: CalcwiseHeroCard(
                        label: 'ANNUAL TAKE-HOME',
                        value: _fmtGbp.format(r.netIncome),
                        secondary: '${_region.label} rates 2025/26',
                        stats: [
                          (
                            label: 'Income Tax',
                            value: _fmtGbp.format(r.incomeTax),
                          ),
                          (
                            label: r.isSelfEmployed ? 'NI (Class 2+4)' : 'NI',
                            value: _fmtGbp.format(r.nationalInsurance),
                          ),
                          (
                            label: 'Effective Rate',
                            value: _fmtPct.format(r.effectiveOverallRate),
                          ),
                        ],
                      ),
                    ),
                    CalcwiseStaggerItem(
                      index: 1,
                      child: _SummaryCard(
                        result: r,
                        fmtGbp: _fmtGbp,
                        fmtPct: _fmtPct,
                        ct: ct,
                      ),
                    ),
                    CalcwiseStaggerItem(
                      index: 2,
                      child: _BandBreakdown(
                        bands: r.bandBreakdown,
                        fmtGbp: _fmtGbp,
                        ct: ct,
                        isScotland: r.isScotland,
                      ),
                    ),
                    CalcwiseStaggerItem(
                      index: 3,
                      child: _NiBreakdown(
                        gross: r.effectiveGross,
                        ni: r.nationalInsurance,
                        isSelfEmployed: r.isSelfEmployed,
                        class2NI: r.class2NI,
                        class4NI: r.class4NI,
                        fmtGbp: _fmtGbp,
                        ct: ct,
                      ),
                    ),
                    CalcwiseStaggerItem(
                      index: 4,
                      child: _MonthlyWeeklyCard(
                        result: r,
                        fmtGbp: _fmtGbp,
                        ct: ct,
                      ),
                    ),
                    CalcwiseStaggerItem(
                      index: 5,
                      child: _CompareButton(ct: ct),
                    ),
                    CalcwiseStaggerItem(
                      index: 6,
                      child: _SaveButton(onSave: _save),
                    ),
                  ]),
                ),
              ],
            ],
          ),
        ),
        const CalcwiseAdFooter(),
      ],
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  final CalcwiseTheme ct;
  const _SectionLabel(this.text, this.ct);

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
          color: ct.textSecondary,
        ),
      );
}

class _RegionSelector extends StatelessWidget {
  final IncomeTaxRegion region;
  final CalcwiseTheme ct;
  final ValueChanged<IncomeTaxRegion> onChanged;

  const _RegionSelector({
    required this.region,
    required this.ct,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: IncomeTaxRegion.values.map((r) {
          final sel = region == r;
          return ChoiceChip(
            label: Text(r.shortLabel),
            selected: sel,
            onSelected: (_) => onChanged(r),
            selectedColor: AppTheme.primary.withValues(alpha: 0.15),
            labelStyle: TextStyle(
              fontSize: 13,
              color: sel ? AppTheme.primary : ct.textSecondary,
              fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
            ),
            side: BorderSide(
              color: sel
                  ? AppTheme.primary.withValues(alpha: 0.5)
                  : ct.cardBorder,
            ),
            backgroundColor: ct.surface,
            showCheckmark: false,
          );
        }).toList(),
      );
}

class _ModeToggle extends StatelessWidget {
  final bool isReverse;
  final CalcwiseTheme ct;
  final ValueChanged<bool> onChanged;

  const _ModeToggle({
    required this.isReverse,
    required this.ct,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Row(
        children: [
          _ToggleOption(
            label: 'Gross → Net',
            icon: Icons.south_rounded,
            selected: !isReverse,
            ct: ct,
            onTap: () => onChanged(false),
          ),
          const SizedBox(width: AppSpacing.sm),
          _ToggleOption(
            label: 'Net → Gross',
            icon: Icons.north_rounded,
            selected: isReverse,
            ct: ct,
            onTap: () => onChanged(true),
          ),
        ],
      );
}

class _ToggleOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final CalcwiseTheme ct;
  final VoidCallback onTap;

  const _ToggleOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.ct,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Expanded(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: selected
                  ? AppTheme.primary.withValues(alpha: 0.12)
                  : ct.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: selected
                    ? AppTheme.primary.withValues(alpha: 0.5)
                    : ct.cardBorder,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 14,
                  color: selected ? AppTheme.primary : ct.textSecondary,
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected ? AppTheme.primary : ct.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _ReverseInsightCard extends StatelessWidget {
  final double gross;
  final double targetNet;
  final NumberFormat fmtGbp;
  final CalcwiseTheme ct;

  const _ReverseInsightCard({
    required this.gross,
    required this.targetNet,
    required this.fmtGbp,
    required this.ct,
  });

  @override
  Widget build(BuildContext context) => Container(
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
            const Icon(Icons.swap_vert_rounded,
                color: AppTheme.primary, size: 20),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'To take home ${fmtGbp.format(targetNet)} per year, '
                'you need a gross salary of ${fmtGbp.format(gross)} '
                '(${fmtGbp.format(gross / 12)}/month gross). '
                'Deductions total ${fmtGbp.format(gross - targetNet)}.',
                style: TextStyle(
                  fontSize: 13,
                  color: ct.textPrimary,
                  height: 1.45,
                ),
              ),
            ),
          ],
        ),
      );
}

class _SummaryCard extends StatelessWidget {
  final IncomeTaxResult result;
  final NumberFormat fmtGbp;
  final NumberFormat fmtPct;
  final CalcwiseTheme ct;

  const _SummaryCard({
    required this.result,
    required this.fmtGbp,
    required this.fmtPct,
    required this.ct,
  });

  @override
  Widget build(BuildContext context) => SectionCard(
        title: 'Summary',
        children: [
          _Row('Gross Income', fmtGbp.format(result.grossIncome), ct),
          if (result.pensionContribution > 0)
            _Row(
              'Pension (salary sacrifice)',
              '− ${fmtGbp.format(result.pensionContribution)}',
              ct,
            ),
          _Row(
            'Taxable Income',
            fmtGbp.format(result.effectiveGross),
            ct,
          ),
          _Row(
            'Personal Allowance',
            fmtGbp.format(result.personalAllowance),
            ct,
          ),
          _Row(
            'Income Tax',
            fmtGbp.format(result.incomeTax),
            ct,
            highlight: true,
          ),
          if (result.hasMarriageAllowance && result.marriageAllowanceCreditApplied > 0)
            _Row(
              'Marriage Allowance Credit',
              '− ${fmtGbp.format(result.marriageAllowanceCreditApplied)}',
              ct,
            ),
          if (result.isSelfEmployed) ...[
            _Row(
              'National Insurance (Class 2+4)',
              fmtGbp.format(result.nationalInsurance),
              ct,
              highlight: true,
            ),
            _IndentRow(' ↳ Class 2 (£3.45/wk)', result.class2NI, fmtGbp, ct),
            _IndentRow(' ↳ Class 4 (6%/2%)', result.class4NI, fmtGbp, ct),
          ] else
            _Row(
              'National Insurance (Class 1)',
              fmtGbp.format(result.nationalInsurance),
              ct,
              highlight: true,
            ),
          _Divider(ct),
          _Row(
            'Take-Home Pay',
            fmtGbp.format(result.netIncome),
            ct,
            bold: true,
          ),
          _Row(
            'Effective Tax Rate',
            fmtPct.format(result.effectiveTaxRate),
            ct,
          ),
          _Row(
            'Effective Overall Rate',
            fmtPct.format(result.effectiveOverallRate),
            ct,
          ),
          _Row(
            'Marginal Rate',
            '${(result.marginalTaxRate * 100).toStringAsFixed(0)}%',
            ct,
          ),
        ],
      );
}

class _BandBreakdown extends StatelessWidget {
  final List<TaxBandRow> bands;
  final NumberFormat fmtGbp;
  final CalcwiseTheme ct;
  final bool isScotland;

  const _BandBreakdown({
    required this.bands,
    required this.fmtGbp,
    required this.ct,
    required this.isScotland,
  });

  @override
  Widget build(BuildContext context) => SectionCard(
        title: 'Tax Band Breakdown',
        children: [
          for (final b in bands)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          b.name,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: b.amount > 0
                                ? ct.textPrimary
                                : ct.textSecondary,
                          ),
                        ),
                        Text(
                          '${(b.rate * 100).toStringAsFixed(0)}%  '
                          '${fmtGbp.format(b.rangeFrom)}–'
                          '${b.rangeTo.isInfinite ? '∞' : fmtGbp.format(b.rangeTo)}',
                          style: TextStyle(
                            fontSize: 11,
                            color: ct.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    b.amount > 0 ? fmtGbp.format(b.amount) : '—',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color:
                          b.amount > 0 ? AppTheme.primary : ct.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
}

class _NiBreakdown extends StatelessWidget {
  final double gross;
  final double ni;
  final bool isSelfEmployed;
  final double class2NI;
  final double class4NI;
  final NumberFormat fmtGbp;
  final CalcwiseTheme ct;

  const _NiBreakdown({
    required this.gross,
    required this.ni,
    required this.isSelfEmployed,
    required this.class2NI,
    required this.class4NI,
    required this.fmtGbp,
    required this.ct,
  });

  @override
  Widget build(BuildContext context) {
    final title = isSelfEmployed
        ? 'National Insurance (Self-Employed)'
        : 'National Insurance (Class 1)';

    if (isSelfEmployed) {
      // Derive Class 4 band split from the stored total class4NI
      final class4band1 = gross > 12570
          ? (min(gross, 50270) - 12570) * 0.06
          : 0.0;
      final class4band2 =
          gross > 50270 ? (gross - 50270) * 0.02 : 0.0;
      return SectionCard(
        title: title,
        children: [
          if (class2NI > 0)
            _SubRow('Class 2 (£3.45/week)', class2NI, fmtGbp, ct),
          if (class4band1 > 0)
            _SubRow('Class 4 @ 6% (£12,570–£50,270)', class4band1, fmtGbp, ct),
          if (class4band2 > 0)
            _SubRow(
                'Class 4 @ 2% (above £50,270)', class4band2, fmtGbp, ct),
          Divider(color: ct.cardBorder, height: AppSpacing.xl, thickness: 1),
          _SubRow('Total NI', ni, fmtGbp, ct, bold: true),
        ],
      );
    }

    final band1 = gross > UKTaxEngine.niPrimaryThreshold
        ? (min(gross, UKTaxEngine.niUpperEarningsLimit) -
                UKTaxEngine.niPrimaryThreshold) *
            UKTaxEngine.niRate1
        : 0.0;
    final band2 = gross > UKTaxEngine.niUpperEarningsLimit
        ? (gross - UKTaxEngine.niUpperEarningsLimit) * UKTaxEngine.niRate2
        : 0.0;

    return SectionCard(
      title: title,
      children: [
        if (band1 > 0)
          _SubRow(
            'Main rate 8% (£${UKTaxEngine.niPrimaryThreshold.toStringAsFixed(0)}–'
            '£${UKTaxEngine.niUpperEarningsLimit.toStringAsFixed(0)})',
            band1,
            fmtGbp,
            ct,
          ),
        if (band2 > 0)
          _SubRow(
            'Upper rate 2% (above £${UKTaxEngine.niUpperEarningsLimit.toStringAsFixed(0)})',
            band2,
            fmtGbp,
            ct,
          ),
        Divider(color: ct.cardBorder, height: AppSpacing.xl, thickness: 1),
        _SubRow('Total NI', ni, fmtGbp, ct, bold: true),
      ],
    );
  }
}

class _MonthlyWeeklyCard extends StatelessWidget {
  final IncomeTaxResult result;
  final NumberFormat fmtGbp;
  final CalcwiseTheme ct;

  const _MonthlyWeeklyCard({
    required this.result,
    required this.fmtGbp,
    required this.ct,
  });

  @override
  Widget build(BuildContext context) => SectionCard(
        title: 'Monthly & Weekly Breakdown',
        children: [
          _SubRow('Monthly gross', result.grossIncome / 12, fmtGbp, ct),
          if (result.pensionContribution > 0)
            _SubRow(
              'Monthly pension',
              result.pensionContribution / 12,
              fmtGbp,
              ct,
            ),
          _SubRow('Monthly income tax', result.incomeTax / 12, fmtGbp, ct),
          _SubRow(
              'Monthly NI', result.nationalInsurance / 12, fmtGbp, ct),
          Divider(color: ct.cardBorder, height: AppSpacing.xl, thickness: 1),
          _SubRow('Monthly take-home', result.netIncome / 12, fmtGbp, ct,
              bold: true),
          _SubRow('Weekly take-home', result.netIncome / 52, fmtGbp, ct,
              bold: true),
        ],
      );
}

class _CompareButton extends StatelessWidget {
  final CalcwiseTheme ct;
  const _CompareButton({required this.ct});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: OutlinedButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const SalaryComparisonScreen(),
            ),
          ),
          icon: const Icon(Icons.compare_arrows_rounded, size: 18),
          label: const Text('Compare Two Salaries →'),
        ),
      );
}

class _SaveButton extends StatelessWidget {
  final VoidCallback onSave;
  const _SaveButton({required this.onSave});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xs),
        child: OutlinedButton.icon(
          onPressed: onSave,
          icon: const Icon(Icons.bookmark_outline_rounded, size: 18),
          label: const Text('Save to History'),
        ),
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

class _IndentRow extends StatelessWidget {
  final String label;
  final double value;
  final NumberFormat fmt;
  final CalcwiseTheme ct;

  const _IndentRow(this.label, this.value, this.fmt, this.ct);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(
          left: AppSpacing.md,
          top: 2,
          bottom: 2,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: ct.textSecondary,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            Text(
              fmt.format(value),
              style: TextStyle(
                fontSize: 12,
                color: ct.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
}

class _SubRow extends StatelessWidget {
  final String label;
  final double value;
  final NumberFormat fmt;
  final CalcwiseTheme ct;
  final bool bold;

  const _SubRow(this.label, this.value, this.fmt, this.ct,
      {this.bold = false});

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
                  fontSize: 13,
                  color: ct.textSecondary,
                  fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            Text(
              fmt.format(value),
              style: TextStyle(
                fontSize: 13,
                color: bold ? AppTheme.primary : ct.textPrimary,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
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
