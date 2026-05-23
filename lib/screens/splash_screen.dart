import 'package:flutter/material.dart';
import 'package:calcwise_core/calcwise_core.dart';
import '../core/theme/app_theme.dart';
import '../core/analytics/analytics_service.dart';
import '../main.dart' show paywallSession;
import 'onboarding_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    try {
      analyticsService.logAppOpen();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => CalcwiseSplash(
        appName: 'Tax',
        appSuffix: 'UK',
        tagline: 'VAT & Income Tax Calculator',
        chips: const [
          'VAT 20%/5%/0%',
          'Scottish Tax',
          'NI 2025/26',
          'Income Tax',
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
            await paywallSession.recordSession();
          }
        },
      );
}
