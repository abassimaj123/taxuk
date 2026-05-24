import 'package:calcwise_core/calcwise_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../core/uk_tax_engine.dart';
import '../core/analytics/analytics_service.dart';
import '../core/db/database_service.dart';
import '../core/freemium/freemium_service.dart';
import '../core/freemium/iap_service.dart';
import '../core/theme/app_theme.dart';
import '../l10n/strings_en.dart';
import '../main.dart';
import '../widgets/paywall_soft.dart';

// ── VAT rate options ─────────────────────────────────────────────────────────

enum _VatRateOption { standard, reduced, zero, custom }

extension _VatRateLabel on _VatRateOption {
  String get label {
    switch (this) {
      case _VatRateOption.standard:
        return 'Standard (20%)';
      case _VatRateOption.reduced:
        return 'Reduced (5%)';
      case _VatRateOption.zero:
        return 'Zero (0%)';
      case _VatRateOption.custom:
        return 'Custom';
    }
  }

  double? get rate {
    switch (this) {
      case _VatRateOption.standard:
        return UKTaxEngine.vatStandard;
      case _VatRateOption.reduced:
        return UKTaxEngine.vatReduced;
      case _VatRateOption.zero:
        return UKTaxEngine.vatZero;
      case _VatRateOption.custom:
        return null;
    }
  }
}

// ── Screen ────────────────────────────────────────────────────────────────────

class VatScreen extends StatefulWidget {
  const VatScreen({super.key});

  @override
  State<VatScreen> createState() => _VatScreenState();
}

class _VatScreenState extends State<VatScreen> {
  final _amountCtrl = TextEditingController(text: '100');
  final _customRateCtrl = TextEditingController(text: '20');
  final _fmtGbp = NumberFormat.currency(locale: 'en_GB', symbol: '£');

  _VatRateOption _rateOption = _VatRateOption.standard;
  bool _fromGross = false; // false = from net, true = from gross
  VatResult? _result;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _customRateCtrl.dispose();
    super.dispose();
  }

  double get _resolvedRate {
    if (_rateOption == _VatRateOption.custom) {
      return (double.tryParse(_customRateCtrl.text) ?? 0) / 100;
    }
    return _rateOption.rate!;
  }

  void _calculate() {
    final amount = double.tryParse(
          _amountCtrl.text.replaceAll(',', '.').trim(),
        ) ??
        0;
    if (amount <= 0) return;

    final rate = _resolvedRate;
    final double net, vatAmt, gross;

    if (_fromGross) {
      gross = amount;
      vatAmt = UKTaxEngine.vatAmountFromGross(gross, rate);
      net = UKTaxEngine.netFromGross(gross, rate);
    } else {
      net = amount;
      vatAmt = UKTaxEngine.vatAmountFromNet(net, rate);
      gross = UKTaxEngine.grossFromNet(net, rate);
    }

    setState(() {
      _result = VatResult(
        netAmount: net,
        vatAmount: vatAmt,
        grossAmount: gross,
        rate: rate,
        rateLabel: _rateOption == _VatRateOption.custom
            ? '${(_resolvedRate * 100).toStringAsFixed(1)}%'
            : _rateOption.label,
      );
    });

    analyticsService.logVatCalculated(
      amount: amount,
      rate: rate,
      isFromGross: _fromGross,
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
        featureTitle: 'Unlimited History',
        featureSubtitle:
            'You\'ve saved ${MonetizationConfig.freeHistoryLimit} calculations. '
            'Upgrade to save more.',
      );
      return;
    }
    await DatabaseService.instance.insert(
      inputs: {
        'type': 'vat',
        'amount': r.netAmount,
        'rate': r.rate,
        'from_gross': _fromGross,
        'rate_label': r.rateLabel,
      },
      results: {
        'net': r.netAmount,
        'vat': r.vatAmount,
        'gross': r.grossAmount,
      },
    );
    analyticsService.logResultSaved();
    adService.onSave();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saved to history')),
    );
  }

  void _reset() {
    _amountCtrl.text = '100';
    _customRateCtrl.text = '20';
    setState(() {
      _rateOption = _VatRateOption.standard;
      _fromGross = false;
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
              // ── Rate quick-select chips ─────────────────────────────────
              _SectionLabel('VAT Rate', ct),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                children: _VatRateOption.values.map((opt) {
                  final sel = _rateOption == opt;
                  return FilterChip(
                    label: Text(opt.label),
                    selected: sel,
                    onSelected: (_) => setState(() {
                      _rateOption = opt;
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
              if (_rateOption == _VatRateOption.custom) ...[
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _customRateCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Custom VAT Rate',
                    suffixText: '%',
                    filled: true,
                  ),
                  onChanged: (_) {
                    if (_result != null) _calculate();
                  },
                ),
              ],
              const SizedBox(height: AppSpacing.xl),

              // ── Input mode toggle ──────────────────────────────────────
              _SectionLabel('Amount', ct),
              const SizedBox(height: AppSpacing.sm),
              _ToggleRow(
                leftLabel: 'From Net',
                rightLabel: 'From Gross',
                isRight: _fromGross,
                onChanged: (v) => setState(() {
                  _fromGross = v;
                  if (_result != null) _calculate();
                }),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                decoration: InputDecoration(
                  labelText: _fromGross ? 'Gross Amount (£)' : 'Net Amount (£)',
                  prefixText: '£',
                  filled: true,
                ),
                onSubmitted: (_) => _calculate(),
              ),
              const SizedBox(height: AppSpacing.xl),

              // ── Action buttons ─────────────────────────────────────────
              Row(children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _calculate,
                    child: const Text('Calculate VAT'),
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
                        label: 'VAT AMOUNT',
                        value: _fmtGbp.format(r.vatAmount),
                        secondary: 'At ${r.rateLabel}',
                        stats: [
                          (label: 'Net', value: _fmtGbp.format(r.netAmount)),
                          (
                            label: 'Gross',
                            value: _fmtGbp.format(r.grossAmount)
                          ),
                        ],
                      ),
                    ),
                    CalcwiseStaggerItem(
                      index: 1,
                      child: SectionCard(
                        title: 'Breakdown',
                        children: [
                          _ResultRow(
                            'Net (ex-VAT)',
                            _fmtGbp.format(r.netAmount),
                            ct,
                          ),
                          _ResultRow(
                            'VAT (${r.rateLabel})',
                            _fmtGbp.format(r.vatAmount),
                            ct,
                            highlight: true,
                          ),
                          _ResultRow(
                            'Gross (inc-VAT)',
                            _fmtGbp.format(r.grossAmount),
                            ct,
                          ),
                        ],
                      ),
                    ),
                    CalcwiseStaggerItem(
                      index: 2,
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

// ── Private sub-widgets ───────────────────────────────────────────────────────

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

class _ToggleRow extends StatelessWidget {
  final String leftLabel;
  final String rightLabel;
  final bool isRight;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.leftLabel,
    required this.rightLabel,
    required this.isRight,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final ct = CalcwiseTheme.of(context);
    return Row(
      children: [
        _ToggleOption(
          label: leftLabel,
          selected: !isRight,
          ct: ct,
          onTap: () => onChanged(false),
        ),
        const SizedBox(width: AppSpacing.sm),
        _ToggleOption(
          label: rightLabel,
          selected: isRight,
          ct: ct,
          onTap: () => onChanged(true),
        ),
      ],
    );
  }
}

class _ToggleOption extends StatelessWidget {
  final String label;
  final bool selected;
  final CalcwiseTheme ct;
  final VoidCallback onTap;

  const _ToggleOption({
    required this.label,
    required this.selected,
    required this.ct,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.primary.withValues(alpha: 0.15)
                : ct.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: selected
                  ? AppTheme.primary.withValues(alpha: 0.5)
                  : ct.cardBorder,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? AppTheme.primary : ct.textSecondary,
            ),
          ),
        ),
      );
}

class _ResultRow extends StatelessWidget {
  final String label;
  final String value;
  final CalcwiseTheme ct;
  final bool highlight;

  const _ResultRow(
    this.label,
    this.value,
    this.ct, {
    this.highlight = false,
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
                color: highlight ? AppTheme.primary : ct.textSecondary,
                fontWeight: highlight ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                color: highlight ? AppTheme.primary : ct.textPrimary,
                fontWeight: highlight ? FontWeight.w700 : FontWeight.w600,
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
