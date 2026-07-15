import 'package:calcwise_core/calcwise_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../core/analytics/analytics_service.dart';
import '../core/db/database_service.dart';
import '../core/theme/app_theme.dart';

class HistoryDetailScreen extends StatefulWidget {
  final Map<String, dynamic> row;

  const HistoryDetailScreen({super.key, required this.row});

  @override
  State<HistoryDetailScreen> createState() => _HistoryDetailScreenState();

  Widget _build(BuildContext context) {
    final ct = CalcwiseTheme.of(context);
    final inputs = row['inputs'] as Map<String, dynamic>? ?? {};
    final results = row['results'] as Map<String, dynamic>? ?? {};
    final type = inputs['type'] as String? ?? 'vat';
    final timestamp = row['timestamp'] as String?;
    final pinLabel = row['pin_label'] as String?;

    final fmtGbp = NumberFormat.currency(locale: 'en_GB', symbol: '£', decimalDigits: 2);
    final fmtDate = DateFormat('d MMM yyyy, HH:mm', 'en');
    final dateStr = timestamp != null ? fmtDate.format(DateTime.parse(timestamp)) : '';

    final title = _titleFor(type, inputs, results, fmtGbp, pinLabel);
    final rows = _rowsFor(type, inputs, results, fmtGbp);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: ct.surface,
        elevation: 0,
        title: Text(
          title,
          style: TextStyle(fontSize: AppTextSize.md, fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_rounded),
            tooltip: 'Share',
            onPressed: () => _share(context, title, rows, dateStr),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline_rounded, color: AppTheme.errorRed),
            tooltip: 'Delete',
            onPressed: () => _confirmDelete(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          // Date chip
          if (dateStr.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Text(
                dateStr,
                style: TextStyle(fontSize: AppTextSize.sm, color: ct.textSecondary),
              ),
            ),

          // Results section
          _SectionCard(
            title: 'Results',
            ct: ct,
            children: rows
                .where((r) => r.isResult)
                .map((r) => _DataRow(label: r.label, value: r.value, ct: ct, highlight: r.isHighlight))
                .toList(),
          ),

          const SizedBox(height: AppSpacing.md),

          // Inputs section
          _SectionCard(
            title: 'Inputs',
            ct: ct,
            children: rows
                .where((r) => !r.isResult)
                .map((r) => _DataRow(label: r.label, value: r.value, ct: ct))
                .toList(),
          ),

          const SizedBox(height: AppSpacing.xl),

          // Disclaimer
          Text(
            'This app is for informational purposes only. Consult a qualified tax professional.',
            style: TextStyle(fontSize: AppTextSize.xs, color: ct.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  String _titleFor(String type, Map<String, dynamic> inputs, Map<String, dynamic> results,
      NumberFormat fmt, String? pinLabel) {
    if (pinLabel?.isNotEmpty == true) return pinLabel!;
    switch (type) {
      case 'income_tax':
        final gross = (inputs['gross'] as num?)?.toDouble() ?? 0;
        return 'Income Tax — ${fmt.format(gross)} gross';
      case 'dividend':
        final div = (inputs['dividendIncome'] as num?)?.toDouble() ?? 0;
        return 'Dividend — ${fmt.format(div)}';
      case 'student_loan':
        final plan = inputs['plan'] as String? ?? '';
        return 'Student Loan — $plan';
      case 'cgt':
        final gain = (inputs['gains'] as num?)?.toDouble() ?? 0;
        return 'CGT — ${fmt.format(gain)} gain';
      case 'rental_income':
        final rentalIncome = (inputs['rentalIncome'] as num?)?.toDouble() ?? 0;
        return 'Rental Income — ${fmt.format(rentalIncome)}';
      case 'savings_interest':
        final interest = (inputs['interest'] as num?)?.toDouble() ?? 0;
        return 'Savings Interest — ${fmt.format(interest)}';
      case 'salary_compare':
        final a = inputs['name_a'] as String? ?? 'Job A';
        final b = inputs['name_b'] as String? ?? 'Job B';
        return 'Salary Compare — $a vs $b';
      default:
        return 'VAT Calculation';
    }
  }

  List<_Row> _rowsFor(String type, Map<String, dynamic> inputs,
      Map<String, dynamic> results, NumberFormat fmt) {
    switch (type) {
      case 'income_tax':
        return [
          _Row('Take-home (Annual)', fmt.format((results['net'] as num?)?.toDouble() ?? 0), isResult: true, isHighlight: true),
          _Row('Income Tax', fmt.format((results['income_tax'] as num?)?.toDouble() ?? 0), isResult: true),
          _Row('National Insurance', fmt.format((results['ni'] as num?)?.toDouble() ?? 0), isResult: true),
          _Row('Take-home (Monthly)', fmt.format(((results['net'] as num?)?.toDouble() ?? 0) / 12), isResult: true),
          _Row('Gross Salary', fmt.format((inputs['gross'] as num?)?.toDouble() ?? 0)),
          _Row('Tax Code', inputs['tax_code'] as String? ?? 'Standard'),
          if (inputs['is_scotland'] == true) _Row('Region', 'Scotland'),
          if (inputs['has_marriage_allowance'] == true)
            _Row('Marriage Allowance', 'Applied'),
        ];
      case 'dividend':
        final divTax = (results['dividendTax'] as num?)?.toDouble() ?? 0;
        final divIncome = (inputs['dividendIncome'] as num?)?.toDouble() ?? 0;
        return [
          _Row('Tax Due', fmt.format(divTax), isResult: true, isHighlight: true),
          _Row('Net Dividend', fmt.format(divIncome - divTax), isResult: true),
          _Row('Effective Rate', '${(((results['effectiveRate'] as num?)?.toDouble() ?? 0) * 100).toStringAsFixed(1)}%', isResult: true),
          _Row('Gross Dividend', fmt.format(divIncome)),
          _Row('Other Income', fmt.format((inputs['grossIncome'] as num?)?.toDouble() ?? 0)),
          _Row('Taxable Dividend', fmt.format((results['taxableDiv'] as num?)?.toDouble() ?? 0)),
        ];
      case 'student_loan':
        return [
          _Row('Monthly Repayment', fmt.format((results['monthly_repayment'] as num?)?.toDouble() ?? 0), isResult: true, isHighlight: true),
          _Row('Annual Repayment', fmt.format(((results['monthly_repayment'] as num?)?.toDouble() ?? 0) * 12), isResult: true),
          _Row('Weekly Repayment', fmt.format(((results['monthly_repayment'] as num?)?.toDouble() ?? 0) * 12 / 52), isResult: true),
          _Row('Salary', fmt.format((inputs['salary'] as num?)?.toDouble() ?? 0)),
          _Row('Plan', inputs['plan'] as String? ?? ''),
        ];
      case 'cgt':
        return [
          _Row('CGT Due', fmt.format((results['cgtTax'] as num?)?.toDouble() ?? 0), isResult: true, isHighlight: true),
          _Row('Taxable Gain', fmt.format((results['taxableGain'] as num?)?.toDouble() ?? 0), isResult: true),
          _Row('Effective Rate', '${(((results['effectiveRate'] as num?)?.toDouble() ?? 0) * 100).toStringAsFixed(1)}%', isResult: true),
          _Row('Total Gain', fmt.format((inputs['gains'] as num?)?.toDouble() ?? 0)),
          _Row('Asset Type', inputs['assetType'] as String? ?? ''),
          _Row('Annual Exemption', fmt.format((results['allowance'] as num?)?.toDouble() ?? 0)),
        ];
      case 'rental_income':
        return [
          _Row('Tax on Rental', fmt.format((results['tax'] as num?)?.toDouble() ?? 0), isResult: true, isHighlight: true),
          _Row('Taxable Profit', fmt.format((results['taxableProfit'] as num?)?.toDouble() ?? 0), isResult: true),
          _Row('Rental Income', fmt.format((inputs['rentalIncome'] as num?)?.toDouble() ?? 0)),
          _Row('Other Income', fmt.format((inputs['otherIncome'] as num?)?.toDouble() ?? 0)),
          _Row('Allowable Expenses', fmt.format((inputs['expenses'] as num?)?.toDouble() ?? 0)),
        ];
      case 'savings_interest':
        return [
          _Row('Tax on Savings', fmt.format((results['tax'] as num?)?.toDouble() ?? 0), isResult: true, isHighlight: true),
          _Row('Net Interest', fmt.format((results['netInterest'] as num?)?.toDouble() ?? 0), isResult: true),
          _Row('Personal Savings Allowance', fmt.format((results['psa'] as num?)?.toDouble() ?? 0), isResult: true),
          _Row('Gross Interest', fmt.format((inputs['interest'] as num?)?.toDouble() ?? 0)),
          _Row('Other Income', fmt.format((inputs['otherIncome'] as num?)?.toDouble() ?? 0)),
        ];
      case 'salary_compare':
        return [
          _Row('${inputs['name_a'] ?? 'Job A'} Take-home (Annual)', fmt.format((results['net_a'] as num?)?.toDouble() ?? 0), isResult: true, isHighlight: true),
          _Row('${inputs['name_b'] ?? 'Job B'} Take-home (Annual)', fmt.format((results['net_b'] as num?)?.toDouble() ?? 0), isResult: true, isHighlight: true),
          _Row('Difference (Monthly)', fmt.format((((results['net_a'] as num?)?.toDouble() ?? 0) - ((results['net_b'] as num?)?.toDouble() ?? 0)).abs() / 12), isResult: true),
          _Row('${inputs['name_a'] ?? 'Job A'} Gross', fmt.format((inputs['gross_a'] as num?)?.toDouble() ?? 0)),
          _Row('${inputs['name_b'] ?? 'Job B'} Gross', fmt.format((inputs['gross_b'] as num?)?.toDouble() ?? 0)),
        ];
      default: // vat
        return [
          _Row('VAT Amount', fmt.format((results['vat'] as num?)?.toDouble() ?? 0), isResult: true, isHighlight: true),
          _Row('Gross (inc. VAT)', fmt.format((results['gross'] as num?)?.toDouble() ?? 0), isResult: true),
          _Row('Net Amount', fmt.format((results['net'] as num?)?.toDouble() ?? 0), isResult: true),
          _Row('VAT Rate', inputs['rate_label'] as String? ?? '20%'),
          _Row('Input Amount', fmt.format((inputs['amount'] as num?)?.toDouble() ?? 0)),
        ];
    }
  }

  void _share(BuildContext context, String title, List<_Row> rows, String dateStr) {
    final sb = StringBuffer();
    sb.writeln(title);
    if (dateStr.isNotEmpty) sb.writeln(dateStr);
    sb.writeln();
    final resultRows = rows.where((r) => r.isResult).toList();
    final inputRows = rows.where((r) => !r.isResult).toList();
    if (resultRows.isNotEmpty) {
      sb.writeln('── Results ──');
      for (final r in resultRows) sb.writeln('${r.label}: ${r.value}');
    }
    if (inputRows.isNotEmpty) {
      sb.writeln();
      sb.writeln('── Inputs ──');
      for (final r in inputRows) sb.writeln('${r.label}: ${r.value}');
    }
    sb.writeln();
    sb.writeln('Calculated with TaxUK · https://calqwise.com/privacy');
    Clipboard.setData(ClipboardData(text: sb.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied to clipboard'), duration: Duration(seconds: 2)),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final id = row['id'] as int?;
    if (id == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete entry?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: TextStyle(color: AppTheme.errorRed)),
          ),
        ],
      ),
    );
    if (confirm == true && context.mounted) {
      await DatabaseService.instance.delete(id);
      if (context.mounted) Navigator.pop(context, 'deleted');
    }
  }
}

class _HistoryDetailScreenState extends State<HistoryDetailScreen> {
  @override
  void initState() {
    super.initState();
    analyticsService.logScreenView('history_detail');
  }

  @override
  Widget build(BuildContext context) => widget._build(context);
}

class _Row {
  final String label;
  final String value;
  final bool isResult;
  final bool isHighlight;
  const _Row(this.label, this.value, {this.isResult = false, this.isHighlight = false});
}

class _SectionCard extends StatelessWidget {
  final String title;
  final CalcwiseTheme ct;
  final List<Widget> children;
  const _SectionCard({required this.title, required this.ct, required this.children});

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        color: ct.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: ct.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xs),
            child: Text(
              title.toUpperCase(),
              style: TextStyle(
                fontSize: AppTextSize.xs,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: ct.textSecondary,
              ),
            ),
          ),
          const Divider(height: 1),
          ...children,
        ],
      ),
    );
  }
}

class _DataRow extends StatelessWidget {
  final String label;
  final String value;
  final CalcwiseTheme ct;
  final bool highlight;
  const _DataRow({required this.label, required this.value, required this.ct, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.smPlus),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              label,
              style: TextStyle(fontSize: AppTextSize.sm, color: ct.textSecondary),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: highlight ? AppTextSize.body : AppTextSize.sm,
                fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
                color: highlight ? AppTheme.primary : ct.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
