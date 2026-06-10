import 'package:calcwise_core/calcwise_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../core/analytics/analytics_service.dart';
import '../core/freemium/freemium_service.dart';
import '../core/services/pdf_export_service.dart';
import '../core/theme/app_theme.dart';
import '../core/uk_tax_engine.dart';
import '../main.dart' show adService, analyticsService, smartHistoryService;
import '../widgets/paywall_soft.dart';
import '../widgets/save_scenario_button.dart';
import 'history_screen.dart';

// ── Result model ──────────────────────────────────────────────────────────────

class _JobResult {
  final String name;
  final double gross;
  final double pension;
  final double effectiveGross;
  final double tax;
  final double ni;
  final double netPay;
  final double monthly;
  final double effectiveRate;

  const _JobResult({
    required this.name,
    required this.gross,
    required this.pension,
    required this.effectiveGross,
    required this.tax,
    required this.ni,
    required this.netPay,
    required this.monthly,
    required this.effectiveRate,
  });
}

// ── Screen ────────────────────────────────────────────────────────────────────

class SalaryComparisonScreen extends StatefulWidget {
  const SalaryComparisonScreen({super.key});

  @override
  State<SalaryComparisonScreen> createState() =>
      _SalaryComparisonScreenState();
}

class _SalaryComparisonScreenState extends State<SalaryComparisonScreen> with CalcwiseAutoCalcMixin {
  // Job A controllers
  final _nameACtrl = TextEditingController(text: 'Job A');
  final _grossACtrl = TextEditingController(text: '45000');
  final _pensionACtrl = TextEditingController(text: '0');
  bool _selfEmployedA = false;

  // Job B controllers
  final _nameBCtrl = TextEditingController(text: 'Job B');
  final _grossBCtrl = TextEditingController(text: '52000');
  final _pensionBCtrl = TextEditingController(text: '0');
  bool _selfEmployedB = false;

  bool _isScotland = false;

  _JobResult? _resultA;
  _JobResult? _resultB;

  final _fmtGbp = NumberFormat.currency(locale: 'en_GB', symbol: '£');

  @override
  void initState() {
    super.initState();
    analyticsService.logScreenView('salary_comparison');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _calculate();
    });
  }

  @override
  void dispose() {
    _nameACtrl.dispose();
    _grossACtrl.dispose();
    _pensionACtrl.dispose();
    _nameBCtrl.dispose();
    _grossBCtrl.dispose();
    _pensionBCtrl.dispose();
    smartHistoryService.cancelPendingSave('taxuk', 'salary_comparison');
    super.dispose();
  }

  _JobResult _computeJob({
    required String name,
    required double gross,
    required double pensionPct,
    required bool isSelfEmployed,
  }) {
    final pension = gross * pensionPct / 100;
    final effectiveGross = gross - pension;
    final tax = UKTaxEngine.incomeTax(
      effectiveGross,
      isScotland: _isScotland,
    );
    final niEmployee = UKTaxEngine.nationalInsurance(effectiveGross);
    final finalNI =
        isSelfEmployed ? calculateSelfEmployedNI(effectiveGross) : niEmployee;
    final netPay = effectiveGross - tax - finalNI;
    final monthly = netPay / 12;
    final effectiveRate =
        effectiveGross > 0 ? (tax + finalNI) / effectiveGross : 0.0;

    return _JobResult(
      name: name.isEmpty ? 'Job' : name,
      gross: gross,
      pension: pension,
      effectiveGross: effectiveGross,
      tax: tax,
      ni: finalNI,
      netPay: netPay,
      monthly: monthly,
      effectiveRate: effectiveRate,
    );
  }

  void _calculate() {
    final grossA =
        double.tryParse(_grossACtrl.text.replaceAll(',', '.').trim()) ?? 0;
    final grossB =
        double.tryParse(_grossBCtrl.text.replaceAll(',', '.').trim()) ?? 0;
    final pensionA =
        double.tryParse(_pensionACtrl.text.replaceAll(',', '.').trim()) ?? 0;
    final pensionB =
        double.tryParse(_pensionBCtrl.text.replaceAll(',', '.').trim()) ?? 0;

    final rA = _computeJob(
      name: _nameACtrl.text,
      gross: grossA,
      pensionPct: pensionA.clamp(0, 100),
      isSelfEmployed: _selfEmployedA,
    );
    final rB = _computeJob(
      name: _nameBCtrl.text,
      gross: grossB,
      pensionPct: pensionB.clamp(0, 100),
      isSelfEmployed: _selfEmployedB,
    );

    setState(() {
      _resultA = rA;
      _resultB = rB;
    });

    analyticsService.logCalculationCompleted(params: {
      'type': 'salary_compare',
      'gross_a': grossA.round(),
      'gross_b': grossB.round(),
      'is_scotland': '$_isScotland',
    });
    adService.onAction();
    _scheduleAutoSave();
  }

  double _roundTo(double v, double step) => (v / step).round() * step;

  void _scheduleAutoSave() {
    final rA = _resultA;
    final rB = _resultB;
    if (rA == null || rB == null) return;
    if (rA.gross <= 0 && rB.gross <= 0) return;
    final inputHash = ResultHasher.hashMixed({
      'salary_a': _roundTo(rA.gross, 1000),
      'salary_b': _roundTo(rB.gross, 1000),
    });
    smartHistoryService.scheduleAutoSave(
      appKey: 'taxuk',
      screenId: 'salary_comparison',
      inputHash: inputHash,
      l1: {
        'salary_a': rA.gross,
        'salary_b': rB.gross,
        'net_a': rA.netPay,
        'net_b': rB.netPay,
        'difference': (rA.netPay - rB.netPay).abs(),
      },
      l2: {
        'inputs': {
          'salaryA': rA.gross,
          'salaryB': rB.gross,
          'regionA': _isScotland ? 'scotland' : 'england',
          'regionB': _isScotland ? 'scotland' : 'england',
        },
        'results': {
          'netA': rA.netPay,
          'netB': rB.netPay,
          'taxA': rA.tax,
          'taxB': rB.tax,
          'difference': (rA.netPay - rB.netPay).abs(),
        },
      },
      onSaved: () { if (mounted) HistoryScreen.refreshNotifier.value++; },
    );
  }

  Future<void> _saveScenario(String? label) async {
    final rA = _resultA;
    final rB = _resultB;
    if (rA == null || rB == null) return;
    final inputHash = ResultHasher.hashMixed({
      'salary_a': _roundTo(rA.gross, 1000),
      'salary_b': _roundTo(rB.gross, 1000),
    });
    await smartHistoryService.saveScenario(
      appKey: 'taxuk',
      screenId: 'salary_comparison',
      inputHash: inputHash,
      l1: {
        'salary_a': rA.gross,
        'salary_b': rB.gross,
        'net_a': rA.netPay,
        'net_b': rB.netPay,
        'difference': (rA.netPay - rB.netPay).abs(),
      },
      l2: {
        'inputs': {
          'salaryA': rA.gross,
          'salaryB': rB.gross,
          'regionA': _isScotland ? 'scotland' : 'england',
          'regionB': _isScotland ? 'scotland' : 'england',
        },
        'results': {
          'netA': rA.netPay,
          'netB': rB.netPay,
          'taxA': rA.tax,
          'taxB': rB.tax,
          'difference': (rA.netPay - rB.netPay).abs(),
        },
      },
      label: label,
    );
    analyticsService.logResultSaved();
    adService.onSave();
  }

  void _reset() {
    _nameACtrl.text = 'Job A';
    _grossACtrl.text = '45000';
    _pensionACtrl.text = '0';
    _nameBCtrl.text = 'Job B';
    _grossBCtrl.text = '52000';
    _pensionBCtrl.text = '0';
    setState(() {
      _selfEmployedA = false;
      _selfEmployedB = false;
      _isScotland = false;
      _resultA = null;
      _resultB = null;
    });
  }


  Future<void> _exportPdf() async {
    final rA = _resultA;
    final rB = _resultB;
    if (rA == null || rB == null) return;
    if (!freemiumService.hasFullAccess) {
      if (!mounted) return;
      await PaywallSoft.show(
        context,
        featureTitle: 'Export PDF',
        featureSubtitle: 'Upgrade to export and share your results as PDF.',
      );
      return;
    }
    await TaxUkPdfExportService.exportSalaryComparison(
      context: context,
      nameA: rA.name,
      grossA: rA.gross,
      taxA: rA.tax,
      niA: rA.ni,
      netA: rA.netPay,
      monthlyA: rA.monthly,
      nameB: rB.name,
      grossB: rB.gross,
      taxB: rB.tax,
      niB: rB.ni,
      netB: rB.netPay,
      monthlyB: rB.monthly,
      isScotland: _isScotland,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ct = CalcwiseTheme.of(context);
    final rA = _resultA;
    final rB = _resultB;

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
              // ── Column headers ─────────────────────────────────────────
              _ColumnHeaders(ct: ct),
              const SizedBox(height: AppSpacing.sm),

              // ── Job name row ──────────────────────────────────────────
              _InputRow(
                label: 'Job Name',
                fieldA: TextField(
                  controller: _nameACtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    hintText: 'Job A',
                    filled: true,
                  ),
                  onChanged: (_) => scheduleCalc(_calculate),
                  onSubmitted: (_) => _calculate(),
                ),
                fieldB: TextField(
                  controller: _nameBCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    hintText: 'Job B',
                    filled: true,
                  ),
                  onChanged: (_) => scheduleCalc(_calculate),
                  onSubmitted: (_) => _calculate(),
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // ── Gross salary row ──────────────────────────────────────
              _InputRow(
                label: 'Gross Salary (£)',
                fieldA: TextField(
                  controller: _grossACtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: false,
                  ),
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    prefixText: '£',
                    hintText: '45000',
                    filled: true,
                  ),
                  onChanged: (_) => scheduleCalc(_calculate),
                  onSubmitted: (_) => _calculate(),
                ),
                fieldB: TextField(
                  controller: _grossBCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: false,
                  ),
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    prefixText: '£',
                    hintText: '52000',
                    filled: true,
                  ),
                  onChanged: (_) => scheduleCalc(_calculate),
                  onSubmitted: (_) => _calculate(),
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // ── Pension % row ──────────────────────────────────────────
              _InputRow(
                label: 'Pension (%)',
                fieldA: TextField(
                  controller: _pensionACtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'^\d{0,2}(\.\d{0,1})?'),
                    ),
                  ],
                  decoration: const InputDecoration(
                    suffixText: '%',
                    hintText: '0',
                    filled: true,
                  ),
                  onChanged: (_) => scheduleCalc(_calculate),
                  onSubmitted: (_) => _calculate(),
                ),
                fieldB: TextField(
                  controller: _pensionBCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'^\d{0,2}(\.\d{0,1})?'),
                    ),
                  ],
                  decoration: const InputDecoration(
                    suffixText: '%',
                    hintText: '0',
                    filled: true,
                  ),
                  onChanged: (_) => scheduleCalc(_calculate),
                  onSubmitted: (_) => _calculate(),
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // ── Self-employed toggles ──────────────────────────────────
              _ToggleRow(
                label: 'Self-Employed',
                ct: ct,
                valueA: _selfEmployedA,
                valueB: _selfEmployedB,
                onChangedA: (v) {
                  setState(() => _selfEmployedA = v);
                  if (_resultA != null) _calculate();
                },
                onChangedB: (v) {
                  setState(() => _selfEmployedB = v);
                  if (_resultB != null) _calculate();
                },
              ),
              const SizedBox(height: AppSpacing.lg),

              // ── Scotland toggle ───────────────────────────────────────
              Container(
                decoration: BoxDecoration(
                  color: ct.surface,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: ct.cardBorder),
                ),
                child: SwitchListTile(
                  title: Text(
                    'Scottish Income Tax Rates',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: ct.textPrimary,
                    ),
                  ),
                  subtitle: Text(
                    _isScotland
                        ? 'Scotland: 6 bands (19%–48%)'
                        : 'England / Wales / NI: 3 bands (20%–45%)',
                    style: TextStyle(
                      fontSize: 12,
                      color: ct.textSecondary,
                    ),
                  ),
                  value: _isScotland,
                  activeColor: AppTheme.primary,
                  onChanged: (v) {
                    setState(() => _isScotland = v);
                    analyticsService.logScotlandToggled(v);
                    if (_resultA != null) _calculate();
                  },
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.xs,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),

              // ── Action buttons ────────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: _calculate,
                      child: const Text('Compare'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  OutlinedButton(
                    onPressed: _reset,
                    child: const Text('Reset'),
                  ),
                ],
              ),

              // ── Results ───────────────────────────────────────────────
              if (rA != null && rB != null) ...[
                const SizedBox(height: AppSpacing.xl),
                CalcwisePageEntrance(
                  child: Column(
                    children: [
                      // Hero cards
                      CalcwiseStaggerItem(
                        index: 0,
                        child: _HeroSection(
                          rA: rA,
                          rB: rB,
                          fmtGbp: _fmtGbp,
                          ct: ct,
                        ),
                      ),

                      // Comparison table
                      CalcwiseStaggerItem(
                        index: 1,
                        child: _ComparisonTable(
                          rA: rA,
                          rB: rB,
                          fmtGbp: _fmtGbp,
                          ct: ct,
                        ),
                      ),

                      // Insights
                      CalcwiseStaggerItem(
                        index: 2,
                        child: _InsightsCard(
                          rA: rA,
                          rB: rB,
                          fmtGbp: _fmtGbp,
                          ct: ct,
                        ),
                      ),

                      // Save button
                      CalcwiseStaggerItem(
                        index: 3,
                        child: Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.sm),
                          child: SaveScenarioButton(onSave: _saveScenario),
                        ),
                      ),
                      // Export PDF button
                      CalcwiseStaggerItem(
                        index: 4,
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
                    ],
                  ),
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

// ── Layout helpers ────────────────────────────────────────────────────────────

class _ColumnHeaders extends StatelessWidget {
  final CalcwiseTheme ct;
  const _ColumnHeaders({required this.ct});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          const SizedBox(width: 100),
          Expanded(
            child: Center(
              child: Text(
                'JOB A',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primary,
                  letterSpacing: 1.0,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Center(
              child: Text(
                'JOB B',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.accent,
                  letterSpacing: 1.0,
                ),
              ),
            ),
          ),
        ],
      );
}

class _InputRow extends StatelessWidget {
  final String label;
  final Widget fieldA;
  final Widget fieldB;

  const _InputRow({
    required this.label,
    required this.fieldA,
    required this.fieldB,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: CalcwiseTheme.of(context).textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Expanded(child: fieldA),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: fieldB),
            ],
          ),
        ],
      );
}

class _ToggleRow extends StatelessWidget {
  final String label;
  final CalcwiseTheme ct;
  final bool valueA;
  final bool valueB;
  final ValueChanged<bool> onChangedA;
  final ValueChanged<bool> onChangedB;

  const _ToggleRow({
    required this.label,
    required this.ct,
    required this.valueA,
    required this.valueB,
    required this.onChangedA,
    required this.onChangedB,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: ct.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Expanded(
                child: _ToggleChip(
                  label: valueA ? 'Self-Employed' : 'Employed',
                  value: valueA,
                  onChanged: onChangedA,
                  ct: ct,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _ToggleChip(
                  label: valueB ? 'Self-Employed' : 'Employed',
                  value: valueB,
                  onChanged: onChangedB,
                  ct: ct,
                ),
              ),
            ],
          ),
        ],
      );
}

class _ToggleChip extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final CalcwiseTheme ct;

  const _ToggleChip({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.ct,
  });

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            color: value
                ? AppTheme.primary.withValues(alpha: 0.12)
                : ct.surface,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(
              color: value ? AppTheme.primary : ct.cardBorder,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                value
                    ? Icons.business_center_rounded
                    : Icons.work_outline_rounded,
                size: 14,
                color: value ? AppTheme.primary : ct.textSecondary,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: value ? AppTheme.primary : ct.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );
}

// ── Hero section ──────────────────────────────────────────────────────────────

class _HeroSection extends StatelessWidget {
  final _JobResult rA;
  final _JobResult rB;
  final NumberFormat fmtGbp;
  final CalcwiseTheme ct;

  const _HeroSection({
    required this.rA,
    required this.rB,
    required this.fmtGbp,
    required this.ct,
  });

  @override
  Widget build(BuildContext context) {
    final aIsBetter = rA.monthly >= rB.monthly;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _HeroJobCard(
            result: rA,
            isBetter: aIsBetter,
            accentColor: AppTheme.primary,
            fmtGbp: fmtGbp,
            ct: ct,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _HeroJobCard(
            result: rB,
            isBetter: !aIsBetter,
            accentColor: AppTheme.accent,
            fmtGbp: fmtGbp,
            ct: ct,
          ),
        ),
      ],
    );
  }
}

class _HeroJobCard extends StatelessWidget {
  final _JobResult result;
  final bool isBetter;
  final Color accentColor;
  final NumberFormat fmtGbp;
  final CalcwiseTheme ct;

  const _HeroJobCard({
    required this.result,
    required this.isBetter,
    required this.accentColor,
    required this.fmtGbp,
    required this.ct,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: ct.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: isBetter ? accentColor : ct.cardBorder,
            width: isBetter ? 2 : 1,
          ),
          boxShadow: isBetter
              ? [
                  BoxShadow(
                    color: accentColor.withValues(alpha: 0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    result.name,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: ct.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isBetter)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.successGreen,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'BETTER ↑',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: Theme.of(context).colorScheme.onPrimary,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'MONTHLY',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: ct.textSecondary,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              fmtGbp.format(result.monthly),
              style: TextStyle(
                fontSize: AppTextSize.titleMd,
                fontWeight: FontWeight.w800,
                color: accentColor,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${fmtGbp.format(result.netPay)} / yr',
              style: TextStyle(
                fontSize: 12,
                color: ct.textSecondary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Eff. rate: ${(result.effectiveRate * 100).toStringAsFixed(1)}%',
              style: TextStyle(
                fontSize: 11,
                color: ct.textSecondary,
              ),
            ),
          ],
        ),
      );
}

// ── Comparison table ──────────────────────────────────────────────────────────

class _ComparisonTable extends StatelessWidget {
  final _JobResult rA;
  final _JobResult rB;
  final NumberFormat fmtGbp;
  final CalcwiseTheme ct;

  const _ComparisonTable({
    required this.rA,
    required this.rB,
    required this.fmtGbp,
    required this.ct,
  });

  @override
  Widget build(BuildContext context) {
    final diffMonthly = rA.monthly - rB.monthly;
    final betterName = diffMonthly >= 0 ? rA.name : rB.name;
    final diffAbs = diffMonthly.abs();

    return SectionCard(
      title: 'Side-by-Side Comparison',
      children: [
        // Header
        _TableHeader(nameA: rA.name, nameB: rB.name, ct: ct),
        _CmpDivider(ct),

        _CmpRow(
          label: 'Gross Salary',
          valueA: fmtGbp.format(rA.gross),
          valueB: fmtGbp.format(rB.gross),
          ct: ct,
        ),
        _CmpRow(
          label: 'Pension',
          valueA: fmtGbp.format(rA.pension),
          valueB: fmtGbp.format(rB.pension),
          ct: ct,
        ),
        _CmpRow(
          label: 'Income Tax',
          valueA: fmtGbp.format(rA.tax),
          valueB: fmtGbp.format(rB.tax),
          ct: ct,
          highlight: true,
        ),
        _CmpRow(
          label: 'Nat. Insurance',
          valueA: fmtGbp.format(rA.ni),
          valueB: fmtGbp.format(rB.ni),
          ct: ct,
          highlight: true,
        ),
        _CmpDivider(ct),
        _CmpRow(
          label: 'Take-Home / mo',
          valueA: fmtGbp.format(rA.monthly),
          valueB: fmtGbp.format(rB.monthly),
          ct: ct,
          bold: true,
        ),
        _CmpRow(
          label: 'Take-Home / yr',
          valueA: fmtGbp.format(rA.netPay),
          valueB: fmtGbp.format(rB.netPay),
          ct: ct,
          bold: true,
        ),
        _CmpRow(
          label: 'Effective Rate',
          valueA: '${(rA.effectiveRate * 100).toStringAsFixed(1)}%',
          valueB: '${(rB.effectiveRate * 100).toStringAsFixed(1)}%',
          ct: ct,
        ),
        _CmpDivider(ct),

        // Monthly difference — full width
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: AppTheme.successGreen.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(
                  color: AppTheme.successGreen.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Monthly Difference',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: ct.textPrimary,
                    ),
                  ),
                ),
                Text(
                  '${fmtGbp.format(diffAbs)}/mo',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.successGreen,
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 2, bottom: AppSpacing.xs),
          child: Text(
            'in favour of $betterName',
            style: TextStyle(
              fontSize: 12,
              color: ct.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

class _TableHeader extends StatelessWidget {
  final String nameA;
  final String nameB;
  final CalcwiseTheme ct;

  const _TableHeader({
    required this.nameA,
    required this.nameB,
    required this.ct,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
        child: Row(
          children: [
            const Expanded(flex: 2, child: SizedBox()),
            Expanded(
              flex: 3,
              child: Text(
                nameA,
                textAlign: TextAlign.end,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              flex: 3,
              child: Text(
                nameB,
                textAlign: TextAlign.end,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.accent,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
}

class _CmpRow extends StatelessWidget {
  final String label;
  final String valueA;
  final String valueB;
  final CalcwiseTheme ct;
  final bool highlight;
  final bool bold;

  const _CmpRow({
    required this.label,
    required this.valueA,
    required this.valueB,
    required this.ct,
    this.highlight = false,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: highlight ? AppTheme.accent : ct.textSecondary,
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                valueA,
                textAlign: TextAlign.end,
                style: TextStyle(
                  fontSize: 13,
                  color: bold
                      ? AppTheme.primary
                      : highlight
                          ? AppTheme.accent
                          : ct.textPrimary,
                  fontWeight:
                      bold || highlight ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              flex: 3,
              child: Text(
                valueB,
                textAlign: TextAlign.end,
                style: TextStyle(
                  fontSize: 13,
                  color: bold
                      ? AppTheme.accent
                      : highlight
                          ? AppTheme.accent
                          : ct.textPrimary,
                  fontWeight:
                      bold || highlight ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );
}

class _CmpDivider extends StatelessWidget {
  final CalcwiseTheme ct;
  const _CmpDivider(this.ct);

  @override
  Widget build(BuildContext context) => Divider(
        color: ct.cardBorder,
        height: AppSpacing.xl,
        thickness: 1,
      );
}

// ── Insights card ─────────────────────────────────────────────────────────────

class _InsightsCard extends StatelessWidget {
  final _JobResult rA;
  final _JobResult rB;
  final NumberFormat fmtGbp;
  final CalcwiseTheme ct;

  const _InsightsCard({
    required this.rA,
    required this.rB,
    required this.fmtGbp,
    required this.ct,
  });

  @override
  Widget build(BuildContext context) {
    final diffAnnual = (rA.netPay - rB.netPay).abs();
    final diffGross = (rA.gross - rB.gross).abs();
    final diffMonthly = (rA.monthly - rB.monthly).abs();
    final betterResult = rA.monthly >= rB.monthly ? rA : rB;
    final worseResult = rA.monthly >= rB.monthly ? rB : rA;
    final diffEffRate =
        (rA.effectiveRate - rB.effectiveRate).abs() * 100;

    final grossDiffText = diffGross > 0
        ? ' Despite a ${fmtGbp.format(diffGross)} higher gross,'
        : '';

    final insight1 =
        '${betterResult.name} pays ${fmtGbp.format(diffAnnual)} more per year '
        'after tax (${fmtGbp.format(diffMonthly)}/mo).$grossDiffText';

    final insight2 = diffEffRate >= 0.1
        ? 'The effective tax+NI rate difference is '
            '${diffEffRate.toStringAsFixed(1)}% — '
            '${betterResult.name} at '
            '${(betterResult.effectiveRate * 100).toStringAsFixed(1)}% vs '
            '${worseResult.name} at '
            '${(worseResult.effectiveRate * 100).toStringAsFixed(1)}%.'
        : 'Both jobs carry nearly identical effective tax+NI rates '
            '(${(betterResult.effectiveRate * 100).toStringAsFixed(1)}%).';

    return SectionCard(
      title: 'Insights',
      children: [
        _InsightBullet(
          icon: Icons.trending_up_rounded,
          text: insight1,
          color: AppTheme.successGreen,
          ct: ct,
        ),
        const SizedBox(height: AppSpacing.sm),
        _InsightBullet(
          icon: Icons.percent_rounded,
          text: insight2,
          color: AppTheme.primary,
          ct: ct,
        ),
        if (rA.pension > 0 || rB.pension > 0) ...[
          const SizedBox(height: AppSpacing.sm),
          _InsightBullet(
            icon: Icons.savings_rounded,
            text: 'Pension contributions reduce taxable income. '
                '${rA.name}: ${fmtGbp.format(rA.pension)}/yr, '
                '${rB.name}: ${fmtGbp.format(rB.pension)}/yr.',
            color: AppTheme.warningOrange,
            ct: ct,
          ),
        ],
        if (rA.gross > 100000 || rB.gross > 100000) ...[
          const SizedBox(height: AppSpacing.sm),
          _InsightBullet(
            icon: Icons.warning_amber_rounded,
            text: 'Salary above £100k triggers Personal Allowance taper — '
                'the marginal rate reaches 60% between £100k–£125,140.',
            color: AppTheme.warningOrange,
            ct: ct,
          ),
        ],
      ],
    );
  }
}

class _InsightBullet extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  final CalcwiseTheme ct;

  const _InsightBullet({
    required this.icon,
    required this.text,
    required this.color,
    required this.ct,
  });

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 1),
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                color: ct.textPrimary,
                height: 1.4,
              ),
            ),
          ),
        ],
      );
}
