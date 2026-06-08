import 'package:calcwise_core/calcwise_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../core/tax_code_engine.dart';
import '../core/analytics/analytics_service.dart';
import '../core/theme/app_theme.dart';
import '../main.dart';

/// Tax Code Checker — decodes a UK PAYE tax code and explains it.
class TaxCodeCheckerScreen extends StatefulWidget {
  const TaxCodeCheckerScreen({super.key});

  @override
  State<TaxCodeCheckerScreen> createState() => _TaxCodeCheckerScreenState();
}

class _TaxCodeCheckerScreenState extends State<TaxCodeCheckerScreen>
    with CalcwiseAutoCalcMixin {
  final _codeCtrl = TextEditingController(text: '1257L');
  final _fmtGbp = NumberFormat.currency(locale: 'en_GB', symbol: '£');
  TaxCodeResult? _result;

  @override
  void initState() {
    super.initState();
    analyticsService.logScreenView('tax_code_checker');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _check();
    });
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  void _check() {
    final input = _codeCtrl.text.trim();
    if (input.isEmpty) {
      setState(() => _result = null);
      return;
    }
    final result = TaxCodeEngine.parse(input);
    setState(() => _result = result);
    analyticsService.logTaxCodeChecked(
      code: input,
      isValid: result.isValid,
    );
    adService.onAction();
  }

  void _reset() {
    _codeCtrl.text = '1257L';
    _check();
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
              _SectionLabel('Your Tax Code', ct),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _codeCtrl,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9 /]')),
                  LengthLimitingTextInputFormatter(12),
                ],
                style: const TextStyle(
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w700,
                ),
                decoration: const InputDecoration(
                  labelText: 'Tax Code',
                  hintText: '1257L',
                  helperText: 'On your payslip, P45 or P60 (e.g. 1257L, BR, K475)',
                  filled: true,
                ),
                onChanged: (_) => scheduleCalc(_check),
                onSubmitted: (_) => _check(),
              ),
              const SizedBox(height: AppSpacing.md),

              // ── Examples ───────────────────────────────────────────────
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: ['1257L', 'BR', 'D0', '0T', 'K475', 'S1257L']
                    .map((ex) => ActionChip(
                          label: Text(ex),
                          onPressed: () {
                            _codeCtrl.text = ex;
                            _check();
                          },
                          backgroundColor: ct.surface,
                          side: BorderSide(color: ct.cardBorder),
                          labelStyle: TextStyle(
                            fontSize: 12,
                            color: ct.textSecondary,
                          ),
                        ))
                    .toList(),
              ),
              const SizedBox(height: AppSpacing.lg),

              Row(children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _check,
                    child: const Text('Check Tax Code'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                OutlinedButton(
                  onPressed: _reset,
                  child: const Text('Reset'),
                ),
              ]),

              if (r != null) ...[
                const SizedBox(height: AppSpacing.xl),
                if (!r.isValid)
                  _InvalidCard(message: r.errorMessage ?? 'Invalid tax code.', ct: ct)
                else
                  CalcwisePageEntrance(
                    child: Column(children: [
                      CalcwiseStaggerItem(
                        index: 0,
                        child: CalcwiseHeroCard(
                          label: 'PERSONAL ALLOWANCE',
                          value: r.isKCode
                              ? '+ ${_fmtGbp.format(r.kAddition)}'
                              : _fmtGbp.format(r.personalAllowance),
                          secondary: r.isKCode
                              ? 'Added to taxable income (K code)'
                              : r.allowanceLabel,
                          stats: [
                            (label: 'Code', value: r.input.toUpperCase().trim()),
                            (label: 'Region', value: r.region.label),
                            if (r.isEmergency)
                              (label: 'Type', value: 'Emergency'),
                          ],
                        ),
                      ),
                      CalcwiseStaggerItem(
                        index: 1,
                        child: SectionCard(
                          title: 'What it means',
                          children: [
                            _ExplainRow(
                              icon: Icons.payments_rounded,
                              title: r.isKCode
                                  ? 'Negative allowance'
                                  : 'Allowance: ${_fmtGbp.format(r.personalAllowance)}',
                              body: r.meaning,
                              ct: ct,
                            ),
                          ],
                        ),
                      ),
                      CalcwiseStaggerItem(
                        index: 2,
                        child: SectionCard(
                          title: 'Region',
                          children: [
                            _ExplainRow(
                              icon: Icons.public_rounded,
                              title: r.region.label,
                              body: r.region.description,
                              ct: ct,
                            ),
                          ],
                        ),
                      ),
                      if (r.isEmergency)
                        CalcwiseStaggerItem(
                          index: 3,
                          child: _WarningCard(
                            title: 'Emergency tax code',
                            body:
                                'The W1, M1 or X marker means this is a '
                                'non-cumulative (emergency) code. Tax is worked '
                                'out on each pay period in isolation, ignoring '
                                'what you have already paid this year. It is '
                                'usually temporary — check with HMRC if it does '
                                'not update.',
                            ct: ct,
                          ),
                        ),
                      CalcwiseStaggerItem(
                        index: 4,
                        child: _DisclaimerCard(ct: ct),
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

class _ExplainRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final CalcwiseTheme ct;

  const _ExplainRow({
    required this.icon,
    required this.title,
    required this.body,
    required this.ct,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: AppTheme.primary),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: ct.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    body,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: ct.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _WarningCard extends StatelessWidget {
  final String title;
  final String body;
  final CalcwiseTheme ct;

  const _WarningCard({
    required this.title,
    required this.body,
    required this.ct,
  });

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.md),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppTheme.warning.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppTheme.warning.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: AppTheme.warning, size: 20),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: ct.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    body,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: ct.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _InvalidCard extends StatelessWidget {
  final String message;
  final CalcwiseTheme ct;
  const _InvalidCard({required this.message, required this.ct});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppTheme.accent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppTheme.accent.withValues(alpha: 0.3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: AppTheme.accent, size: 20),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: ct.textPrimary,
                ),
              ),
            ),
          ],
        ),
      );
}

class _DisclaimerCard extends StatelessWidget {
  final CalcwiseTheme ct;
  const _DisclaimerCard({required this.ct});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xs),
        child: Text(
          'This is a guide based on HMRC 2025/26 tax codes. Always check your '
          'official tax code with HMRC or your employer.',
          style: TextStyle(
            fontSize: 11,
            height: 1.4,
            color: ct.textSecondary,
          ),
        ),
      );
}
