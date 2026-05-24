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

class IncomeTaxScreen extends StatefulWidget {
  const IncomeTaxScreen({super.key});

  @override
  State<IncomeTaxScreen> createState() => _IncomeTaxScreenState();
}

class _IncomeTaxScreenState extends State<IncomeTaxScreen> {
  final _grossCtrl = TextEditingController(text: '35000');
  final _fmtGbp = NumberFormat.currency(locale: 'en_GB', symbol: '£');
  final _fmtPct = NumberFormat.percentPattern('en_GB');

  bool _isScotland = false;
  IncomeTaxResult? _result;

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
    super.dispose();
  }

  void _calculate() {
    final gross = double.tryParse(
          _grossCtrl.text.replaceAll(',', '.').trim(),
        ) ??
        0;
    if (gross < 0) return;

    final pa = UKTaxEngine.effectivePersonalAllowance(gross);
    final tax = UKTaxEngine.incomeTax(gross, isScotland: _isScotland);
    final ni = UKTaxEngine.nationalInsurance(gross);
    final net = UKTaxEngine.netIncome(gross, isScotland: _isScotland);
    final effRate =
        UKTaxEngine.effectiveTaxRate(gross, isScotland: _isScotland);
    final margRate =
        UKTaxEngine.marginalTaxRate(gross, isScotland: _isScotland);
    final bands = UKTaxEngine.taxBandBreakdown(
      gross,
      isScotland: _isScotland,
    );

    setState(() {
      _result = IncomeTaxResult(
        grossIncome: gross,
        personalAllowance: pa,
        incomeTax: tax,
        nationalInsurance: ni,
        netIncome: net,
        effectiveTaxRate: effRate,
        marginalTaxRate: margRate,
        bandBreakdown: bands,
        isScotland: _isScotland,
      );
    });

    analyticsService.logIncomeTaxCalculated(
      grossIncome: gross,
      isScotland: _isScotland,
    );
    adService.onAction();
  }

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
    setState(() {
      _isScotland = false;
      _result = null;
    });
  }

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
              // ── Gross salary input ─────────────────────────────────────
              TextField(
                controller: _grossCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: false,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: const InputDecoration(
                  labelText: 'Gross Annual Salary',
                  prefixText: '£',
                  hintText: '35000',
                  filled: true,
                ),
                onSubmitted: (_) => _calculate(),
              ),
              const SizedBox(height: AppSpacing.lg),

              // ── Scotland toggle ────────────────────────────────────────
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
                    if (_result != null) _calculate();
                  },
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.xs,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),

              // ── Action buttons ─────────────────────────────────────────
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

              // ── Results ────────────────────────────────────────────────
              if (r != null) ...[
                const SizedBox(height: AppSpacing.xl),
                CalcwisePageEntrance(
                  child: Column(children: [
                    CalcwiseStaggerItem(
                      index: 0,
                      child: CalcwiseHeroCard(
                        label: 'ANNUAL TAKE-HOME',
                        value: _fmtGbp.format(r.netIncome),
                        secondary: r.isScotland
                            ? 'Scottish rates 2025/26'
                            : 'England / Wales / NI rates 2025/26',
                        stats: [
                          (
                            label: 'Income Tax',
                            value: _fmtGbp.format(r.incomeTax)
                          ),
                          (
                            label: 'NI',
                            value: _fmtGbp.format(r.nationalInsurance)
                          ),
                          (
                            label: 'Effective Rate',
                            value: _fmtPct.format(r.effectiveOverallRate)
                          ),
                        ],
                      ),
                    ),
                    CalcwiseStaggerItem(
                      index: 1,
                      child: SectionCard(
                        title: 'Summary',
                        children: [
                          _Row(
                            'Gross Income',
                            _fmtGbp.format(r.grossIncome),
                            ct,
                          ),
                          _Row(
                            'Personal Allowance',
                            _fmtGbp.format(r.personalAllowance),
                            ct,
                          ),
                          _Row(
                            'Income Tax',
                            _fmtGbp.format(r.incomeTax),
                            ct,
                            highlight: true,
                          ),
                          _Row(
                            'National Insurance',
                            _fmtGbp.format(r.nationalInsurance),
                            ct,
                            highlight: true,
                          ),
                          _Divider(ct),
                          _Row(
                            'Take-Home Pay',
                            _fmtGbp.format(r.netIncome),
                            ct,
                            bold: true,
                          ),
                          _Row(
                            'Effective Tax Rate',
                            _fmtPct.format(r.effectiveTaxRate),
                            ct,
                          ),
                          _Row(
                            'Marginal Rate',
                            '${(r.marginalTaxRate * 100).toStringAsFixed(0)}%',
                            ct,
                          ),
                        ],
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
                        gross: r.grossIncome,
                        ni: r.nationalInsurance,
                        fmtGbp: _fmtGbp,
                        ct: ct,
                      ),
                    ),
                    CalcwiseStaggerItem(
                      index: 4,
                      child: _MonthlyWeeklyCard(
                          result: r, fmtGbp: _fmtGbp, ct: ct),
                    ),
                    CalcwiseStaggerItem(
                      index: 5,
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
          for (final b in bands) ...[
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
                          '${b.rangeTo.isInfinite ? "∞" : fmtGbp.format(b.rangeTo)}',
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
                      color: b.amount > 0 ? AppTheme.primary : ct.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      );
}

class _NiBreakdown extends StatelessWidget {
  final double gross;
  final double ni;
  final NumberFormat fmtGbp;
  final CalcwiseTheme ct;

  const _NiBreakdown({
    required this.gross,
    required this.ni,
    required this.fmtGbp,
    required this.ct,
  });

  @override
  Widget build(BuildContext context) {
    final band1 = gross > UKTaxEngine.niPrimaryThreshold
        ? (gross.clamp(
                  UKTaxEngine.niPrimaryThreshold,
                  UKTaxEngine.niUpperEarningsLimit,
                ) -
                UKTaxEngine.niPrimaryThreshold) *
            UKTaxEngine.niRate1
        : 0.0;
    final band2 = gross > UKTaxEngine.niUpperEarningsLimit
        ? (gross - UKTaxEngine.niUpperEarningsLimit) * UKTaxEngine.niRate2
        : 0.0;

    return SectionCard(
      title: 'National Insurance (Class 1)',
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Main rate (8%)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: ct.textPrimary,
                      ),
                    ),
                    Text(
                      '${fmtGbp.format(UKTaxEngine.niPrimaryThreshold)}–'
                      '${fmtGbp.format(UKTaxEngine.niUpperEarningsLimit)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: ct.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                fmtGbp.format(band1),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primary,
                ),
              ),
            ],
          ),
        ),
        if (band2 > 0)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Upper rate (2%)',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: ct.textPrimary,
                        ),
                      ),
                      Text(
                        'Above ${fmtGbp.format(UKTaxEngine.niUpperEarningsLimit)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: ct.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  fmtGbp.format(band2),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primary,
                  ),
                ),
              ],
            ),
          ),
        Divider(color: ct.cardBorder, height: AppSpacing.xl, thickness: 1),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Total NI',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: ct.textPrimary,
              ),
            ),
            Text(
              fmtGbp.format(ni),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppTheme.primary,
              ),
            ),
          ],
        ),
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
          _SubRow('Monthly income tax', result.incomeTax / 12, fmtGbp, ct),
          _SubRow('Monthly NI', result.nationalInsurance / 12, fmtGbp, ct),
          Divider(color: ct.cardBorder, height: AppSpacing.xl, thickness: 1),
          _SubRow('Monthly take-home', result.netIncome / 12, fmtGbp, ct,
              bold: true),
          _SubRow('Weekly take-home', result.netIncome / 52, fmtGbp, ct,
              bold: true),
        ],
      );
}

class _SubRow extends StatelessWidget {
  final String label;
  final double value;
  final NumberFormat fmt;
  final CalcwiseTheme ct;
  final bool bold;

  const _SubRow(this.label, this.value, this.fmt, this.ct, {this.bold = false});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: ct.textSecondary,
                fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
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
