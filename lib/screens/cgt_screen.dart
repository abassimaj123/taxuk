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

// ── CGT asset type (UI labels only) ─────────────────────────────────────────

enum _AssetType { property, other }

extension _AssetTypeLabel on _AssetType {
  String get label {
    switch (this) {
      case _AssetType.property:
        return 'Residential Property';
      case _AssetType.other:
        return 'Other Assets (Shares, Crypto, etc.)';
    }
  }

  String get shortLabel {
    switch (this) {
      case _AssetType.property:
        return 'Residential Property';
      case _AssetType.other:
        return 'Other Assets';
    }
  }

}

// ── Screen ────────────────────────────────────────────────────────────────────

class CGTScreen extends StatefulWidget {
  const CGTScreen({super.key});

  @override
  State<CGTScreen> createState() => _CGTScreenState();
}

class _CGTScreenState extends State<CGTScreen> with CalcwiseAutoCalcMixin {
  final _grossCtrl = TextEditingController(text: '35000');
  final _salePriceCtrl = TextEditingController(text: '200000');
  final _purchasePriceCtrl = TextEditingController(text: '150000');
  final _costsCtrl = TextEditingController(text: '0');
  final _fmtGbp = NumberFormat.currency(locale: 'en_GB', symbol: '£');
  final _fmtPct = NumberFormat.percentPattern('en_GB');

  _AssetType _assetType = _AssetType.property;
  CGTResult? _result;
  // Input values stored alongside result (engine's CGTResult doesn't retain them)
  double _salePrice = 0;
  double _purchasePrice = 0;
  double _costs = 0;
  double _grossIncome = 0;

  @override
  void initState() {
    super.initState();
    analyticsService.logScreenView('cgt');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _calculate();
    });
  }

  @override
  void dispose() {
    _grossCtrl.dispose();
    _salePriceCtrl.dispose();
    _purchasePriceCtrl.dispose();
    _costsCtrl.dispose();
    smartHistoryService.cancelPendingSave('taxuk', 'cgt');
    super.dispose();
  }

  void _calculate() {
    final gross =
        double.tryParse(_grossCtrl.text.replaceAll(',', '.').trim()) ?? 0;
    final salePrice =
        double.tryParse(_salePriceCtrl.text.replaceAll(',', '.').trim()) ?? 0;
    final purchasePrice =
        double.tryParse(_purchasePriceCtrl.text.replaceAll(',', '.').trim()) ??
            0;
    final costs =
        double.tryParse(_costsCtrl.text.replaceAll(',', '.').trim()) ?? 0;

    if (gross < 0 || salePrice < 0 || purchasePrice < 0 || costs < 0) return;

    final gain = salePrice - purchasePrice - costs;
    final result = calculateCGT(
      gain: gain,
      grossIncome: gross,
      isResidentialProperty: _assetType == _AssetType.property,
    );

    setState(() {
      _result = result;
      _salePrice = salePrice;
      _purchasePrice = purchasePrice;
      _costs = costs;
      _grossIncome = gross;
    });

    analyticsService.logCalculationCompleted(
      params: {
        'calc_type': 'cgt',
        'gross_income': gross.round(),
        'total_gain': result.totalGain.round(),
        'asset_type': _assetType.name,
      },
    );
    adService.onAction();
    _scheduleAutoSave();
  }

  double _roundTo(double v, double step) => (v / step).round() * step;

  void _scheduleAutoSave() {
    final r = _result;
    if (r == null) return;
    final gain = _salePrice - _purchasePrice - _costs;
    if (gain <= 0 && _grossIncome <= 0) return;
    final inputHash = ResultHasher.hashMixed({
      'gains': _roundTo(r.totalGain, 500),
      'gross_income': _roundTo(_grossIncome, 1000),
    });
    smartHistoryService.scheduleAutoSave(
      appKey: 'taxuk',
      screenId: 'cgt',
      inputHash: inputHash,
      l1: {
        'gains': r.totalGain,
        'gross_income': _grossIncome,
        'taxable_gain': r.taxableGain,
        'cgt_tax': r.totalTax,
        'effective_rate': r.effectiveRate,
      },
      l2: {
        'inputs': {
          'gains': r.totalGain,
          'grossIncome': _grossIncome,
          'assetType': _assetType.name,
        },
        'results': {
          'allowance': r.annualExemption,
          'taxableGain': r.taxableGain,
          'cgtTax': r.totalTax,
          'effectiveRate': r.effectiveRate,
        },
      },
    );
  }

  Future<void> _saveScenario(String? label) async {
    final r = _result;
    if (r == null) return;
    final inputHash = ResultHasher.hashMixed({
      'gains': _roundTo(r.totalGain, 500),
      'gross_income': _roundTo(_grossIncome, 1000),
    });
    await smartHistoryService.saveScenario(
      appKey: 'taxuk',
      screenId: 'cgt',
      inputHash: inputHash,
      l1: {
        'gains': r.totalGain,
        'gross_income': _grossIncome,
        'taxable_gain': r.taxableGain,
        'cgt_tax': r.totalTax,
        'effective_rate': r.effectiveRate,
      },
      l2: {
        'inputs': {
          'gains': r.totalGain,
          'grossIncome': _grossIncome,
          'assetType': _assetType.name,
        },
        'results': {
          'allowance': r.annualExemption,
          'taxableGain': r.taxableGain,
          'cgtTax': r.totalTax,
          'effectiveRate': r.effectiveRate,
        },
      },
      label: label,
    );
    analyticsService.logResultSaved();
    adService.onSave();
  }


  void _reset() {
    _grossCtrl.text = '35000';
    _salePriceCtrl.text = '200000';
    _purchasePriceCtrl.text = '150000';
    _costsCtrl.text = '0';
    setState(() {
      _assetType = _AssetType.property;
      _result = null;
      _salePrice = 0;
      _purchasePrice = 0;
      _costs = 0;
      _grossIncome = 0;
    });
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
    await TaxUkPdfExportService.exportCgt(
      context: context,
      totalGain: r.totalGain,
      annualExemption: r.annualExemption,
      taxableGain: r.taxableGain,
      totalTax: r.totalTax,
      effectiveRate: r.effectiveRate,
      assetType: _assetType.label,
      grossIncome: _grossIncome,
      salePrice: _salePrice,
      purchasePrice: _purchasePrice,
      costs: _costs,
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
              // ── Asset type chips ──────────────────────────────────────────
              _SectionLabel('Asset Type', ct),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: _AssetType.values.map((opt) {
                  final sel = _assetType == opt;
                  return FilterChip(
                    label: Text(opt.shortLabel),
                    selected: sel,
                    onSelected: (_) => setState(() {
                      _assetType = opt;
                      if (_result != null) _calculate();
                    }),
                    selectedColor: AppTheme.primary.withValues(alpha: 0.15),
                    checkmarkColor: AppTheme.primary,
                    labelStyle: TextStyle(
                      color: sel ? AppTheme.primary : ct.textSecondary,
                      fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                    ),
                    side: BorderSide(
                      color: sel
                          ? AppTheme.primary.withValues(alpha: 0.5)
                          : ct.cardBorder,
                    ),
                    backgroundColor: ct.surface,
                  );
                }).toList(),
              ),
              const SizedBox(height: AppSpacing.xl),

              // ── Gross income ──────────────────────────────────────────────
              _SectionLabel('Your Income', ct),
              const SizedBox(height: AppSpacing.sm),
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
                  helperText:
                      'Used to determine your income tax band for CGT rates',
                  filled: true,
                ),
                onChanged: (_) => scheduleCalc(_calculate),
                onSubmitted: (_) => _calculate(),
              ),
              const SizedBox(height: AppSpacing.xl),

              // ── Asset values ──────────────────────────────────────────────
              _SectionLabel('Asset Values', ct),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _salePriceCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: false,
                ),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Sale Price',
                  prefixText: '£',
                  hintText: '200000',
                  filled: true,
                ),
                onChanged: (_) => scheduleCalc(_calculate),
                onSubmitted: (_) => _calculate(),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _purchasePriceCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: false,
                ),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Purchase Price',
                  prefixText: '£',
                  hintText: '150000',
                  filled: true,
                ),
                onChanged: (_) => scheduleCalc(_calculate),
                onSubmitted: (_) => _calculate(),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _costsCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: false,
                ),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Incidental Costs (optional)',
                  prefixText: '£',
                  hintText: '0',
                  helperText:
                      'Estate agent fees, legal costs, improvement costs',
                  filled: true,
                ),
                onChanged: (_) => scheduleCalc(_calculate),
                onSubmitted: (_) => _calculate(),
              ),
              const SizedBox(height: AppSpacing.xl),

              // ── Action buttons ────────────────────────────────────────────
              Row(children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _calculate,
                    child: const Text('Calculate CGT'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                OutlinedButton(
                  onPressed: _reset,
                  child: const Text('Reset'),
                ),
              ]),

              // ── Results ───────────────────────────────────────────────────
              if (r != null) ...[
                const SizedBox(height: AppSpacing.xl),
                CalcwisePageEntrance(
                  child: Column(children: [
                    CalcwiseStaggerItem(
                      index: 0,
                      child: CalcwiseHeroCard(
                        label: 'CAPITAL GAINS TAX DUE',
                        value: _fmtGbp.format(r.totalTax),
                        secondary:
                            '${_assetType.shortLabel} · 2025/26 rates',
                        stats: [
                          (
                            label: 'Total Gain',
                            value: _fmtGbp.format(r.totalGain),
                          ),
                          (
                            label: 'Taxable Gain',
                            value: _fmtGbp.format(r.taxableGain),
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
                      child: _BreakdownCard(
                        result: r,
                        salePrice: _salePrice,
                        purchasePrice: _purchasePrice,
                        costs: _costs,
                        assetType: _assetType,
                        fmtGbp: _fmtGbp,
                        ct: ct,
                      ),
                    ),
                    CalcwiseStaggerItem(
                      index: 2,
                      child: _RatesReferenceCard(
                        currentType: _assetType,
                        ct: ct,
                      ),
                    ),
                    CalcwiseStaggerItem(
                      index: 3,
                      child: _TipsCard(
                        result: r,
                        assetType: _assetType,
                        fmtGbp: _fmtGbp,
                        ct: ct,
                      ),
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

// ── Breakdown SectionCard ─────────────────────────────────────────────────────

class _BreakdownCard extends StatelessWidget {
  final CGTResult result;
  final double salePrice;
  final double purchasePrice;
  final double costs;
  final _AssetType assetType;
  final NumberFormat fmtGbp;
  final CalcwiseTheme ct;

  const _BreakdownCard({
    required this.result,
    required this.salePrice,
    required this.purchasePrice,
    required this.costs,
    required this.assetType,
    required this.fmtGbp,
    required this.ct,
  });

  String _pct(double rate) => '${(rate * 100).toStringAsFixed(0)}%';

  @override
  Widget build(BuildContext context) {
    final r = result;

    return SectionCard(
      title: 'Breakdown',
      children: [
        _Row('Sale Price', fmtGbp.format(salePrice), ct),
        _Row(
          'Purchase Price',
          '− ${fmtGbp.format(purchasePrice)}',
          ct,
        ),
        if (costs > 0)
          _Row('Incidental Costs', '− ${fmtGbp.format(costs)}', ct),
        _Divider(ct),
        _Row('Total Gain', fmtGbp.format(r.totalGain), ct, bold: true),
        _Row(
          'Annual Exemption',
          '− ${fmtGbp.format(r.annualExemption)}',
          ct,
        ),
        _Divider(ct),
        _Row(
          'Taxable Gain',
          fmtGbp.format(r.taxableGain),
          ct,
          bold: true,
        ),
        if (r.gainInBasicBand > 0)
          _Row(
            'In Basic Band @ ${_pct(r.basicRate)}',
            fmtGbp.format(r.taxInBasicBand),
            ct,
            highlight: true,
          ),
        if (r.gainInHigherBand > 0)
          _Row(
            'In Higher Band @ ${_pct(r.higherRate)}',
            fmtGbp.format(r.taxInHigherBand),
            ct,
            highlight: true,
          ),
        _Divider(ct),
        _Row(
          'CGT Due',
          fmtGbp.format(r.totalTax),
          ct,
          bold: true,
          highlight: true,
        ),
      ],
    );
  }
}

// ── CGT Rates reference SectionCard ──────────────────────────────────────────

class _RatesReferenceCard extends StatelessWidget {
  final _AssetType currentType;
  final CalcwiseTheme ct;

  const _RatesReferenceCard({
    required this.currentType,
    required this.ct,
  });

  @override
  Widget build(BuildContext context) {
    // Each entry: (rowLabel, basicRateStr, higherRateStr, assetType)
    const rows = [
      (
        'Residential Property',
        '18%',
        '24%',
        _AssetType.property,
      ),
      (
        'Other Assets (Shares, Crypto…)',
        '10%',
        '20%',
        _AssetType.other,
      ),
    ];

    return SectionCard(
      title: '2025/26 CGT Rates',
      children: [
        // Header row
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Text(
                  'Asset Type',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: ct.textSecondary,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              _HeaderCell('Basic', ct),
              const SizedBox(width: AppSpacing.sm),
              _HeaderCell('Higher', ct),
            ],
          ),
        ),
        Divider(color: ct.cardBorder, height: AppSpacing.sm, thickness: 1),
        for (final entry in rows) ...[
          const SizedBox(height: AppSpacing.xs),
          _RateRow(
            label: entry.$1,
            basicRate: entry.$2,
            higherRate: entry.$3,
            isActive: entry.$4 == currentType,
            ct: ct,
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        Divider(color: ct.cardBorder, height: AppSpacing.sm, thickness: 1),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Annual CGT exemption: £3,000 (2025/26). '
          'Basic rate applies to gains within your remaining Income Tax basic rate band.',
          style: TextStyle(
            fontSize: 11,
            color: ct.textSecondary,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final String label;
  final CalcwiseTheme ct;
  const _HeaderCell(this.label, this.ct);

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 52,
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: ct.textSecondary,
            letterSpacing: 0.5,
          ),
        ),
      );
}

class _RateRow extends StatelessWidget {
  final String label;
  final String basicRate;
  final String higherRate;
  final bool isActive;
  final CalcwiseTheme ct;

  const _RateRow({
    required this.label,
    required this.basicRate,
    required this.higherRate,
    required this.isActive,
    required this.ct,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: isActive
            ? BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(
                  color: AppTheme.primary.withValues(alpha: 0.2),
                ),
              )
            : null,
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                  color: isActive ? ct.textPrimary : ct.textSecondary,
                ),
              ),
            ),
            _RateBadge(rate: basicRate, isActive: isActive),
            const SizedBox(width: AppSpacing.sm),
            _RateBadge(rate: higherRate, isActive: isActive),
          ],
        ),
      );
}

class _RateBadge extends StatelessWidget {
  final String rate;
  final bool isActive;
  const _RateBadge({required this.rate, required this.isActive});

  @override
  Widget build(BuildContext context) {
    final ct = CalcwiseTheme.of(context);
    return SizedBox(
      width: 52,
      child: Container(
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.xxs,
        ),
        decoration: BoxDecoration(
          color: isActive
              ? AppTheme.primary.withValues(alpha: 0.15)
              : ct.cardBorder.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        alignment: Alignment.center,
        child: Text(
          rate,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: isActive ? AppTheme.primary : ct.textSecondary,
          ),
        ),
      ),
    );
  }
}

// ── Tips SectionCard ──────────────────────────────────────────────────────────

class _TipsCard extends StatelessWidget {
  final CGTResult result;
  final _AssetType assetType;
  final NumberFormat fmtGbp;
  final CalcwiseTheme ct;

  const _TipsCard({
    required this.result,
    required this.assetType,
    required this.fmtGbp,
    required this.ct,
  });

  String _buildInsight() {
    final r = result;

    if (r.totalGain <= 0) {
      return 'No gain to report — you made a loss or broke even on this asset. '
          'Capital losses can be reported to HMRC and offset against future gains.';
    }

    if (r.taxableGain == 0) {
      return 'Your gain of ${fmtGbp.format(r.totalGain)} is fully covered by '
          'the £${r.annualExemption.toStringAsFixed(0)} annual CGT exemption. '
          'No tax is due — but you should still consider reporting to HMRC if your total gains '
          'exceed the exemption threshold across all assets.';
    }

    final basicPctStr = '${(r.basicRate * 100).toStringAsFixed(0)}%';
    final higherPctStr = '${(r.higherRate * 100).toStringAsFixed(0)}%';

    final buffer = StringBuffer();

    if (r.gainInBasicBand > 0 && r.gainInHigherBand == 0) {
      buffer.write(
        'Your entire taxable gain falls within the basic rate band, '
        'taxed at $basicPctStr for ${assetType.shortLabel}. ',
      );
    } else if (r.gainInBasicBand > 0 && r.gainInHigherBand > 0) {
      buffer.write(
        '${fmtGbp.format(r.gainInBasicBand)} of your taxable gain falls '
        'in the basic rate band ($basicPctStr) and '
        '${fmtGbp.format(r.gainInHigherBand)} in the higher rate band '
        '($higherPctStr). ',
      );
    } else {
      buffer.write(
        'All of your taxable gain falls in the higher rate band, '
        'taxed at $higherPctStr for ${assetType.shortLabel}. ',
      );
    }

    buffer.write(
      'Consider spreading disposals across tax years to use each year\'s '
      '£${r.annualExemption.toStringAsFixed(0)} exemption. '
      'If your income falls in a future year, more of your gain could be taxed at the lower rate.',
    );

    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) => SectionCard(
        title: 'Tips & Insights',
        children: [
          Container(
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
                Icon(
                  Icons.lightbulb_outline_rounded,
                  color: AppTheme.primary,
                  size: 20,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    _buildInsight(),
                    style: TextStyle(
                      fontSize: 13,
                      color: ct.textPrimary,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'CGT is due by 31 January following the tax year end for assets '
            'other than property. Residential property gains must be reported '
            'to HMRC within 60 days of completion.',
            style: TextStyle(
              fontSize: 11,
              color: ct.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      );
}

// ── Shared row / divider / save-button widgets ────────────────────────────────

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

