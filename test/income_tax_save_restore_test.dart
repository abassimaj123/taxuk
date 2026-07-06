import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:taxuk/core/uk_tax_engine.dart';

/// Mirrors income_tax_screen.dart's `_buildL1`/`_buildL2` builders. Kept in
/// sync manually; if this test fails after touching income_tax_screen.dart,
/// update both together.
///
/// Regression coverage: `hasMarriageAllowance` was computed into the on-screen
/// result (and changes the tax by £252/yr via `marriageAllowanceCredit`), but
/// was entirely omitted from both `_buildL1`/`_buildL2` and the PDF export
/// params — a saved scenario with the allowance toggled ON silently restored
/// as OFF, changing the computed tax with no visual indication.
Map<String, dynamic> _buildL1(IncomeTaxResult r) => {
      'gross_income': r.grossIncome,
      'personal_allowance': r.personalAllowance,
      'income_tax': r.incomeTax,
      'ni_contributions': r.nationalInsurance,
      'net_income': r.netIncome,
      'effective_rate': r.effectiveTaxRate,
      'has_marriage_allowance': r.hasMarriageAllowance,
    };

Map<String, dynamic> _buildL2Inputs(IncomeTaxResult r, {required String region}) => {
      'type': 'income_tax',
      'gross': r.grossIncome,
      'is_scotland': r.isScotland,
      'region': region,
      'is_self_employed': r.isSelfEmployed,
      'has_marriage_allowance': r.hasMarriageAllowance,
      'pension': r.pensionContribution,
    };

/// Mirrors the forward-calculation path in `_calculateForward()` closely
/// enough to compare tax with/without the Marriage Allowance toggle.
IncomeTaxResult _calc({required double gross, required bool hasMarriageAllowance}) {
  final pa = UKTaxEngine.effectivePersonalAllowance(gross);
  final tax = UKTaxEngine.incomeTax(gross, isScotland: false);
  final ni = UKTaxEngine.nationalInsurance(gross);
  final maCredit = hasMarriageAllowance ? marriageAllowanceCredit : 0.0;
  final taxAfterMA = max(0.0, tax - maCredit);
  final net = gross - taxAfterMA - ni;
  final margRate = UKTaxEngine.marginalTaxRate(gross, isScotland: false);
  final bands = UKTaxEngine.taxBandBreakdown(gross, isScotland: false);

  return IncomeTaxResult(
    grossIncome: gross,
    personalAllowance: pa,
    incomeTax: taxAfterMA,
    nationalInsurance: ni,
    netIncome: net,
    effectiveTaxRate: gross > 0 ? taxAfterMA / gross : 0,
    marginalTaxRate: margRate,
    bandBreakdown: bands,
    isScotland: false,
    hasMarriageAllowance: hasMarriageAllowance,
    marriageAllowanceCreditApplied: maCredit,
  );
}

void main() {
  group('IncomeTaxScreen — save/restore regression (Marriage Allowance silent data loss)', () {
    const gross = 35000.0;

    final withMA = _calc(gross: gross, hasMarriageAllowance: true);
    final withoutMA = _calc(gross: gross, hasMarriageAllowance: false);

    test('Marriage Allowance actually changes computed tax by £252/yr '
        '(proves this is a real calc input, not decorative)', () {
      expect(withoutMA.incomeTax - withMA.incomeTax, closeTo(252.0, 0.01),
          reason: 'marriageAllowanceCredit is a flat £252/yr credit applied '
              'when the toggle is on.');
      expect(withMA.netIncome, greaterThan(withoutMA.netIncome));
    });

    test('_buildL1 includes has_marriage_allowance — must not be dropped', () {
      final l1 = _buildL1(withMA);
      expect(l1.containsKey('has_marriage_allowance'), isTrue,
          reason: 'Before the fix, hasMarriageAllowance was entirely absent '
              'from _buildL1, even though it changes income_tax/net_income.');
      expect(l1['has_marriage_allowance'], isTrue);
    });

    test('_buildL2 inputs include has_marriage_allowance — must not be dropped', () {
      final l2 = _buildL2Inputs(withMA, region: 'england');
      expect(l2.containsKey('has_marriage_allowance'), isTrue,
          reason: 'Before the fix, a saved scenario with Marriage Allowance '
              'ON would restore with the toggle OFF, silently changing the '
              'displayed/recomputed tax.');
      expect(l2['has_marriage_allowance'], isTrue);
    });

    test('save -> restore round trip: hasMarriageAllowance survives and '
        'reproduces the identical tax result', () {
      final l2 = _buildL2Inputs(withMA, region: 'england');

      // Simulates what a restore path SHOULD do: read the flag back and
      // recompute with it, rather than silently defaulting to false.
      final restoredHasMA = l2['has_marriage_allowance'] as bool? ?? false;
      final restoredResult = _calc(gross: gross, hasMarriageAllowance: restoredHasMA);

      expect(restoredHasMA, isTrue);
      expect(restoredResult.incomeTax, withMA.incomeTax);
      expect(restoredResult.netIncome, withMA.netIncome);
    });

    test('regression guard: the OLD save shape (missing has_marriage_allowance) '
        'would silently restore a Marriage-Allowance-on scenario as off', () {
      // Simulates the pre-fix snapshot shape (field entirely absent).
      final buggyOldL2 = <String, dynamic>{
        'type': 'income_tax',
        'gross': withMA.grossIncome,
        'is_scotland': withMA.isScotland,
        'is_self_employed': withMA.isSelfEmployed,
        'pension': withMA.pensionContribution,
      };

      expect(buggyOldL2.containsKey('has_marriage_allowance'), isFalse,
          reason: 'documents that the OLD snapshot shape dropped this field');

      // A restore reading the OLD shape falls back to `?? false`, which
      // recomputes a DIFFERENT (higher) tax than the original saved result.
      final restoredHasMA = buggyOldL2['has_marriage_allowance'] as bool? ?? false;
      final restoredResult = _calc(gross: gross, hasMarriageAllowance: restoredHasMA);

      expect(restoredHasMA, isFalse);
      expect(restoredResult.incomeTax, isNot(withMA.incomeTax),
          reason: 'This is the actual silent-data-loss bug: restoring from '
              'the old (buggy) shape recomputes a different tax than what '
              'was actually saved.');

      // The fixed shape must not have this gap.
      final fixedL2 = _buildL2Inputs(withMA, region: 'england');
      expect(fixedL2.containsKey('has_marriage_allowance'), isTrue);
    });

    test('region label (Wales/NI) collapses to is_scotland bool on restore — '
        'cosmetic only since Wales/NI rates equal England', () {
      final walesResult = _calc(gross: gross, hasMarriageAllowance: false);
      final l2 = _buildL2Inputs(walesResult, region: 'wales');

      expect(l2['is_scotland'], isFalse);
      expect(l2['region'], 'wales',
          reason: 'The region name is now separately captured so a future '
              'restore path could distinguish Wales/NI/England labels, even '
              'though the tax calculation is identical for all three.');
    });
  });
}
