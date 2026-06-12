/// IAP service — wraps CalcwiseIAP for TaxUK app.
import 'package:calcwise_core/calcwise_core.dart';
import 'package:flutter/foundation.dart' show ValueNotifier;
import 'freemium_service.dart';
import '../analytics/analytics_service.dart' show analyticsService;

export 'package:calcwise_core/services/iap_service.dart' show iapErrorNotifier;

class IAPService {
  IAPService._();
  static final instance = IAPService._();
  static const productId = 'premium_upgrade';
  late final CalcwiseIAP _iap;
  ValueNotifier<String?> get localizedPrice => _iap.localizedPrice;

  Future<void> initialize() async {
    _iap = CalcwiseIAP(
      productId: productId,
      freemium: freemiumService,
      analytics: analyticsService,
      onPurchaseCompleted: () =>
          CalcwiseReviewService.instance.requestAfterSave(),
    );
    await _iap.initialize();
    PaywallHard.registerPrice(_iap.localizedPrice);
  }

  Future<void> buy() => _iap.buy();
  Future<void> restore() => _iap.restore();
  void dispose() => _iap.dispose();
}
