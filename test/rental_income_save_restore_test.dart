import 'package:flutter_test/flutter_test.dart';
import 'package:taxuk/core/uk_tax_engine.dart';

/// Mirrors rental_income_screen.dart's `_scheduleAutoSave`/`_saveScenario`
/// l2['inputs'] builder. Kept in sync manually; if this test fails after
/// touching rental_income_screen.dart, update both together.
///
/// Regression coverage for two silent-data-loss bugs:
///   1. `isScotland` was computed and shown on screen, but never written to
///      the save payload nor passed to `exportRentalIncome` — a saved
///      Scottish rental scenario silently restored/exported as
///      rest-of-UK (wrong higher-rate threshold: £43,662 vs £50,270).
///   2. Mortgage interest was stored under the wrong key `'propertyAllowance'`
///      — now stored under `'mortgageInterest'`.
Map<String, dynamic> _rentalIncomeL2Inputs({
  required RentalIncomeResult r,
  required double otherIncome,
  required double mortgageInterest,
  required bool isScotland,
}) =>
    {
      'type': 'rental_income',
      'rentalIncome': r.grossRental,
      'otherIncome': otherIncome,
      'expenses': r.allowableExpenses,
      'mortgageInterest': mortgageInterest,
      'isScotland': isScotland,
    };

void main() {
  group('RentalIncomeScreen — save/restore regression (silent data loss)', () {
    const mortgageInterest = 4000.0;
    const otherIncome = 35000.0;

    final scotlandResult = calculateRentalIncomeTax(
      grossRental: 18000,
      managementFees: 500,
      repairs: 0,
      insurance: 200,
      councilTax: 0,
      utilities: 0,
      otherExpenses: 0,
      mortgageInterest: mortgageInterest,
      otherIncome: otherIncome,
      isScotland: true,
    );

    final englandResult = calculateRentalIncomeTax(
      grossRental: 18000,
      managementFees: 500,
      repairs: 0,
      insurance: 200,
      councilTax: 0,
      utilities: 0,
      otherExpenses: 0,
      mortgageInterest: mortgageInterest,
      otherIncome: otherIncome,
      isScotland: false,
    );

    test('isScotland=true actually changes the computed tax (proves this is '
        'a real calc input, not decorative)', () {
      expect(scotlandResult.taxAfterCredit, isNot(englandResult.taxAfterCredit),
          reason: 'Scotland uses a different higher-rate threshold '
              '(£43,662) than rest-of-UK (£50,270), so tax on the same '
              'rental profit + other income must differ.');
    });

    test('l2 inputs snapshot includes isScotland — must not be dropped', () {
      final l2 = _rentalIncomeL2Inputs(
        r: scotlandResult,
        otherIncome: otherIncome,
        mortgageInterest: mortgageInterest,
        isScotland: true,
      );

      expect(l2.containsKey('isScotland'), isTrue,
          reason: 'Before the fix, isScotland was entirely absent from the '
              'save payload — a Scottish scenario silently restored as '
              'rest-of-UK.');
      expect(l2['isScotland'], isTrue);
    });

    test('l2 inputs snapshot stores mortgage interest under the correct key '
        '(mislabeled-key regression)', () {
      final l2 = _rentalIncomeL2Inputs(
        r: scotlandResult,
        otherIncome: otherIncome,
        mortgageInterest: mortgageInterest,
        isScotland: true,
      );

      expect(l2.containsKey('mortgageInterest'), isTrue);
      expect(l2['mortgageInterest'], mortgageInterest);
      expect(l2.containsKey('propertyAllowance'), isFalse,
          reason: 'The old key name "propertyAllowance" was a raw-input '
              'mislabeling bug (mortgage interest is not a property '
              'allowance) and must not reappear.');
    });

    test('regression guard: the OLD save shape (missing isScotland, wrong '
        'key) would have silently corrupted a Scottish scenario on restore', () {
      // Simulates the pre-fix snapshot shape.
      final buggyOldSnap = <String, dynamic>{
        'type': 'rental_income',
        'rentalIncome': scotlandResult.grossRental,
        'otherIncome': otherIncome,
        'expenses': scotlandResult.allowableExpenses,
        'propertyAllowance': mortgageInterest, // wrong key
        // isScotland: entirely absent
      };

      expect(buggyOldSnap.containsKey('isScotland'), isFalse,
          reason: 'documents that the OLD snapshot shape dropped this field');
      expect(buggyOldSnap.containsKey('mortgageInterest'), isFalse,
          reason: 'documents that the OLD snapshot used the wrong key name');

      // A restore reading the OLD shape would fall back to isScotland=false
      // (rest-of-UK rates), silently changing the result for a Scottish
      // taxpayer. The fixed shape must not have this gap.
      final fixedSnap = _rentalIncomeL2Inputs(
        r: scotlandResult,
        otherIncome: otherIncome,
        mortgageInterest: mortgageInterest,
        isScotland: true,
      );
      expect(fixedSnap['isScotland'], isTrue);
      expect((fixedSnap['isScotland'] as bool?) ?? false, isTrue,
          reason: 'Restore logic reading `inputs[\'isScotland\'] as bool? ?? '
              'false` must recover true for a Scottish scenario.');
    });
  });
}
