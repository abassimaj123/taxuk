import 'package:calcwise_core/calcwise_core.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/analytics/analytics_service.dart';
import '../core/db/database_service.dart';
import '../core/freemium/freemium_service.dart';
import '../core/freemium/iap_service.dart';
import '../core/theme/app_theme.dart';
import '../l10n/strings_en.dart';
import '../main.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Map<String, dynamic>> _history = [];
  bool _loading = true;

  final _fmtGbp = NumberFormat.currency(locale: 'en_GB', symbol: '£');
  final _fmtDate = DateFormat('MMM d, yyyy · hh:mm a');

  @override
  void initState() {
    super.initState();
    analyticsService.logHistoryViewed();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await DatabaseService.instance.getAll();
    if (mounted) {
      setState(() {
        _history = rows;
        _loading = false;
      });
    }
  }

  Future<void> _delete(int id) async {
    await DatabaseService.instance.delete(id);
    _load();
  }

  Future<void> _clearAll(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final ct = CalcwiseTheme.of(ctx);
        return AlertDialog(
          backgroundColor: ct.surfaceHigh,
          title: Text(
            'Clear History?',
            style: TextStyle(color: ct.textPrimary),
          ),
          content: Text(
            'All history entries will be deleted.',
            style: TextStyle(color: ct.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: TextStyle(color: ct.textSecondary)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Clear',
                  style: TextStyle(color: AppTheme.errorRed)),
            ),
          ],
        );
      },
    );
    if (confirm == true) {
      await DatabaseService.instance.clearAll();
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ct = CalcwiseTheme.of(context);
    if (_loading) return const CalcwiseLoadingState();

    return Column(
      children: [
        Expanded(
          child: _history.isEmpty
              ? CalcwiseEmptyState(
                  icon: Icons.history_rounded,
                  title: AppStringsEN.historyEmpty,
                  body:
                      'Your saved VAT and income tax calculations will appear here.',
                  actionLabel: 'Calculate now',
                  onAction: () => mainTabNotifier.requestTab(0),
                )
              : Column(
                  children: [
                    // ── Premium lock banner ──────────────────────────────
                    ValueListenableBuilder<bool>(
                      valueListenable: freemiumService.isPremiumNotifier,
                      builder: (_, isPremium, __) {
                        if (isPremium || freemiumService.hasFullAccess) {
                          return const SizedBox.shrink();
                        }
                        final free = MonetizationConfig.freeHistoryLimit;
                        final count = _history.length;
                        if (count < free) return const SizedBox.shrink();
                        return Container(
                          margin: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.lg,
                            vertical: AppSpacing.sm,
                          ),
                          padding: const EdgeInsets.all(AppSpacing.md),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            border: Border.all(
                              color: AppTheme.primary.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(children: [
                            const Icon(Icons.lock_outline_rounded,
                                color: AppTheme.primary, size: 18),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                AppStringsEN.historyLimit,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: ct.textSecondary,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () => IAPService.instance.buy(),
                              child: const Text(
                                'Upgrade',
                                style: TextStyle(
                                  color: AppTheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ]),
                        );
                      },
                    ),
                    // ── List ─────────────────────────────────────────────
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg,
                          vertical: AppSpacing.sm,
                        ),
                        itemCount: _history.length,
                        itemBuilder: (ctx, i) {
                          final entry = _history[i];
                          return _HistoryTile(
                            entry: entry,
                            fmtGbp: _fmtGbp,
                            fmtDate: _fmtDate,
                            ct: ct,
                            onDelete: () => _delete(entry['id'] as int),
                          );
                        },
                      ),
                    ),
                    // ── Clear all button ──────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        AppSpacing.sm,
                        AppSpacing.lg,
                        AppSpacing.lg,
                      ),
                      child: TextButton.icon(
                        onPressed: () => _clearAll(context),
                        icon: const Icon(Icons.delete_sweep_rounded,
                            size: 18, color: AppTheme.errorRed),
                        label: const Text(
                          'Clear All',
                          style: TextStyle(color: AppTheme.errorRed),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
        const CalcwiseAdFooter(),
      ],
    );
  }
}

// ── History tile ──────────────────────────────────────────────────────────────

class _HistoryTile extends StatelessWidget {
  final Map<String, dynamic> entry;
  final NumberFormat fmtGbp;
  final DateFormat fmtDate;
  final CalcwiseTheme ct;
  final VoidCallback onDelete;

  const _HistoryTile({
    required this.entry,
    required this.fmtGbp,
    required this.fmtDate,
    required this.ct,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final inputs = entry['inputs'] as Map<String, dynamic>;
    final results = entry['results'] as Map<String, dynamic>;
    final type = inputs['type'] as String? ?? 'vat';
    final timestamp = entry['timestamp'] as String?;
    final dateStr =
        timestamp != null ? fmtDate.format(DateTime.parse(timestamp)) : '';

    final String title;
    final String subtitle;
    final IconData icon;

    if (type == 'income_tax') {
      final takeHome = (results['net'] as num?)?.toDouble() ?? 0;
      final taxAmt = (results['income_tax'] as num?)?.toDouble() ?? 0;
      final isScotland = inputs['is_scotland'] as bool? ?? false;
      title = 'Income Tax — ${fmtGbp.format(inputs['gross'] ?? 0)} gross';
      final niAmt = (results['ni'] as num?)?.toDouble() ?? 0;
      subtitle =
          'Take-home: ${fmtGbp.format(takeHome)} · Tax: ${fmtGbp.format(taxAmt)} · NI: ${fmtGbp.format(niAmt)}'
          '${isScotland ? ' (Scotland)' : ''}';
      icon = Icons.account_balance_rounded;
    } else if (type == 'dividend') {
      final taxDue = (results['tax_due'] as num?)?.toDouble() ?? 0;
      final band = results['band'] as String? ?? '';
      title = 'Dividend — ${fmtGbp.format(inputs['gross_dividend'] ?? 0)}';
      subtitle = 'Tax due: ${fmtGbp.format(taxDue)} · $band Rate';
      icon = Icons.bar_chart_rounded;
    } else if (type == 'student_loan') {
      final monthly = (results['monthly_repayment'] as num?)?.toDouble() ?? 0;
      final plan = inputs['plan'] as String? ?? '';
      title = 'Student Loan — $plan';
      subtitle =
          'Monthly: ${fmtGbp.format(monthly)} · ${fmtGbp.format(inputs['gross_income'] ?? 0)} income';
      icon = Icons.school_rounded;
    } else if (type == 'cgt') {
      final taxDue = (results['tax_due'] as num?)?.toDouble() ?? 0;
      final gain = (inputs['gain'] as num?)?.toDouble() ?? 0;
      final assetType = inputs['asset_type'] as String? ?? 'Other Assets';
      title = 'CGT — ${fmtGbp.format(gain)} gain';
      subtitle = 'Tax due: ${fmtGbp.format(taxDue)} · $assetType';
      icon = Icons.trending_up_rounded;
    } else if (type == 'salary_compare') {
      final netA = (results['net_a'] as num?)?.toDouble() ?? 0;
      final netB = (results['net_b'] as num?)?.toDouble() ?? 0;
      final nameA = inputs['name_a'] as String? ?? 'Job A';
      final nameB = inputs['name_b'] as String? ?? 'Job B';
      title = 'Salary Compare — $nameA vs $nameB';
      subtitle =
          '${fmtGbp.format(netA / 12)}/mo vs ${fmtGbp.format(netB / 12)}/mo';
      icon = Icons.compare_arrows_rounded;
    } else {
      final net = (results['net'] as num?)?.toDouble() ?? 0;
      final vat = (results['vat'] as num?)?.toDouble() ?? 0;
      final rateLabel = inputs['rate_label'] as String? ?? '';
      title = 'VAT — $rateLabel';
      subtitle = 'Net: ${fmtGbp.format(net)} · VAT: ${fmtGbp.format(vat)}';
      icon = Icons.percent_rounded;
    }

    return Dismissible(
      key: Key('history_${entry['id']}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppTheme.errorRed.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child:
            const Icon(Icons.delete_outline_rounded, color: AppTheme.errorRed),
      ),
      onDismissed: (_) => onDelete(),
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        decoration: BoxDecoration(
          color: ct.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: ct.cardBorder),
        ),
        child: ListTile(
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(icon, color: AppTheme.primary, size: 20),
          ),
          title: Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: ct.textPrimary,
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                subtitle,
                style: TextStyle(fontSize: 12, color: ct.textSecondary),
              ),
              Text(
                dateStr,
                style: TextStyle(
                  fontSize: 11,
                  color: ct.textSecondary.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
          isThreeLine: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
        ),
      ),
    );
  }
}
