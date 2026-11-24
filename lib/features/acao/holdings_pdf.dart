import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../data/acao/acao_api.dart';

String _xaf(num v) =>
    '${NumberFormat('#,##0', 'en').format(v.round()).replaceAll(',', ' ')} XAF';

String _safe(String s) => s
    .replaceAll('·', '-')
    .replaceAll(RegExp('[‘’]'), "'")
    .replaceAll(RegExp('[–—]'), '-')
    .replaceAll(RegExp(r'[^\x00-\xFF]'), '?');

/// A4 statement of a member's shares (holdings, history, dividends) and
/// investments (amounts, terms, payouts), as recorded by Nchemty.
Future<Uint8List> buildHoldingsPdf({
  required String memberName,
  AcaoShareStatement? shares,
  List<AcaoInvestment> investments = const [],
}) async {
  const green = PdfColor.fromInt(0xFF0F4C3A);
  const gold = PdfColor.fromInt(0xFFC8962E);
  const muted = PdfColor.fromInt(0xFF5B6660);
  const line = PdfColor.fromInt(0xFFE3E0D8);

  pw.Widget heading(String t) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
        child: pw.Text(t, style: const pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: green)),
      );

  pw.Widget table(List<String> headers, List<List<String>> rows, {Set<int> right = const {}}) =>
      pw.TableHelper.fromTextArray(
        headers: headers,
        data: rows,
        headerStyle: const pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: green),
        headerDecoration:
            const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: green, width: 1))),
        cellStyle: const pw.TextStyle(fontSize: 8),
        cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        rowDecoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: line, width: 0.5))),
        cellAlignments: {for (final i in right) i: pw.Alignment.centerRight},
      );

  final invested = investments
      .where((i) => i.status == 'active' || i.status == 'requested')
      .fold<num>(0, (t, i) => t + i.amount);

  final doc = pw.Document(title: 'Nchemty shares and investments');
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(32, 32, 32, 40),
    footer: (ctx) => pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
      pw.Text('Generated ${DateFormat('d MMM y, HH:mm').format(DateTime.now())} from the Nchemty app. Amounts in XAF.',
          style: const pw.TextStyle(color: muted, fontSize: 7)),
      pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}', style: const pw.TextStyle(color: muted, fontSize: 7)),
    ]),
    build: (ctx) => [
      pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: const pw.BoxDecoration(color: green, borderRadius: pw.BorderRadius.all(pw.Radius.circular(8))),
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('Nchemty Credit Union',
                style: const pw.TextStyle(color: PdfColors.white, fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.Text('Shares and investments statement', style: const pw.TextStyle(color: gold, fontSize: 10)),
          ]),
          pw.Text(_safe(memberName),
              style: const pw.TextStyle(color: PdfColors.white, fontSize: 11, fontWeight: pw.FontWeight.bold)),
        ]),
      ),
      pw.SizedBox(height: 12),
      pw.Row(children: [
        if (shares != null)
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('Shares, value today', style: const pw.TextStyle(color: muted, fontSize: 8)),
              pw.Text(_xaf(shares.totalValue), style: const pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
            ]),
          ),
        pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('Invested (running and pending)', style: const pw.TextStyle(color: muted, fontSize: 8)),
            pw.Text(_xaf(invested), style: const pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          ]),
        ),
      ]),
      if (shares != null) ...[
        heading('Shares held'),
        if (shares.holdings.where((h) => h.units > 0).isEmpty)
          pw.Text('No shares held.', style: const pw.TextStyle(color: muted, fontSize: 9))
        else
          table(['Class', 'Shares', 'Price', 'Value', 'Paid in'], [
            for (final h in shares.holdings.where((h) => h.units > 0))
              [_safe(h.cls.name), '${h.units}', _xaf(h.cls.price), _xaf(h.value), _xaf(h.paidIn)],
          ], right: {1, 2, 3, 4}),
        if (shares.dividends.isNotEmpty) ...[
          heading('Dividends'),
          table(['Reference', 'Class', 'Period', 'Gross', 'Tax', 'Net'], [
            for (final d in shares.dividends)
              [d.reference, d.classCode, '${d.periodStart ?? ''} - ${d.periodEnd ?? ''}', _xaf(d.gross), _xaf(d.tax), _xaf(d.net)],
          ], right: {3, 4, 5}),
        ],
        if (shares.movements.isNotEmpty) ...[
          heading('Share history'),
          table(['Date', 'Class', 'Movement', 'Shares', 'Amount', 'Certificate'], [
            for (final m in shares.movements)
              [m.date ?? '', m.classCode, m.label, '${m.units}', _xaf(m.amount.abs()), m.certificateNo ?? ''],
          ], right: {3, 4}),
        ],
      ],
      heading('Investments'),
      if (investments.isEmpty)
        pw.Text('No investments.', style: const pw.TextStyle(color: muted, fontSize: 9))
      else
        table(['Reference', 'Product', 'Amount', 'Rate', 'Start', 'Maturity', 'Status', 'Interest paid'], [
          for (final i in investments)
            [
              i.reference,
              _safe(i.productName),
              _xaf(i.amount),
              i.ratePa == null ? '' : '${i.ratePa}%',
              i.startDate ?? '',
              i.maturityDate ?? '',
              i.status,
              _xaf(i.interestPaid),
            ],
        ], right: {2, 3, 7}),
    ],
  ));
  return doc.save();
}
