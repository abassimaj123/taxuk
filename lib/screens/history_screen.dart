import 'package:calcwise_core/calcwise_core.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/analytics/analytics_service.dart' show analyticsService;
import '../core/db/database_service.dart';
import '../core/freemium/freemium_service.dart';
import '../core/freemium/iap_service.dart';
import '../core/theme/app_theme.dart';
import '../l10n/strings_en.dart';
import '../main.dart' show mainTabNotifier;

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  static final refreshNotifier = ValueNotifier<int>(0);

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;

  final _fmtGbp = NumberFormat.currency(locale: 'en_GB', symbol: '£');
  final _fmtDate = DateFormat('MMM d, yyyy · hh:mm a');

  // ── Getters ────────────────────────────────────────────────────────────────

  List<Map<String, dynamic>> get _pinned =>
      _rows.where((r) => (r['is_pinned'] as int? ?? 0) == 1).toList();

  List<Map<String, dynamic>> get _autoSaves =>
      _rows.where((r) => (r['is_pinned'] as int? ?? 0) == 0).toList();

  List<Map<String, dynamic>> get _visibleAutoSaves {
    final limit = freemiumService.hasFullAccess
        ? MonetizationConfig.premiumRingBufferSize
        : MonetizationConfig.freeRingBufferSize;
    final all = _autoSaves;
    return all.length > limit ? all.sublist(0, limit) : all;
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    analyticsService.logHistoryViewed();
    _load();
    HistoryScreen.refreshNotifier.addListener(_onRefresh);
  }

  @override
  void dispose() {
    HistoryScreen.refreshNotifier.removeListener(_onRefresh);
    super.dispose();
  }

  void _onRefresh() => _load();

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await DatabaseService.instance.getAll();
    if (mounted) {
      setState(() {
        _rows = rows;
        _loading = false;
      });
    }
  }

  // ── Mutations ──────────────────────────────────────────────────────────────

  Future<void> _delete(int id) async {
    await DatabaseService.instance.delete(id);
    _load();
  }

  Future<void> _unpin(int id) async {
    await DatabaseService.instance.update(id, {'is_pinned': 0});
    _load();
  }

  Future<void> _rename(Map<String, dynamic> row) async {
    final controller =
        TextEditingController(text: row['pin_label'] as String? ?? '');
    final newLabel = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Rename Scenario'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Scenario name'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newLabel == null) return;
    await DatabaseService.instance
        .update(row['id'] as int, {'pin_label': newLabel.trim()});
    _load();
  }

  Future<void> _clearAll() async {
    final ct = CalcwiseTheme.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ct.surfaceHigh,
        title: Text('Clear History?', style: TextStyle(color: ct.textPrimary)),
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
      ),
    );
    if (confirm == true) {
      await DatabaseService.instance.clearAll();
      _load();
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) return const CalcwiseLoadingState();
    final ct = CalcwiseTheme.of(context);

    if (_rows.isEmpty) {
      return Column(
        children: [
          Expanded(
            child: CalcwiseEmptyState(
              icon: Icons.history_rounded,
              title: AppStringsEN.historyEmpty,
              body:
                  'Your saved tax calculations will appear here. '
                  'Run a calculation to get started.',
              actionLabel: 'Calculate now',
              onAction: () => mainTabNotifier.requestTab(0),
            ),
          ),
          const CalcwiseAdFooter(),
        ],
      );
    }

    final pinned = _pinned;
    final recent = _visibleAutoSaves;

    return Column(
      children: [
        Expanded(
          child: CustomScrollView(
            slivers: [
              // ── Saved Scenarios (pinned) ─────────────────────────────────
              if (pinned.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: _SectionHeader(
                    icon: Icons.bookmark_rounded,
                    title: 'Saved Scenarios',
                    ct: ct,
                  ),
                ),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => _HistoryCard(
                      row: pinned[i],
                      fmtGbp: _fmtGbp,
                      fmtDate: _fmtDate,
                      ct: ct,
                      isPinned: true,
                      onUnpin: () => _unpin(pinned[i]['id'] as int),
                      onRename: () => _rename(pinned[i]),
                      onDelete: () => _delete(pinned[i]['id'] as int),
                    ),
                    childCount: pinned.length,
                  ),
                ),
              ],

              // ── Recent Calculations (auto-saves) ─────────────────────────
              if (recent.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: _SectionHeader(
                    icon: Icons.history_rounded,
                    title: 'Recent Calculations',
                    subtitle: !freemiumService.hasFullAccess
                        ? 'Free: up to ${MonetizationConfig.freeRingBufferSize}'
                        : null,
                    ct: ct,
                  ),
                ),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => _HistoryCard(
                      row: recent[i],
                      fmtGbp: _fmtGbp,
                      fmtDate: _fmtDate,
                      ct: ct,
                      isPinned: false,
                      onDelete: () => _delete(recent[i]['id'] as int),
                    ),
                    childCount: recent.length,
                  ),
                ),
              ],

              // ── Upgrade banner ───────────────────────────────────────────
              SliverToBoxAdapter(
                child: ValueListenableBuilder<bool>(
                  valueListenable: freemiumService.isPremiumNotifier,
                  builder: (_, isPremium, __) {
                    if (isPremium) return const SizedBox.shrink();
                    return Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                        vertical: AppSpacing.sm,
                      ),
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(
                          color: AppTheme.primary.withValues(alpha: 0.25),
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
                                fontSize: 12, color: ct.textSecondary),
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
              ),

              // ── Clear all ────────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.sm,
                    AppSpacing.lg,
                    AppSpacing.lg,
                  ),
                  child: TextButton.icon(
                    onPressed: _clearAll,
                    icon: const Icon(Icons.delete_sweep_rounded,
                        size: 18, color: AppTheme.errorRed),
                    label: const Text('Clear All',
                        style: TextStyle(color: AppTheme.errorRed)),
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

// ── Section Header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final CalcwiseTheme ct;

  const _SectionHeader({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.ct,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.sm,
        ),
        child: Row(children: [
          Icon(icon, size: 14, color: AppTheme.primary),
          const SizedBox(width: AppSpacing.xs),
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: ct.textSecondary,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(width: AppSpacing.sm),
            Text(
              subtitle!,
              style: TextStyle(fontSize: 11, color: ct.textSecondary),
            ),
          ],
        ]),
      );
}

// ── History Card ──────────────────────────────────────────────────────────────

enum _CardAction { unpin, rename, delete }

class _HistoryCard extends StatelessWidget {
  final Map<String, dynamic> row;
  final NumberFormat fmtGbp;
  final DateFormat fmtDate;
  final CalcwiseTheme ct;
  final bool isPinned;
  final VoidCallback onDelete;
  final VoidCallback? onUnpin;
  final VoidCallback? onRename;

  const _HistoryCard({
    required this.row,
    required this.fmtGbp,
    required this.fmtDate,
    required this.ct,
    required this.isPinned,
    required this.onDelete,
    this.onUnpin,
    this.onRename,
  });

  @override
  Widget build(BuildContext context) {
    final inputs = row['inputs'] as Map<String, dynamic>;
    final results = row['results'] as Map<String, dynamic>;
    final type = inputs['type'] as String? ?? 'vat';
    final timestamp = row['timestamp'] as String?;
    final dateStr =
        timestamp != null ? fmtDate.format(DateTime.parse(timestamp)) : '';
    final pinLabel = row['pin_label'] as String?;

    final String title;
    final String subtitle;
    final IconData icon;

    switch (type) {
      case 'income_tax':
        final takeHome = (results['net'] as num?)?.toDouble() ?? 0;
        final taxAmt = (results['income_tax'] as num?)?.toDouble() ?? 0;
        final niAmt = (results['ni'] as num?)?.toDouble() ?? 0;
        final isScotland = inputs['is_scotland'] as bool? ?? false;
        title = pinLabel?.isNotEmpty == true
            ? pinLabel!
            : 'Income Tax — ${fmtGbp.format(inputs['gross'] ?? 0)} gross';
        subtitle =
            'Take-home: ${fmtGbp.format(takeHome)} · Tax: ${fmtGbp.format(taxAmt)}'
            ' · NI: ${fmtGbp.format(niAmt)}${isScotland ? ' (Scotland)' : ''}';
        icon = Icons.account_balance_rounded;
      case 'dividend':
        final taxDue = (results['tax_due'] as num?)?.toDouble() ?? 0;
        final band = results['band'] as String? ?? '';
        title = 'Dividend — ${fmtGbp.format(inputs['gross_dividend'] ?? 0)}';
        subtitle = 'Tax due: ${fmtGbp.format(taxDue)} · $band Rate';
        icon = Icons.bar_chart_rounded;
      case 'student_loan':
        final monthly =
            (results['monthly_repayment'] as num?)?.toDouble() ?? 0;
        final plan = inputs['plan'] as String? ?? '';
        title = 'Student Loan — $plan';
        subtitle =
            'Monthly: ${fmtGbp.format(monthly)} · ${fmtGbp.format(inputs['gross_income'] ?? 0)} income';
        icon = Icons.school_rounded;
      case 'cgt':
        final taxDue = (results['tax_due'] as num?)?.toDouble() ?? 0;
        final gain = (inputs['gain'] as num?)?.toDouble() ?? 0;
        final assetType = inputs['asset_type'] as String? ?? 'Other Assets';
        title = 'CGT — ${fmtGbp.format(gain)} gain';
        subtitle = 'Tax due: ${fmtGbp.format(taxDue)} · $assetType';
        icon = Icons.trending_up_rounded;
      case 'salary_compare':
        final netA = (results['net_a'] as num?)?.toDouble() ?? 0;
        final netB = (results['net_b'] as num?)?.toDouble() ?? 0;
        final nameA = inputs['name_a'] as String? ?? 'Job A';
        final nameB = inputs['name_b'] as String? ?? 'Job B';
        title = 'Salary Compare — $nameA vs $nameB';
        subtitle =
            '${fmtGbp.format(netA / 12)}/mo vs ${fmtGbp.format(netB / 12)}/mo';
        icon = Icons.compare_arrows_rounded;
      default: // vat
        final net = (results['net'] as num?)?.toDouble() ?? 0;
        final vat = (results['vat'] as num?)?.toDouble() ?? 0;
        final rateLabel = inputs['rate_label'] as String? ?? '';
        title = 'VAT — $rateLabel';
        subtitle = 'Net: ${fmtGbp.format(net)} · VAT: ${fmtGbp.format(vat)}';
        icon = Icons.percent_rounded;
    }

    final cardBorder = isPinned
        ? Border.all(color: AppTheme.primary.withValues(alpha: 0.45), width: 1.5)
        : Border.all(color: ct.cardBorder);

    Widget card = Container(
      margin: const EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        bottom: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: ct.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: cardBorder,
      ),
      child: ListTile(
        leading: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(icon, color: AppTheme.primary, size: 20),
            ),
            if (isPinned)
              Positioned(
                top: -4,
                right: -4,
                child: Icon(Icons.bookmark_rounded,
                    size: 14, color: AppTheme.primary),
              ),
          ],
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
        trailing: isPinned
            ? PopupMenuButton<_CardAction>(
                icon: const Icon(Icons.more_vert_rounded, size: 18),
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: _CardAction.unpin,
                    child: Row(children: [
                      Icon(Icons.bookmark_remove_rounded, size: 16),
                      SizedBox(width: AppSpacing.sm),
                      Text('Unpin'),
                    ]),
                  ),
                  const PopupMenuItem(
                    value: _CardAction.rename,
                    child: Row(children: [
                      Icon(Icons.edit_outlined, size: 16),
                      SizedBox(width: AppSpacing.sm),
                      Text('Rename'),
                    ]),
                  ),
                  PopupMenuItem(
                    value: _CardAction.delete,
                    child: Row(children: [
                      Icon(Icons.delete_outline_rounded,
                          size: 16, color: AppTheme.errorRed),
                      const SizedBox(width: AppSpacing.sm),
                      Text('Delete',
                          style: TextStyle(color: AppTheme.errorRed)),
                    ]),
                  ),
                ],
                onSelected: (action) {
                  switch (action) {
                    case _CardAction.unpin:
                      onUnpin?.call();
                    case _CardAction.rename:
                      onRename?.call();
                    case _CardAction.delete:
                      onDelete();
                  }
                },
              )
            : null,
      ),
    );

    if (!isPinned) {
      card = Dismissible(
        key: Key('history_${row['id']}'),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: AppSpacing.lg),
          margin: const EdgeInsets.only(
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            bottom: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: AppTheme.errorRed.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: const Icon(Icons.delete_outline_rounded,
              color: AppTheme.errorRed),
        ),
        onDismissed: (_) => onDelete(),
        child: card,
      );
    }

    return card;
  }
}
