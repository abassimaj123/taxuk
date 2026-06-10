import 'package:flutter_test/flutter_test.dart';
import 'package:taxuk/core/tax_code_engine.dart';

void main() {
  // ── HMRC Tax Code Reference (2025/26) ────────────────────────────────────
  // Standard code: 1257L → personal allowance £12,570 (multiply code number by 10)
  // Source: HMRC — gov.uk/tax-codes/what-your-tax-code-means
  //
  // Letter meanings: L=standard PA, M=marriage allowance received (+10%),
  // N=transferred to partner, T=other, BR=all income at basic rate,
  // D0=higher rate, D1=additional rate, 0T=no PA, NT=no tax, K=negative PA
  // S prefix=Scotland, C prefix=Wales
  // Emergency codes: W1/M1/X suffix = non-cumulative (week/month basis)
  group('TaxCodeEngine.parse — standard numeric codes', () {
    test('1257L → £12,570 standard allowance, England/NI', () {
      final r = TaxCodeEngine.parse('1257L');
      expect(r.isValid, isTrue);
      expect(r.personalAllowance, 12570);
      expect(r.letter, 'L');
      expect(r.region, TaxRegion.englandNi);
      expect(r.isEmergency, isFalse);
      expect(r.isKCode, isFalse);
    });

    test('number × 10 rule (1000L → £10,000)', () {
      expect(TaxCodeEngine.parse('1000L').personalAllowance, 10000);
    });

    test('lowercase + whitespace is normalised', () {
      final r = TaxCodeEngine.parse('  1257l  ');
      expect(r.isValid, isTrue);
      expect(r.personalAllowance, 12570);
    });

    test('M suffix = marriage allowance received', () {
      final r = TaxCodeEngine.parse('1383M');
      expect(r.isValid, isTrue);
      expect(r.letter, 'M');
      expect(r.personalAllowance, 13830);
    });

    test('N suffix = marriage allowance transferred', () {
      expect(TaxCodeEngine.parse('1131N').letter, 'N');
    });

    test('T suffix = other calculations', () {
      expect(TaxCodeEngine.parse('500T').letter, 'T');
    });
  });

  group('TaxCodeEngine.parse — whole-letter codes', () {
    test('BR = basic rate, no allowance', () {
      final r = TaxCodeEngine.parse('BR');
      expect(r.isValid, isTrue);
      expect(r.letter, 'BR');
      expect(r.personalAllowance, 0);
      expect(r.hasAllowance, isFalse);
    });

    test('D0 = higher rate', () {
      expect(TaxCodeEngine.parse('D0').letter, 'D0');
      expect(TaxCodeEngine.parse('D0').personalAllowance, 0);
    });

    test('D1 = additional rate', () {
      expect(TaxCodeEngine.parse('D1').letter, 'D1');
    });

    test('0T = no personal allowance', () {
      final r = TaxCodeEngine.parse('0T');
      expect(r.isValid, isTrue);
      expect(r.letter, '0T');
      expect(r.personalAllowance, 0);
    });

    test('NT = no tax', () {
      expect(TaxCodeEngine.parse('NT').letter, 'NT');
    });
  });

  // K codes: negative allowance — income added to taxable pay. Common for: company car
  // benefit-in-kind exceeding personal allowance.
  // Source: HMRC Employment Income Manual — gov.uk/hmrc-internal-manuals/employment-income-manual
  group('TaxCodeEngine.parse — K codes', () {
    test('K475 → +£4,750 added to taxable income', () {
      final r = TaxCodeEngine.parse('K475');
      expect(r.isValid, isTrue);
      expect(r.isKCode, isTrue);
      expect(r.letter, 'K');
      expect(r.personalAllowance, 0);
      expect(r.kAddition, 4750);
    });

    test('SK100 → Scotland + K code', () {
      final r = TaxCodeEngine.parse('SK100');
      expect(r.isValid, isTrue);
      expect(r.region, TaxRegion.scotland);
      expect(r.kAddition, 1000);
    });
  });

  group('TaxCodeEngine.parse — region prefixes', () {
    test('S prefix = Scotland', () {
      final r = TaxCodeEngine.parse('S1257L');
      expect(r.region, TaxRegion.scotland);
      expect(r.personalAllowance, 12570);
    });

    test('C prefix = Wales', () {
      final r = TaxCodeEngine.parse('C1257L');
      expect(r.region, TaxRegion.wales);
      expect(r.personalAllowance, 12570);
    });

    test('SBR = Scotland basic rate', () {
      final r = TaxCodeEngine.parse('SBR');
      expect(r.region, TaxRegion.scotland);
      expect(r.letter, 'BR');
    });
  });

  group('TaxCodeEngine.parse — emergency codes', () {
    test('1257L W1/M1 flagged as emergency', () {
      final r = TaxCodeEngine.parse('1257L W1/M1');
      expect(r.isValid, isTrue);
      expect(r.isEmergency, isTrue);
      expect(r.personalAllowance, 12570);
      expect(r.letter, 'L');
    });

    test('1257L X flagged as emergency', () {
      final r = TaxCodeEngine.parse('1257L X');
      expect(r.isEmergency, isTrue);
      expect(r.personalAllowance, 12570);
    });

    test('1257LM1 (no space) flagged as emergency', () {
      expect(TaxCodeEngine.parse('1257LM1').isEmergency, isTrue);
    });
  });

  group('TaxCodeEngine.parse — invalid', () {
    test('empty string is invalid', () {
      expect(TaxCodeEngine.parse('').isValid, isFalse);
    });

    test('gibberish is invalid', () {
      final r = TaxCodeEngine.parse('ZZZ');
      expect(r.isValid, isFalse);
      expect(r.errorMessage, isNotNull);
    });

    test('number with no suffix is invalid', () {
      expect(TaxCodeEngine.parse('1257').isValid, isFalse);
    });
  });
}
