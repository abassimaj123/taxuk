import 'dart:math';

/// UK income-tax region. Only Scotland has its own rates/bands for 2025/26.
///
/// Wales has the Welsh Rate of Income Tax (WRIT): the UK rates are reduced by
/// 10p in each band and the Welsh Government adds back 10p, so the effective
/// Welsh rates are currently IDENTICAL to England — only the label differs.
/// Northern Ireland uses the same rates as England. We keep them as separate
/// values so the UI can show the correct label and the calculation stays
/// future-proof if Wales/NI ever diverge.
enum IncomeTaxRegion { england, scotland, wales, northernIreland }

extension IncomeTaxRegionInfo on IncomeTaxRegion {
  /// Whether Scottish rates/bands apply.
  bool get usesScottishRates => this == IncomeTaxRegion.scotland;

  String get label {
    switch (this) {
      case IncomeTaxRegion.england:
        return 'England';
      case IncomeTaxRegion.scotland:
        return 'Scotland';
      case IncomeTaxRegion.wales:
        return 'Wales';
      case IncomeTaxRegion.northernIreland:
        return 'Northern Ireland';
    }
  }

  String get shortLabel {
    switch (this) {
      case IncomeTaxRegion.england:
        return 'England';
      case IncomeTaxRegion.scotland:
        return 'Scotland';
      case IncomeTaxRegion.wales:
        return 'Wales';
      case IncomeTaxRegion.northernIreland:
        return 'N. Ireland';
    }
  }

  /// One-line description of the rates that apply.
  String get ratesNote {
    switch (this) {
      case IncomeTaxRegion.scotland:
        return 'Scotland: 6 bands (19%–48%)';
      case IncomeTaxRegion.wales:
        return 'Wales (WRIT): same as England — 3 bands (20%–45%)';
      case IncomeTaxRegion.northernIreland:
        return 'Northern Ireland: same as England — 3 bands (20%–45%)';
      case IncomeTaxRegion.england:
        return 'England: 3 bands (20%–45%)';
    }
  }
}

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
  static const double ukHigherLimit =
      112570.0; // 37700–112570 = 40% (above PA+37700=50270)

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
    return isScotland ? _calculateScottish(taxable) : _calculateUK(taxable);
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
      final basic =
          min(taxable - scotStarterLimit, scotBasicLimit - scotStarterLimit);
      tax += basic * 0.20;
    }

    // Intermediate: 13,991–31,092 @ 21%
    if (taxable > scotBasicLimit) {
      final intermediate =
          min(taxable - scotBasicLimit, scotIntermediateLimit - scotBasicLimit);
      tax += intermediate * 0.21;
    }

    // Higher: 31,092–62,430 @ 42%
    if (taxable > scotIntermediateLimit) {
      final higher = min(taxable - scotIntermediateLimit,
          scotHigherLimit - scotIntermediateLimit);
      tax += higher * 0.42;
    }

    // Advanced: 62,430–112,570 @ 45%
    if (taxable > scotHigherLimit) {
      final advanced =
          min(taxable - scotHigherLimit, scotAdvancedLimit - scotHigherLimit);
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
    return gross -
        incomeTax(gross, isScotland: isScotland) -
        nationalInsurance(gross);
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
      (
        name: 'Basic Rate',
        rate: 0.20,
        from: scotStarterLimit,
        to: scotBasicLimit
      ),
      (
        name: 'Intermediate Rate',
        rate: 0.21,
        from: scotBasicLimit,
        to: scotIntermediateLimit
      ),
      (
        name: 'Higher Rate',
        rate: 0.42,
        from: scotIntermediateLimit,
        to: scotHigherLimit
      ),
      (
        name: 'Advanced Rate',
        rate: 0.45,
        from: scotHigherLimit,
        to: scotAdvancedLimit
      ),
      (
        name: 'Top Rate',
        rate: 0.48,
        from: scotAdvancedLimit,
        to: double.infinity
      ),
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

  static double effectiveTaxRate(double grossIncome,
      {bool isScotland = false}) {
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
  // Extended fields
  final double pensionContribution;
  final bool isSelfEmployed;
  final bool hasMarriageAllowance;
  final double marriageAllowanceCreditApplied;
  // NI breakdown for self-employed (Class 2 + Class 4 separately)
  final double class2NI;
  final double class4NI;

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
    this.pensionContribution = 0,
    this.isSelfEmployed = false,
    this.hasMarriageAllowance = false,
    this.marriageAllowanceCreditApplied = 0,
    this.class2NI = 0.0,
    this.class4NI = 0.0,
  });

  double get totalDeductions => incomeTax + nationalInsurance;
  double get effectiveOverallRate =>
      grossIncome > 0 ? totalDeductions / grossIncome : 0;
  double get effectiveGross => grossIncome - pensionContribution;
}

// ══════════════════════════════════════════════════════════════════════════
// Dividend Tax (2024/25 — same rates for 2025/26)
// ══════════════════════════════════════════════════════════════════════════

extension DividendTax on UKTaxEngine {
  // All static — accessed via UKTaxEngine.calculateDividend(...)
}

/// 2025/26 UK dividend tax constants (inchangés depuis 2024/25)
class DividendTaxConstants {
  DividendTaxConstants._();
  static const double allowance = 500.0;
  static const double basicRateThreshold = 50270.0; // total income
  static const double higherRateThreshold = 125140.0;
  static const double basicRate = 0.0875;
  static const double higherRate = 0.3375;
  static const double additionalRate = 0.3935;
}

class DividendResult {
  final double grossDividend;
  final double allowance; // £500
  final double taxableDividend; // max(0, grossDividend - allowance)
  final double taxDue;
  final double effectiveRate;
  final String band; // "Basic", "Higher", "Additional"
  final double annualRepaymentStudentLoan; // unused here, but keep model clean

  const DividendResult({
    required this.grossDividend,
    required this.allowance,
    required this.taxableDividend,
    required this.taxDue,
    required this.effectiveRate,
    required this.band,
    this.annualRepaymentStudentLoan = 0,
  });
}

/// Calculate dividend tax for a UK taxpayer.
///
/// [grossIncome] = employment / self-employment income (determines band).
/// [grossDividend] = total dividend income received.
///
/// Dividends are NOT subject to Scottish income tax — same rates everywhere.
DividendResult calculateDividend({
  required double grossIncome,
  required double grossDividend,
}) {
  final totalIncome = grossIncome + grossDividend;
  final taxable = max(0.0, grossDividend - DividendTaxConstants.allowance);

  // Determine band from total income
  String band;
  double rate;
  if (totalIncome <= DividendTaxConstants.basicRateThreshold) {
    band = 'Basic';
    rate = DividendTaxConstants.basicRate;
  } else if (totalIncome <= DividendTaxConstants.higherRateThreshold) {
    band = 'Higher';
    rate = DividendTaxConstants.higherRate;
  } else {
    band = 'Additional';
    rate = DividendTaxConstants.additionalRate;
  }

  // Dividends that push into a higher band are taxed at the higher rate
  // For simplicity we apply a single band (the band of total income).
  // For borderline cases a split calculation would be more precise, but
  // this matches what most Play Store apps do.
  final taxDue = taxable * rate;
  final effectiveRate = grossDividend > 0 ? taxDue / grossDividend : 0.0;

  return DividendResult(
    grossDividend: grossDividend,
    allowance: DividendTaxConstants.allowance,
    taxableDividend: taxable,
    taxDue: taxDue,
    effectiveRate: effectiveRate,
    band: band,
  );
}

// ══════════════════════════════════════════════════════════════════════════
// Student Loan Repayment
// ══════════════════════════════════════════════════════════════════════════

enum StudentLoanPlan {
  plan1,
  plan2,
  plan4,
  plan5,
  postgraduate,
}

extension StudentLoanPlanLabel on StudentLoanPlan {
  String get label {
    switch (this) {
      case StudentLoanPlan.plan1:
        return 'Plan 1 (before Sept 2012)';
      case StudentLoanPlan.plan2:
        return 'Plan 2 (Sept 2012 – July 2023)';
      case StudentLoanPlan.plan4:
        return 'Plan 4 (Scotland)';
      case StudentLoanPlan.plan5:
        return 'Plan 5 (from Aug 2023)';
      case StudentLoanPlan.postgraduate:
        return 'Postgraduate (PGL)';
    }
  }

  String get shortLabel {
    switch (this) {
      case StudentLoanPlan.plan1:
        return 'Plan 1';
      case StudentLoanPlan.plan2:
        return 'Plan 2';
      case StudentLoanPlan.plan4:
        return 'Plan 4';
      case StudentLoanPlan.plan5:
        return 'Plan 5';
      case StudentLoanPlan.postgraduate:
        return 'Postgraduate';
    }
  }

  double get threshold {
    switch (this) {
      case StudentLoanPlan.plan1:
        return 24990.0;
      case StudentLoanPlan.plan2:
        return 27295.0;
      case StudentLoanPlan.plan4:
        return 31395.0;
      case StudentLoanPlan.plan5:
        return 25000.0;
      case StudentLoanPlan.postgraduate:
        return 21000.0;
    }
  }

  double get repaymentRate {
    switch (this) {
      case StudentLoanPlan.postgraduate:
        return 0.06;
      default:
        return 0.09;
    }
  }

  String get writeOffNote {
    switch (this) {
      case StudentLoanPlan.plan1:
        return 'Written off at age 65';
      case StudentLoanPlan.plan2:
        return 'Written off after 30 years';
      case StudentLoanPlan.plan4:
        return 'Written off after 30 years';
      case StudentLoanPlan.plan5:
        return 'Written off after 40 years';
      case StudentLoanPlan.postgraduate:
        return 'Written off after 30 years';
    }
  }
}

class StudentLoanResult {
  final StudentLoanPlan plan;
  final double grossIncome;
  final double threshold;
  final double annualRepayment;
  final double monthlyRepayment;
  final double weeklyRepayment;

  const StudentLoanResult({
    required this.plan,
    required this.grossIncome,
    required this.threshold,
    required this.annualRepayment,
    required this.monthlyRepayment,
    required this.weeklyRepayment,
  });

  bool get hasRepayment => annualRepayment > 0;
}

StudentLoanResult calculateStudentLoan({
  required double grossIncome,
  required StudentLoanPlan plan,
}) {
  final threshold = plan.threshold;
  final rate = plan.repaymentRate;
  final annual =
      grossIncome > threshold ? (grossIncome - threshold) * rate : 0.0;
  return StudentLoanResult(
    plan: plan,
    grossIncome: grossIncome,
    threshold: threshold,
    annualRepayment: annual,
    monthlyRepayment: annual / 12,
    weeklyRepayment: annual / 52,
  );
}

// ══════════════════════════════════════════════════════════════════════════
// Self-Employed National Insurance (Class 2 + Class 4) 2025/26
// ══════════════════════════════════════════════════════════════════════════

extension SelfEmployedNI on UKTaxEngine {
  // Accessed as static helpers below
}

/// Self-employed NI: Class 2 (£3.45/week if profits > SPT) + Class 4 (6%/2%)
double calculateSelfEmployedNI(double grossProfit) {
  const double class2Weekly = 3.45;
  const double spt = 12570.0; // Small Profits Threshold
  const double lpl = 12570.0; // Lower Profits Limit
  const double upl = 50270.0; // Upper Profits Limit
  double ni = 0;
  if (grossProfit > spt) ni += class2Weekly * 52;
  if (grossProfit > lpl) {
    ni += (min(grossProfit, upl) - lpl) * 0.06;
  }
  if (grossProfit > upl) {
    ni += (grossProfit - upl) * 0.02;
  }
  return ni;
}

/// Returns Class 2 + Class 4 as separate amounts for detailed display.
/// Use alongside [calculateSelfEmployedNI] for self-employed scenarios.
({double class2, double class4}) calculateSelfEmployedNIBreakdown(
    double grossProfit) {
  const double class2Weekly = 3.45;
  const double spt = 12570.0;
  const double lpl = 12570.0;
  const double upl = 50270.0;
  final class2 = grossProfit > spt ? class2Weekly * 52 : 0.0; // £179.40/yr
  double class4 = 0;
  if (grossProfit > lpl) {
    class4 += (min(grossProfit, upl) - lpl) * 0.06; // 6% on £12,570-£50,270
  }
  if (grossProfit > upl) {
    class4 += (grossProfit - upl) * 0.02; // 2% above £50,270
  }
  return (class2: class2, class4: class4);
}

// ══════════════════════════════════════════════════════════════════════════
// Pension salary sacrifice helper
// ══════════════════════════════════════════════════════════════════════════

/// Gross income after pension salary sacrifice (reduces taxable + NI-able income)
double grossAfterPension(double gross, double pensionContrib) =>
    max(0.0, gross - pensionContrib);

// ══════════════════════════════════════════════════════════════════════════
// Marriage Allowance (2025/26)
// ══════════════════════════════════════════════════════════════════════════

/// Marriage Allowance tax credit for recipient (£1,260 @ 20% = £252/year)
const double marriageAllowanceCredit = 252.0;

// ══════════════════════════════════════════════════════════════════════════
// Reverse calculator — target net → required gross
// ══════════════════════════════════════════════════════════════════════════

/// Binary search: find gross salary needed to achieve [targetNet] take-home.
/// Accounts for pension salary sacrifice (reduces taxable income).
/// Uses Class 1 NI (PAYE) or Class 2+4 (self-employed).
double reverseCalculateGross({
  required double targetNet,
  bool isScotland = false,
  double pensionContrib = 0,
  bool selfEmployed = false,
}) {
  if (targetNet <= 0) return 0;

  // net(gross) function
  double netFor(double gross) {
    final effective = grossAfterPension(gross, pensionContrib);
    final tax = UKTaxEngine.incomeTax(effective, isScotland: isScotland);
    final ni = selfEmployed
        ? calculateSelfEmployedNI(effective)
        : UKTaxEngine.nationalInsurance(effective);
    return effective - tax - ni;
  }

  // Find upper bound
  double lo = targetNet;
  double hi = targetNet * 2.5;
  for (int i = 0; i < 12; i++) {
    if (netFor(hi) >= targetNet) break;
    hi *= 2;
  }

  // Binary search (50 iterations → precision < £0.01)
  for (int i = 0; i < 60; i++) {
    final mid = (lo + hi) / 2;
    if ((hi - lo) < 0.01) break;
    if (netFor(mid) < targetNet) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return (lo + hi) / 2;
}

// ══════════════════════════════════════════════════════════════════════════
// Capital Gains Tax (CGT) 2025/26
// ══════════════════════════════════════════════════════════════════════════

class CGTResult {
  final double totalGain;
  final double annualExemption; // £3,000
  final double taxableGain;
  final double gainInBasicBand;
  final double gainInHigherBand;
  final double taxInBasicBand;
  final double taxInHigherBand;
  final double totalTax;
  final double effectiveRate; // on totalGain
  final bool isResidentialProperty;

  const CGTResult({
    required this.totalGain,
    required this.annualExemption,
    required this.taxableGain,
    required this.gainInBasicBand,
    required this.gainInHigherBand,
    required this.taxInBasicBand,
    required this.taxInHigherBand,
    required this.totalTax,
    required this.effectiveRate,
    required this.isResidentialProperty,
  });

  bool get hasGain => totalGain > 0;
  bool get hasTax => totalTax > 0;
  double get basicRate => isResidentialProperty ? 0.18 : 0.10;
  double get higherRate => isResidentialProperty ? 0.24 : 0.20;
}

CGTResult calculateCGT({
  required double gain,
  required double grossIncome,
  required bool isResidentialProperty,
}) {
  const double exemption = 3000.0;
  const double basicBandLimit = 37700.0;
  const double pa = 12570.0;

  final taxableGain = max(0.0, gain - exemption);

  if (taxableGain <= 0) {
    return CGTResult(
      totalGain: gain,
      annualExemption: exemption,
      taxableGain: 0,
      gainInBasicBand: 0,
      gainInHigherBand: 0,
      taxInBasicBand: 0,
      taxInHigherBand: 0,
      totalTax: 0,
      effectiveRate: 0,
      isResidentialProperty: isResidentialProperty,
    );
  }

  // Remaining basic rate band
  final taxableIncome = max(0.0, grossIncome - pa);
  final remainingBasic = max(0.0, basicBandLimit - taxableIncome);
  final gainInBasic = min(taxableGain, remainingBasic);
  final gainInHigher = taxableGain - gainInBasic;

  final basicRate = isResidentialProperty ? 0.18 : 0.10;
  final higherRate = isResidentialProperty ? 0.24 : 0.20;

  final taxBasic = gainInBasic * basicRate;
  final taxHigher = gainInHigher * higherRate;
  final total = taxBasic + taxHigher;

  return CGTResult(
    totalGain: gain,
    annualExemption: exemption,
    taxableGain: taxableGain,
    gainInBasicBand: gainInBasic,
    gainInHigherBand: gainInHigher,
    taxInBasicBand: taxBasic,
    taxInHigherBand: taxHigher,
    totalTax: total,
    effectiveRate: gain > 0 ? total / gain : 0,
    isResidentialProperty: isResidentialProperty,
  );
}

// ══════════════════════════════════════════════════════════════════════════
// Rental Income Tax (2025/26)
// ══════════════════════════════════════════════════════════════════════════

/// Result model for UK rental income tax calculation (2025/26 rules).
class RentalIncomeResult {
  final double grossRental;
  final double allowableExpenses;
  final double taxableProfit;
  final double mortgageInterestCredit; // 20% of mortgage interest
  final double taxBeforeCredit;
  final double taxAfterCredit;
  final double netProfit; // after all tax
  final double effectiveYield; // % of gross rental

  const RentalIncomeResult({
    required this.grossRental,
    required this.allowableExpenses,
    required this.taxableProfit,
    required this.mortgageInterestCredit,
    required this.taxBeforeCredit,
    required this.taxAfterCredit,
    required this.netProfit,
    required this.effectiveYield,
  });
}

/// Calculate UK rental income tax (2025/26 rules).
/// Mortgage interest is NOT deducted from profit — instead a 20% tax credit applies.
RentalIncomeResult calculateRentalIncomeTax({
  required double grossRental,
  required double managementFees,
  required double repairs,
  required double insurance,
  required double councilTax,
  required double utilities,
  required double otherExpenses,
  required double mortgageInterest,
  required double otherIncome,
  bool isScotland = false,
}) {
  final allowableExpenses =
      managementFees + repairs + insurance + councilTax + utilities + otherExpenses;
  final taxableProfit =
      (grossRental - allowableExpenses).clamp(0.0, double.infinity);

  // Marginal rate based on total income (other income + rental profit)
  final totalIncome = otherIncome + taxableProfit;
  final taxOnTotal = UKTaxEngine.incomeTax(totalIncome, isScotland: isScotland);
  final taxOnOther = UKTaxEngine.incomeTax(otherIncome, isScotland: isScotland);
  final taxBeforeCredit =
      (taxOnTotal - taxOnOther).clamp(0.0, double.infinity);

  // Mortgage interest: 20% basic rate tax credit
  final mortgageInterestCredit = mortgageInterest * 0.20;
  final taxAfterCredit =
      (taxBeforeCredit - mortgageInterestCredit).clamp(0.0, double.infinity);

  final netProfit = taxableProfit - taxAfterCredit;
  final effectiveYield =
      grossRental > 0 ? (netProfit / grossRental) * 100 : 0.0;

  return RentalIncomeResult(
    grossRental: grossRental,
    allowableExpenses: allowableExpenses,
    taxableProfit: taxableProfit,
    mortgageInterestCredit: mortgageInterestCredit,
    taxBeforeCredit: taxBeforeCredit,
    taxAfterCredit: taxAfterCredit,
    netProfit: netProfit,
    effectiveYield: effectiveYield,
  );
}

// ══════════════════════════════════════════════════════════════════════════
// Savings Interest Tax (2025/26)
// ══════════════════════════════════════════════════════════════════════════

/// Personal Savings Allowance 2025/26.
/// Scottish higher rate starts at £43,662 (vs £50,270 for rest of UK).
double personalSavingsAllowance(double grossIncome, {bool isScotland = false}) {
  final higherThreshold = isScotland ? 43662.0 : 50270.0;
  const additionalThreshold = 125140.0;
  if (grossIncome <= higherThreshold) return 1000.0; // Basic rate
  if (grossIncome <= additionalThreshold) return 500.0; // Higher rate
  return 0.0; // Additional/Top rate
}

/// Savings starter rate band (0% on savings if non-savings income < £17,570).
double savingsStarterRateRelief(double nonSavingsIncome, double savingsIncome) {
  const pa = 12570.0;
  const starterBandMax = 5000.0;
  final available =
      (pa + starterBandMax - nonSavingsIncome).clamp(0.0, starterBandMax);
  return min(available, savingsIncome); // amount of savings taxed at 0%
}

class SavingsInterestResult {
  final double grossInterest;
  final double personalSavingsAllowance;
  final double starterRateRelief;
  final double taxableInterest;
  final double taxDue;
  final String band; // 'Basic Rate', 'Higher Rate', 'Additional Rate'
  final double effectiveRate;

  const SavingsInterestResult({
    required this.grossInterest,
    required this.personalSavingsAllowance,
    required this.starterRateRelief,
    required this.taxableInterest,
    required this.taxDue,
    required this.band,
    required this.effectiveRate,
  });
}

/// Calculate UK savings interest tax (2025/26).
SavingsInterestResult calculateSavingsInterestTax({
  required double grossInterest,
  required double otherIncome, // employment/self-emp income
  bool isScotland = false,
}) {
  // Total income drives both the PSA tier and the band rate.
  final totalIncome = otherIncome + grossInterest;
  final psa = personalSavingsAllowance(totalIncome, isScotland: isScotland);
  final starterRelief = savingsStarterRateRelief(otherIncome, grossInterest);

  // Determine income tax band rate from total income.
  // Savings interest is taxed at the BAND rate (20/40/45%), NOT the blended
  // 60% marginal rate that applies in the PA taper zone (£100k–£125,140).
  // Scotland: Higher Rate threshold is £43,662 (vs £50,270 England/Wales/NI).
  // Advanced Rate threshold is £75,000; Top Rate is £125,140.
  final double higherThreshold = isScotland ? 43662.0 : 50270.0;
  final double advancedThreshold = isScotland ? 75000.0 : 125140.0;
  final double higherBandRate = isScotland ? 0.42 : 0.40;
  // Scotland: Advanced Rate = 45% (£75k–£125,140), Top Rate = 48% (>£125,140)
  // England/Wales/NI: Additional Rate = 45% (>£125,140)

  final double bandRate;
  final String band;
  if (totalIncome <= higherThreshold) {
    bandRate = 0.20;
    band = 'Basic Rate';
  } else if (totalIncome <= advancedThreshold) {
    bandRate = higherBandRate;
    band = isScotland ? 'Higher Rate (Scotland)' : 'Higher Rate';
  } else if (isScotland && totalIncome <= 125140.0) {
    bandRate = 0.45;
    band = 'Advanced Rate (Scotland)';
  } else if (isScotland) {
    bandRate = 0.48;
    band = 'Top Rate (Scotland)';
  } else {
    bandRate = 0.45;
    band = 'Additional Rate';
  }

  // Taxable interest = gross − PSA − starter rate relief (clamped ≥ 0)
  final taxableInterest =
      (grossInterest - psa - starterRelief).clamp(0.0, double.infinity);
  final taxDue = taxableInterest * bandRate;
  final effectiveRate =
      grossInterest > 0 ? (taxDue / grossInterest) * 100 : 0.0;

  return SavingsInterestResult(
    grossInterest: grossInterest,
    personalSavingsAllowance: psa,
    starterRateRelief: starterRelief,
    taxableInterest: taxableInterest,
    taxDue: taxDue,
    band: band,
    effectiveRate: effectiveRate,
  );
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
