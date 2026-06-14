// Tests for UKTaxEngine — 2025/26 rates
// Covers: effectivePersonalAllowance, incomeTax (UK + Scotland),
// nationalInsurance, netIncome, taxBandBreakdown (continuity + sum).
// All golden values derived from gov.uk and gov.scot 2025/26 published rates.
//
// CalcwiseTax.registry is pre-seeded with baked-in data at class load —
// no init() call needed in tests.

import 'package:flutter_test/flutter_test.dart';
import 'package:taxuk/core/uk_tax_engine.dart';

void main() {
  // ─── helpers ──────────────────────────────────────────────────────────────

  void approx(double actual, double expected, {double tol = 0.01}) {
    expect(actual, closeTo(expected, tol),
        reason: 'Expected ≈$expected, got $actual');
  }

  void approx1(double actual, double expected) => approx(actual, expected, tol: 1.0);

  // ─── effectivePersonalAllowance ───────────────────────────────────────────

  group('effectivePersonalAllowance', () {
    test('under £100k → full £12,570', () {
      approx(UKTaxEngine.effectivePersonalAllowance(30000), 12570);
    });

    test('exactly at taper start £100k → full £12,570', () {
      approx(UKTaxEngine.effectivePersonalAllowance(100000), 12570);
    });

    test('£110k → £7,570 (lost £5,000: (110k-100k)/2)', () {
      approx(UKTaxEngine.effectivePersonalAllowance(110000), 7570);
    });

    test('£125,140 → £0 (PA fully tapered)', () {
      approx(UKTaxEngine.effectivePersonalAllowance(125140), 0);
    });

    test('£150k → £0 (beyond full taper)', () {
      approx(UKTaxEngine.effectivePersonalAllowance(150000), 0);
    });

    test('zero income → full PA', () {
      approx(UKTaxEngine.effectivePersonalAllowance(0), 12570);
    });
  });

  // ─── incomeTax — England/Wales/NI ─────────────────────────────────────────

  group('incomeTax — rUK (England/Wales/NI)', () {
    test('zero income → £0', () {
      approx(UKTaxEngine.incomeTax(0), 0);
    });

    test('exactly at PA (£12,570) → £0', () {
      approx(UKTaxEngine.incomeTax(12570), 0);
    });

    test('£30,000 — basic rate only', () {
      // taxable = 30000 - 12570 = 17430; 17430 × 20% = 3486
      approx(UKTaxEngine.incomeTax(30000), 3486);
    });

    test('£50,000 — all in basic rate (gov.uk golden)', () {
      // taxable = 37430; 37430 × 20% = 7486
      approx(UKTaxEngine.incomeTax(50000), 7486);
    });

    test('£60,000 — spans basic+higher (gov.uk golden)', () {
      // taxable = 47430; 37700×20% + 9730×40% = 7540 + 3892 = 11432
      approx(UKTaxEngine.incomeTax(60000), 11432);
    });

    test('£110,000 — allowance taper (gov.uk golden)', () {
      // PA = 7570; taxable = 102430; 37700×20% + 64730×40% = 7540+25892 = 33432
      approx(UKTaxEngine.incomeTax(110000), 33432);
    });
  });

  // ─── incomeTax — Scotland ─────────────────────────────────────────────────

  group('incomeTax — Scotland', () {
    test('zero → £0', () {
      approx(UKTaxEngine.incomeTax(0, isScotland: true), 0);
    });

    test('at PA (£12,570) → £0', () {
      approx(UKTaxEngine.incomeTax(12570, isScotland: true), 0);
    });

    test('£50,000 — 4 bands (gov.scot golden)', () {
      // taxable = 37430:
      //   Starter  2827 × 19% =  537.13
      //   Basic   12094 × 20% = 2418.80
      //   Interm  16171 × 21% = 3395.91
      //   Higher   6338 × 42% = 2661.96
      //   Total = 9013.80
      approx(UKTaxEngine.incomeTax(50000, isScotland: true), 9013.80);
    });

    test('Scotland higher than rUK at £50k', () {
      expect(UKTaxEngine.incomeTax(50000, isScotland: true),
          greaterThan(UKTaxEngine.incomeTax(50000)));
    });
  });

  // ─── nationalInsurance ────────────────────────────────────────────────────

  group('nationalInsurance — Class 1 employee', () {
    test('zero income → £0', () {
      approx(UKTaxEngine.nationalInsurance(0), 0);
    });

    test('at PT (£12,570) → £0', () {
      approx(UKTaxEngine.nationalInsurance(12570), 0);
    });

    test('£25,000 — only band 1 (8%)', () {
      // (25000 - 12570) × 8% = 12430 × 0.08 = 994.40
      approx(UKTaxEngine.nationalInsurance(25000), 994.40);
    });

    test('exactly at UEL (£50,270)', () {
      // (50270 - 12570) × 8% = 37700 × 0.08 = 3016.00
      approx(UKTaxEngine.nationalInsurance(50270), 3016.00);
    });

    test('£55,000 — spans both NI bands', () {
      // band1: 37700 × 8% = 3016.00
      // band2: (55000 - 50270) × 2% = 4730 × 0.02 = 94.60
      // Total = 3110.60
      approx(UKTaxEngine.nationalInsurance(55000), 3110.60);
    });

    test('£100,000 — high earner', () {
      // band1: 37700 × 8% = 3016.00
      // band2: (100000 - 50270) × 2% = 49730 × 0.02 = 994.60
      // Total = 4010.60
      approx(UKTaxEngine.nationalInsurance(100000), 4010.60);
    });
  });

  // ─── netIncome ────────────────────────────────────────────────────────────

  group('netIncome', () {
    test('integrity: net = gross − incomeTax − NI (£50k rUK)', () {
      const gross = 50000.0;
      final tax = UKTaxEngine.incomeTax(gross);
      final ni = UKTaxEngine.nationalInsurance(gross);
      approx(UKTaxEngine.netIncome(gross), gross - tax - ni);
    });

    test('integrity: net = gross − incomeTax − NI (£50k Scotland)', () {
      const gross = 50000.0;
      final tax = UKTaxEngine.incomeTax(gross, isScotland: true);
      final ni = UKTaxEngine.nationalInsurance(gross);
      approx(UKTaxEngine.netIncome(gross, isScotland: true), gross - tax - ni);
    });

    test('Scotland net < rUK net at £50k (higher tax burden)', () {
      expect(
        UKTaxEngine.netIncome(50000, isScotland: true),
        lessThan(UKTaxEngine.netIncome(50000)),
      );
    });
  });

  // ─── taxBandBreakdown — continuity + sum ─────────────────────────────────

  group('taxBandBreakdown — rUK', () {
    void assertContinuous(List<TaxBandRow> rows, double gross) {
      expect(rows.isNotEmpty, isTrue);
      expect(rows.first.rangeFrom, closeTo(0, 0.01),
          reason: 'first row starts at 0');
      for (int i = 1; i < rows.length; i++) {
        expect(rows[i].rangeFrom, closeTo(rows[i - 1].rangeTo, 0.01),
            reason: 'gap/overlap between row ${i - 1} and $i');
      }
      expect(rows.last.rangeTo, closeTo(gross, 0.01),
          reason: 'last row ends at gross');
    }

    void assertSumMatchesTax(List<TaxBandRow> rows, double gross,
        {bool isScotland = false}) {
      final sum = rows.fold(0.0, (acc, r) => acc + r.amount);
      final expected = UKTaxEngine.incomeTax(gross, isScotland: isScotland);
      expect(sum, closeTo(expected, 0.02),
          reason: 'sum of band amounts must equal incomeTax($gross)');
    }

    test('£30,000 — continuity', () {
      final rows = UKTaxEngine.taxBandBreakdown(30000);
      assertContinuous(rows, 30000);
    });

    test('£30,000 — sum matches incomeTax', () {
      final rows = UKTaxEngine.taxBandBreakdown(30000);
      assertSumMatchesTax(rows, 30000);
    });

    test('£50,000 — structure: PA + Basic Rate (all in first band)', () {
      final rows = UKTaxEngine.taxBandBreakdown(50000);
      // Rows: Personal Allowance + Basic Rate (taxable 37430 < 37700 limit)
      expect(rows.length, 2);
      expect(rows[0].name, 'Personal Allowance');
      expect(rows[0].rate, 0.0);
      expect(rows[0].rangeFrom, 0);
      expect(rows[0].rangeTo, closeTo(12570, 0.01));
      expect(rows[1].name, 'Basic Rate');
      expect(rows[1].rate, 0.20);
      expect(rows[1].amount, closeTo(7486, 0.01));
    });

    test('£50,000 — continuity', () {
      assertContinuous(UKTaxEngine.taxBandBreakdown(50000), 50000);
    });

    test('£50,000 — sum matches incomeTax', () {
      assertSumMatchesTax(UKTaxEngine.taxBandBreakdown(50000), 50000);
    });

    test('£60,000 — spans Basic + Higher Rate', () {
      final rows = UKTaxEngine.taxBandBreakdown(60000);
      expect(rows.length, 3); // PA + Basic + Higher
      expect(rows[1].name, 'Basic Rate');
      expect(rows[1].amount, closeTo(7540, 0.01)); // 37700 × 20%
      expect(rows[2].name, 'Higher Rate');
      expect(rows[2].amount, closeTo(3892, 0.01)); // 9730 × 40%
    });

    test('£60,000 — continuity', () {
      assertContinuous(UKTaxEngine.taxBandBreakdown(60000), 60000);
    });

    test('£60,000 — sum matches incomeTax', () {
      assertSumMatchesTax(UKTaxEngine.taxBandBreakdown(60000), 60000);
    });

    test('£110,000 — taper zone: PA reduced to 7570', () {
      final rows = UKTaxEngine.taxBandBreakdown(110000);
      expect(rows.first.rangeTo, closeTo(7570, 0.01)); // tapered PA
      assertContinuous(rows, 110000);
    });

    test('£110,000 — sum matches incomeTax', () {
      assertSumMatchesTax(UKTaxEngine.taxBandBreakdown(110000), 110000);
    });

    test('£125,140 — PA fully tapered (no PA row)', () {
      final rows = UKTaxEngine.taxBandBreakdown(125140);
      // PA = 0 → no Personal Allowance row (pa == 0 skips it)
      expect(rows.first.name, isNot('Personal Allowance'));
      assertContinuous(rows, 125140);
      assertSumMatchesTax(rows, 125140);
    });
  });

  group('taxBandBreakdown — Scotland', () {
    void assertContinuous(List<TaxBandRow> rows, double gross) {
      expect(rows.isNotEmpty, isTrue);
      expect(rows.first.rangeFrom, closeTo(0, 0.01));
      for (int i = 1; i < rows.length; i++) {
        expect(rows[i].rangeFrom, closeTo(rows[i - 1].rangeTo, 0.01),
            reason: 'gap between row ${i - 1} and $i');
      }
      expect(rows.last.rangeTo, closeTo(gross, 0.01));
    }

    void assertSumMatchesTax(List<TaxBandRow> rows, double gross) {
      final sum = rows.fold(0.0, (acc, r) => acc + r.amount);
      final expected = UKTaxEngine.incomeTax(gross, isScotland: true);
      expect(sum, closeTo(expected, 0.02));
    }

    test('£50,000 — 5 rows: PA + Starter + Basic + Intermediate + Higher', () {
      final rows = UKTaxEngine.taxBandBreakdown(50000, isScotland: true);
      expect(rows.length, 5);
      expect(rows[0].name, 'Personal Allowance');
      expect(rows[1].name, 'Starter Rate');
      expect(rows[1].rate, 0.19);
      expect(rows[2].name, 'Basic Rate');
      expect(rows[2].rate, 0.20);
      expect(rows[3].name, 'Intermediate Rate');
      expect(rows[3].rate, 0.21);
      expect(rows[4].name, 'Higher Rate');
      expect(rows[4].rate, 0.42);
    });

    test('£50,000 — Starter boundary at taxable £2,827 (gross £15,397)', () {
      final rows = UKTaxEngine.taxBandBreakdown(50000, isScotland: true);
      // PA row ends at 12570; Starter ends at 12570+2827=15397
      expect(rows[1].rangeTo, closeTo(15397, 0.01));
      expect(rows[1].amount, closeTo(537.13, 0.02)); // 2827 × 19%
    });

    test('£50,000 — Intermediate ends at taxable £31,092 (gross £43,662)', () {
      final rows = UKTaxEngine.taxBandBreakdown(50000, isScotland: true);
      expect(rows[3].rangeTo, closeTo(43662, 0.01)); // 12570 + 31092
    });

    test('£50,000 — sum matches incomeTax (9013.80)', () {
      final rows = UKTaxEngine.taxBandBreakdown(50000, isScotland: true);
      assertSumMatchesTax(rows, 50000);
    });

    test('£50,000 — continuity', () {
      assertContinuous(
          UKTaxEngine.taxBandBreakdown(50000, isScotland: true), 50000);
    });

    test('£80,000 — includes Advanced Rate band', () {
      final rows = UKTaxEngine.taxBandBreakdown(80000, isScotland: true);
      final names = rows.map((r) => r.name).toList();
      expect(names.contains('Advanced Rate'), isTrue);
      assertContinuous(rows, 80000);
      assertSumMatchesTax(rows, 80000);
    });
  });

  // ─── effectiveTaxRate ─────────────────────────────────────────────────────

  group('effectiveTaxRate', () {
    test('zero income → 0%', () {
      approx(UKTaxEngine.effectiveTaxRate(0), 0);
    });

    test('£50,000 rUK → ~14.97% (7486/50000)', () {
      approx(UKTaxEngine.effectiveTaxRate(50000), 7486 / 50000, tol: 0.001);
    });

    test('£50,000 Scotland → ~18.03% (9013.80/50000)', () {
      approx(UKTaxEngine.effectiveTaxRate(50000, isScotland: true),
          9013.80 / 50000, tol: 0.001);
    });
  });

  // ─── VAT helpers ──────────────────────────────────────────────────────────

  group('VAT helpers', () {
    test('vatAmountFromNet standard 20%: 100 × 20% = 20', () {
      approx(UKTaxEngine.vatAmountFromNet(100, UKTaxEngine.vatStandard), 20);
    });

    test('vatAmountFromGross standard 20%: 120 gross → 20 VAT', () {
      approx(UKTaxEngine.vatAmountFromGross(120, UKTaxEngine.vatStandard), 20);
    });

    test('netFromGross: 120 at 20% → 100', () {
      approx(UKTaxEngine.netFromGross(120, UKTaxEngine.vatStandard), 100);
    });

    test('grossFromNet: 100 at 20% → 120', () {
      approx(UKTaxEngine.grossFromNet(100, UKTaxEngine.vatStandard), 120);
    });

    test('zero rate: vatAmountFromGross = 0', () {
      approx(UKTaxEngine.vatAmountFromGross(100, UKTaxEngine.vatZero), 0);
    });
  });
}
