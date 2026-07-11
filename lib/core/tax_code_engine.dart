/// UK Tax Code Checker — 2026/27 rules (HMRC).
///
/// Parses a PAYE tax code (e.g. "1257L", "BR", "D0", "K475", "1257L W1/M1")
/// and explains what it means: the personal allowance it implies, the meaning
/// of its suffix/letter, the region (England/NI, Scotland, Wales) and whether
/// it is an emergency (non-cumulative) code.
///
/// Reference values 2026/27:
///   - Standard Personal Allowance: £12,570  → numeric code 1257L
///   - The number × 10 ≈ the tax-free allowance for the year.
///   - BR = all income taxed at basic rate (20%)
///   - D0 = all income taxed at higher rate (40%)
///   - D1 = all income taxed at additional rate (45%)
///   - 0T = no Personal Allowance
///   - NT = no tax deducted
///   - K codes = negative allowance → the number × 10 is ADDED to taxable income
///     (e.g. K475 → +£4,750 added to taxable pay for the year).
class TaxCodeEngine {
  TaxCodeEngine._();

  /// Parse and explain a UK tax code. Always returns a result; check
  /// [TaxCodeResult.isValid] to know whether parsing succeeded.
  static TaxCodeResult parse(String rawInput) {
    final original = rawInput.trim();
    if (original.isEmpty) {
      return const TaxCodeResult.invalid('Enter a tax code (e.g. 1257L).');
    }

    // Normalise: uppercase, strip all spaces and slashes (handles
    // "1257L W1/M1", "1257L M1", "1257 L", etc.).
    var code = original.toUpperCase().replaceAll(RegExp(r'[\s/]+'), '');

    // ── Region prefix (S = Scotland, C = Wales/Cymru) ───────────────────────
    var region = TaxRegion.englandNi;
    if (code.startsWith('S')) {
      region = TaxRegion.scotland;
      code = code.substring(1);
    } else if (code.startsWith('C')) {
      region = TaxRegion.wales;
      code = code.substring(1);
    }

    if (code.isEmpty) {
      return TaxCodeResult.invalid('"$original" is not a recognised tax code.');
    }

    // ── Emergency / non-cumulative marker (W1, M1, X) ───────────────────────
    // Appears as a suffix: W1, M1 or X (e.g. "1257LW1M1", "1257LX").
    bool isEmergency = false;
    final emergencyMatch =
        RegExp(r'(W1|M1|X)+$').firstMatch(code);
    if (emergencyMatch != null) {
      isEmergency = true;
      code = code.substring(0, emergencyMatch.start);
    }

    if (code.isEmpty) {
      return TaxCodeResult.invalid('"$original" is not a recognised tax code.');
    }

    // ── Whole-letter codes (no number): BR, D0, D1, NT, 0T ──────────────────
    switch (code) {
      case 'BR':
        return TaxCodeResult(
          input: original,
          isValid: true,
          region: region,
          isEmergency: isEmergency,
          letter: 'BR',
          personalAllowance: 0,
          kAddition: 0,
          allowanceLabel: 'No Personal Allowance',
          meaning:
              'All income from this job or pension is taxed at the basic rate '
              '(20%). Usually used for a second job or pension where your '
              'Personal Allowance is already used elsewhere.',
        );
      case 'D0':
        return TaxCodeResult(
          input: original,
          isValid: true,
          region: region,
          isEmergency: isEmergency,
          letter: 'D0',
          personalAllowance: 0,
          kAddition: 0,
          allowanceLabel: 'No Personal Allowance',
          meaning:
              'All income from this job or pension is taxed at the higher rate '
              '(40%). Typically used for a second income when your other income '
              'already uses the basic-rate band.',
        );
      case 'D1':
        return TaxCodeResult(
          input: original,
          isValid: true,
          region: region,
          isEmergency: isEmergency,
          letter: 'D1',
          personalAllowance: 0,
          kAddition: 0,
          allowanceLabel: 'No Personal Allowance',
          meaning:
              'All income from this job or pension is taxed at the additional '
              'rate (45%). Typically used for a second income for higher '
              'earners.',
        );
      case 'NT':
        return TaxCodeResult(
          input: original,
          isValid: true,
          region: region,
          isEmergency: isEmergency,
          letter: 'NT',
          personalAllowance: 0,
          kAddition: 0,
          allowanceLabel: 'No tax',
          meaning:
              'No tax is deducted from this income. Rare — used in specific '
              'situations such as certain non-resident or special arrangements.',
        );
      case '0T':
        return TaxCodeResult(
          input: original,
          isValid: true,
          region: region,
          isEmergency: isEmergency,
          letter: '0T',
          personalAllowance: 0,
          kAddition: 0,
          allowanceLabel: 'No Personal Allowance',
          meaning:
              'Your Personal Allowance has been used up, or you started a new '
              'job without a P45. Income is taxed from the first pound across '
              'the normal bands (20%/40%/45%).',
        );
    }

    // ── K codes: "K475" → negative allowance, number × 10 added to income ───
    final kMatch = RegExp(r'^K(\d+)$').firstMatch(code);
    if (kMatch != null) {
      final number = int.parse(kMatch.group(1)!);
      final addition = number * 10.0;
      return TaxCodeResult(
        input: original,
        isValid: true,
        region: region,
        isEmergency: isEmergency,
        letter: 'K',
        personalAllowance: 0,
        kAddition: addition,
        allowanceLabel: 'Negative allowance',
        meaning:
            'A K code means you have no tax-free Personal Allowance and an '
            'extra amount is added to your taxable income — here £'
            '${_money(addition)} for the year (£${_money(addition / 12)} per '
            'month). This happens when you owe tax from a previous year, or '
            'receive taxable benefits (e.g. a company car or State Pension) '
            'worth more than your allowance.',
      );
    }

    // ── Numeric + suffix codes: "1257L", "1257M", "1257N", "1257T" ──────────
    final numMatch = RegExp(r'^(\d+)([LMNT])$').firstMatch(code);
    if (numMatch != null) {
      final number = int.parse(numMatch.group(1)!);
      final suffix = numMatch.group(2)!;
      final allowance = number * 10.0;
      final String letterMeaning;
      switch (suffix) {
        case 'L':
          letterMeaning =
              'You are entitled to the standard tax-free Personal Allowance. '
              'The most common tax code — 1257L matches the full £12,570 '
              'allowance for 2026/27.';
          break;
        case 'M':
          letterMeaning =
              'Marriage Allowance: you have RECEIVED a transfer of 10% of your '
              'partner\'s Personal Allowance, increasing your tax-free amount.';
          break;
        case 'N':
          letterMeaning =
              'Marriage Allowance: you have TRANSFERRED 10% of your Personal '
              'Allowance to your partner, reducing your tax-free amount.';
          break;
        case 'T':
        default:
          letterMeaning =
              'Your code includes other calculations to work out your Personal '
              'Allowance (for example the income-related taper above £100,000).';
          break;
      }
      return TaxCodeResult(
        input: original,
        isValid: true,
        region: region,
        isEmergency: isEmergency,
        letter: suffix,
        personalAllowance: allowance,
        kAddition: 0,
        allowanceLabel: 'Tax-free Personal Allowance',
        meaning: letterMeaning,
      );
    }

    return TaxCodeResult.invalid(
        '"$original" is not a recognised UK tax code. Examples: 1257L, BR, '
        'D0, K475, S1257L.');
  }

  static String _money(double v) {
    final rounded = v.round();
    final s = rounded.abs().toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}

/// Region implied by a tax code prefix.
enum TaxRegion { englandNi, scotland, wales }

extension TaxRegionLabel on TaxRegion {
  /// Short display label.
  String get label {
    switch (this) {
      case TaxRegion.englandNi:
        return 'England / Northern Ireland';
      case TaxRegion.scotland:
        return 'Scotland';
      case TaxRegion.wales:
        return 'Wales';
    }
  }

  String get description {
    switch (this) {
      case TaxRegion.englandNi:
        return 'No region prefix — standard rates and bands apply.';
      case TaxRegion.scotland:
        return 'S prefix — Scottish Income Tax rates apply (different bands).';
      case TaxRegion.wales:
        return 'C prefix (Cymru) — Welsh rates currently match England.';
    }
  }
}

/// Result of parsing a tax code.
class TaxCodeResult {
  final String input;
  final bool isValid;
  final String? errorMessage;

  final TaxRegion region;
  final bool isEmergency;

  /// The code letter/whole-letter: L, M, N, T, K, BR, D0, D1, NT, 0T.
  final String letter;

  /// Tax-free Personal Allowance implied (£). 0 for BR/D0/D1/0T/NT/K.
  final double personalAllowance;

  /// For K codes: amount added to taxable income (£). 0 otherwise.
  final double kAddition;

  final String allowanceLabel;
  final String meaning;

  const TaxCodeResult({
    required this.input,
    required this.isValid,
    required this.region,
    required this.isEmergency,
    required this.letter,
    required this.personalAllowance,
    required this.kAddition,
    required this.allowanceLabel,
    required this.meaning,
    this.errorMessage,
  });

  const TaxCodeResult.invalid(String message)
      : input = '',
        isValid = false,
        errorMessage = message,
        region = TaxRegion.englandNi,
        isEmergency = false,
        letter = '',
        personalAllowance = 0,
        kAddition = 0,
        allowanceLabel = '',
        meaning = '';

  bool get hasAllowance => personalAllowance > 0;
  bool get isKCode => letter == 'K';
}
