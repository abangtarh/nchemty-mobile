import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/config/env.dart';
import '../../data/models/models.dart';

/// What the receipt QR carries: a verification link when one is configured,
/// otherwise a compact, human-checkable reference string that staff can
/// look up in Cyclos.
String receiptQrData(TransferDetails t) {
  final ref = t.transactionNumber ?? t.id;
  if (Env.receiptVerifyUrl.isNotEmpty) {
    return Uri.parse(Env.receiptVerifyUrl)
        .replace(queryParameters: {'tx': ref})
        .toString();
  }
  return 'NCHEMTY|$ref|${t.amount.abs().round()} XAF|${t.date.toUtc().toIso8601String()}';
}

/// PDF-safe money (the built-in PDF fonts are Latin-1 only).
String _xaf(num v) {
  final s = NumberFormat('#,##0', 'en').format(v.abs().round()).replaceAll(',', ' ');
  return '${v < 0 ? '-' : ''}$s XAF';
}

/// Branded A6-ish transaction slip for one transfer.
Future<Uint8List> buildReceiptPdf(TransferDetails t, {String? printedFor}) async {
  final doc = pw.Document(title: 'Nchemty receipt ${t.transactionNumber ?? t.id}');
  const green = PdfColor.fromInt(0xFF0F4C3A);
  const gold = PdfColor.fromInt(0xFFC8962E);
  const muted = PdfColor.fromInt(0xFF5B6660);
  final when = DateFormat('d MMM y, HH:mm').format(t.date);
  final printed = DateFormat('d MMM y, HH:mm').format(DateTime.now());

  pw.Widget row(String label, String value, {bool strong = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 4),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: 110,
              child: pw.Text(label, style: const pw.TextStyle(color: muted, fontSize: 10)),
            ),
            pw.Expanded(
              child: pw.Text(value,
                  style: pw.TextStyle(
                      fontSize: 10, fontWeight: strong ? pw.FontWeight.bold : pw.FontWeight.normal)),
            ),
          ],
        ),
      );

  final feeTotal = t.fees.fold<num>(0, (s, f) => s + f.$2);

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a5,
      margin: const pw.EdgeInsets.all(28),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: const pw.BoxDecoration(
              color: green,
              borderRadius: pw.BorderRadius.all(pw.Radius.circular(8)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text('Nchemty Credit Union',
                      style: const pw.TextStyle(
                          color: PdfColors.white, fontSize: 13, fontWeight: pw.FontWeight.bold)),
                  pw.Text('Transaction receipt',
                      style: const pw.TextStyle(color: gold, fontSize: 10)),
                ]),
                pw.Text(when, style: const pw.TextStyle(color: PdfColors.white, fontSize: 9)),
              ],
            ),
          ),
          pw.SizedBox(height: 16),
          pw.Center(
            child: pw.Text(_xaf(t.amount),
                style: const pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
          ),
          if (t.statuses.isNotEmpty)
            pw.Center(
              child: pw.Text(t.statuses.join(' · '),
                  style: const pw.TextStyle(color: muted, fontSize: 10)),
            ),
          pw.SizedBox(height: 14),
          pw.Divider(color: PdfColors.grey300),
          row('Reference', t.transactionNumber ?? t.id, strong: true),
          row('Date', when),
          if (t.typeName != null) row('Type', t.typeName!),
          row('From', t.fromName),
          if (t.fromAccount != null) row('From account', t.fromAccount!),
          row('To', t.toName),
          if (t.toAccount != null) row('To account', t.toAccount!),
          if (t.description?.isNotEmpty == true) row('Description', t.description!),
          if (t.channel != null) row('Channel', t.channel!),
          if (t.fees.isNotEmpty) ...[
            pw.Divider(color: PdfColors.grey300),
            for (final f in t.fees) row(f.$1, _xaf(f.$2)),
            row('Total fees', _xaf(feeTotal), strong: true),
          ],
          pw.Divider(color: PdfColors.grey300),
          pw.SizedBox(height: 10),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.BarcodeWidget(
                barcode: pw.Barcode.qrCode(),
                data: receiptQrData(t),
                width: 84,
                height: 84,
              ),
              pw.SizedBox(width: 14),
              pw.Expanded(
                child: pw.Text(
                  Env.receiptVerifyUrl.isNotEmpty
                      ? 'Scan this code to verify the receipt online, or quote the reference at any Nchemty branch.'
                      : 'To verify this receipt, quote the reference at any Nchemty branch. The code holds the reference, amount and time recorded by Nchemty.',
                  style: const pw.TextStyle(color: muted, fontSize: 9),
                ),
              ),
            ],
          ),
          pw.Spacer(),
          pw.Text(
            'Printed ${printedFor != null ? 'for $printedFor ' : ''}on $printed from the Nchemty app.',
            style: const pw.TextStyle(color: muted, fontSize: 8),
          ),
        ],
      ),
    ),
  );
  return doc.save();
}
