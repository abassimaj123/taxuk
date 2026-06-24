import 'dart:async';
import 'package:calcwise_core/calcwise_core.dart' hide CrashlyticsService;
import 'package:intl/date_symbol_data_local.dart';
import 'core/db/taxuk_database_adapter.dart';
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
import 'screens/income_tax_screen.dart';
import 'screens/investments_shell_screen.dart';
import 'screens/tools_hub_screen.dart';
import 'screens/salary_comparison_screen.dart';
import 'screens/history_screen.dart';
import 'screens/settings_screen.dart';
import 'l10n/strings_en.dart';
import 'widgets/paywall_hard.dart';
import 'widgets/paywall_soft.dart';

final paywallSession = PaywallSessionService(
  appKey: 'taxuk',
  hasFullAccess: () => freemiumService.hasFullAccess,
);

/// SmartHistory ring buffer + pinned scenarios service.
final smartHistoryService = SmartHistoryService(
  db: const TaxUKDatabaseAdapter(),
  freemium: freemiumService,
);

/// Requests the main shell to switch to a given bottom-nav tab index.
/// Index 0 is the primary Income Tax calculator.
class _MainTabNotifier extends ChangeNotifier {
  int _value = 0;
  int get value => _value;

  /// Requests a tab switch. Always notifies, even if the target index
  /// equals the last requested value, so the shell reacts reliably.
  void requestTab(int index) {
    _value = index;
    notifyListeners();
  }
}

final _MainTabNotifier mainTabNotifier = _MainTabNotifier();

/// Shared gross income from the Income Tax calculator.
/// Updated on every calculation so Dividend and Student Loan screens
/// can pre-fill their salary field when the user navigates to them.
final ValueNotifier<double?> grossIncomeNotifier = ValueNotifier<double?>(null);

final adService = CalcwiseAdService(
  config: CalcwiseAdConfig(
    bannerAndroid: AdConfig.bannerAndroid,
    interstitialAndroid: AdConfig.interstitialAndroid,
    rewardedAndroid: AdConfig.rewardedAndroid,
  ),
  freemium: freemiumService,
  analytics: analyticsService,
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('en_GB', null);
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  unawaited(CalcwiseRemoteConfig.initialize());
  await CalcwiseTax.init(remoteFetcher: calcwiseTaxRemoteFetch);
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
    if (kDebugMode) {
      await MobileAds.instance.updateRequestConfiguration(
        RequestConfiguration(testDeviceIds: ['FD16D4616C3A21C3ACE5E48F8DC9C1DC']),
      );
    }
    if (AdConfig.adsEnabled) await adService.initialize();
  } catch (e) {
    if (kDebugMode) debugPrint('AdMob init error: $e');
  }

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
  ));

  AnalyticsService.instance.setUserPremium(freemiumService.hasFullAccess);

  CalcwiseAdFooter.configure(
    adService: adService,
    freemium: freemiumService,
    isSpanishNotifier: ValueNotifier<bool>(false), // EN-only app
    onGetPremium: () => IAPService.instance.buy(),
    analytics: AnalyticsService.instance,
  );
  CalcwiseRewardAdSheet.configure(
    adService: adService,
    freemium: freemiumService,
    isSpanishNotifier: ValueNotifier<bool>(false),
  );
  PaywallHard.setAnalytics(AnalyticsService.instance);
  PaywallSoft.setAnalytics(AnalyticsService.instance);
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

  static const List<Widget> _screens = [
    IncomeTaxScreen(),
    SalaryComparisonScreen(),
    InvestmentsShellScreen(),
    ToolsHubScreen(),
    HistoryScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _wasPremium = freemiumService.hasFullAccess;
    freemiumService.isPremiumNotifier.addListener(_onPremiumChange);
    iapErrorNotifier.addListener(_onIapError);
    iapRestoreResultNotifier.addListener(_onRestoreResult);
    mainTabNotifier.addListener(_onTabRequested);
    WidgetsBinding.instance.addPostFrameCallback(
        (_) async => await paywallSession.recordSession());
  }

  @override
  void dispose() {
    freemiumService.isPremiumNotifier.removeListener(_onPremiumChange);
    iapErrorNotifier.removeListener(_onIapError);
    iapRestoreResultNotifier.removeListener(_onRestoreResult);
    mainTabNotifier.removeListener(_onTabRequested);
    super.dispose();
  }

  void _onRestoreResult() {
    final result = iapRestoreResultNotifier.value;
    if (result == null || !mounted) return;
    final msg = result == 'restored' ? 'Premium restored!' : 'No purchases to restore.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
    iapRestoreResultNotifier.value = null;
  }

  void _onTabRequested() {
    final i = mainTabNotifier.value;
    if (!mounted || i == _index) return;
    setState(() => _index = i);
  }

  void _onPremiumChange() {
    final now = freemiumService.hasFullAccess;
    if (now && !_wasPremium && mounted) {
      showPremiumWelcomeSnackBar(context, isSpanish: false);
      try { AnalyticsService.instance.logPaywallConverted('iap'); } catch (_) {}
    }
    _wasPremium = now;
    unawaited(AnalyticsService.instance.setUserPremium(now));
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
            onPremium: () {
              PaywallHard.show(context);
            },
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: List.generate(
          _screens.length,
          (i) => IgnorePointer(
            ignoring: _index != i,
            child: CalcwiseTabReveal(active: _index == i, child: _screens[i]),
          ),
        ),
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
            if (i == 0) return;
            adService.onAction();
            final trigger = await paywallSession.recordAction();
            if (!mounted) return;
            if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;
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
              icon: Icon(Icons.account_balance_outlined),
              selectedIcon: Icon(Icons.account_balance_rounded),
              label: 'Income Tax',
            ),
            NavigationDestination(
              icon: Icon(Icons.compare_arrows_outlined),
              selectedIcon: Icon(Icons.compare_arrows_rounded),
              label: 'Compare',
            ),
            NavigationDestination(
              icon: Icon(Icons.bar_chart_outlined),
              selectedIcon: Icon(Icons.bar_chart_rounded),
              label: 'Investments',
            ),
            NavigationDestination(
              icon: Icon(Icons.grid_view_outlined),
              selectedIcon: Icon(Icons.grid_view_rounded),
              label: 'Tools',
            ),
            NavigationDestination(
              icon: Icon(Icons.history_outlined),
              selectedIcon: Icon(Icons.history_rounded),
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
