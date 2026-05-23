import 'package:flutter/material.dart';
import 'package:calcwise_core/calcwise_core.dart';
import '../main.dart' show paywallSession;

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) => CalcwiseOnboarding(
        appKey: 'taxuk',
        onDone: () async {
          Navigator.of(context).pushReplacementNamed('/home');
          await paywallSession.recordSession();
        },
        pages: const [
          OnboardingPage(
            icon: Icons.percent_rounded,
            title: 'UK VAT\nCalculator',
            subtitle:
                'Instantly calculate VAT at 20%, 5%, 0% or any custom rate. '
                'Works both ways — net to gross or gross to net.',
            pills: ['Standard 20%', 'Reduced 5%', 'Zero Rate', 'Custom'],
          ),
          OnboardingPage(
            icon: Icons.account_balance_rounded,
            title: 'Income Tax\n& NI 2025/26',
            subtitle:
                'Enter your salary and see your exact take-home pay, '
                'including Scottish rates and National Insurance.',
            pills: [
              'England / Wales / NI',
              'Scottish Rates',
              'NI Class 1',
              'Tax Bands',
            ],
          ),
          OnboardingPage(
            icon: Icons.history_rounded,
            title: 'Save & Share\nYour Results',
            subtitle:
                'Keep a history of your calculations and share or export '
                'results as a PDF.',
            pills: ['History', 'Share', 'PDF Export'],
          ),
        ],
      );
}
