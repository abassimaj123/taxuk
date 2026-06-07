import 'dart:io';
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
final _dateShort = DateFormat('dd MMM yyyy');

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
    final pdf = pw.Document();
    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _header('Income Tax Calculator', 'UK Income Tax Summary'),
          pw.SizedBox(height: 16),
          _heroBox('ANNUAL TAKE-HOME', _gbp.format(takeHome)),
          pw.SizedBox(height: 16),
          _section('INCOME DETAILS', [
            _row('Gross Salary', _gbp.format(gross)),
            if (pension > 0) _row('Pension Contribution', _gbp.format(pension)),
            _row('Tax Region', region),
            _row('Employment Type', isSelfEmployed ? 'Self-Employed' : 'PAYE'),
          ]),
          pw.SizedBox(height: 12),
          _section('TAX BREAKDOWN', [
            _row('Income Tax', _gbp.format(tax)),
            _row('National Insurance', _gbp.format(ni)),
            _row('Total Deductions', _gbp.format(tax + ni)),
            _rowHighlight('Take-Home Pay', _gbp.format(takeHome)),
          ]),
          pw.SizedBox(height: 12),
          _section('EFFECTIVE RATES', [
            _row('Effective Tax Rate', '${_pct.format(effectiveTaxRate * 100)}%'),
            _row('Marginal Rate', '${_pct.format(marginalTaxRate * 100)}%'),
            _row('Monthly Take-Home', _gbp.format(takeHome / 12)),
            _row('Weekly Take-Home', _gbp.format(takeHome / 52)),
          ]),
          pw.Spacer(),
          _footer(),
        ],
      ),
    ));
    await _save(pdf, 'taxuk_income_tax');
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
    final betterName = monthlyA >= monthlyB ? nameA : nameB;
    final diff = (monthlyA - monthlyB).abs();

    final pdf = pw.Document();
    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _header('Salary Comparison', 'Side-by-side UK tax comparison'),
          pw.SizedBox(height: 16),
          _infoRow(
            '$betterName pays ${_gbp.format(diff)}/mo more after tax',
          ),
          pw.SizedBox(height: 16),
          _comparisonSection(
            nameA: nameA,
            nameB: nameB,
            rows: [
              ('Gross Salary', _gbp.format(grossA), _gbp.format(grossB)),
              ('Income Tax', _gbp.format(taxA), _gbp.format(taxB)),
              ('National Insurance', _gbp.format(niA), _gbp.format(niB)),
              ('Annual Take-Home', _gbp.format(netA), _gbp.format(netB)),
              ('Monthly Take-Home', _gbp.format(monthlyA), _gbp.format(monthlyB)),
            ],
          ),
          pw.Spacer(),
          _footer(),
        ],
      ),
    ));
    await _save(pdf, 'taxuk_salary_comparison');
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
    final pdf = pw.Document();
    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _header('Capital Gains Tax', 'UK CGT Summary 2025/26'),
          pw.SizedBox(height: 16),
          _heroBox('CGT DUE', _gbp.format(totalTax)),
          pw.SizedBox(height: 16),
          _section('TRANSACTION DETAILS', [
            if (salePrice > 0) _row('Sale Price', _gbp.format(salePrice)),
            if (purchasePrice > 0) _row('Purchase Price', _gbp.format(purchasePrice)),
            if (costs > 0) _row('Costs / Expenses', _gbp.format(costs)),
            _row('Asset Type', assetType),
            if (grossIncome > 0) _row('Other Income', _gbp.format(grossIncome)),
          ]),
          pw.SizedBox(height: 12),
          _section('GAIN CALCULATION', [
            _row('Total Gain', _gbp.format(totalGain)),
            _row('Annual Exemption (2025/26)', _gbp.format(annualExemption)),
            _row('Taxable Gain', _gbp.format(taxableGain)),
            _rowHighlight('Capital Gains Tax Due', _gbp.format(totalTax)),
            _row('Effective Rate on Gain', '${_pct.format(effectiveRate * 100)}%'),
          ]),
          pw.Spacer(),
          _footer(),
        ],
      ),
    ));
    await _save(pdf, 'taxuk_cgt');
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
    final pdf = pw.Document();
    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _header('Dividend Tax Calculator', 'UK Dividend Tax Summary 2025/26'),
          pw.SizedBox(height: 16),
          _heroBox('DIVIDEND TAX DUE', _gbp.format(taxDue)),
          pw.SizedBox(height: 16),
          _section('INCOME DETAILS', [
            _row('Employment / Other Income', _gbp.format(grossIncome)),
            _row('Gross Dividend Income', _gbp.format(grossDividend)),
            _row('Tax Band', band),
          ]),
          pw.SizedBox(height: 12),
          _section('DIVIDEND TAX CALCULATION', [
            _row('Dividend Allowance (2025/26)', _gbp.format(allowance)),
            _row('Taxable Dividend', _gbp.format(taxableDividend)),
            _rowHighlight('Tax Due', _gbp.format(taxDue)),
            _row('Effective Rate on Dividend', '${_pct.format(effectiveRate * 100)}%'),
          ]),
          pw.Spacer(),
          _footer(),
        ],
      ),
    ));
    await _save(pdf, 'taxuk_dividend');
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
    final pdf = pw.Document();
    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _header('VAT Calculator', 'UK VAT Breakdown'),
          pw.SizedBox(height: 16),
          _heroBox('VAT AMOUNT', _gbp.format(vatAmount)),
          pw.SizedBox(height: 16),
          _section('VAT BREAKDOWN', [
            _row('VAT Rate', rateLabel),
            _row('Net Amount (ex-VAT)', _gbp.format(netAmount)),
            _row('VAT Amount', _gbp.format(vatAmount)),
            _rowHighlight('Gross Amount (inc-VAT)', _gbp.format(grossAmount)),
          ]),
          pw.Spacer(),
          _footer(),
        ],
      ),
    ));
    await _save(pdf, 'taxuk_vat');
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
    final pdf = pw.Document();
    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _header('Student Loan Repayment', 'UK Student Loan Calculator'),
          pw.SizedBox(height: 16),
          _heroBox('ANNUAL REPAYMENT', _gbp.format(annualRepayment)),
          pw.SizedBox(height: 16),
          _section('LOAN DETAILS', [
            _row('Repayment Plan', plan),
            _row('Gross Annual Salary', _gbp.format(salary)),
            _row('Repayment Threshold', _gbp.format(threshold)),
          ]),
          pw.SizedBox(height: 12),
          _section('REPAYMENT BREAKDOWN', [
            _rowHighlight('Annual Repayment', _gbp.format(annualRepayment)),
            _row('Monthly Repayment', _gbp.format(monthlyRepayment)),
            _row('Weekly Repayment', _gbp.format(monthlyRepayment / 4.33)),
            _row(
              'Income Above Threshold',
              _gbp.format(salary > threshold ? salary - threshold : 0),
            ),
          ]),
          pw.Spacer(),
          _footer(),
        ],
      ),
    ));
    await _save(pdf, 'taxuk_student_loan');
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
    final pdf = pw.Document();
    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _header('Rental Income Tax', 'UK Rental Income Tax Summary 2025/26'),
          pw.SizedBox(height: 16),
          _heroBox('NET PROFIT AFTER TAX', _gbp.format(netProfit)),
          pw.SizedBox(height: 16),
          _section('INCOME & EXPENSES', [
            _row('Gross Rental Income', _gbp.format(grossRental)),
            _row('Allowable Expenses', _gbp.format(allowableExpenses)),
            _row('Taxable Profit', _gbp.format(taxableProfit)),
            if (otherIncome > 0) _row('Other Income', _gbp.format(otherIncome)),
          ]),
          pw.SizedBox(height: 12),
          _section('TAX CALCULATION', [
            if (mortgageInterestCredit > 0)
              _row('Mortgage Interest Credit (20%)', _gbp.format(mortgageInterestCredit)),
            _rowHighlight('Tax Due', _gbp.format(taxAfterCredit)),
            _row('Net Profit After Tax', _gbp.format(netProfit)),
            _row('Effective Yield on Rental', '${_pct.format(effectiveYield)}%'),
          ]),
          pw.Spacer(),
          _footer(),
        ],
      ),
    ));
    await _save(pdf, 'taxuk_rental_income');
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
    final pdf = pw.Document();
    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _header('Savings Interest Tax', 'UK Savings Interest Tax Summary 2025/26'),
          pw.SizedBox(height: 16),
          _heroBox('TAX DUE ON INTEREST', _gbp.format(taxDue)),
          pw.SizedBox(height: 16),
          _section('INCOME DETAILS', [
            _row('Gross Interest', _gbp.format(grossInterest)),
            _row('Other Income', _gbp.format(otherIncome)),
            _row('Tax Band', band),
          ]),
          pw.SizedBox(height: 12),
          _section('SAVINGS TAX CALCULATION', [
            _row('Personal Savings Allowance', _gbp.format(personalSavingsAllowance)),
            _row('Taxable Interest', _gbp.format(taxableInterest)),
            _rowHighlight('Tax Due', _gbp.format(taxDue)),
            if (effectiveRate > 0)
              _row('Effective Rate', '${_pct.format(effectiveRate * 100)}%'),
          ]),
          pw.Spacer(),
          _footer(),
        ],
      ),
    ));
    await _save(pdf, 'taxuk_savings_interest');
  }

  // ── Private builders ──────────────────────────────────────────────────────

  static pw.Widget _header(String title, String subtitle) => pw.Column(
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
                    _dateShort.format(DateTime.now()),
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

  static pw.Widget _heroBox(String label, String value) => pw.Container(
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

  static pw.Widget _infoRow(String text) => pw.Container(
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

  static pw.Widget _section(String title, List<pw.Widget> rows) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: double.infinity,
            padding:
                const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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

  static pw.Widget _comparisonSection({
    required String nameA,
    required String nameB,
    required List<(String, String, String)> rows,
  }) =>
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: double.infinity,
            padding:
                const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                // Header row
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
                ...rows.map((r) => _cmpRow(r.$1, r.$2, r.$3)),
              ],
            ),
          ),
        ],
      );

  static pw.Widget _cmpRow(String label, String valueA, String valueB) =>
      pw.Padding(
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

  static pw.Widget _row(String label, String value) => pw.Padding(
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

  static pw.Widget _rowHighlight(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 4),
        child: pw.Container(
          padding:
              const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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

  static pw.Widget _footer() => pw.Column(
        children: [
          pw.Divider(color: PdfColors.grey300),
          pw.Text(
            'Generated by TaxUK — UK Tax Calculator  ·  For informational purposes only. Consult a tax professional.',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500),
          ),
        ],
      );

  // ── File save & share ─────────────────────────────────────────────────────

  static Future<void> _save(pw.Document pdf, String baseName) async {
    final bytes = await pdf.save();
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
