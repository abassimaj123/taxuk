import 'package:flutter/material.dart';
import 'package:calcwise_core/calcwise_core.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) => CalcwiseOnboarding(
        appKey: 'taxuk',
        onDone: () {
          Navigator.of(context).pushReplacementNamed('/home');
        },
        pages: const [
          OnboardingPage(
            icon: Icons.account_balance_rounded,
            title: 'Know Your\nTake-Home Pay',
            subtitle:
                'Enter your salary and instantly see how much you keep after '
                'Income Tax and National Insurance — with 2026/27 rates for '
                'England, Wales, NI and Scotland.',
            pills: [
              'England & Wales',
              'Scottish Rates',
              'NI Class 1 & 4',
              'Pension & MA',
            ],
          ),
          OnboardingPage(
            icon: Icons.calculate_rounded,
            title: 'Every UK Tax\nin One App',
            subtitle:
                'Beyond income tax — calculate Capital Gains Tax on shares '
                'and property, UK dividend tax, student loan repayments, '
                'VAT, and compare two job offers side by side.',
            pills: [
              'CGT 2026/27',
              'Dividends',
              'Student Loan',
              'Salary Compare',
            ],
          ),
          OnboardingPage(
            icon: Icons.history_rounded,
            title: 'Save, Share\n& Go Premium',
            subtitle:
                'Save unlimited calculations to your history, share results '
                'or export as PDF. Upgrade once and remove all limits — '
                'no subscription, no ads, forever.',
            pills: ['History', 'Share', 'PDF Export', 'No Ads'],
          ),
        ],
      );
}
