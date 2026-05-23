import 'package:calcwise_core/calcwise_core.dart' hide CrashlyticsService;
import 'package:firebase_analytics/firebase_analytics.dart';
import 'config/ad_config.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'core/freemium/freemium_service.dart';
import 'core/freemium/iap_service.dart';
import 'core/firebase/firebase_options.dart';
import 'core/analytics/analytics_service.dart';
import 'core/services/crashlytics_service.dart';
import 'core/theme/app_theme.dart';
import 'screens/splash_screen.dart';
import 'screens/vat_screen.dart';
import 'screens/income_tax_screen.dart';
import 'screens/history_screen.dart';
import 'screens/settings_screen.dart';
import 'l10n/strings_en.dart';
import 'widgets/paywall_hard.dart';

final paywallSession = PaywallSessionService(appKey: 'taxuk');

final adService = CalcwiseAdService(
  config: CalcwiseAdConfig(
    bannerAndroid: AdConfig.bannerAndroid,
    interstitialAndroid: AdConfig.interstitialAndroid,
    rewardedAndroid: AdConfig.rewardedAndroid,
    calcThreshold: AdConfig.calcThreshold,
    cooldownMinutes: AdConfig.cooldownMinutes,
  ),
  freemium: freemiumService,
  analytics: analyticsService,
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await CrashlyticsService.init();
  await analyticsService.initialize();
  await analyticsService.logAppOpen();

  await themeModeService.initialize();
  await freemiumService.initialize();
  await IAPService.instance.initialize();
  await paywallSession.initialize();

  try {
    await requestCalcwiseConsent();
    await MobileAds.instance.initialize();
    if (AdConfig.adsEnabled) await adService.initialize();
  } catch (e) {
    debugPrint('AdMob init error: $e');
  }

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
  ));

  CalcwiseAdFooter.configure(
    adService: adService,
    freemium: freemiumService,
    isSpanishNotifier: ValueNotifier<bool>(false), // EN-only app
    onGetPremium: () => IAPService.instance.buy(),
  );
  CalcwiseRewardAdSheet.configure(
    adService: adService,
    freemium: freemiumService,
    isSpanishNotifier: ValueNotifier<bool>(false),
  );
  runApp(const TaxUKApp());
}

class TaxUKApp extends StatelessWidget {
  const TaxUKApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeService.notifier,
      builder: (context, themeMode, child) => MaterialApp(
        title: AppStringsEN.appName,
        theme: AppTheme.theme,
        darkTheme: AppTheme.dark,
        themeMode: themeMode,
        navigatorObservers: [
          FirebaseAnalyticsObserver(analytics: FirebaseAnalytics.instance),
        ],
        debugShowCheckedModeBanner: false,
        builder: (context, child) {
          if (!MediaQuery.of(context).disableAnimations) return child!;
          return Theme(
            data: Theme.of(context).copyWith(
              pageTransitionsTheme: const PageTransitionsTheme(
                builders: {
                  TargetPlatform.android: _NoAnimPageTransitionsBuilder(),
                  TargetPlatform.iOS: _NoAnimPageTransitionsBuilder(),
                },
              ),
            ),
            child: child!,
          );
        },
        home: const SplashScreen(),
        routes: {
          '/home': (_) => const MainShell(),
        },
      ),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;
  bool _wasPremium = false;

  @override
  void initState() {
    super.initState();
    _wasPremium = freemiumService.hasFullAccess;
    freemiumService.isPremiumNotifier.addListener(_onPremiumChange);
    iapErrorNotifier.addListener(_onIapError);
    WidgetsBinding.instance.addPostFrameCallback(
        (_) async => await paywallSession.recordSession());
  }

  @override
  void dispose() {
    freemiumService.isPremiumNotifier.removeListener(_onPremiumChange);
    iapErrorNotifier.removeListener(_onIapError);
    super.dispose();
  }

  void _onPremiumChange() {
    final now = freemiumService.hasFullAccess;
    if (now && !_wasPremium && mounted) {
      showPremiumWelcomeSnackBar(context, isSpanish: false);
    }
    _wasPremium = now;
  }

  void _onIapError() {
    final msg = iapErrorNotifier.value;
    if (msg == null || !mounted) return;
    showIapErrorSnackBar(context, msg);
    iapErrorNotifier.value = null;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      systemNavigationBarColor:
          isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC),
      systemNavigationBarIconBrightness:
          isDark ? Brightness.light : Brightness.dark,
    ));
    final ct = CalcwiseTheme.of(context);
    return Scaffold(
      backgroundColor: ct.surface,
      appBar: AppBar(
        backgroundColor: ct.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Row(children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              gradient: AppTheme.ctaGradient,
              borderRadius: BorderRadius.circular(AppRadius.mdPlus),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primary.withValues(alpha: 0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: const Icon(Icons.account_balance_rounded,
                color: Colors.white, size: 18),
          ),
          const SizedBox(width: AppSpacing.smPlus),
          RichText(
            text: TextSpan(children: [
              TextSpan(
                text: 'Tax',
                style: TextStyle(
                  color: ct.textPrimary,
                  fontSize: AppTextSize.subtitleSm,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                ),
              ),
              TextSpan(
                text: ' UK',
                style: const TextStyle(
                  color: AppTheme.primary,
                  fontSize: AppTextSize.subtitleSm,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
            ]),
          ),
        ]),
        actions: [
          CalcwiseAppBarActions(
            freemium: freemiumService,
            session: paywallSession,
            onSettings: () => Navigator.push(
              context,
              PageRouteBuilder(
                pageBuilder: (_, __, ___) => const SettingsScreen(),
                transitionsBuilder: (_, anim, __, child) =>
                    FadeTransition(opacity: anim, child: child),
                transitionDuration: AppDuration.base,
              ),
            ),
            onRewardAd: () => CalcwiseRewardAdSheet.show(context),
            onPremium: () => PaywallHard.show(context),
          ),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: const [
          VatScreen(),
          IncomeTaxScreen(),
          HistoryScreen(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: ct.surface,
          border: Border(top: BorderSide(color: ct.cardBorder)),
        ),
        child: NavigationBar(
          backgroundColor: ct.surface,
          surfaceTintColor: Colors.transparent,
          selectedIndex: _index,
          onDestinationSelected: (i) async {
            analyticsService.logTabSwitch(i);
            setState(() => _index = i);
            final trigger = await paywallSession.recordAction();
            if (!mounted) return;
            if (trigger == PaywallTrigger.hard) {
              PaywallHard.show(context);
            } else if (trigger == PaywallTrigger.soft) {
              PaywallSoft.show(
                context,
                featureTitle: 'Unlimited History',
              );
            }
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.percent_rounded),
              selectedIcon: Icon(Icons.percent),
              label: 'VAT',
            ),
            NavigationDestination(
              icon: Icon(Icons.account_balance_outlined),
              selectedIcon: Icon(Icons.account_balance_rounded),
              label: 'Income Tax',
            ),
            NavigationDestination(
              icon: Icon(Icons.history_rounded),
              selectedIcon: Icon(Icons.history),
              label: 'History',
            ),
          ],
        ),
      ),
    );
  }
}

class _NoAnimPageTransitionsBuilder extends PageTransitionsBuilder {
  const _NoAnimPageTransitionsBuilder();
  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      child;
}
