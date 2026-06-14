import 'package:calcwise_core/calcwise_core.dart';
import 'package:flutter/material.dart';
import 'vat_screen.dart';
import 'tax_code_checker_screen.dart';
import 'student_loan_screen.dart';
import 'rental_income_screen.dart';
import 'savings_interest_screen.dart';
import 'salary_dividends_screen.dart';
import '../main.dart' show grossIncomeNotifier;

class ToolsHubScreen extends StatelessWidget {
  const ToolsHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ct = CalcwiseTheme.of(context);
    final tools = [
      _ToolEntry(
        icon: Icons.percent_rounded,
        label: 'VAT Calculator',
        subtitle: 'Add or remove 20% VAT instantly',
        screen: const VatScreen(),
      ),
      _ToolEntry(
        icon: Icons.qr_code_2_rounded,
        label: 'Tax Code Checker',
        subtitle: 'Decode your PAYE tax code',
        screen: const TaxCodeCheckerScreen(),
      ),
      _ToolEntry(
        icon: Icons.school_rounded,
        label: 'Student Loan',
        subtitle: 'Plan 1, 2, 4 & 5 repayment calc',
        screenBuilder: () => StudentLoanScreen(
          initialGrossIncome: grossIncomeNotifier.value,
        ),
      ),
      _ToolEntry(
        icon: Icons.home_work_rounded,
        label: 'Rental Income',
        subtitle: 'Rental profit & tax estimate',
        screen: const RentalIncomeScreen(),
      ),
      _ToolEntry(
        icon: Icons.savings_rounded,
        label: 'Savings Interest',
        subtitle: 'PSA & ISA tax on savings',
        screen: const SavingsInterestScreen(),
      ),
      _ToolEntry(
        icon: Icons.balance_rounded,
        label: 'Salary vs Dividends',
        subtitle: 'Optimal split for limited company directors',
        screen: const SalaryDividendsScreen(),
      ),
    ];

    return Scaffold(
      backgroundColor: ct.surface,
      body: SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          itemCount: tools.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final t = tools[i];
            return _ToolTile(entry: t, ct: ct);
          },
        ),
      ),
    );
  }
}

class _ToolEntry {
  final IconData icon;
  final String label;
  final String subtitle;
  final Widget? screen;
  final Widget Function()? screenBuilder;

  const _ToolEntry({
    required this.icon,
    required this.label,
    required this.subtitle,
    this.screen,
    this.screenBuilder,
  }) : assert(screen != null || screenBuilder != null,
            '_ToolEntry requires screen or screenBuilder');
}

class _ToolTile extends StatelessWidget {
  final _ToolEntry entry;
  final CalcwiseTheme ct;

  const _ToolTile({required this.entry, required this.ct});


  @override
  Widget build(BuildContext context) {
    return Material(
      color: ct.surfaceHigh,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => entry.screenBuilder?.call() ?? entry.screen!,
          ),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            border: Border.all(color: ct.cardBorder),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: ct.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(entry.icon, color: ct.primary, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.label,
                      style: TextStyle(
                        color: ct.textPrimary,
                        fontSize: AppTextSize.body,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      entry.subtitle,
                      style: TextStyle(
                        color: ct.textSecondary,
                        fontSize: AppTextSize.sm,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: ct.textSecondary, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
