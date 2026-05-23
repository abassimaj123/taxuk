import 'dart:math';

/// UK Tax Engine — 2025/26 rates
/// Covers Income Tax (England/Wales/NI + Scotland), National Insurance (Class 1),
/// and VAT (Standard 20%, Reduced 5%, Zero 0%, Custom).
class UKTaxEngine {
  UKTaxEngine._();

  // ── Personal Allowance ─────────────────────────────────────────────────────
  static const double personalAllowance = 12570.0;

  // ── Income Tax band limits (taxable income above PA) ──────────────────────
  // England / Wales / NI
  static const double ukBasicLimit = 37700.0; // 0–37700 = 20%
  static const double ukHigherLimit = 112570.0; // 37700–112570 = 40% (above PA+37700=50270)

  // PA taper: £1 lost per £2 above £100k gross
  static const double paTaperStart = 100000.0;

  // Scottish band thresholds (taxable income above PA)
  static const double scotStarterLimit = 2306.0;
  static const double scotBasicLimit = 13991.0;
  static const double scotIntermediateLimit = 31092.0;
  static const double scotHigherLimit = 62430.0;
  static const double scotAdvancedLimit = 112570.0;

  // ── NI Class 1 (employee) thresholds ──────────────────────────────────────
  static const double niPrimaryThreshold = 12570.0;
  static const double niUpperEarningsLimit = 50270.0;
  static const double niRate1 = 0.08; // between PT and UEL
  static const double niRate2 = 0.02; // above UEL

  // ── VAT rates ─────────────────────────────────────────────────────────────
  static const double vatStandard = 0.20;
  static const double vatReduced = 0.05;
  static const double vatZero = 0.00;

  // ══════════════════════════════════════════════════════════════════════════
  // Income Tax
  // ══════════════════════════════════════════════════════════════════════════

  /// Effective personal allowance (tapered above £100k)
  static double effectivePersonalAllowance(double grossIncome) {
    if (grossIncome <= paTaperStart) return personalAllowance;
    final excess = grossIncome - paTaperStart;
    return max(0, personalAllowance - excess / 2);
  }

  /// Income tax for England/Wales/NI or Scotland
  static double incomeTax(double grossIncome, {bool isScotland = false}) {
    final pa = effectivePersonalAllowance(grossIncome);
    final taxable = max(0.0, grossIncome - pa);
    return isScotland
        ? _calculateScottish(taxable)
        : _calculateUK(taxable);
  }

  /// England/Wales/NI bands (applied to taxable income = gross - PA)
  static double _calculateUK(double taxable) {
    double tax = 0;
    if (taxable <= 0) return 0;

    // Basic rate band: 0–37,700 @ 20%
    final basic = min(taxable, ukBasicLimit);
    tax += basic * 0.20;

    // Higher rate band: 37,700–112,570 @ 40%
    if (taxable > ukBasicLimit) {
      final higher = min(taxable - ukBasicLimit, ukHigherLimit - ukBasicLimit);
      tax += higher * 0.40;
    }

    // Additional rate: above 112,570 @ 45%
    if (taxable > ukHigherLimit) {
      tax += (taxable - ukHigherLimit) * 0.45;
    }

    return tax;
  }

  /// Scottish rates (applied to taxable income = gross - PA)
  static double _calculateScottish(double taxable) {
    double tax = 0;
    if (taxable <= 0) return 0;

    // Starter: 0–2,306 @ 19%
    final starter = min(taxable, scotStarterLimit);
    tax += starter * 0.19;

    // Basic: 2,306–13,991 @ 20%
    if (taxable > scotStarterLimit) {
      final basic = min(taxable - scotStarterLimit, scotBasicLimit - scotStarterLimit);
      tax += basic * 0.20;
    }

    // Intermediate: 13,991–31,092 @ 21%
    if (taxable > scotBasicLimit) {
      final intermediate = min(taxable - scotBasicLimit, scotIntermediateLimit - scotBasicLimit);
      tax += intermediate * 0.21;
    }

    // Higher: 31,092–62,430 @ 42%
    if (taxable > scotIntermediateLimit) {
      final higher = min(taxable - scotIntermediateLimit, scotHigherLimit - scotIntermediateLimit);
      tax += higher * 0.42;
    }

    // Advanced: 62,430–112,570 @ 45%
    if (taxable > scotHigherLimit) {
      final advanced = min(taxable - scotHigherLimit, scotAdvancedLimit - scotHigherLimit);
      tax += advanced * 0.45;
    }

    // Top: above 112,570 @ 48%
    if (taxable > scotAdvancedLimit) {
      tax += (taxable - scotAdvancedLimit) * 0.48;
    }

    return tax;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // National Insurance (Class 1 employee)
  // ══════════════════════════════════════════════════════════════════════════

  static double nationalInsurance(double grossIncome) {
    if (grossIncome <= niPrimaryThreshold) return 0;
    double ni = 0;
    final band1 = min(grossIncome, niUpperEarningsLimit) - niPrimaryThreshold;
    ni += band1 * niRate1;
    if (grossIncome > niUpperEarningsLimit) {
      ni += (grossIncome - niUpperEarningsLimit) * niRate2;
    }
    return ni;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Net income
  // ══════════════════════════════════════════════════════════════════════════

  static double netIncome(double gross, {bool isScotland = false}) {
    return gross
        - incomeTax(gross, isScotland: isScotland)
        - nationalInsurance(gross);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Tax band breakdown (for UI display)
  // ══════════════════════════════════════════════════════════════════════════

  static List<TaxBandRow> taxBandBreakdown(
    double grossIncome, {
    bool isScotland = false,
  }) {
    final pa = effectivePersonalAllowance(grossIncome);
    final taxable = max(0.0, grossIncome - pa);
    final rows = <TaxBandRow>[];

    if (pa > 0) {
      rows.add(TaxBandRow(
        name: 'Personal Allowance',
        rate: 0.0,
        amount: 0.0,
        rangeFrom: 0,
        rangeTo: pa,
      ));
    }

    if (isScotland) {
      _addScottishBands(taxable, pa, rows);
    } else {
      _addUKBands(taxable, pa, rows);
    }
    return rows;
  }

  static void _addUKBands(double taxable, double pa, List<TaxBandRow> rows) {
    if (taxable <= 0) return;
    final basic = min(taxable, ukBasicLimit);
    rows.add(TaxBandRow(
      name: 'Basic Rate',
      rate: 0.20,
      amount: basic * 0.20,
      rangeFrom: pa,
      rangeTo: pa + basic,
    ));
    if (taxable > ukBasicLimit) {
      final higher = min(taxable - ukBasicLimit, ukHigherLimit - ukBasicLimit);
      rows.add(TaxBandRow(
        name: 'Higher Rate',
        rate: 0.40,
        amount: higher * 0.40,
        rangeFrom: pa + ukBasicLimit,
        rangeTo: pa + ukBasicLimit + higher,
      ));
    }
    if (taxable > ukHigherLimit) {
      final add = taxable - ukHigherLimit;
      rows.add(TaxBandRow(
        name: 'Additional Rate',
        rate: 0.45,
        amount: add * 0.45,
        rangeFrom: pa + ukHigherLimit,
        rangeTo: pa + taxable,
      ));
    }
  }

  static void _addScottishBands(
      double taxable, double pa, List<TaxBandRow> rows) {
    if (taxable <= 0) return;
    final bands = [
      (name: 'Starter Rate', rate: 0.19, from: 0.0, to: scotStarterLimit),
      (name: 'Basic Rate', rate: 0.20, from: scotStarterLimit, to: scotBasicLimit),
      (name: 'Intermediate Rate', rate: 0.21, from: scotBasicLimit, to: scotIntermediateLimit),
      (name: 'Higher Rate', rate: 0.42, from: scotIntermediateLimit, to: scotHigherLimit),
      (name: 'Advanced Rate', rate: 0.45, from: scotHigherLimit, to: scotAdvancedLimit),
      (name: 'Top Rate', rate: 0.48, from: scotAdvancedLimit, to: double.infinity),
    ];
    for (final b in bands) {
      if (taxable <= b.from) break;
      final inBand = min(taxable, b.to) - b.from;
      if (inBand <= 0) continue;
      rows.add(TaxBandRow(
        name: b.name,
        rate: b.rate,
        amount: inBand * b.rate,
        rangeFrom: pa + b.from,
        rangeTo: pa + b.from + inBand,
      ));
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Effective & marginal rates
  // ══════════════════════════════════════════════════════════════════════════

  static double effectiveTaxRate(double grossIncome, {bool isScotland = false}) {
    if (grossIncome <= 0) return 0;
    return incomeTax(grossIncome, isScotland: isScotland) / grossIncome;
  }

  /// Marginal income tax rate on the last £1 earned
  static double marginalTaxRate(double grossIncome, {bool isScotland = false}) {
    final pa = effectivePersonalAllowance(grossIncome);
    // PA taper zone: effective marginal = 60% (40% tax + losing 50p PA per £1)
    if (grossIncome > paTaperStart &&
        grossIncome <= paTaperStart + 2 * personalAllowance) {
      return isScotland ? 0.63 : 0.60;
    }
    final taxable = max(0.0, grossIncome - pa);
    if (isScotland) {
      if (taxable <= 0) return 0;
      if (taxable <= scotStarterLimit) return 0.19;
      if (taxable <= scotBasicLimit) return 0.20;
      if (taxable <= scotIntermediateLimit) return 0.21;
      if (taxable <= scotHigherLimit) return 0.42;
      if (taxable <= scotAdvancedLimit) return 0.45;
      return 0.48;
    } else {
      if (taxable <= 0) return 0;
      if (taxable <= ukBasicLimit) return 0.20;
      if (taxable <= ukHigherLimit) return 0.40;
      return 0.45;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // VAT
  // ══════════════════════════════════════════════════════════════════════════

  static double vatAmountFromNet(double netAmount, double rate) =>
      netAmount * rate;

  static double vatAmountFromGross(double grossAmount, double rate) {
    if (rate <= 0) return 0;
    return grossAmount * rate / (1 + rate);
  }

  static double netFromGross(double gross, double rate) =>
      rate <= 0 ? gross : gross / (1 + rate);

  static double grossFromNet(double net, double rate) => net * (1 + rate);
}

/// A single row in the tax band breakdown table.
class TaxBandRow {
  final String name;
  final double rate;
  final double amount;
  final double rangeFrom;
  final double rangeTo;

  const TaxBandRow({
    required this.name,
    required this.rate,
    required this.amount,
    required this.rangeFrom,
    required this.rangeTo,
  });
}

/// Result model for the income tax screen
class IncomeTaxResult {
  final double grossIncome;
  final double personalAllowance;
  final double incomeTax;
  final double nationalInsurance;
  final double netIncome;
  final double effectiveTaxRate;
  final double marginalTaxRate;
  final List<TaxBandRow> bandBreakdown;
  final bool isScotland;

  const IncomeTaxResult({
    required this.grossIncome,
    required this.personalAllowance,
    required this.incomeTax,
    required this.nationalInsurance,
    required this.netIncome,
    required this.effectiveTaxRate,
    required this.marginalTaxRate,
    required this.bandBreakdown,
    required this.isScotland,
  });

  double get totalDeductions => incomeTax + nationalInsurance;
  double get effectiveOverallRate =>
      grossIncome > 0 ? totalDeductions / grossIncome : 0;
}

/// Result model for the VAT screen
class VatResult {
  final double netAmount;
  final double vatAmount;
  final double grossAmount;
  final double rate;
  final String rateLabel;

  const VatResult({
    required this.netAmount,
    required this.vatAmount,
    required this.grossAmount,
    required this.rate,
    required this.rateLabel,
  });
}
