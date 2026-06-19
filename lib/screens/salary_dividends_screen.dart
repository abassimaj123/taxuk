import 'dart:math';
import 'package:calcwise_core/calcwise_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../core/uk_tax_engine.dart';
import '../core/analytics/analytics_service.dart';
import '../core/freemium/freemium_service.dart';
import '../core/freemium/iap_service.dart';
import '../core/theme/app_theme.dart';
import '../main.dart' show adService, analyticsService;
import '../widgets/paywall_soft.dart';

// ── Corporation Tax (2025/26) ─────────────────────────────────────────────────

const double _corpTaxSmall = 0.19;
const double _corpTaxMain = 0.25;
const double _corpTaxSmallProfitLimit = 50000.0;
const double _corpTaxMainProfitLimit = 250000.0;

double _corporationTax(double profit) {
  if (profit <= 0) return 0;
  if (profit <= _corpTaxSmallProfitLimit) return profit * _corpTaxSmall;
  if (profit >= _corpTaxMainProfitLimit) return profit * _corpTaxMain;
  final mainTax = profit * _corpTaxMain;
  final marginalRelief =
      ((_corpTaxMainProfitLimit - profit) / (_corpTaxMainProfitLimit - _corpTaxSmallProfitLimit)) *
          ((_corpTaxMain - _corpTaxSmall) * _corpTaxMainProfitLimit);
  return max(0, mainTax - marginalRelief);
}

double _corpTaxEffectiveRate(double profit) =>
    profit > 0 ? _corporationTax(profit) / profit : 0;

// ── Employer NI ───────────────────────────────────────────────────────────────

const double _employerNiThreshold = 9100.0;
const double _employerNiRate = 0.138;

double _employerNI(double salary) =>
    salary > _employerNiThreshold ? (salary - _employerNiThreshold) * _employerNiRate : 0;

// ── Split Result Model ────────────────────────────────────────────────────────

class _SplitResult {
  final double companyProfit;
  final double salary;
  final double employerNI;
  final double companyTaxableProfit;
  final double corporationTax;
  final double availableForDividend;
  final double grossDividend;
  final double incomeTax;
  final double employeeNI;
  final double dividendTax;
  final double totalPersonalTax;
  final double totalTaxBurden;
  final double personalTakeHome;
  final double effectiveTotalRate;

  const _SplitResult({
    required this.companyProfit,
    required this.salary,
    required this.employerNI,
    required this.companyTaxableProfit,
    required this.corporationTax,
    required this.availableForDividend,
    required this.grossDividend,
    required this.incomeTax,
    required this.employeeNI,
    required this.dividendTax,
    required this.totalPersonalTax,
    required this.totalTaxBurden,
    required this.personalTakeHome,
    required this.effectiveTotalRate,
  });
}

_SplitResult _calculate({
  required double companyProfit,
  required double salary,
}) {
  final empNI = _employerNI(salary);
  final taxableProfit = max(0.0, companyProfit - salary - empNI);
  final corpTax = _corporationTax(taxableProfit);
  final retainedProfit = taxableProfit - corpTax;

  final grossDividend = retainedProfit;
  final incomeTax = UKTaxEngine.incomeTax(salary);
  final employeeNI = UKTaxEngine.nationalInsurance(salary);
  final divResult = calculateDividend(
    grossIncome: salary,
    grossDividend: grossDividend,
  );

  final totalPersonalTax = incomeTax + employeeNI + divResult.taxDue;
  final totalTaxBurden = corpTax + totalPersonalTax + empNI;
  final personalTakeHome = salary - incomeTax - employeeNI + grossDividend - divResult.taxDue;
  final effectiveTotalRate = companyProfit > 0 ? totalTaxBurden / companyProfit : 0.0;

  return _SplitResult(
    companyProfit: companyProfit,
    salary: salary,
    employerNI: empNI,
    companyTaxableProfit: taxableProfit,
    corporationTax: corpTax,
    availableForDividend: retainedProfit,
    grossDividend: grossDividend,
    incomeTax: incomeTax,
    employeeNI: employeeNI,
    dividendTax: divResult.taxDue,
    totalPersonalTax: totalPersonalTax,
    totalTaxBurden: totalTaxBurden,
    personalTakeHome: personalTakeHome,
    effectiveTotalRate: effectiveTotalRate,
  );
}

_SplitResult _findOptimal(double companyProfit) {
  double bestSalary = 0;
  double bestTax = double.infinity;
  const step = 500.0;
  final maxSalary = min(companyProfit, UKTaxEngine.personalAllowance);
  for (double s = 0; s <= maxSalary; s += step) {
    final r = _calculate(companyProfit: companyProfit, salary: s);
    if (r.totalTaxBurden < bestTax) {
      bestTax = r.totalTaxBurden;
      bestSalary = s;
    }
  }
  return _calculate(companyProfit: companyProfit, salary: bestSalary);
}

// ── Screen ────────────────────────────────────────────────────────────────────

class SalaryDividendsScreen extends StatefulWidget {
  const SalaryDividendsScreen({super.key});

  @override
  State<SalaryDividendsScreen> createState() => _SalaryDividendsScreenState();
}

class _SalaryDividendsScreenState extends State<SalaryDividendsScreen>
    with CalcwiseAutoCalcMixin {
  final _profitCtrl = TextEditingController(text: '50000');
  final _fmtGbp = NumberFormat.currency(locale: 'en_GB', symbol: '£');
  final _fmtPct = NumberFormat.percentPattern('en_GB');

  _SplitResult? _allSalary;
  _SplitResult? _optimal;
  _SplitResult? _allDividends;

  double _sliderSalary = UKTaxEngine.personalAllowance;

  @override
  void initState() {
    super.initState();
    analyticsService.logScreenView('salary_dividends');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _runCalc();
    });
  }

  @override
  void dispose() {
    _profitCtrl.dispose();
    super.dispose();
  }

  double get _profit =>
      double.tryParse(_profitCtrl.text.replaceAll(',', '.').trim()) ?? 0;

  void _runCalc() {
    analyticsService.maybeLogFirstCalculate();
    final profit = _profit;
    if (profit <= 0) {
      setState(() {
        _allSalary = null;
        _optimal = null;
        _allDividends = null;
      });
      return;
    }

    final allSalary = _calculate(companyProfit: profit, salary: profit);
    final optimal = _findOptimal(profit);
    final allDividends = _calculate(companyProfit: profit, salary: 0);

    setState(() {
      _allSalary = allSalary;
      _optimal = optimal;
      _allDividends = allDividends;
      _sliderSalary = optimal.salary.clamp(0, UKTaxEngine.personalAllowance);
    });

    analyticsService.logCalculationCompleted(
      params: {
        'calc_type': 'salary_dividends',
        'company_profit': profit.round(),
      },
    );
    adService.onAction();
  }

  void _onSliderChanged(double val) {
    final profit = _profit;
    if (profit <= 0) return;
    setState(() {
      _sliderSalary = val;
    });
  }

  void _onSliderEnd(double val) {
    final profit = _profit;
    if (profit <= 0) return;
    setState(() {
      _sliderSalary = val;
    });
    adService.onAction();
  }

  void _showPaywall() {
    if (freemiumService.hasFullAccess) return;
    PaywallSoft.show(
      context,
      featureTitle: 'Detailed Tax Breakdown',
      featureSubtitle:
          'See the full per-scenario breakdown including corp tax, NI and dividend tax.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final ct = CalcwiseTheme.of(context);
    final hasResult = _allSalary != null && _optimal != null && _allDividends != null;
    final profit = _profit;
    final maxSlider = profit > 0 ? min(profit, UKTaxEngine.personalAllowance) : UKTaxEngine.personalAllowance;

    final sliderResult = hasResult && profit > 0
        ? _calculate(companyProfit: profit, salary: _sliderSalary)
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Salary vs Dividends'),
        leading: const BackButton(),
      ),
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
                TextField(
                  controller: _profitCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: false),
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Company Profit (before salary)',
                    prefixText: '£',
                    hintText: '50000',
                    filled: true,
                  ),
                  onChanged: (_) => scheduleCalc(_runCalc),
                  onSubmitted: (_) => _runCalc(),
                ),
                const SizedBox(height: AppSpacing.xs),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Text(
                    "Enter your company's profit before paying yourself. "
                    'We compare three strategies to find the most tax-efficient split.',
                    style: TextStyle(
                      fontSize: AppTextSize.sm,
                      color: ct.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                Row(children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: _runCalc,
                      child: const Text('Calculate'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  OutlinedButton(
                    onPressed: () {
                      _profitCtrl.text = '50000';
                      setState(() {
                        _allSalary = null;
                        _optimal = null;
                        _allDividends = null;
                        _sliderSalary = UKTaxEngine.personalAllowance;
                      });
                    },
                    child: const Text('Reset'),
                  ),
                ]),

                if (hasResult) ...[
                  const SizedBox(height: AppSpacing.xl),
                  CalcwisePageEntrance(
                    child: Column(
                      children: [
                        CalcwiseStaggerItem(
                          index: 0,
                          child: _ComparisonTable(
                            allSalary: _allSalary!,
                            optimal: _optimal!,
                            allDividends: _allDividends!,
                            fmtGbp: _fmtGbp,
                            fmtPct: _fmtPct,
                            ct: ct,
                          ),
                        ),
                        CalcwiseStaggerItem(
                          index: 1,
                          child: _OptimalInsightCard(
                            optimal: _optimal!,
                            allSalary: _allSalary!,
                            allDividends: _allDividends!,
                            fmtGbp: _fmtGbp,
                            ct: ct,
                          ),
                        ),
                        CalcwiseStaggerItem(
                          index: 2,
                          child: _SliderSection(
                            salary: _sliderSalary,
                            maxSalary: maxSlider,
                            result: sliderResult,
                            fmtGbp: _fmtGbp,
                            fmtPct: _fmtPct,
                            ct: ct,
                            onChanged: _onSliderChanged,
                            onEnd: _onSliderEnd,
                          ),
                        ),
                        CalcwiseStaggerItem(
                          index: 3,
                          child: _EmployerNiCard(
                            allSalary: _allSalary!,
                            optimal: _optimal!,
                            fmtGbp: _fmtGbp,
                            ct: ct,
                          ),
                        ),
                        CalcwiseStaggerItem(
                          index: 4,
                          child: ValueListenableBuilder<bool>(
                            valueListenable: freemiumService.isPremiumNotifier,
                            builder: (_, isPremium, __) {
                              if (isPremium) {
                                return _DetailedBreakdownCard(
                                  allSalary: _allSalary!,
                                  optimal: _optimal!,
                                  allDividends: _allDividends!,
                                  fmtGbp: _fmtGbp,
                                  fmtPct: _fmtPct,
                                  ct: ct,
                                );
                              }
                              return CalcwisePremiumGate(
                                title: 'Detailed Tax Breakdown',
                                description:
                                    'See a full line-by-line breakdown of corp tax, '
                                    'NI and dividend tax for each strategy.',
                                price: IAPService.instance.localizedPrice,
                                onUnlock: _showPaywall,
                              );
                            },
                          ),
                        ),
                        CalcwiseStaggerItem(
                          index: 5,
                          child: _CorpTaxNoteCard(ct: ct),
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

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _ComparisonTable extends StatelessWidget {
  final _SplitResult allSalary;
  final _SplitResult optimal;
  final _SplitResult allDividends;
  final NumberFormat fmtGbp;
  final NumberFormat fmtPct;
  final CalcwiseTheme ct;

  const _ComparisonTable({
    required this.allSalary,
    required this.optimal,
    required this.allDividends,
    required this.fmtGbp,
    required this.fmtPct,
    required this.ct,
  });

  int get _bestIndex {
    final burdens = [
      allSalary.totalTaxBurden,
      optimal.totalTaxBurden,
      allDividends.totalTaxBurden,
    ];
    return burdens.indexOf(burdens.reduce(min));
  }

  @override
  Widget build(BuildContext context) {
    final best = _bestIndex;
    return SectionCard(
      title: 'Strategy Comparison',
      children: [
        _HeaderRow(ct: ct),
        const SizedBox(height: AppSpacing.xs),
        _DataRow(
          label: 'Take-Home',
          values: [
            fmtGbp.format(allSalary.personalTakeHome),
            fmtGbp.format(optimal.personalTakeHome),
            fmtGbp.format(allDividends.personalTakeHome),
          ],
          bold: true,
          bestIndex: best,
          isHighlight: true,
          ct: ct,
        ),
        _DataRow(
          label: 'Total Tax',
          values: [
            fmtGbp.format(allSalary.totalTaxBurden),
            fmtGbp.format(optimal.totalTaxBurden),
            fmtGbp.format(allDividends.totalTaxBurden),
          ],
          bold: false,
          bestIndex: best,
          isHighlight: false,
          ct: ct,
          invertBest: true,
        ),
        _DataRow(
          label: 'Eff. Rate',
          values: [
            fmtPct.format(allSalary.effectiveTotalRate),
            fmtPct.format(optimal.effectiveTotalRate),
            fmtPct.format(allDividends.effectiveTotalRate),
          ],
          bold: false,
          bestIndex: best,
          isHighlight: false,
          ct: ct,
          invertBest: true,
        ),
      ],
    );
  }
}

class _HeaderRow extends StatelessWidget {
  final CalcwiseTheme ct;
  const _HeaderRow({required this.ct});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          const SizedBox(width: 80),
          for (final label in ['All Salary', 'Optimal', 'All Div.'])
            Expanded(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: AppTextSize.xs,
                  fontWeight: FontWeight.w700,
                  color: label == 'Optimal' ? AppTheme.primary : ct.textSecondary,
                  letterSpacing: 0.4,
                ),
              ),
            ),
        ],
      );
}

class _DataRow extends StatelessWidget {
  final String label;
  final List<String> values;
  final bool bold;
  final int bestIndex;
  final bool isHighlight;
  final bool invertBest;
  final CalcwiseTheme ct;

  const _DataRow({
    required this.label,
    required this.values,
    required this.bold,
    required this.bestIndex,
    required this.isHighlight,
    required this.ct,
    this.invertBest = false,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          children: [
            SizedBox(
              width: 80,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: AppTextSize.sm,
                  color: ct.textSecondary,
                ),
              ),
            ),
            for (int i = 0; i < values.length; i++)
              Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  padding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.xs,
                    horizontal: 4,
                  ),
                  decoration: i == 1
                      ? BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        )
                      : null,
                  child: Text(
                    values[i],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: AppTextSize.sm,
                      fontWeight: i == bestIndex || bold
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: i == bestIndex && isHighlight
                          ? AppTheme.primary
                          : i == 1
                              ? AppTheme.primary
                              : ct.textPrimary,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
}

class _OptimalInsightCard extends StatelessWidget {
  final _SplitResult optimal;
  final _SplitResult allSalary;
  final _SplitResult allDividends;
  final NumberFormat fmtGbp;
  final CalcwiseTheme ct;

  const _OptimalInsightCard({
    required this.optimal,
    required this.allSalary,
    required this.allDividends,
    required this.fmtGbp,
    required this.ct,
  });

  @override
  Widget build(BuildContext context) {
    final savingVsSalary = allSalary.totalTaxBurden - optimal.totalTaxBurden;
    final savingVsDividends = allDividends.totalTaxBurden - optimal.totalTaxBurden;
    final bestAlternative = savingVsSalary > savingVsDividends
        ? ('All Salary', savingVsSalary)
        : ('All Dividends', savingVsDividends);

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
          const Icon(Icons.lightbulb_outline_rounded,
              color: AppTheme.primary, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Optimal: £${optimal.salary.toStringAsFixed(0)} salary + dividends. '
              'Saves ${fmtGbp.format(bestAlternative.$2)} vs ${bestAlternative.$1} '
              'strategy on a total tax burden of ${fmtGbp.format(optimal.totalTaxBurden)}.',
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

class _SliderSection extends StatelessWidget {
  final double salary;
  final double maxSalary;
  final _SplitResult? result;
  final NumberFormat fmtGbp;
  final NumberFormat fmtPct;
  final CalcwiseTheme ct;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onEnd;

  const _SliderSection({
    required this.salary,
    required this.maxSalary,
    required this.result,
    required this.fmtGbp,
    required this.fmtPct,
    required this.ct,
    required this.onChanged,
    required this.onEnd,
  });

  @override
  Widget build(BuildContext context) {
    final r = result;
    return SectionCard(
      title: 'Custom Salary Split',
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Salary: ${fmtGbp.format(salary)}',
              style: TextStyle(
                fontSize: AppTextSize.body,
                fontWeight: FontWeight.w600,
                color: ct.textPrimary,
              ),
            ),
            Text(
              'PA limit: ${fmtGbp.format(maxSalary)}',
              style: TextStyle(
                fontSize: AppTextSize.sm,
                color: ct.textSecondary,
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: AppTheme.primary,
            thumbColor: AppTheme.primary,
            inactiveTrackColor: AppTheme.primary.withValues(alpha: 0.2),
            overlayColor: AppTheme.primary.withValues(alpha: 0.12),
          ),
          child: Slider(
            value: salary.clamp(0, maxSalary),
            min: 0,
            max: maxSalary,
            divisions: maxSalary > 0 ? (maxSalary / 500).round() : 1,
            onChanged: onChanged,
            onChangeEnd: onEnd,
          ),
        ),
        if (r != null) ...[
          const SizedBox(height: AppSpacing.xs),
          _SliderResultRow(
            label: 'Take-Home',
            value: fmtGbp.format(r.personalTakeHome),
            bold: true,
            ct: ct,
          ),
          _SliderResultRow(
            label: 'Total Tax Burden',
            value: fmtGbp.format(r.totalTaxBurden),
            bold: false,
            ct: ct,
          ),
          _SliderResultRow(
            label: 'Effective Rate',
            value: fmtPct.format(r.effectiveTotalRate),
            bold: false,
            ct: ct,
          ),
        ],
      ],
    );
  }
}

class _SliderResultRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  final CalcwiseTheme ct;

  const _SliderResultRow({
    required this.label,
    required this.value,
    required this.bold,
    required this.ct,
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
                fontSize: AppTextSize.body,
                color: ct.textSecondary,
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: AppTextSize.body,
                color: bold ? AppTheme.primary : ct.textPrimary,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ],
        ),
      );
}

class _EmployerNiCard extends StatelessWidget {
  final _SplitResult allSalary;
  final _SplitResult optimal;
  final NumberFormat fmtGbp;
  final CalcwiseTheme ct;

  const _EmployerNiCard({
    required this.allSalary,
    required this.optimal,
    required this.fmtGbp,
    required this.ct,
  });

  @override
  Widget build(BuildContext context) => SectionCard(
        title: 'Employer NI Cost',
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              'Employers pay 13.8% NI on salary above £9,100. '
              'Dividends are exempt from employer NI — a key advantage of the dividend route.',
              style: TextStyle(
                fontSize: AppTextSize.sm,
                color: ct.textSecondary,
                height: 1.45,
              ),
            ),
          ),
          _NiRow(
            label: 'All Salary scenario',
            value: allSalary.employerNI,
            fmt: fmtGbp,
            ct: ct,
          ),
          _NiRow(
            label: 'Optimal scenario',
            value: optimal.employerNI,
            fmt: fmtGbp,
            ct: ct,
          ),
          _NiRow(
            label: 'All Dividends scenario',
            value: 0,
            fmt: fmtGbp,
            ct: ct,
          ),
          Divider(color: ct.cardBorder, height: AppSpacing.xl, thickness: 1),
          _NiRow(
            label: 'Saving vs All Salary',
            value: allSalary.employerNI - optimal.employerNI,
            fmt: fmtGbp,
            ct: ct,
            highlight: true,
          ),
        ],
      );
}

class _NiRow extends StatelessWidget {
  final String label;
  final double value;
  final NumberFormat fmt;
  final CalcwiseTheme ct;
  final bool highlight;

  const _NiRow({
    required this.label,
    required this.value,
    required this.fmt,
    required this.ct,
    this.highlight = false,
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
                  fontSize: AppTextSize.body,
                  color: highlight ? AppTheme.primary : ct.textSecondary,
                ),
              ),
            ),
            Text(
              fmt.format(value),
              style: TextStyle(
                fontSize: AppTextSize.body,
                color: highlight ? AppTheme.primary : ct.textPrimary,
                fontWeight: highlight ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ],
        ),
      );
}

class _DetailedBreakdownCard extends StatelessWidget {
  final _SplitResult allSalary;
  final _SplitResult optimal;
  final _SplitResult allDividends;
  final NumberFormat fmtGbp;
  final NumberFormat fmtPct;
  final CalcwiseTheme ct;

  const _DetailedBreakdownCard({
    required this.allSalary,
    required this.optimal,
    required this.allDividends,
    required this.fmtGbp,
    required this.fmtPct,
    required this.ct,
  });

  @override
  Widget build(BuildContext context) => SectionCard(
        title: 'Detailed Breakdown',
        children: [
          _SectionTitle('Company Level', ct),
          _BreakdownRow('Salary paid', allSalary.salary, optimal.salary, allDividends.salary, fmtGbp, ct),
          _BreakdownRow('Employer NI', allSalary.employerNI, optimal.employerNI, 0, fmtGbp, ct),
          _BreakdownRow(
              'Corp tax', allSalary.corporationTax, optimal.corporationTax, allDividends.corporationTax, fmtGbp, ct),
          _BreakdownRow(
              'Dividend paid', allSalary.grossDividend, optimal.grossDividend, allDividends.grossDividend, fmtGbp, ct),
          Divider(color: ct.cardBorder, height: AppSpacing.xl, thickness: 1),
          _SectionTitle('Personal Level', ct),
          _BreakdownRow('Income tax', allSalary.incomeTax, optimal.incomeTax, 0, fmtGbp, ct),
          _BreakdownRow('Employee NI', allSalary.employeeNI, optimal.employeeNI, 0, fmtGbp, ct),
          _BreakdownRow('Dividend tax', allSalary.dividendTax, optimal.dividendTax, allDividends.dividendTax, fmtGbp, ct),
          Divider(color: ct.cardBorder, height: AppSpacing.xl, thickness: 1),
          _SectionTitle('Total', ct),
          _BreakdownRow(
              'Total tax burden', allSalary.totalTaxBurden, optimal.totalTaxBurden, allDividends.totalTaxBurden, fmtGbp, ct,
              bold: true),
          _BreakdownRow('Take-home', allSalary.personalTakeHome, optimal.personalTakeHome, allDividends.personalTakeHome,
              fmtGbp, ct,
              bold: true, highlight: true),
        ],
      );
}

class _SectionTitle extends StatelessWidget {
  final String text;
  final CalcwiseTheme ct;
  const _SectionTitle(this.text, this.ct);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xs, bottom: AppSpacing.xs),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: AppTextSize.xs,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
            color: ct.textSecondary,
          ),
        ),
      );
}

class _BreakdownRow extends StatelessWidget {
  final String label;
  final double salary;
  final double optimal;
  final double dividends;
  final NumberFormat fmt;
  final CalcwiseTheme ct;
  final bool bold;
  final bool highlight;

  const _BreakdownRow(
    this.label,
    this.salary,
    this.optimal,
    this.dividends,
    this.fmt,
    this.ct, {
    this.bold = false,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final values = [salary, optimal, dividends];
    final minVal = values.reduce(min);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 86,
            child: Text(
              label,
              style: TextStyle(
                fontSize: AppTextSize.sm,
                color: ct.textSecondary,
              ),
            ),
          ),
          for (int i = 0; i < values.length; i++)
            Expanded(
              child: Text(
                fmt.format(values[i]),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: AppTextSize.sm,
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                  color: highlight && values[i] == values.reduce(max)
                      ? AppTheme.primary
                      : !highlight && values[i] == minVal && minVal < values.reduce(max)
                          ? AppTheme.primary
                          : ct.textPrimary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CorpTaxNoteCard extends StatelessWidget {
  final CalcwiseTheme ct;
  const _CorpTaxNoteCard({required this.ct});

  @override
  Widget build(BuildContext context) => SectionCard(
        title: '2025/26 Rates Used',
        children: [
          for (final row in const [
            ('Corp Tax (small)', '19% (profits ≤ £50k)'),
            ('Corp Tax (marginal)', '19–25% (£50k–£250k)'),
            ('Corp Tax (main)', '25% (profits > £250k)'),
            ('Dividend Allowance', '£500'),
            ('Employer NI rate', '13.8% above £9,100'),
            ('Employee NI', '8% (£12,570–£50,270)'),
          ])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    row.$1,
                    style: TextStyle(
                      fontSize: AppTextSize.md,
                      color: ct.textSecondary,
                    ),
                  ),
                  Text(
                    row.$2,
                    style: TextStyle(
                      fontSize: AppTextSize.md,
                      color: ct.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          Divider(color: ct.cardBorder, height: AppSpacing.xl, thickness: 1),
          Text(
            'Calculations assume a single-director limited company. '
            'Does not include pension contributions, salary sacrifice, or other reliefs. '
            'For professional advice consult a qualified accountant.',
            style: TextStyle(
              fontSize: AppTextSize.xs,
              color: ct.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      );
}
