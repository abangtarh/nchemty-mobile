import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../data/models/models.dart';

/// PDF-safe money (built-in PDF fonts are Latin-1 only).
String _xaf(num v, {bool sign = false}) {
  final s = NumberFormat('#,##0', 'en').format(v.abs().round()).replaceAll(',', ' ');
  return '${v < 0 ? '-' : (sign && v > 0 ? '+' : '')}$s';
}

/// Latin-1 only: replace characters the built-in fonts cannot draw.
String _safe(String s) => s
    .replaceAll('·', '-')
    .replaceAll(RegExp('[‘’]'), "'")
    .replaceAll(RegExp('[“”]'), '"')
    .replaceAll(RegExp('[–—]'), '-')
    .replaceAll(RegExp(r'[^\x00-\xFF]'), '?');

/// A4 account statement: header, period summary (opening balance, money
/// in/out, closing balance, all from Cyclos) and every transaction.
/// The running balance column is shown only when it reconciles exactly
/// with the closing balance Cyclos reports.
Future<Uint8List> buildStatementPdf({
  required AccountPeriodStatus account,
  required List<HistoryEntry> entries,
  required DateTime from,
  required DateTime to,
  required String memberName,
  bool truncated = false,
}) async {
  const green = PdfColor.fromInt(0xFF0F4C3A);
  const gold = PdfColor.fromInt(0xFFC8962E);
  const muted = PdfColor.fromInt(0xFF5B6660);
  const line = PdfColor.fromInt(0xFFE3E0D8);
  final d = DateFormat('d MMM y');
  final dt = DateFormat('dd/MM/yy HH:mm');

  // Running balance from Cyclos's opening balance; only trusted when it lands
  // exactly on Cyclos's closing balance.
  List<num>? running;
  if (account.balanceAtBegin != null && !truncated) {
    var b = account.balanceAtBegin!;
    running = [for (final e in entries) b += e.amount];
    final end = account.balanceAtEnd;
    if (end != null && (b - end).abs() > 0.5) running = null;
  }

  final totalIn = account.incomingSum ??
      entries.where((e) => e.amount > 0).fold<num>(0, (s, e) => s + e.amount);
  final totalOut = account.outgoingSum ??
      entries.where((e) => e.amount < 0).fold<num>(0, (s, e) => s - e.amount);

  pw.Widget summaryCell(String label, String value, {bool strong = false}) => pw.Expanded(
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(label, style: const pw.TextStyle(color: muted, fontSize: 8)),
          pw.SizedBox(height: 2),
          pw.Text(value,
              style: pw.TextStyle(
                  fontSize: strong ? 12 : 11,
                  fontWeight: strong ? pw.FontWeight.bold : pw.FontWeight.normal)),
        ]),
      );

  final headers = ['Date', 'Reference', 'Details', 'Debit', 'Credit', if (running != null) 'Balance'];
  final rows = <List<String>>[
    for (var i = 0; i < entries.length; i++)
      [
        dt.format(entries[i].date.toLocal()),
        _safe(entries[i].transactionNumber ?? ''),
        _safe([entries[i].title, entries[i].description]
            .whereType<String>()
            .where((s) => s.trim().isNotEmpty)
            .toSet()
            .join(' - ')),
        entries[i].amount < 0 ? _xaf(entries[i].amount.abs()) : '',
        entries[i].amount > 0 ? _xaf(entries[i].amount) : '',
        if (running != null) _xaf(running[i]),
      ],
  ];

  final doc = pw.Document(title: 'Nchemty statement ${d.format(from)} - ${d.format(to)}');
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(32, 32, 32, 40),
      header: (ctx) => ctx.pageNumber == 1
          ? pw.SizedBox()
          : pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 8),
              child: pw.Text(
                  _safe('${account.typeName} - ${d.format(from)} to ${d.format(to)} (continued)'),
                  style: const pw.TextStyle(color: muted, fontSize: 8)),
            ),
      footer: (ctx) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
              'Generated ${DateFormat('d MMM y, HH:mm').format(DateTime.now())} from the Nchemty app. Amounts in XAF.',
              style: const pw.TextStyle(color: muted, fontSize: 7)),
          pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}',
              style: const pw.TextStyle(color: muted, fontSize: 7)),
        ],
      ),
      build: (ctx) => [
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: const pw.BoxDecoration(
            color: green,
            borderRadius: pw.BorderRadius.all(pw.Radius.circular(8)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text('Nchemty Credit Union',
                    style: const pw.TextStyle(
                        color: PdfColors.white, fontSize: 14, fontWeight: pw.FontWeight.bold)),
                pw.Text('Account statement', style: const pw.TextStyle(color: gold, fontSize: 10)),
              ]),
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                pw.Text(_safe(memberName),
                    style: const pw.TextStyle(
                        color: PdfColors.white, fontSize: 11, fontWeight: pw.FontWeight.bold)),
                pw.Text(
                    _safe('${account.typeName}${account.number != null ? ' - ${account.number}' : ''}'),
                    style: const pw.TextStyle(color: PdfColors.white, fontSize: 9)),
                pw.Text('${d.format(from)} to ${d.format(to)}',
                    style: const pw.TextStyle(color: PdfColors.white, fontSize: 9)),
              ]),
            ],
          ),
        ),
        pw.SizedBox(height: 14),
        pw.Container(
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: line),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
          ),
          child: pw.Row(children: [
            summaryCell('Opening balance',
                account.balanceAtBegin == null ? '-' : '${_xaf(account.balanceAtBegin!)} XAF'),
            summaryCell(
                'Money in${account.incomingCount != null ? ' (${account.incomingCount})' : ''}',
                '${_xaf(totalIn)} XAF'),
            summaryCell(
                'Money out${account.outgoingCount != null ? ' (${account.outgoingCount})' : ''}',
                '${_xaf(totalOut)} XAF'),
            summaryCell('Closing balance',
                account.balanceAtEnd == null ? '-' : '${_xaf(account.balanceAtEnd!)} XAF',
                strong: true),
          ]),
        ),
        pw.SizedBox(height: 14),
        if (entries.isEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.all(24),
            child: pw.Center(
              child: pw.Text('No transactions in this period.',
                  style: const pw.TextStyle(color: muted)),
            ),
          )
        else
          pw.TableHelper.fromTextArray(
            headers: headers,
            data: rows,
            headerStyle: const pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: green),
            headerDecoration: const pw.BoxDecoration(
                border: pw.Border(bottom: pw.BorderSide(color: green, width: 1))),
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            rowDecoration: const pw.BoxDecoration(
                border: pw.Border(bottom: pw.BorderSide(color: line, width: 0.5))),
            columnWidths: {
              0: const pw.FixedColumnWidth(62),
              1: const pw.FixedColumnWidth(60),
              2: const pw.FlexColumnWidth(),
              3: const pw.FixedColumnWidth(58),
              4: const pw.FixedColumnWidth(58),
              if (running != null) 5: const pw.FixedColumnWidth(62),
            },
            cellAlignments: {
              3: pw.Alignment.centerRight,
              4: pw.Alignment.centerRight,
              5: pw.Alignment.centerRight,
            },
          ),
        if (truncated)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 8),
            child: pw.Text(
                'This period has more transactions than one statement can hold. Choose a shorter period for the full list.',
                style: const pw.TextStyle(color: muted, fontSize: 8)),
          ),
      ],
    ),
  );
  return doc.save();
}
