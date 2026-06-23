import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

// ── Brand colours ─────────────────────────────────────────────────────────────

const _taxukNavy = PdfColor(0.051, 0.137, 0.396); // #0D2366 — TaxUK primary
const _taxukLight = PdfColor(0.929, 0.949, 0.992); // #EDF2FD — tint
const _taxukAccent = PdfColor(0.102, 0.580, 0.969); // #1A94F7 — accent

// ── Formatters ────────────────────────────────────────────────────────────────

final _gbp = NumberFormat.currency(locale: 'en_GB', symbol: '£', decimalDigits: 2);
final _gbp0 = NumberFormat.currency(locale: 'en_GB', symbol: '£', decimalDigits: 0);
final _pct = NumberFormat('##0.00', 'en_GB');
final _dateShort = DateFormat('dd MMM yyyy', 'en');

// ── Params classes (only sendable types: primitives + Uint8List) ──────────────

class _IncomeTaxParams {
  const _IncomeTaxParams({
    required this.gross,
    required this.tax,
    required this.ni,
    required this.takeHome,
    required this.effectiveTaxRate,
    required this.marginalTaxRate,
    required this.region,
    required this.pension,
    required this.isSelfEmployed,
    required this.dateStr,
  });
  final double gross, tax, ni, takeHome, effectiveTaxRate, marginalTaxRate, pension;
  final String region, dateStr;
  final bool isSelfEmployed;
}

class _SalaryComparisonParams {
  const _SalaryComparisonParams({
    required this.nameA,
    required this.grossA,
    required this.taxA,
    required this.niA,
    required this.netA,
    required this.monthlyA,
    required this.nameB,
    required this.grossB,
    required this.taxB,
    required this.niB,
    required this.netB,
    required this.monthlyB,
    required this.isScotland,
    required this.dateStr,
  });
  final String nameA, nameB, dateStr;
  final double grossA, taxA, niA, netA, monthlyA;
  final double grossB, taxB, niB, netB, monthlyB;
  final bool isScotland;
}

class _CgtParams {
  const _CgtParams({
    required this.totalGain,
    required this.annualExemption,
    required this.taxableGain,
    required this.totalTax,
    required this.effectiveRate,
    required this.assetType,
    required this.grossIncome,
    required this.salePrice,
    required this.purchasePrice,
    required this.costs,
    required this.dateStr,
  });
  final double totalGain, annualExemption, taxableGain, totalTax, effectiveRate;
  final double grossIncome, salePrice, purchasePrice, costs;
  final String assetType, dateStr;
}

class _DividendParams {
  const _DividendParams({
    required this.grossIncome,
    required this.grossDividend,
    required this.allowance,
    required this.taxableDividend,
    required this.taxDue,
    required this.effectiveRate,
    required this.band,
    required this.dateStr,
  });
  final double grossIncome, grossDividend, allowance, taxableDividend, taxDue, effectiveRate;
  final String band, dateStr;
}

class _VatParams {
  const _VatParams({
    required this.netAmount,
    required this.vatRate,
    required this.vatAmount,
    required this.grossAmount,
    required this.rateLabel,
    required this.dateStr,
  });
  final double netAmount, vatRate, vatAmount, grossAmount;
  final String rateLabel, dateStr;
}

class _StudentLoanParams {
  const _StudentLoanParams({
    required this.salary,
    required this.threshold,
    required this.annualRepayment,
    required this.monthlyRepayment,
    required this.plan,
    required this.dateStr,
  });
  final double salary, threshold, annualRepayment, monthlyRepayment;
  final String plan, dateStr;
}

class _RentalIncomeParams {
  const _RentalIncomeParams({
    required this.grossRental,
    required this.allowableExpenses,
    required this.taxableProfit,
    required this.taxAfterCredit,
    required this.netProfit,
    required this.effectiveYield,
    required this.mortgageInterestCredit,
    required this.otherIncome,
    required this.dateStr,
  });
  final double grossRental, allowableExpenses, taxableProfit, taxAfterCredit;
  final double netProfit, effectiveYield, mortgageInterestCredit, otherIncome;
  final String dateStr;
}

class _SavingsInterestParams {
  const _SavingsInterestParams({
    required this.grossInterest,
    required this.otherIncome,
    required this.personalSavingsAllowance,
    required this.taxableInterest,
    required this.taxDue,
    required this.band,
    required this.effectiveRate,
    required this.dateStr,
  });
  final double grossInterest, otherIncome, personalSavingsAllowance;
  final double taxableInterest, taxDue, effectiveRate;
  final String band, dateStr;
}

// ── Top-level isolate builders ────────────────────────────────────────────────
// These functions run in a worker isolate — must be top-level (not closures).
// No BuildContext, no rootBundle, no Flutter services. Primitives only.

Future<Uint8List> _buildIncomeTaxPdf(_IncomeTaxParams p) async {
  final gbp = NumberFormat.currency(locale: 'en_GB', symbol: '£', decimalDigits: 2);
  final pct = NumberFormat('##0.00', 'en_GB');

  final pdf = pw.Document();
  pdf.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(40),
    build: (_) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _isoHeader('Income Tax Calculator', 'UK Income Tax Summary', p.dateStr),
        pw.SizedBox(height: 16),
        _isoHeroBox('ANNUAL TAKE-HOME', gbp.format(p.takeHome)),
        pw.SizedBox(height: 16),
        _isoSection('INCOME DETAILS', [
          _isoRow('Gross Salary', gbp.format(p.gross)),
          if (p.pension > 0) _isoRow('Pension Contribution', gbp.format(p.pension)),
          _isoRow('Tax Region', p.region),
          _isoRow('Employment Type', p.isSelfEmployed ? 'Self-Employed' : 'PAYE'),
        ]),
        pw.SizedBox(height: 12),
        _isoSection('TAX BREAKDOWN', [
          _isoRow('Income Tax', gbp.format(p.tax)),
          _isoRow('National Insurance', gbp.format(p.ni)),
          _isoRow('Total Deductions', gbp.format(p.tax + p.ni)),
          _isoRowHighlight('Take-Home Pay', gbp.format(p.takeHome)),
        ]),
        pw.SizedBox(height: 12),
        _isoSection('EFFECTIVE RATES', [
          _isoRow('Effective Tax Rate', '${pct.format(p.effectiveTaxRate * 100)}%'),
          _isoRow('Marginal Rate', '${pct.format(p.marginalTaxRate * 100)}%'),
          _isoRow('Monthly Take-Home', gbp.format(p.takeHome / 12)),
          _isoRow('Weekly Take-Home', gbp.format(p.takeHome / 52)),
        ]),
        pw.Spacer(),
        _isoFooter(),
      ],
    ),
  ));
  return await pdf.save();
}

Future<Uint8List> _buildSalaryComparisonPdf(_SalaryComparisonParams p) async {
  final gbp = NumberFormat.currency(locale: 'en_GB', symbol: '£', decimalDigits: 2);
  final betterName = p.monthlyA >= p.monthlyB ? p.nameA : p.nameB;
  final diff = (p.monthlyA - p.monthlyB).abs();

  final pdf = pw.Document();
  pdf.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(40),
    build: (_) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _isoHeader('Salary Comparison', 'Side-by-side UK tax comparison', p.dateStr),
        pw.SizedBox(height: 16),
        _isoInfoRow('$betterName pays ${gbp.format(diff)}/mo more after tax'),
        pw.SizedBox(height: 16),
        _isoComparisonSection(
          nameA: p.nameA,
          nameB: p.nameB,
          rows: [
            ('Gross Salary', gbp.format(p.grossA), gbp.format(p.grossB)),
            ('Income Tax', gbp.format(p.taxA), gbp.format(p.taxB)),
            ('National Insurance', gbp.format(p.niA), gbp.format(p.niB)),
            ('Annual Take-Home', gbp.format(p.netA), gbp.format(p.netB)),
            ('Monthly Take-Home', gbp.format(p.monthlyA), gbp.format(p.monthlyB)),
          ],
        ),
        pw.Spacer(),
        _isoFooter(),
      ],
    ),
  ));
  return await pdf.save();
}

Future<Uint8List> _buildCgtPdf(_CgtParams p) async {
  final gbp = NumberFormat.currency(locale: 'en_GB', symbol: '£', decimalDigits: 2);
  final pct = NumberFormat('##0.00', 'en_GB');

  final pdf = pw.Document();
  pdf.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(40),
    build: (_) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _isoHeader('Capital Gains Tax', 'UK CGT Summary 2025/26', p.dateStr),
        pw.SizedBox(height: 16),
        _isoHeroBox('CGT DUE', gbp.format(p.totalTax)),
        pw.SizedBox(height: 16),
        _isoSection('TRANSACTION DETAILS', [
          if (p.salePrice > 0) _isoRow('Sale Price', gbp.format(p.salePrice)),
          if (p.purchasePrice > 0) _isoRow('Purchase Price', gbp.format(p.purchasePrice)),
          if (p.costs > 0) _isoRow('Costs / Expenses', gbp.format(p.costs)),
          _isoRow('Asset Type', p.assetType),
          if (p.grossIncome > 0) _isoRow('Other Income', gbp.format(p.grossIncome)),
        ]),
        pw.SizedBox(height: 12),
        _isoSection('GAIN CALCULATION', [
          _isoRow('Total Gain', gbp.format(p.totalGain)),
          _isoRow('Annual Exemption (2025/26)', gbp.format(p.annualExemption)),
          _isoRow('Taxable Gain', gbp.format(p.taxableGain)),
          _isoRowHighlight('Capital Gains Tax Due', gbp.format(p.totalTax)),
          _isoRow('Effective Rate on Gain', '${pct.format(p.effectiveRate * 100)}%'),
        ]),
        pw.Spacer(),
        _isoFooter(),
      ],
    ),
  ));
  return await pdf.save();
}

Future<Uint8List> _buildDividendPdf(_DividendParams p) async {
  final gbp = NumberFormat.currency(locale: 'en_GB', symbol: '£', decimalDigits: 2);
  final pct = NumberFormat('##0.00', 'en_GB');

  final pdf = pw.Document();
  pdf.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(40),
    build: (_) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _isoHeader('Dividend Tax Calculator', 'UK Dividend Tax Summary 2025/26', p.dateStr),
        pw.SizedBox(height: 16),
        _isoHeroBox('DIVIDEND TAX DUE', gbp.format(p.taxDue)),
        pw.SizedBox(height: 16),
        _isoSection('INCOME DETAILS', [
          _isoRow('Employment / Other Income', gbp.format(p.grossIncome)),
          _isoRow('Gross Dividend Income', gbp.format(p.grossDividend)),
          _isoRow('Tax Band', p.band),
        ]),
        pw.SizedBox(height: 12),
        _isoSection('DIVIDEND TAX CALCULATION', [
          _isoRow('Dividend Allowance (2025/26)', gbp.format(p.allowance)),
          _isoRow('Taxable Dividend', gbp.format(p.taxableDividend)),
          _isoRowHighlight('Tax Due', gbp.format(p.taxDue)),
          _isoRow('Effective Rate on Dividend', '${pct.format(p.effectiveRate * 100)}%'),
        ]),
        pw.Spacer(),
        _isoFooter(),
      ],
    ),
  ));
  return await pdf.save();
}

Future<Uint8List> _buildVatPdf(_VatParams p) async {
  final gbp = NumberFormat.currency(locale: 'en_GB', symbol: '£', decimalDigits: 2);

  final pdf = pw.Document();
  pdf.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(40),
    build: (_) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _isoHeader('VAT Calculator', 'UK VAT Breakdown', p.dateStr),
        pw.SizedBox(height: 16),
        _isoHeroBox('VAT AMOUNT', gbp.format(p.vatAmount)),
        pw.SizedBox(height: 16),
        _isoSection('VAT BREAKDOWN', [
          _isoRow('VAT Rate', p.rateLabel),
          _isoRow('Net Amount (ex-VAT)', gbp.format(p.netAmount)),
          _isoRow('VAT Amount', gbp.format(p.vatAmount)),
          _isoRowHighlight('Gross Amount (inc-VAT)', gbp.format(p.grossAmount)),
        ]),
        pw.Spacer(),
        _isoFooter(),
      ],
    ),
  ));
  return await pdf.save();
}

Future<Uint8List> _buildStudentLoanPdf(_StudentLoanParams p) async {
  final gbp = NumberFormat.currency(locale: 'en_GB', symbol: '£', decimalDigits: 2);

  final pdf = pw.Document();
  pdf.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(40),
    build: (_) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _isoHeader('Student Loan Repayment', 'UK Student Loan Calculator', p.dateStr),
        pw.SizedBox(height: 16),
        _isoHeroBox('ANNUAL REPAYMENT', gbp.format(p.annualRepayment)),
        pw.SizedBox(height: 16),
        _isoSection('LOAN DETAILS', [
          _isoRow('Repayment Plan', p.plan),
          _isoRow('Gross Annual Salary', gbp.format(p.salary)),
          _isoRow('Repayment Threshold', gbp.format(p.threshold)),
        ]),
        pw.SizedBox(height: 12),
        _isoSection('REPAYMENT BREAKDOWN', [
          _isoRowHighlight('Annual Repayment', gbp.format(p.annualRepayment)),
          _isoRow('Monthly Repayment', gbp.format(p.monthlyRepayment)),
          _isoRow('Weekly Repayment', gbp.format(p.monthlyRepayment * 12 / 52)),
          _isoRow(
            'Income Above Threshold',
            gbp.format(p.salary > p.threshold ? p.salary - p.threshold : 0),
          ),
        ]),
        pw.Spacer(),
        _isoFooter(),
      ],
    ),
  ));
  return await pdf.save();
}

Future<Uint8List> _buildRentalIncomePdf(_RentalIncomeParams p) async {
  final gbp = NumberFormat.currency(locale: 'en_GB', symbol: '£', decimalDigits: 2);
  final pct = NumberFormat('##0.00', 'en_GB');

  final pdf = pw.Document();
  pdf.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(40),
    build: (_) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _isoHeader('Rental Income Tax', 'UK Rental Income Tax Summary 2025/26', p.dateStr),
        pw.SizedBox(height: 16),
        _isoHeroBox('NET PROFIT AFTER TAX', gbp.format(p.netProfit)),
        pw.SizedBox(height: 16),
        _isoSection('INCOME & EXPENSES', [
          _isoRow('Gross Rental Income', gbp.format(p.grossRental)),
          _isoRow('Allowable Expenses', gbp.format(p.allowableExpenses)),
          _isoRow('Taxable Profit', gbp.format(p.taxableProfit)),
          if (p.otherIncome > 0) _isoRow('Other Income', gbp.format(p.otherIncome)),
        ]),
        pw.SizedBox(height: 12),
        _isoSection('TAX CALCULATION', [
          if (p.mortgageInterestCredit > 0)
            _isoRow('Mortgage Interest Credit (20%)', gbp.format(p.mortgageInterestCredit)),
          _isoRowHighlight('Tax Due', gbp.format(p.taxAfterCredit)),
          _isoRow('Net Profit After Tax', gbp.format(p.netProfit)),
          _isoRow('Effective Yield on Rental', '${pct.format(p.effectiveYield)}%'),
        ]),
        pw.Spacer(),
        _isoFooter(),
      ],
    ),
  ));
  return await pdf.save();
}

Future<Uint8List> _buildSavingsInterestPdf(_SavingsInterestParams p) async {
  final gbp = NumberFormat.currency(locale: 'en_GB', symbol: '£', decimalDigits: 2);
  final pct = NumberFormat('##0.00', 'en_GB');

  final pdf = pw.Document();
  pdf.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(40),
    build: (_) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _isoHeader('Savings Interest Tax', 'UK Savings Interest Tax Summary 2025/26', p.dateStr),
        pw.SizedBox(height: 16),
        _isoHeroBox('TAX DUE ON INTEREST', gbp.format(p.taxDue)),
        pw.SizedBox(height: 16),
        _isoSection('INCOME DETAILS', [
          _isoRow('Gross Interest', gbp.format(p.grossInterest)),
          _isoRow('Other Income', gbp.format(p.otherIncome)),
          _isoRow('Tax Band', p.band),
        ]),
        pw.SizedBox(height: 12),
        _isoSection('SAVINGS TAX CALCULATION', [
          _isoRow('Personal Savings Allowance', gbp.format(p.personalSavingsAllowance)),
          _isoRow('Taxable Interest', gbp.format(p.taxableInterest)),
          _isoRowHighlight('Tax Due', gbp.format(p.taxDue)),
          if (p.effectiveRate > 0)
            _isoRow('Effective Rate', '${pct.format(p.effectiveRate * 100)}%'),
        ]),
        pw.Spacer(),
        _isoFooter(),
      ],
    ),
  ));
  return await pdf.save();
}

// ── Isolate-safe widget builders (top-level, no Flutter services) ─────────────

pw.Widget _isoHeader(String title, String subtitle, String dateStr) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'TaxUK',
                  style: pw.TextStyle(
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                    color: _taxukNavy,
                  ),
                ),
                pw.Text(
                  title,
                  style: const pw.TextStyle(
                    fontSize: 11,
                    color: PdfColors.grey700,
                  ),
                ),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  dateStr,
                  style: const pw.TextStyle(
                    fontSize: 10,
                    color: PdfColors.grey600,
                  ),
                ),
                pw.Text(
                  subtitle,
                  style: const pw.TextStyle(
                    fontSize: 9,
                    color: PdfColors.grey500,
                  ),
                ),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 6),
        pw.Divider(color: _taxukNavy, thickness: 1.5),
      ],
    );

pw.Widget _isoHeroBox(String label, String value) => pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: const pw.BoxDecoration(color: _taxukNavy),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: _taxukLight,
              letterSpacing: 1.2,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 26,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
          ),
        ],
      ),
    );

pw.Widget _isoInfoRow(String text) => pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: pw.BoxDecoration(
        color: _taxukLight,
        border: pw.Border.all(color: _taxukNavy, width: 0.5),
      ),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 10,
          fontWeight: pw.FontWeight.bold,
          color: _taxukNavy,
        ),
      ),
    );

pw.Widget _isoSection(String title, List<pw.Widget> rows) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          color: _taxukNavy,
          child: pw.Text(
            title,
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
              letterSpacing: 0.8,
            ),
          ),
        ),
        pw.Container(
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
          ),
          padding: const pw.EdgeInsets.all(10),
          child: pw.Column(children: rows),
        ),
      ],
    );

pw.Widget _isoComparisonSection({
  required String nameA,
  required String nameB,
  required List<(String, String, String)> rows,
}) =>
    pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          color: _taxukNavy,
          child: pw.Text(
            'COMPARISON',
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
          ),
        ),
        pw.Container(
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
          ),
          padding: const pw.EdgeInsets.all(10),
          child: pw.Column(
            children: [
              pw.Row(
                children: [
                  pw.Expanded(flex: 3, child: pw.SizedBox()),
                  pw.Expanded(
                    flex: 2,
                    child: pw.Text(
                      nameA,
                      textAlign: pw.TextAlign.right,
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                        color: _taxukNavy,
                      ),
                    ),
                  ),
                  pw.SizedBox(width: 8),
                  pw.Expanded(
                    flex: 2,
                    child: pw.Text(
                      nameB,
                      textAlign: pw.TextAlign.right,
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                        color: _taxukAccent,
                      ),
                    ),
                  ),
                ],
              ),
              pw.Divider(color: PdfColors.grey300, height: 8),
              ...rows.map((r) => _isoCmpRow(r.$1, r.$2, r.$3)),
            ],
          ),
        ),
      ],
    );

pw.Widget _isoCmpRow(String label, String valueA, String valueB) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        children: [
          pw.Expanded(
            flex: 3,
            child: pw.Text(
              label,
              style: const pw.TextStyle(
                fontSize: 9,
                color: PdfColors.grey700,
              ),
            ),
          ),
          pw.Expanded(
            flex: 2,
            child: pw.Text(
              valueA,
              textAlign: pw.TextAlign.right,
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            flex: 2,
            child: pw.Text(
              valueB,
              textAlign: pw.TextAlign.right,
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

pw.Widget _isoRow(String label, String value) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: const pw.TextStyle(
              fontSize: 10,
              color: PdfColors.grey800,
            ),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );

pw.Widget _isoRowHighlight(String label, String value) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        color: _taxukLight,
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              label,
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                color: _taxukNavy,
              ),
            ),
            pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                color: _taxukNavy,
              ),
            ),
          ],
        ),
      ),
    );

pw.Widget _isoFooter() => pw.Column(
      children: [
        pw.Divider(color: PdfColors.grey300),
        pw.Text(
          'Generated by TaxUK - UK Tax Calculator  ·  For informational purposes only. Consult a tax professional.',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500),
        ),
      ],
    );

// ── Public service ────────────────────────────────────────────────────────────

class TaxUkPdfExportService {
  TaxUkPdfExportService._();

  // ── 1 · Income Tax ───────────────────────────────────────────────────────

  static Future<void> exportIncomeTax({
    required BuildContext context,
    required double gross,
    required double tax,
    required double ni,
    required double takeHome,
    required double effectiveTaxRate,
    required double marginalTaxRate,
    required String region,
    double pension = 0,
    bool isSelfEmployed = false,
  }) async {
    final params = _IncomeTaxParams(
      gross: gross,
      tax: tax,
      ni: ni,
      takeHome: takeHome,
      effectiveTaxRate: effectiveTaxRate,
      marginalTaxRate: marginalTaxRate,
      region: region,
      pension: pension,
      isSelfEmployed: isSelfEmployed,
      dateStr: DateFormat('dd MMM yyyy', 'en').format(DateTime.now()),
    );
    final bytes = await Isolate.run(() => _buildIncomeTaxPdf(params));
    await _saveBytes(bytes, 'taxuk_income_tax');
  }

  // ── 2 · Salary Comparison ────────────────────────────────────────────────

  static Future<void> exportSalaryComparison({
    required BuildContext context,
    required String nameA,
    required double grossA,
    required double taxA,
    required double niA,
    required double netA,
    required double monthlyA,
    required String nameB,
    required double grossB,
    required double taxB,
    required double niB,
    required double netB,
    required double monthlyB,
    bool isScotland = false,
  }) async {
    final params = _SalaryComparisonParams(
      nameA: nameA,
      grossA: grossA,
      taxA: taxA,
      niA: niA,
      netA: netA,
      monthlyA: monthlyA,
      nameB: nameB,
      grossB: grossB,
      taxB: taxB,
      niB: niB,
      netB: netB,
      monthlyB: monthlyB,
      isScotland: isScotland,
      dateStr: DateFormat('dd MMM yyyy', 'en').format(DateTime.now()),
    );
    final bytes = await Isolate.run(() => _buildSalaryComparisonPdf(params));
    await _saveBytes(bytes, 'taxuk_salary_comparison');
  }

  // ── 3 · Capital Gains Tax ────────────────────────────────────────────────

  static Future<void> exportCgt({
    required BuildContext context,
    required double totalGain,
    required double annualExemption,
    required double taxableGain,
    required double totalTax,
    required double effectiveRate,
    required String assetType,
    double grossIncome = 0,
    double salePrice = 0,
    double purchasePrice = 0,
    double costs = 0,
  }) async {
    final params = _CgtParams(
      totalGain: totalGain,
      annualExemption: annualExemption,
      taxableGain: taxableGain,
      totalTax: totalTax,
      effectiveRate: effectiveRate,
      assetType: assetType,
      grossIncome: grossIncome,
      salePrice: salePrice,
      purchasePrice: purchasePrice,
      costs: costs,
      dateStr: DateFormat('dd MMM yyyy', 'en').format(DateTime.now()),
    );
    final bytes = await Isolate.run(() => _buildCgtPdf(params));
    await _saveBytes(bytes, 'taxuk_cgt');
  }

  // ── 4 · Dividend Tax ────────────────────────────────────────────────────

  static Future<void> exportDividend({
    required BuildContext context,
    required double grossIncome,
    required double grossDividend,
    required double allowance,
    required double taxableDividend,
    required double taxDue,
    required double effectiveRate,
    required String band,
  }) async {
    final params = _DividendParams(
      grossIncome: grossIncome,
      grossDividend: grossDividend,
      allowance: allowance,
      taxableDividend: taxableDividend,
      taxDue: taxDue,
      effectiveRate: effectiveRate,
      band: band,
      dateStr: DateFormat('dd MMM yyyy', 'en').format(DateTime.now()),
    );
    final bytes = await Isolate.run(() => _buildDividendPdf(params));
    await _saveBytes(bytes, 'taxuk_dividend');
  }

  // ── 5 · VAT ──────────────────────────────────────────────────────────────

  static Future<void> exportVat({
    required BuildContext context,
    required double netAmount,
    required double vatRate,
    required double vatAmount,
    required double grossAmount,
    required String rateLabel,
  }) async {
    final params = _VatParams(
      netAmount: netAmount,
      vatRate: vatRate,
      vatAmount: vatAmount,
      grossAmount: grossAmount,
      rateLabel: rateLabel,
      dateStr: DateFormat('dd MMM yyyy', 'en').format(DateTime.now()),
    );
    final bytes = await Isolate.run(() => _buildVatPdf(params));
    await _saveBytes(bytes, 'taxuk_vat');
  }

  // ── 6 · Student Loan ────────────────────────────────────────────────────

  static Future<void> exportStudentLoan({
    required BuildContext context,
    required double salary,
    required double threshold,
    required double annualRepayment,
    required double monthlyRepayment,
    required String plan,
  }) async {
    final params = _StudentLoanParams(
      salary: salary,
      threshold: threshold,
      annualRepayment: annualRepayment,
      monthlyRepayment: monthlyRepayment,
      plan: plan,
      dateStr: DateFormat('dd MMM yyyy', 'en').format(DateTime.now()),
    );
    final bytes = await Isolate.run(() => _buildStudentLoanPdf(params));
    await _saveBytes(bytes, 'taxuk_student_loan');
  }

  // ── 7 · Rental Income ────────────────────────────────────────────────────

  static Future<void> exportRentalIncome({
    required BuildContext context,
    required double grossRental,
    required double allowableExpenses,
    required double taxableProfit,
    required double taxAfterCredit,
    required double netProfit,
    required double effectiveYield,
    double mortgageInterestCredit = 0,
    double otherIncome = 0,
  }) async {
    final params = _RentalIncomeParams(
      grossRental: grossRental,
      allowableExpenses: allowableExpenses,
      taxableProfit: taxableProfit,
      taxAfterCredit: taxAfterCredit,
      netProfit: netProfit,
      effectiveYield: effectiveYield,
      mortgageInterestCredit: mortgageInterestCredit,
      otherIncome: otherIncome,
      dateStr: DateFormat('dd MMM yyyy', 'en').format(DateTime.now()),
    );
    final bytes = await Isolate.run(() => _buildRentalIncomePdf(params));
    await _saveBytes(bytes, 'taxuk_rental_income');
  }

  // ── 8 · Savings Interest ─────────────────────────────────────────────────

  static Future<void> exportSavingsInterest({
    required BuildContext context,
    required double grossInterest,
    required double otherIncome,
    required double personalSavingsAllowance,
    required double taxableInterest,
    required double taxDue,
    required String band,
    double effectiveRate = 0,
  }) async {
    final params = _SavingsInterestParams(
      grossInterest: grossInterest,
      otherIncome: otherIncome,
      personalSavingsAllowance: personalSavingsAllowance,
      taxableInterest: taxableInterest,
      taxDue: taxDue,
      band: band,
      effectiveRate: effectiveRate,
      dateStr: DateFormat('dd MMM yyyy', 'en').format(DateTime.now()),
    );
    final bytes = await Isolate.run(() => _buildSavingsInterestPdf(params));
    await _saveBytes(bytes, 'taxuk_savings_interest');
  }

  // ── File save & share ─────────────────────────────────────────────────────

  static Future<void> _saveBytes(Uint8List bytes, String baseName) async {
    final tmpDir = await getTemporaryDirectory();
    final file = File(
      '${tmpDir.path}/${baseName}_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
    await file.writeAsBytes(bytes);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf')],
    );
  }
}
