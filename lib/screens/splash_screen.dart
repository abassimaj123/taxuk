import 'package:flutter/material.dart';
import 'package:calcwise_core/calcwise_core.dart';
import '../core/theme/app_theme.dart';
import 'onboarding_screen.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) => CalcwiseSplash(
        appName: 'Tax',
        appSuffix: 'UK',
        tagline: 'UK Tax Calculator 2025/26',
        chips: const [
          'Income Tax',
          'Scottish Rates',
          'CGT & Dividends',
          'Student Loan',
        ],
        badgeIcon: Icons.account_balance_rounded,
        backgroundColor: AppTheme.primary,
        onComplete: () async {
          final done = await isOnboardingComplete('taxuk');
          if (!context.mounted) return;
          if (!done) {
            Navigator.of(context).pushReplacement(
              PageRouteBuilder(
                pageBuilder: (_, __, ___) => const OnboardingScreen(),
                transitionsBuilder: (_, anim, __, child) =>
                    FadeTransition(opacity: anim, child: child),
                transitionDuration: AppDuration.base,
              ),
            );
          } else {
            Navigator.of(context).pushReplacementNamed('/home');
          }
        },
      );
}
