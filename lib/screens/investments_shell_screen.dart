import 'package:calcwise_core/calcwise_core.dart';
import 'package:flutter/material.dart';
import 'dividend_screen.dart';
import 'cgt_screen.dart';

class InvestmentsShellScreen extends StatelessWidget {
  const InvestmentsShellScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ct = CalcwiseTheme.of(context);
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            color: ct.surface,
            child: TabBar(
              labelColor: ct.primary,
              unselectedLabelColor: ct.textSecondary,
              indicatorColor: ct.primary,
              indicatorWeight: 2.5,
              labelStyle: const TextStyle(
                fontSize: AppTextSize.body,
                fontWeight: FontWeight.w600,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: AppTextSize.body,
                fontWeight: FontWeight.w500,
              ),
              tabs: const [
                Tab(
                  icon: Icon(Icons.bar_chart_rounded, size: 20),
                  text: 'Dividends',
                  iconMargin: EdgeInsets.only(bottom: 2),
                ),
                Tab(
                  icon: Icon(Icons.trending_up_rounded, size: 20),
                  text: 'CGT',
                  iconMargin: EdgeInsets.only(bottom: 2),
                ),
              ],
            ),
          ),
          const Expanded(
            child: TabBarView(
              children: [
                DividendScreen(),
                CGTScreen(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
