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

class StudentLoanScreen extends StatefulWidget {
  /// Optional pre-filled gross salary from the income tax tab.
  final double? initialGrossIncome;

  const StudentLoanScreen({super.key, this.initialGrossIncome});

  @override
  State<StudentLoanScreen> createState() => _StudentLoanScreenState();
}

class _StudentLoanScreenState extends State<StudentLoanScreen> with CalcwiseAutoCalcMixin {
  late final TextEditingController _grossCtrl;
  final _fmtGbp = NumberFormat.currency(locale: 'en_GB', symbol: '£');

  StudentLoanPlan _plan = StudentLoanPlan.plan2;
  StudentLoanResult? _result;

  static const _plans = StudentLoanPlan.values;

  @override
  void initState() {
    super.initState();
    analyticsService.logScreenView('student_loan');
    final initial = widget.initialGrossIncome;
    _grossCtrl = TextEditingController(
      text: initial != null ? initial.round().toString() : '35000',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _calculate();
    });
  }

  @override
  void dispose() {
    _grossCtrl.dispose();
    super.dispose();
  }

  void _calculate() {
    final gross =
        double.tryParse(_grossCtrl.text.replaceAll(',', '.').trim()) ?? 0;
    if (gross < 0) return;

    final result = calculateStudentLoan(grossIncome: gross, plan: _plan);
    setState(() => _result = result);

    analyticsService.logCalculationCompleted(
      params: {
        'calc_type': 'student_loan',
        'gross_income': gross.round(),
        'plan': _plan.shortLabel,
      },
    );
    adService.onAction();
  }

  Future<void> _save() async {
    final r = _result;
    if (r == null) return;
    final count = await DatabaseService.instance.count();
    if (!freemiumService.hasFullAccess &&
        count >= MonetizationConfig.freeRingBufferSize) {
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
        'type': 'student_loan',
        'gross_income': r.grossIncome,
        'plan': r.plan.shortLabel,
      },
      results: {
        'annual_repayment': r.annualRepayment,
        'monthly_repayment': r.monthlyRepayment,
        'threshold': r.threshold,
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
    setState(() {
      _plan = StudentLoanPlan.plan2;
      _result = null;
    });
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
              // ── Gross income ───────────────────────────────────────────────
              TextField(
                controller: _grossCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: false,
                ),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Gross Annual Income',
                  prefixText: '£',
                  hintText: '35000',
                  filled: true,
                ),
                onChanged: (_) => scheduleCalc(_calculate),
                onSubmitted: (_) => _calculate(),
              ),
              const SizedBox(height: AppSpacing.lg),

              // ── Plan selector ──────────────────────────────────────────────
              Container(
                decoration: BoxDecoration(
                  color: ct.surface,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: ct.cardBorder),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Student Loan Plan',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: ct.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    DropdownButtonHideUnderline(
                      child: DropdownButton<StudentLoanPlan>(
                        value: _plan,
                        isExpanded: true,
                        dropdownColor: ct.surface,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: ct.textPrimary,
                        ),
                        items: _plans
                            .map(
                              (p) => DropdownMenuItem(
                                value: p,
                                child: Text(p.label),
                              ),
                            )
                            .toList(),
                        onChanged: (p) {
                          if (p == null) return;
                          setState(() => _plan = p);
                          if (_result != null) _calculate();
                        },
                      ),
                    ),
                    Text(
                      'Repayment threshold: ${_fmtGbp.format(_plan.threshold)}/year  ·  '
                      '${_plan.repaymentRate == 0.09 ? '9%' : '6%'} above threshold  ·  '
                      '${_plan.writeOffNote}',
                      style: TextStyle(
                        fontSize: 11,
                        color: ct.textSecondary,
                        height: 1.5,
                      ),
                    ),
                  ],
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
                        label: 'MONTHLY REPAYMENT',
                        value: _fmtGbp.format(r.monthlyRepayment),
                        secondary: r.hasRepayment
                            ? '${r.plan.shortLabel} · ${_fmtGbp.format(r.annualRepayment)}/year'
                            : 'Income below threshold — no repayment',
                        stats: [
                          (
                            label: 'Annual',
                            value: _fmtGbp.format(r.annualRepayment),
                          ),
                          (
                            label: 'Weekly',
                            value: _fmtGbp.format(r.weeklyRepayment),
                          ),
                          (
                            label: 'Threshold',
                            value: _fmtGbp.format(r.threshold),
                          ),
                        ],
                      ),
                    ),
                    CalcwiseStaggerItem(
                      index: 1,
                      child: _InsightCard(result: r, fmtGbp: _fmtGbp, ct: ct),
                    ),
                    CalcwiseStaggerItem(
                      index: 2,
                      child: _SummaryCard(result: r, fmtGbp: _fmtGbp, ct: ct),
                    ),
                    CalcwiseStaggerItem(
                      index: 3,
                      child: _AllPlansCard(
                        grossIncome: r.grossIncome,
                        currentPlan: r.plan,
                        fmtGbp: _fmtGbp,
                        ct: ct,
                      ),
                    ),
                    CalcwiseStaggerItem(
                      index: 4,
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
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _InsightCard extends StatelessWidget {
  final StudentLoanResult result;
  final NumberFormat fmtGbp;
  final CalcwiseTheme ct;

  const _InsightCard(
      {required this.result, required this.fmtGbp, required this.ct});

  @override
  Widget build(BuildContext context) {
    final msg = result.hasRepayment
        ? 'You repay ${fmtGbp.format(result.monthlyRepayment)}/month '
            '(${fmtGbp.format(result.annualRepayment)}/year). '
            '${result.plan.writeOffNote}.'
        : 'Your income of ${fmtGbp.format(result.grossIncome)} is below the '
            '${result.plan.shortLabel} threshold of ${fmtGbp.format(result.threshold)}. '
            'No repayments are due until your income rises above the threshold.';

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
          Icon(Icons.school_outlined, color: AppTheme.primary, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              msg,
              style:
                  TextStyle(fontSize: 13, color: ct.textPrimary, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final StudentLoanResult result;
  final NumberFormat fmtGbp;
  final CalcwiseTheme ct;

  const _SummaryCard(
      {required this.result, required this.fmtGbp, required this.ct});

  @override
  Widget build(BuildContext context) => SectionCard(
        title: 'Repayment Summary',
        children: [
          _Row('Plan', result.plan.shortLabel, ct),
          _Row('Gross Income', fmtGbp.format(result.grossIncome), ct),
          _Row('Repayment Threshold', fmtGbp.format(result.threshold), ct),
          _Row(
            'Income Above Threshold',
            fmtGbp.format(
              result.grossIncome > result.threshold
                  ? result.grossIncome - result.threshold
                  : 0,
            ),
            ct,
          ),
          _Divider(ct),
          _Row(
            'Annual Repayment',
            fmtGbp.format(result.annualRepayment),
            ct,
            highlight: result.hasRepayment,
          ),
          _Row('Monthly Repayment', fmtGbp.format(result.monthlyRepayment), ct,
              bold: true),
          _Row('Weekly Repayment', fmtGbp.format(result.weeklyRepayment), ct),
          Divider(color: ct.cardBorder, height: AppSpacing.xl, thickness: 1),
          Text(
            result.plan.writeOffNote,
            style:
                TextStyle(fontSize: 12, color: ct.textSecondary, height: 1.4),
          ),
        ],
      );
}

class _AllPlansCard extends StatelessWidget {
  final double grossIncome;
  final StudentLoanPlan currentPlan;
  final NumberFormat fmtGbp;
  final CalcwiseTheme ct;

  const _AllPlansCard({
    required this.grossIncome,
    required this.currentPlan,
    required this.fmtGbp,
    required this.ct,
  });

  @override
  Widget build(BuildContext context) {
    final rows = StudentLoanPlan.values.map((p) {
      final r = calculateStudentLoan(grossIncome: grossIncome, plan: p);
      return (plan: p, monthly: r.monthlyRepayment, threshold: p.threshold);
    }).toList();

    return SectionCard(
      title: 'All Plans Comparison',
      children: [
        for (final row in rows) ...[
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
                        row.plan.shortLabel,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: row.plan == currentPlan
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: row.plan == currentPlan
                              ? ct.textPrimary
                              : ct.textSecondary,
                        ),
                      ),
                      Text(
                        'Threshold: ${fmtGbp.format(row.threshold)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: ct.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${fmtGbp.format(row.monthly)}/mo',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: row.plan == currentPlan
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: row.plan == currentPlan
                        ? AppTheme.primary
                        : ct.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
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
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: highlight ? AppTheme.accent : ct.textSecondary,
                fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
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
